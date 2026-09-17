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
  Prowlarr's SABnzbd entry, nothing downloading, no tile amber.

  ## The decision

  Reads `MediaCentaur.IntegrationAvailability` for both hand-off slots.
  The value is written by the grab that discovers an outage and kept
  fresh by `Search.ProbeJob` while down, so the fault lasts exactly as
  long as the outage and clears within one probe of recovery. A grace
  window keeps one failed grab from opening an incident on its own.

  `decide/3` is pure; `assess/0` is the thin shell that reads the two
  statuses.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  # Aligned with the download client's and search's grace.
  @grace_seconds 180

  @type fault :: {:fault, :download_client_handoff_failed, :warning, %{headline: String.t()}}

  @doc "Health probe polled (via the acquisition composite) by the diagnostics evaluator."
  @spec assess() :: :ok | fault()
  @impl true
  def assess do
    IntegrationAvailability.handoff_slots()
    |> Enum.map(&IntegrationAvailability.status({:handoff, &1}))
    |> decide(DateTime.utc_now(), @grace_seconds)
  end

  @doc "Pure fault decision over the hand-off statuses."
  @spec decide([Status.t()], DateTime.t(), pos_integer()) :: :ok | fault()
  def decide(statuses, now, grace_seconds) do
    if Enum.any?(statuses, &down_past_grace?(&1, now, grace_seconds)) do
      {:fault, :download_client_handoff_failed, :warning,
       %{headline: "Prowlarr could not hand releases to the download client"}}
    else
      :ok
    end
  end

  defp down_past_grace?(%Status{state: {:down, since, _reason}}, now, grace_seconds),
    do: DateTime.diff(now, since, :second) >= grace_seconds

  defp down_past_grace?(%Status{state: :up}, _now, _grace_seconds), do: false
end
