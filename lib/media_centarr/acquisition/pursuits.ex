defmodule MediaCentarr.Acquisition.Pursuits do
  @moduledoc """
  Read-side queries over the pursuit aggregate.

  Write-side operations live in `Acquisition.Pursuits.Commands.*`. This
  module is intentionally read-only — it never mutates state, never
  broadcasts, never enqueues jobs. Callers that want to change the world
  go through a command. ViewModel assemblers also live here because
  shaping rows for the UI is a read concern.
  """

  import Ecto.Query

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit, State}

  alias MediaCentarr.Acquisition.ViewModels.{
    PursuitHeader,
    PursuitRow,
    Timeline,
    TimelineEntry
  }

  alias MediaCentarr.Repo

  @recent_events_limit 3

  @spec get(Ecto.UUID.t()) :: {:ok, Pursuit.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Pursuit, id) do
      nil -> {:error, :not_found}
      %Pursuit{} = pursuit -> {:ok, pursuit}
    end
  end

  @doc "Lists every in-flight pursuit (`active` or `needs_decision`), newest-updated first."
  @spec list_active() :: [Pursuit.t()]
  def list_active do
    Pursuit
    |> where([p], p.state in ^State.in_flight())
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc "Lists active pursuits as `PursuitRow` view-models with the last few events attached."
  @spec list_active_rows() :: [PursuitRow.t()]
  def list_active_rows do
    pursuits = list_active()

    pursuit_ids = Enum.map(pursuits, & &1.id)
    events_by_pursuit = recent_events_by_pursuit(pursuit_ids, @recent_events_limit)

    Enum.map(pursuits, fn pursuit ->
      events = Map.get(events_by_pursuit, pursuit.id, [])
      build_row(pursuit, events)
    end)
  end

  @doc "Returns a `PursuitHeader` view-model for the detail page."
  @spec header_for(Ecto.UUID.t()) :: {:ok, PursuitHeader.t()} | {:error, :not_found}
  def header_for(id) do
    case get(id) do
      {:ok, pursuit} -> {:ok, build_header(pursuit)}
      {:error, :not_found} = error -> error
    end
  end

  @doc "Returns a `Timeline` view-model containing every event for a pursuit."
  @spec timeline_for(Ecto.UUID.t()) :: Timeline.t()
  def timeline_for(pursuit_id) do
    entries =
      pursuit_id
      |> events_for()
      |> Enum.map(&entry_for_event/1)

    %Timeline{pursuit_id: pursuit_id, entries: entries}
  end

  @doc """
  Returns events for a pursuit, newest first. Empty list for unknown pursuit_id —
  events with nilified `pursuit_id` are not surfaced here (use a dedicated query
  if you need orphan events).
  """
  @spec events_for(Ecto.UUID.t()) :: [Event.t()]
  def events_for(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  @doc "Returns the most recently inserted grab linked to a pursuit."
  @spec latest_grab(Ecto.UUID.t()) :: {:ok, Grab.t()} | {:error, :not_found}
  def latest_grab(pursuit_id) do
    grab =
      Grab
      |> where([g], g.pursuit_id == ^pursuit_id)
      |> order_by([g], desc: g.inserted_at)
      |> limit(1)
      |> Repo.one()

    case grab do
      nil -> {:error, :not_found}
      %Grab{} = grab -> {:ok, grab}
    end
  end

  # --- ViewModel assembly ----------------------------------------------------

  defp recent_events_by_pursuit([], _limit), do: %{}

  defp recent_events_by_pursuit(pursuit_ids, limit) do
    Event
    |> where([e], e.pursuit_id in ^pursuit_ids)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
    |> Enum.group_by(& &1.pursuit_id)
    |> Map.new(fn {pid, events} -> {pid, Enum.take(events, limit)} end)
  end

  defp build_row(%Pursuit{} = pursuit, events) do
    %PursuitRow{
      id: pursuit.id,
      title: pursuit.title,
      state: String.to_existing_atom(pursuit.state),
      origin: String.to_existing_atom(pursuit.origin),
      attempt_count: pursuit.attempt_count,
      recent_events: Enum.map(events, &entry_for_event/1),
      detail_path: "/download/#{pursuit.id}",
      inserted_at: pursuit.inserted_at,
      updated_at: pursuit.updated_at
    }
  end

  defp build_header(%Pursuit{} = pursuit) do
    %PursuitHeader{
      id: pursuit.id,
      title: pursuit.title,
      state: String.to_existing_atom(pursuit.state),
      origin: String.to_existing_atom(pursuit.origin),
      attempt_count: pursuit.attempt_count,
      tried_count: length(pursuit.tried_release_guids),
      criteria_summary: summarize_criteria(pursuit.criteria),
      inserted_at: pursuit.inserted_at
    }
  end

  defp entry_for_event(%Event{} = event) do
    %TimelineEntry{
      kind: event.kind,
      occurred_at: event.occurred_at,
      summary: summary_for(event.kind, event.payload),
      severity: severity_for(event.kind),
      detail: detail_for(event.kind, event.payload)
    }
  end

  defp summary_for("pursuit_started", %{"origin" => "auto"}), do: "Pursuit started (auto)"
  defp summary_for("pursuit_started", %{"origin" => "manual"}), do: "Pursuit started (manual)"
  defp summary_for("pursuit_started", _), do: "Pursuit started"
  defp summary_for("search_started", _), do: "Searching Prowlarr"

  defp summary_for("release_picked", %{"release_title" => t}) when is_binary(t),
    do: "Release picked — #{t}"

  defp summary_for("release_picked", _), do: "Release picked"
  defp summary_for("release_no_match", _), do: "No acceptable release found"
  defp summary_for("download_started", _), do: "Download started"
  defp summary_for("health_changed", %{"to_state" => to}), do: "Health changed → #{to}"
  defp summary_for("health_changed", _), do: "Health changed"
  defp summary_for("stall_confirmed", _), do: "Stall confirmed"
  defp summary_for("zero_seeders_confirmed", _), do: "Zero seeders confirmed"
  defp summary_for("auto_cancelled", %{"reason" => r}), do: "Auto-cancelled (#{r})"
  defp summary_for("auto_cancelled", _), do: "Auto-cancelled"
  defp summary_for("fallback_initiated", _), do: "Fallback initiated"
  defp summary_for("user_decision_requested", _), do: "User decision requested"
  defp summary_for("user_decision_recorded", %{"choice" => c}), do: "User picked — #{c}"
  defp summary_for("user_decision_recorded", _), do: "User decision recorded"
  defp summary_for("identity_mismatch", _), do: "Identity mismatch — file routed to Review"
  defp summary_for("identity_verified", _), do: "Identity verified"
  defp summary_for("pursuit_satisfied", _), do: "Pursuit satisfied"
  defp summary_for("pursuit_exhausted", %{"reason" => r}), do: "Pursuit exhausted (#{r})"
  defp summary_for("pursuit_exhausted", _), do: "Pursuit exhausted"
  defp summary_for("pursuit_cancelled", _), do: "Pursuit cancelled"
  defp summary_for(kind, _), do: kind

  defp severity_for(kind) when kind in ~w(stall_confirmed zero_seeders_confirmed), do: :warning
  defp severity_for(kind) when kind in ~w(identity_mismatch pursuit_exhausted), do: :error

  defp severity_for(kind) when kind in ~w(release_picked identity_verified pursuit_satisfied),
    do: :success

  defp severity_for(_), do: :info

  defp detail_for("release_picked", %{"indexer" => indexer, "quality" => q}), do: "#{indexer} • #{q}"
  defp detail_for("release_picked", %{"quality" => q}), do: q
  defp detail_for(_, _), do: nil

  defp summarize_criteria(nil), do: nil
  defp summarize_criteria(map) when map_size(map) == 0, do: nil

  defp summarize_criteria(map) when is_map(map) do
    map
    |> Enum.sort()
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{v}" end)
  end
end
