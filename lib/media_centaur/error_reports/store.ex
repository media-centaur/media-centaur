defmodule MediaCentaur.ErrorReports.Store do
  @moduledoc """
  Durable persistence for diagnostic events and incidents — the synchronous,
  pure-`Repo` backbone of the observability subsystem.

  Every function here runs in the calling process and does its own DB work, so
  it is exercised directly from tests under the SQLite sandbox. The
  `Buckets` cache and the capture sink are thin async wrappers *onto* this
  module; capture in the logger handler only hands off, never persists inline
  (a slow or failing write must never block or crash logging).

  In Phase 1 only the `:log` origin is written:

    - `insert_event/1` appends one redacted `%DiagnosticEvent{}` row.
    - `upsert_log_incident/1` opens-or-bumps the single `%Incident{}` grouped
      by fingerprint, reopening it if it had been resolved.

  Callers redact before handing data in — the store stores verbatim.
  """
  import Ecto.Query

  alias MediaCentaur.ErrorReports.DiagnosticEvent
  alias MediaCentaur.ErrorReports.Incident
  alias MediaCentaur.Repo

  @default_recent_limit 5

  @type health_rollup :: %{
          status: :ok | :warning | :error | :critical,
          open_count: non_neg_integer(),
          by_severity: %{optional(atom()) => non_neg_integer()}
        }

  # --- Diagnostic events ---

  @doc "Persists one already-redacted diagnostic event."
  @spec insert_event(map()) :: {:ok, DiagnosticEvent.t()} | {:error, Ecto.Changeset.t()}
  def insert_event(attrs) do
    attrs
    |> DiagnosticEvent.changeset()
    |> Repo.insert()
  end

  @doc """
  Returns the most recent events for a fingerprint, newest first, capped at
  `limit`. Feeds bucket sample reconstruction on cache rebuild.
  """
  @spec list_recent_events(String.t(), pos_integer()) :: [DiagnosticEvent.t()]
  def list_recent_events(fingerprint, limit \\ @default_recent_limit) do
    DiagnosticEvent
    |> where([event], event.fingerprint == ^fingerprint)
    |> order_by([event], desc: event.occurred_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Deletes events whose `occurred_at` is strictly before `cutoff`. Returns the
  number of rows removed. Incidents are never touched here.
  """
  @spec prune_events(DateTime.t()) :: non_neg_integer()
  def prune_events(%DateTime{} = cutoff) do
    {count, _} =
      DiagnosticEvent
      |> where([event], event.occurred_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  # --- Incidents ---

  @doc """
  Opens, or bumps, the `:log` incident grouped by `attrs.fingerprint`.

  First occurrence inserts an open incident (`count: 1`, `first_seen ==
  last_seen == occurred_at`). A recurrence bumps `count`, advances `last_seen`
  to the latest `occurred_at` seen, keeps the earliest `first_seen`, and
  reopens the incident if it had been resolved.
  """
  @spec upsert_log_incident(map()) :: {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
  def upsert_log_incident(attrs) do
    attrs = Map.new(attrs)
    fingerprint = Map.fetch!(attrs, :fingerprint)

    case get_incident_by_fingerprint(fingerprint) do
      nil -> open_log_incident(attrs)
      %Incident{} = incident -> bump_log_incident(incident, attrs)
    end
  end

  @doc "Returns the incident grouped under `fingerprint`, or `nil`."
  @spec get_incident_by_fingerprint(String.t()) :: Incident.t() | nil
  def get_incident_by_fingerprint(fingerprint) do
    Repo.get_by(Incident, fingerprint: fingerprint)
  end

  @doc """
  Lists incidents, newest activity first.

  Options:
    - `:status` — keep only incidents in this lifecycle status.
    - `:limit` — cap the number of rows returned (most-recent first).
  """
  @spec list_incidents(keyword()) :: [Incident.t()]
  def list_incidents(opts \\ []) do
    Incident
    |> filter_status(Keyword.get(opts, :status))
    |> order_by([incident], desc: incident.last_seen)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
  end

  @doc """
  Sets an incident's lifecycle status. Resolving stamps `resolved_at`; moving
  back to `:open`/`:acknowledged` clears it.
  """
  @spec set_status(Incident.t(), :open | :acknowledged | :resolved) ::
          {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
  def set_status(%Incident{} = incident, status) when status in [:open, :acknowledged, :resolved] do
    resolved_at = if status == :resolved, do: DateTime.utc_now()

    incident
    |> Incident.recurrence_changeset(%{
      count: incident.count,
      last_seen: incident.last_seen,
      status: status,
      resolved_at: resolved_at
    })
    |> Repo.update()
  end

  @doc """
  Rolls up the health of the durable store: open (non-resolved) incidents
  counted by severity, plus an overall `status` set to the worst open severity
  (`:ok` when nothing is open). Feeds the dashboard's health surface and the
  discovery badge.
  """
  @spec health() :: health_rollup()
  def health do
    by_severity =
      Incident
      |> where([incident], incident.status != :resolved)
      |> group_by([incident], incident.severity)
      |> select([incident], {incident.severity, count(incident.id)})
      |> Repo.all()
      |> Map.new()

    %{
      status: worst_status(by_severity),
      open_count: by_severity |> Map.values() |> Enum.sum(),
      by_severity: by_severity
    }
  end

  # --- Internals ---

  defp worst_status(by_severity) do
    cond do
      Map.get(by_severity, :critical, 0) > 0 -> :critical
      Map.get(by_severity, :error, 0) > 0 -> :error
      Map.get(by_severity, :warning, 0) > 0 -> :warning
      true -> :ok
    end
  end

  defp open_log_incident(attrs) do
    occurred_at = Map.fetch!(attrs, :occurred_at)

    attrs
    |> Map.merge(%{first_seen: occurred_at, last_seen: occurred_at, count: 1, status: :open})
    |> Incident.log_changeset()
    |> Repo.insert()
  end

  defp bump_log_incident(%Incident{} = incident, attrs) do
    occurred_at = Map.fetch!(attrs, :occurred_at)

    incident
    |> Incident.recurrence_changeset(
      %{
        count: incident.count + 1,
        first_seen: min_dt(incident.first_seen, occurred_at),
        last_seen: max_dt(incident.last_seen, occurred_at),
        status: reopen_status(incident.status),
        resolved_at: reopen_resolved_at(incident)
      }
      |> put_latest(:message, attrs)
      |> put_latest(:display_title, attrs)
    )
    |> Repo.update()
  end

  # Refresh a latest-occurrence field on the recurrence changeset only when the
  # caller supplied it, so callers (e.g. set_status) that don't carry it leave
  # the stored value untouched.
  defp put_latest(changes, key, attrs) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(changes, key, value)
      :error -> changes
    end
  end

  defp reopen_status(:resolved), do: :open
  defp reopen_status(status), do: status

  defp reopen_resolved_at(%Incident{status: :resolved}), do: nil
  defp reopen_resolved_at(%Incident{resolved_at: resolved_at}), do: resolved_at

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: where(query, [incident], incident.status == ^status)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, count) when is_integer(count), do: limit(query, ^count)

  defp max_dt(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
  defp min_dt(a, b), do: if(DateTime.before?(a, b), do: a, else: b)
end
