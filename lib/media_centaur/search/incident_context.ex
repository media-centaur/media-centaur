defmodule MediaCentaur.Search.IncidentContext do
  @moduledoc """
  The acquisition subsystem's search-provider health probe — turns a
  sustained Prowlarr outage into a `:subsystem` incident condition
  (ADR-054, UIDR-016).

  ## Fault conditions

    * `:search_provider_unreachable` (**warning**) — the Prowlarr API
      itself can't be reached.
    * `:search_provider_rejected` (**warning**) — Prowlarr answers and
      refuses the API key (401/403). As useless as unreachable for held
      work, and a different thing to go fix.
    * `:search_indexers_unavailable` (**warning**) — Prowlarr answers,
      but every enabled indexer is backed off after failures; searches
      "succeed" with zero results without asking anyone.

  A partly backed-off roster (`IndexerHealth` `:degraded`) and an empty
  one (`:unconfigured`) leave `:prowlarr` available and never fault —
  the former is partial capability the Incoming page surfaces
  contextually, the latter is a setup state.

  ## Grace, and why there is no staleness rule

  Reads `MediaCentaur.IntegrationAvailability`, whose value is written by
  every real Prowlarr request and kept current while down by
  `Search.ProbeJob` — so the condition lasts exactly as long as the
  outage and clears within one probe of recovery. A grace window keeps
  one failed request from opening an incident on its own.

  This replaces the staleness rule an event-driven signal needed: the
  cached roster observation used to be treated as `:ok` once it aged past
  15 minutes, on the reasoning that nothing was exercising search — which
  is why a three-day outage read as "nothing wrong". With a probe behind
  the value there is no unevidenced state left to resolve into.

  Composed into the `acquisition` component's single assessor by
  `MediaCentaur.Acquisition.IncidentContext` — the evaluator contract is
  one condition per component, and this, the hand-off probe and the
  download-client probe are all acquisition capabilities.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  # Long enough that Prowlarr's own short first back-off (5 min ramp)
  # plus one probe can recover before an incident opens; aligned with the
  # download client's and the hand-off's grace.
  @grace_seconds 180

  @type fault :: {:fault, atom(), :warning, %{headline: String.t()}}

  @doc "Health probe polled (via the acquisition composite) by the diagnostics evaluator."
  @spec assess() :: :ok | fault()
  @impl true
  def assess do
    decide(IntegrationAvailability.status(:prowlarr), DateTime.utc_now(), @grace_seconds)
  end

  @doc "Pure fault decision over Prowlarr's availability."
  @spec decide(Status.t(), DateTime.t(), pos_integer()) :: :ok | fault()
  def decide(%Status{state: {:down, since, reason}}, now, grace_seconds) do
    with {kind, headline} <- fault_for(reason),
         true <- DateTime.diff(now, since, :second) >= grace_seconds do
      {:fault, kind, :warning, %{headline: headline}}
    else
      _quiet -> :ok
    end
  end

  def decide(%Status{state: :up}, _now, _grace_seconds), do: :ok

  defp fault_for(:unreachable), do: {:search_provider_unreachable, "Search provider unreachable"}
  defp fault_for(:rejected), do: {:search_provider_rejected, "Search provider rejected the API key"}
  defp fault_for(:blind), do: {:search_indexers_unavailable, "No indexer available"}

  # The hand-off is `Pursuits.IncidentContext`'s condition — search is
  # unaffected by a download client Prowlarr cannot reach.
  defp fault_for(:client_unavailable), do: nil
end
