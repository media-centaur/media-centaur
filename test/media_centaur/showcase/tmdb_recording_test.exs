defmodule MediaCentaur.Showcase.TmdbRecordingTest do
  @moduledoc """
  The committed TMDB recording answers what the showcase seeder asks.
  A catalog entry added without re-recording (`scripts/reseed-showcase
  --record`) fails here instead of as a `not recorded` warning at seed time.
  """
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Showcase.Catalog
  alias MediaCentaur.Showcase.CatalogMatch
  alias MediaCentaur.TMDB

  setup do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
    :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, :showcase_mode, true))
    :ok
  end

  # Each answer is checked with `match?/2` first so a failure names the
  # catalog entry that is missing from the recording.
  defp recorded!(result, what) do
    assert match?({:ok, _}, result), "#{what} not recorded: #{inspect(result)}"
    {:ok, value} = result
    value
  end

  test "every catalog movie resolves to a TMDB id and a detail from the recording" do
    for %{title: title, year: year} = entry <- Catalog.movies() do
      tmdb_id =
        Map.get_lazy(entry, :tmdb_id, fn ->
          results = recorded!(TMDB.Client.search_movie(title, year), "#{title} (#{year}) search")

          recorded!(
            CatalogMatch.pick(results, title, year, "title"),
            "#{title} (#{year}) in its results"
          )
        end)

      assert %{body: %{"id" => ^tmdb_id}} =
               recorded!(TMDB.Client.detail({tmdb_id, :movie}), "#{title} detail")
    end
  end

  test "every catalog series resolves to a TMDB id, a detail and its seasons from the recording" do
    for %{title: title, year: year, seasons: seasons} <- Catalog.tv_series() do
      results = recorded!(TMDB.Client.search_tv(title, year), "#{title} (#{year}) search")

      tmdb_id =
        recorded!(CatalogMatch.pick(results, title, year, "name"), "#{title} (#{year}) in its results")

      assert %{body: %{"id" => ^tmdb_id}} =
               recorded!(TMDB.Client.detail({tmdb_id, :tv_series}), "#{title} detail")

      for season <- seasons do
        assert %{body: %{"season_number" => ^season}} =
                 recorded!(TMDB.Client.detail({:season, tmdb_id, season}), "#{title} season #{season}")
      end
    end
  end
end
