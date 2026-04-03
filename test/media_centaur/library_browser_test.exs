defmodule MediaCentaur.LibraryBrowserTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.LibraryBrowser
  alias MediaCentaur.Watcher.FilePresence

  # Creates a linked file and registers it as present in watcher_files,
  # which the typed queries require for the EXISTS join.
  defp create_present_file(attrs) do
    file = create_linked_file(attrs)
    FilePresence.record_file(file.file_path, file.watch_dir)
    file
  end

  describe "fetch_all_typed_entries/0" do
    test "includes a standalone movie with a linked file" do
      movie = create_standalone_movie(%{name: "Standalone Movie"})
      create_present_file(%{movie_id: movie.id})

      results = LibraryBrowser.fetch_all_typed_entries()

      assert [%{entity: fetched, progress: nil}] = results
      assert fetched.id == movie.id
      assert fetched.type == :movie
    end

    test "includes a TV series with sorted seasons and episodes" do
      series = create_tv_series(%{name: "Test Show"})
      create_present_file(%{tv_series_id: series.id})

      season2 = create_season(%{tv_series_id: series.id, season_number: 2, name: "Season 2"})
      season1 = create_season(%{tv_series_id: series.id, season_number: 1, name: "Season 1"})

      create_episode(%{season_id: season2.id, episode_number: 1, name: "S2E1"})
      create_episode(%{season_id: season1.id, episode_number: 2, name: "S1E2"})
      create_episode(%{season_id: season1.id, episode_number: 1, name: "S1E1"})

      [%{entity: fetched}] = LibraryBrowser.fetch_all_typed_entries()

      assert fetched.type == :tv_series
      assert [first_season, second_season] = fetched.seasons
      assert first_season.season_number == 1
      assert second_season.season_number == 2

      episode_numbers = Enum.map(first_season.episodes, & &1.episode_number)
      assert episode_numbers == [1, 2]
    end

    test "unwraps a movie_series with a single child into a flat movie" do
      series = create_movie_series(%{name: "Series Name"})
      create_present_file(%{movie_series_id: series.id})
      create_movie(%{movie_series_id: series.id, name: "Only Child", position: 0})

      [%{entity: fetched}] = LibraryBrowser.fetch_all_typed_entries()

      assert fetched.type == :movie
      assert fetched.name == "Only Child"
      assert fetched.movies == []
    end

    test "preserves a movie_series with multiple children" do
      series = create_movie_series(%{name: "Trilogy"})
      create_present_file(%{movie_series_id: series.id})
      create_movie(%{movie_series_id: series.id, name: "Part 1", position: 0})
      create_movie(%{movie_series_id: series.id, name: "Part 2", position: 1})

      [%{entity: fetched}] = LibraryBrowser.fetch_all_typed_entries()

      assert fetched.type == :movie_series
      assert fetched.name == "Trilogy"
      assert length(fetched.movies) == 2
    end

    test "excludes entities where all watched files are absent" do
      movie = create_standalone_movie(%{name: "Gone Movie"})
      file = create_present_file(%{movie_id: movie.id})

      FilePresence.mark_files_absent([file.file_path])

      assert [] = LibraryBrowser.fetch_all_typed_entries()
    end
  end

  describe "fetch_typed_entries_by_ids/1" do
    test "fetches a specific entry by ID" do
      movie = create_standalone_movie(%{name: "Target Movie"})
      create_present_file(%{movie_id: movie.id})

      other = create_standalone_movie(%{name: "Other Movie"})
      create_present_file(%{movie_id: other.id})

      {entries, gone_ids} = LibraryBrowser.fetch_typed_entries_by_ids([movie.id])

      assert [%{entity: fetched}] = entries
      assert fetched.id == movie.id
      assert MapSet.size(gone_ids) == 0
    end

    test "returns gone_ids for destroyed entries" do
      missing_id = Ecto.UUID.generate()

      {entries, gone_ids} = LibraryBrowser.fetch_typed_entries_by_ids([missing_id])

      assert entries == []
      assert MapSet.member?(gone_ids, missing_id)
    end

    test "excludes absent entries and includes them in gone_ids" do
      movie = create_standalone_movie(%{name: "Absent Movie"})
      file = create_present_file(%{movie_id: movie.id})

      FilePresence.mark_files_absent([file.file_path])

      {entries, gone_ids} = LibraryBrowser.fetch_typed_entries_by_ids([movie.id])

      assert entries == []
      assert MapSet.member?(gone_ids, movie.id)
    end
  end
end
