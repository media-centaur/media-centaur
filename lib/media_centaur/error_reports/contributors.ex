defmodule MediaCentaur.ErrorReports.Contributors do
  @moduledoc """
  Runtime registry mapping a subsystem `component` to its
  `ErrorReports.IncidentContext` implementation.

  This is the inversion-of-control seam: the mapping is **config data**
  (`config :media_centaur, :diagnostics_contributors, %{component => module}`),
  resolved at runtime, so `ErrorReports` invokes contributors and assessors
  without a compile-time dependency on any subsystem module.

  Plain functions over data — no process. Every public function takes the
  registry as an optional argument (defaulting to config) so callers and tests
  can inject one explicitly, keeping tests async-safe.

  Invocation is defensive by contract: a contributor runs while something is
  already wrong, so `gather/3` wraps the call and degrades a missing, crashing,
  or misbehaving contributor to `%{}` rather than letting it break capture.
  """
  alias MediaCentaur.ErrorReports.IncidentContext

  @type component :: atom()
  @type registry :: %{optional(component()) => module()}

  @doc "The configured `component => module` registry (defaults to `%{}`)."
  @spec registry() :: registry()
  def registry, do: Application.get_env(:media_centaur, :diagnostics_contributors, %{})

  @doc "The implementation module registered for `component`, or `nil`."
  @spec module_for(component(), registry()) :: module() | nil
  def module_for(component, registry \\ registry()), do: Map.get(registry, component)

  @doc """
  Invokes the `component`'s `gather/1` with `ids`, returning its context map.

  Returns `%{}` when no module is registered, the module doesn't implement
  `gather/1`, or the call raises/exits/throws or returns a non-map — a
  contributor must never break the incident it's describing.
  """
  @spec gather(component(), IncidentContext.ids(), registry()) :: map()
  def gather(component, ids, registry \\ registry()) do
    with module when is_atom(module) and not is_nil(module) <- Map.get(registry, component),
         true <- function_exported?(module, :gather, 1),
         result when is_map(result) <- safe_gather(module, ids) do
      result
    else
      _ -> %{}
    end
  end

  @doc """
  The `{component, module}` pairs whose modules implement `assess/0` — the set
  the periodic evaluator polls.
  """
  @spec assessors(registry()) :: [{component(), module()}]
  def assessors(registry \\ registry()) do
    Enum.filter(registry, fn {_component, module} ->
      is_atom(module) and function_exported?(module, :assess, 0)
    end)
  end

  defp safe_gather(module, ids) do
    module.gather(ids)
  rescue
    _ -> %{}
  catch
    _, _ -> %{}
  end

  @vitals_timeout_ms 250

  @doc """
  Gathers `vitals/0` from every registered module that implements it, returning
  `%{component => vitals_map}`. Runs the probes concurrently with a per-probe
  timeout; a missing, slow, crashing, or non-map probe records `"unavailable"`
  so one dead subsystem can't block or break the snapshot.
  """
  @spec all_vitals(registry()) :: %{optional(component()) => map() | binary()}
  def all_vitals(registry \\ registry()) do
    sources =
      Enum.filter(registry, fn {_component, module} ->
        is_atom(module) and function_exported?(module, :vitals, 0)
      end)

    results =
      sources
      |> Task.async_stream(fn {_component, module} -> safe_vitals(module) end,
        timeout: @vitals_timeout_ms,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.to_list()

    # ordered: true keeps results aligned with `sources`, so a timed-out probe
    # (`{:exit, _}`) maps back to its component as "unavailable".
    sources
    |> Enum.zip(results)
    |> Map.new(fn
      {{component, _module}, {:ok, vitals}} -> {component, vitals}
      {{component, _module}, {:exit, _reason}} -> {component, "unavailable"}
    end)
  end

  defp safe_vitals(module) do
    case module.vitals() do
      vitals when is_map(vitals) -> vitals
      _ -> "unavailable"
    end
  rescue
    _ -> "unavailable"
  catch
    _, _ -> "unavailable"
  end
end
