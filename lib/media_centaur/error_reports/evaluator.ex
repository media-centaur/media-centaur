defmodule MediaCentaur.ErrorReports.Evaluator do
  @moduledoc """
  Polls each registered `IncidentContext.assess/0` and reconciles `:subsystem`
  incidents to match — the duration/trend half of detection (acute faults are
  raised directly by subsystems via `ErrorReports.raise_fault/4`).

  Driven on a schedule by `ErrorReports.EvaluatorJob` (Oban cron). The reconcile
  decision is the pure `plan/2`; `run/1` is the thin shell that reads the
  current open kinds from the store, applies the plan, and is defensive about a
  crashing assessor (skipped, never flaps the incident).

  Contract: a component with a registered assessor lets the evaluator **own**
  its `:subsystem` incidents — `assess/0` reports the single current condition,
  and the evaluator resolves any open kind the assessor is no longer reporting.
  """
  alias MediaCentaur.ErrorReports
  alias MediaCentaur.ErrorReports.Contributors
  alias MediaCentaur.ErrorReports.IncidentContext
  alias MediaCentaur.ErrorReports.Store

  @type assessment ::
          :ok | {:fault, IncidentContext.kind(), IncidentContext.severity(), IncidentContext.ids()}

  @doc """
  Pure reconcile decision: given an `assess/0` result and the kinds currently
  open for that component, returns what to raise and what to resolve.

    - `:ok` → resolve every open kind, raise nothing.
    - `{:fault, kind, severity, _ids}` → raise that kind, resolve any other open
      kind the assessor is no longer reporting.
  """
  @spec plan(assessment(), [String.t()]) :: %{
          raises: [{IncidentContext.kind(), IncidentContext.severity()}],
          resolves: [String.t()]
        }
  def plan(:ok, open_kinds), do: %{raises: [], resolves: open_kinds}

  def plan({:fault, kind, severity, _ids}, open_kinds) do
    %{raises: [{kind, severity}], resolves: open_kinds -- [to_string(kind)]}
  end

  @doc """
  Polls every assessor in `registry` and applies its reconcile plan. A crashing
  assessor is skipped (no raise/resolve) so a broken probe can't flap incidents.
  """
  @spec run(Contributors.registry()) :: :ok
  def run(registry \\ Contributors.registry()) do
    registry
    |> Contributors.assessors()
    |> Enum.each(fn {component, module} -> reconcile(component, safe_assess(module)) end)
  end

  defp reconcile(_component, :skip), do: :ok

  defp reconcile(component, assessment) do
    %{raises: raises, resolves: resolves} = plan(assessment, Store.open_subsystem_kinds(component))

    Enum.each(raises, fn {kind, severity} -> ErrorReports.raise_fault(component, kind, severity) end)
    Enum.each(resolves, fn kind -> ErrorReports.resolve_fault(component, kind) end)
  end

  defp safe_assess(module) do
    case module.assess() do
      :ok -> :ok
      {:fault, _kind, _severity, _ids} = fault -> fault
      _other -> :skip
    end
  rescue
    _ -> :skip
  catch
    _, _ -> :skip
  end
end
