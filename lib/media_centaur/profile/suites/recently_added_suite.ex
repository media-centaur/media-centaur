defmodule MediaCentaur.Profile.Suites.RecentlyAddedSuite do
  @moduledoc """
  Validates the projection vs. legacy DB query for Recently Added
  (ADR-041). Compares cached and uncached read paths.

  Two inputs:

    * `warm-cache` — `RecentlyAdded.refresh_cache/0` is called first,
      so `Views.recently_added/1` reads from
      `:library_view_recently_added` (ETS).
    * `cold-fallback` — the ETS table is wiped, so
      `Views.recently_added/1` falls through to
      `Library.list_recently_added/1` (DB).
  """
  @behaviour MediaCentaur.Profile.Suite

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Views
  alias MediaCentaur.Library.Views.RecentlyAdded

  @table :library_view_recently_added

  @impl true
  def name, do: "Library.Views.RecentlyAdded"

  @impl true
  def inputs do
    %{
      "warm-cache" => fn -> RecentlyAdded.refresh_cache() end,
      "cold-fallback" => fn ->
        case :ets.whereis(@table) do
          :undefined -> :ok
          _ -> :ets.delete(@table)
        end
      end
    }
  end

  @impl true
  def scenarios do
    %{
      "Views.recently_added/1 (limit: 30)" => fn ->
        Views.recently_added(limit: 30)
      end,
      "Library.list_recently_added/1 (limit: 30)" => fn ->
        Library.list_recently_added(limit: 30)
      end
    }
  end
end
