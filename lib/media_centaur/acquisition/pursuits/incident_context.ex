defmodule MediaCentaur.Acquisition.Pursuits.IncidentContext do
  @moduledoc """
  The pursuit side's health probe for the hop the app cannot see
  directly: Prowlarr handing a release to the download client. The
  `assess/0` that `Acquisition.IncidentContext` composes into the
  `acquisition` component's single condition (ADR-054).

  ## Why this exists

  `Downloads.IncidentContext` grades the app's own link to a download
  client. Prowlarr keeps its own link, configured on its side, and when
  that one breaks every grab comes back HTTP 500 while the app's polls
  stay green — the 2026-09-17 outage: a stale host and port in
  Prowlarr's SABnzbd entry, nothing downloading, no tile amber. The only
  evidence is the grab error itself, which `Jobs.PursueTarget` now stamps
  on the target as `last_attempt_outcome: "download_client_unavailable"`
  (spec 2026-09-17 decision 5). This probe reads those stamps.

  ## The decision

  A warning while the latest word about the hop is a failure: some
  seeking target failed a hand-off inside the window, and no grab has
  succeeded since that failure. A later successful grab, on any
  pursuit, clears it at once; otherwise it ages out `@window_seconds`
  after the last failed retry (the retry loop re-tries every 15 minutes
  while the pursuit lives, so an outage keeps the stamp fresh and a
  cancelled pursuit lets it lapse). Cancelled and failed targets are
  ignored — their stamps are history, not a live condition.

  `decide/4` is pure; `assess/0` is the thin shell that reads the two
  timestamps.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  import Ecto.Query

  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Repo

  # Twice the retry loop's `download_client_unavailable` snooze: one
  # missed retry (a pursuit cancelled mid-outage) is not a recovery, but
  # two silent intervals mean nothing is trying any more.
  @window_seconds 30 * 60

  @type fault :: {:fault, :download_client_handoff_failed, :warning, %{headline: String.t()}}

  @doc "Health probe polled (via the acquisition composite) by the diagnostics evaluator."
  @spec assess() :: :ok | fault()
  @impl true
  def assess do
    decide(last_handoff_failure_at(), last_grab_at(), DateTime.utc_now(), @window_seconds)
  end

  @doc """
  Pure fault decision.

    * `last_failure_at` — the newest `last_attempt_at` among seeking
      targets whose last outcome was `download_client_unavailable`, or
      nil.
    * `last_success_at` — the newest `acquired_at` across all targets,
      or nil.
    * `now`, `window_seconds` — a failure older than the window has aged
      out.
  """
  @spec decide(DateTime.t() | nil, DateTime.t() | nil, DateTime.t(), pos_integer()) :: :ok | fault()
  def decide(nil, _last_success_at, _now, _window_seconds), do: :ok

  def decide(%DateTime{} = last_failure_at, last_success_at, now, window_seconds) do
    recent? = DateTime.diff(now, last_failure_at, :second) <= window_seconds

    superseded? =
      match?(%DateTime{}, last_success_at) and DateTime.after?(last_success_at, last_failure_at)

    if recent? and not superseded? do
      {:fault, :download_client_handoff_failed, :warning,
       %{headline: "Prowlarr could not hand releases to the download client"}}
    else
      :ok
    end
  end

  defp last_handoff_failure_at do
    Target
    |> where([t], t.status == "seeking" and t.last_attempt_outcome == "download_client_unavailable")
    |> select([t], max(t.last_attempt_at))
    |> Repo.one()
  end

  defp last_grab_at do
    Target
    |> where([t], not is_nil(t.acquired_at))
    |> select([t], max(t.acquired_at))
    |> Repo.one()
  end
end
