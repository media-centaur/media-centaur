defmodule MediaCentarr.Profile.Suite do
  @moduledoc """
  Behaviour for a profiling suite (ADR-041).

  Each suite measures one projection or one cohesive set of related
  hot-path operations. Suites live under
  `MediaCentarr.Profile.Suites.*` and are auto-discovered at runtime
  by `MediaCentarr.Profile.Bench` — adding a new suite means
  dropping a new file, no central registry to edit.

  ## Required callbacks

    * `name/0` — short human-readable label (becomes the report
      section heading).
    * `inputs/0` — map of `input_name => setup_fn`. The setup fn
      runs once before the suite's scenarios for that input. Use
      this to swap between cache-warm and cache-cold conditions for
      the same set of scenarios. Return `%{}` if there are no
      inputs (the suite runs once with a noop setup).
    * `scenarios/0` — map of `scenario_name => measurement_fn`. Each
      fn is the unit of work Benchee times. Keep them tight: one
      function call per scenario, no inline data setup.

  ## Example

      defmodule MediaCentarr.Profile.Suites.ContinueWatchingSuite do
        @behaviour MediaCentarr.Profile.Suite

        alias MediaCentarr.Library
        alias MediaCentarr.Library.Views
        alias MediaCentarr.Library.Views.ContinueWatching

        def name, do: "Library.Views.ContinueWatching"

        def inputs, do: %{
          "warm-cache"    => fn -> ContinueWatching.refresh_cache() end,
          "cold-fallback" => fn -> :ets.delete_all_objects(:library_view_continue_watching) end
        }

        def scenarios, do: %{
          "Views.continue_watching/1 (limit: 30)" =>
            fn -> Views.continue_watching(limit: 30) end,
          "Library.list_in_progress/1 (limit: 30)" =>
            fn -> Library.list_in_progress(limit: 30) end
        }
      end
  """

  @type setup_fn :: (-> any())
  @type measurement_fn :: (-> any())

  @callback name() :: String.t()
  @callback inputs() :: %{optional(String.t()) => setup_fn()}
  @callback scenarios() :: %{required(String.t()) => measurement_fn()}
end
