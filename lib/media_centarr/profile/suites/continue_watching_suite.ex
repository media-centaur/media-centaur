defmodule MediaCentarr.Profile.Suites.ContinueWatchingSuite do
  @moduledoc """
  Validates the projection vs. legacy DB query for Continue Watching
  (ADR-041). Compares cached and uncached read paths plus the cost
  of a projection rebuild.

  Two inputs:

    * `warm-cache` — `ContinueWatching.refresh_cache/0` is called
      first, so `Views.continue_watching/1` reads from
      `:library_view_continue_watching` (ETS).
    * `cold-fallback` — the ETS table is wiped, so
      `Views.continue_watching/1` falls through to
      `Library.list_in_progress/1` (DB). Both functions are
      timed under both inputs so the comparison is symmetric.
  """
  @behaviour MediaCentarr.Profile.Suite

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Views
  alias MediaCentarr.Library.Views.ContinueWatching

  @table :library_view_continue_watching

  @impl true
  def name, do: "Library.Views.ContinueWatching"

  @impl true
  def inputs do
    %{
      "warm-cache" => fn -> ContinueWatching.refresh_cache() end,
      "cold-fallback" => fn ->
        # Destroy the table (not just clear contents). The read function
        # checks :ets.whereis/1 and falls through to the DB query when
        # the table is absent — clearing contents would still go down
        # the ETS path and just return an empty list, which would
        # silently misreport DB fallback as "fast".
        case :ets.whereis(@table) do
          :undefined -> :ok
          _ -> :ets.delete(@table)
        end
      end
    }
  end

  @impl true
  def scenarios do
    # Refresh-cache is intentionally NOT a scenario here — it would
    # recreate the ETS table mid-bench and pollute subsequent
    # cold-fallback measurements. It gets its own suite below
    # (ContinueWatchingRefreshSuite) so cold reads stay honest.
    %{
      "Views.continue_watching/1 (limit: 30)" => fn ->
        Views.continue_watching(limit: 30)
      end,
      "Library.list_in_progress/1 (limit: 30)" => fn ->
        Library.list_in_progress(limit: 30)
      end
    }
  end
end

defmodule MediaCentarr.Profile.Suites.ContinueWatchingRefreshSuite do
  @moduledoc """
  Standalone refresh-cost measurement, isolated from the read-path
  suite so cold-fallback reads stay honest. Always operates on a
  warm cache (refresh_cache itself ensures the table exists).
  """
  @behaviour MediaCentarr.Profile.Suite

  alias MediaCentarr.Library.Views.ContinueWatching

  @impl true
  def name, do: "Library.Views.ContinueWatching.refresh_cache/0"

  @impl true
  def inputs, do: %{}

  @impl true
  def scenarios do
    %{
      "ContinueWatching.refresh_cache/0" => fn -> ContinueWatching.refresh_cache() end
    }
  end
end
