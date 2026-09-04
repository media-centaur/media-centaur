defmodule MediaCentaur.Search.IncidentContext do
  @moduledoc """
  The acquisition subsystem's search-provider health probe — turns a
  sustained `Search.IndexerHealth` fault into a `:subsystem` incident
  condition (ADR-054, UIDR-016).

  ## Fault conditions

    * `:search_provider_unreachable` (**warning**) — the Prowlarr API
      itself can't be reached.
    * `:search_indexers_unavailable` (**warning**) — Prowlarr answers,
      but every enabled indexer is backed off after failures; searches
      "succeed" with zero results without asking anyone.

  `:degraded` (some indexers backed off) and `:unconfigured` never
  fault — the former is partial capability the Incoming page surfaces
  contextually, the latter is a setup state.

  ## Grace and staleness

  Unlike the download client, search has no continuous poller — the
  `IndexerHealth` cache is refreshed by the Incoming page (30s while
  open) and by every zero-result live search. Two windows keep that
  event-driven signal honest:

    * **grace** — the fault onset (`since`, preserved across
      consecutive faulty observations) must be older than the window,
      so one failed snapshot never opens an incident.
    * **staleness** — an observation older than the window is treated
      as `:ok`: nothing is exercising search, so there is no live
      evidence the condition persists. The incident auto-resolves
      rather than sticking to the last thing anyone saw.

  Composed into the `acquisition` component's single assessor by
  `MediaCentaur.Acquisition.IncidentContext` — the evaluator contract
  is one condition per component, and both this and the download-client
  probe are acquisition capabilities. Fulfils the `assess/0` contract
  structurally (no `@behaviour`), like the other incident contexts.
  """

  alias MediaCentaur.Search.IndexerHealth

  # Long enough that Prowlarr's own short first back-off (5 min ramp)
  # plus one page poll can recover before an incident opens; aligned
  # with the download client's grace.
  @grace_seconds 180

  # After this long without a fresh observation the condition is
  # unevidenced — resolve rather than assume.
  @staleness_seconds 900

  @type fault :: {:fault, atom(), :warning, map()}

  @doc "Health probe polled (via the acquisition composite) by the diagnostics evaluator."
  @spec assess() :: :ok | fault()
  def assess do
    decide(IndexerHealth.cached(), DateTime.utc_now(), @grace_seconds, @staleness_seconds)
  end

  @doc """
  Pure fault decision over the cached observation. See the moduledoc
  for the grace/staleness semantics.
  """
  @spec decide(IndexerHealth.t() | nil, DateTime.t(), pos_integer(), pos_integer()) ::
          :ok | fault()
  def decide(nil, _now, _grace_seconds, _staleness_seconds), do: :ok

  def decide(%IndexerHealth{} = health, now, grace_seconds, staleness_seconds) do
    with kind when not is_nil(kind) <- fault_kind(health.state),
         false <- stale?(health, now, staleness_seconds),
         true <- sustained?(health, now, grace_seconds) do
      {:fault, kind, :warning, %{headline: headline(kind)}}
    else
      _quiet -> :ok
    end
  end

  defp headline(:search_provider_unreachable), do: "Search provider unreachable"
  defp headline(:search_indexers_unavailable), do: "No indexer available"

  defp fault_kind(:unreachable), do: :search_provider_unreachable
  defp fault_kind(:blind), do: :search_indexers_unavailable
  defp fault_kind(_state), do: nil

  defp stale?(health, now, staleness_seconds) do
    DateTime.diff(now, health.checked_at, :second) >= staleness_seconds
  end

  defp sustained?(%IndexerHealth{since: %DateTime{} = since}, now, grace_seconds) do
    DateTime.diff(now, since, :second) >= grace_seconds
  end

  defp sustained?(_health, _now, _grace_seconds), do: false
end
