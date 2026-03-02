defmodule MediaCentaur.LibraryBrowserTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.LibraryBrowser

  describe "fetch_entities/0" do
    test "includes a standalone movie with a linked file" do
      entity = create_entity(%{type: :movie, name: "Standalone Movie"})
      create_linked_file(%{entity: entity})

      results = LibraryBrowser.fetch_entities()

      assert [%{entity: fetched, progress: nil}] = results
      assert fetched.id == entity.id
      assert fetched.type == :movie
    end

    test "includes a TV series with sorted seasons and episodes" do
      entity = create_entity(%{type: :tv_series, name: "Test Show"})
      create_linked_file(%{entity: entity})

      season2 = create_season(%{entity_id: entity.id, season_number: 2, name: "Season 2"})
      season1 = create_season(%{entity_id: entity.id, season_number: 1, name: "Season 1"})

      create_episode(%{season_id: season2.id, episode_number: 1, name: "S2E1"})
      create_episode(%{season_id: season1.id, episode_number: 2, name: "S1E2"})
      create_episode(%{season_id: season1.id, episode_number: 1, name: "S1E1"})

      [%{entity: fetched}] = LibraryBrowser.fetch_entities()

      assert fetched.type == :tv_series
      assert [first_season, second_season] = fetched.seasons
      assert first_season.season_number == 1
      assert second_season.season_number == 2

      episode_numbers = Enum.map(first_season.episodes, & &1.episode_number)
      assert episode_numbers == [1, 2]
    end

    test "unwraps a movie_series with a single child into a flat movie" do
      entity = create_entity(%{type: :movie_series, name: "Series Name"})
      create_linked_file(%{entity: entity})
      create_movie(%{entity_id: entity.id, name: "Only Child", position: 0})

      [%{entity: fetched}] = LibraryBrowser.fetch_entities()

      assert fetched.type == :movie
      assert fetched.name == "Only Child"
      assert fetched.movies == []
    end

    test "preserves a movie_series with multiple children" do
      entity = create_entity(%{type: :movie_series, name: "Trilogy"})
      create_linked_file(%{entity: entity})
      create_movie(%{entity_id: entity.id, name: "Part 1", position: 0})
      create_movie(%{entity_id: entity.id, name: "Part 2", position: 1})

      [%{entity: fetched}] = LibraryBrowser.fetch_entities()

      assert fetched.type == :movie_series
      assert fetched.name == "Trilogy"
      assert length(fetched.movies) == 2
    end

    test "excludes entities where all watched files are absent" do
      entity = create_entity(%{type: :movie, name: "Gone Movie"})
      file = create_linked_file(%{entity: entity})
      MediaCentaur.Library.mark_file_absent!(file)

      assert [] = LibraryBrowser.fetch_entities()
    end
  end
end
