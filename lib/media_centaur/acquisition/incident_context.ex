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

  @type assessment :: MediaCentaur.ErrorReports.IncidentContext.assessment()

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
  the highest-severity fault, first-probe-wins on equal severity; with no
  fault, `{:unknown, kinds}` naming every kind a probe cannot yet vouch
  for, so one probe that cannot tell never holds another probe's
  recovered kind open; `:ok` when every probe is healthy.
  """
  @spec worst([assessment()]) :: assessment()
  def worst(assessments) do
    faults = Enum.filter(assessments, &match?({:fault, _kind, _severity, _ids}, &1))
    unknown_kinds = Enum.flat_map(assessments, &unknown_kinds/1)

    cond do
      faults != [] -> Enum.min_by(faults, &severity_rank/1)
      unknown_kinds != [] -> {:unknown, unknown_kinds}
      true -> :ok
    end
  end

  defp unknown_kinds({:unknown, kinds}), do: kinds
  defp unknown_kinds(_assessment), do: []

  defp severity_rank({:fault, _kind, :error, _ids}), do: 0
  defp severity_rank({:fault, _kind, :warning, _ids}), do: 1
end
