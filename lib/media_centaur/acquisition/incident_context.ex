defmodule MediaCentaur.Acquisition.IncidentContext do
  @moduledoc """
  The `acquisition` component's single `:subsystem` assessor — composes
  the download-client probe (`Downloads.IncidentContext`), the hand-off
  probe (`Pursuits.IncidentContext`: Prowlarr's own link to the client,
  read from `IntegrationAvailability`) and the search-provider probe
  (`Search.IncidentContext`) into one condition (ADR-054, UIDR-016).

  The evaluator contract is one assessor per component reporting *the*
  single current condition; all three probes are acquisition
  capabilities (search finds releases, the client lands them), so they
  share the component. `worst/1` picks what surfaces when several
  fault: highest severity first, probe order (the app's client link,
  then Prowlarr's, then search) on a tie — the client is the more
  directly actionable of the three.

  Registered under `:acquisition` in
  `config :media_centaur, :diagnostics_contributors`.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Downloads
  alias MediaCentaur.Search

  @type assessment :: :ok | {:fault, atom(), :warning | :error, map()}

  @doc "Health probe polled by the diagnostics evaluator."
  @spec assess() :: assessment()
  @impl true
  def assess do
    worst([
      Downloads.IncidentContext.assess(),
      Pursuits.IncidentContext.assess(),
      Search.IncidentContext.assess()
    ])
  end

  @doc """
  The single condition to report from an ordered list of probe results:
  the highest-severity fault, first-probe-wins on equal severity, `:ok`
  when every probe is healthy.
  """
  @spec worst([assessment()]) :: assessment()
  def worst(assessments) do
    assessments
    |> Enum.reject(&(&1 == :ok))
    |> Enum.min_by(&severity_rank/1, fn -> :ok end)
  end

  defp severity_rank({:fault, _kind, :error, _ids}), do: 0
  defp severity_rank({:fault, _kind, :warning, _ids}), do: 1
end
