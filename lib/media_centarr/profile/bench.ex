if Mix.env() in [:dev, :test] do
  defmodule MediaCentarr.Profile.Bench do
    @moduledoc """
    Benchee runner for `MediaCentarr.Profile.Suite` implementations.

    Compiled only under `:dev` and `:test` because Benchee is a dev/test-only
    dependency — pattern-matching on `%Benchee.Suite{}` at module-expansion
    time would otherwise fail the prod build.

    Discovers suites at runtime via `Application.spec/2` so adding a
    new projection's suite is one new file under
    `lib/media_centarr/profile/suites/` — no central registry.

    ## Per-input setup, not per-scenario value

    Benchee's built-in `inputs:` option passes a value to each
    scenario. Our suite contract uses inputs differently — they are
    *setup hooks* that prepare the world (e.g. warm vs cold ETS
    cache) before timing the same set of scenarios. We model that
    by calling `Benchee.run/2` once per input, calling the input's
    setup function first.

    ## Output shape

        %{
          suite: "Library.Views.ContinueWatching",
          runs: [
            %{
              input: "warm-cache",
              scenarios: [
                %{name: "Views.continue_watching/1", stats: %{...}},
                %{name: "Library.list_in_progress/1", stats: %{...}}
              ]
            },
            %{input: "cold-fallback", scenarios: [...]}
          ]
        }

    This is what `Profile.Reporter` consumes.
    """

    alias MediaCentarr.Profile.Suite

    @benchee_opts [
      warmup: 2,
      time: 5,
      memory_time: 1,
      formatters: [],
      print: %{benchmarking: false, configuration: false, fast_warning: false}
    ]

    @doc "Returns the discovered suite modules in stable name order."
    @spec suites() :: [module()]
    def suites do
      :media_centarr
      |> Application.spec(:modules)
      |> Kernel.||([])
      |> Enum.filter(&suite_module?/1)
      |> Enum.sort_by(& &1.name())
    end

    @doc "Runs every discovered suite. Returns one result map per suite."
    @spec run_all() :: [map()]
    def run_all, do: Enum.map(suites(), &run_suite/1)

    @doc "Runs a single suite across each of its inputs."
    @spec run_suite(module()) :: map()
    def run_suite(module) do
      inputs = normalise_inputs(module.inputs())
      scenarios = module.scenarios()

      runs =
        Enum.map(inputs, fn {input_name, setup_fn} ->
          setup_fn.()
          benchee_result = Benchee.run(scenarios, @benchee_opts)
          %{input: input_name, scenarios: extract_scenarios(benchee_result)}
        end)

      %{suite: module.name(), runs: runs}
    end

    defp normalise_inputs(inputs) when map_size(inputs) == 0 do
      [{"default", fn -> :ok end}]
    end

    defp normalise_inputs(inputs), do: Enum.to_list(inputs)

    defp extract_scenarios(%Benchee.Suite{scenarios: scenarios}) do
      Enum.map(scenarios, fn scenario ->
        %{
          name: scenario.name,
          stats: extract_stats(scenario.run_time_data.statistics),
          memory: extract_memory(scenario.memory_usage_data)
        }
      end)
    end

    defp extract_stats(%Benchee.Statistics{} = stats) do
      %{
        ips: stats.ips || safe_div(1_000_000_000, stats.average),
        average_ns: stats.average,
        median_ns: stats.median,
        p99_ns: get_percentile(stats, 99),
        min_ns: stats.minimum,
        max_ns: stats.maximum,
        sample_size: Map.get(stats, :sample_size)
      }
    end

    defp extract_memory(%{statistics: %Benchee.Statistics{average: avg}}) when is_number(avg), do: avg

    defp extract_memory(_), do: nil

    defp get_percentile(%Benchee.Statistics{percentiles: percentiles}, p) when is_map(percentiles) do
      Map.get(percentiles, p) || Map.get(percentiles, p / 1)
    end

    defp get_percentile(_, _), do: nil

    defp safe_div(_, +0.0), do: 0.0
    defp safe_div(_, 0), do: 0.0
    defp safe_div(num, denom), do: num / denom

    defp suite_module?(mod) do
      mod_str = Atom.to_string(mod)

      String.starts_with?(mod_str, "Elixir.MediaCentarr.Profile.Suites.") and
        Code.ensure_loaded?(mod) and
        function_exported?(mod, :name, 0) and
        function_exported?(mod, :inputs, 0) and
        function_exported?(mod, :scenarios, 0) and
        Suite in Keyword.get(mod.module_info(:attributes), :behaviour, [])
    end
  end
end
