defmodule MediaCentaur.Profile.Suites.ContinueWatchingSuite do
  @moduledoc """
  Validates the projection vs. legacy DB query for Continue Watching
  (ADR-041). Compares cached and uncached read paths plus the cost
  of a projection rebuild.

  Two inputs:

    * `warm-cache` — `ContinueWatching.refresh_cache/0` is called
      first, so `Views.continue_watching/2` reads from
      `:library_view_continue_watching` (ETS).
    * `cold-fallback` — the ETS table is wiped, so
      `Views.continue_watching/2` falls through to
      `Library.list_in_progress/2` (DB). Both functions are
      timed under both inputs so the comparison is symmetric.

  Both read as the owner profile (`Profiles.owner/0`), whose rows
  `Profile.Loader` seeds.
  """
  @behaviour MediaCentaur.Profile.Suite

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Views
  alias MediaCentaur.Library.Views.ContinueWatching
  alias MediaCentaur.Profiles

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
    owner_id = Profiles.owner().id

    %{
      "Views.continue_watching/2 (limit: 30)" => fn ->
        Views.continue_watching(owner_id, limit: 30)
      end,
      "Library.list_in_progress/2 (limit: 30)" => fn ->
        Library.list_in_progress(owner_id, limit: 30)
      end
    }
  end
end
