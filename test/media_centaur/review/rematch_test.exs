defmodule MediaCentaur.Review.RematchTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library
  alias MediaCentaur.Review
  alias MediaCentaur.Review.Rematch

  setup do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.review_updates())
    :ok
  end

  describe "rematch_entity/1" do
    test "rematch movie: entity destroyed, PendingFile created with parsed metadata" do
      entity =
        create_entity(%{
          type: :movie,
          name: "Wrong Movie",
          content_url: "/media/movies/Sample Movie (2017).mkv"
        })

      create_linked_file(%{
        entity: entity,
        file_path: "/media/movies/Sample Movie (2017).mkv",
        watch_dir: "/media/movies"
      })

      assert {:ok, 1} = Rematch.rematch_entity(entity.id)

      # Entity destroyed
      assert {:error, _} = Library.get_entity(entity.id)

      # WatchedFiles destroyed
      assert Library.list_watched_files_for_entity!(entity.id) == []

      # PendingFile created with parsed metadata
      [pending] = Review.fetch_pending_files()
      assert pending.file_path == "/media/movies/Sample Movie (2017).mkv"
      assert pending.watch_directory == "/media/movies"
      # Parser extracts "Sample Movie" as title, 2049 as year (from filename pattern)
      assert pending.parsed_title == "Sample Movie"
      assert pending.parsed_year == 2049
      assert pending.parsed_type == "movie"

      # PubSub broadcasts
      assert_received {:entities_changed, [_entity_id]}
      assert_received {:file_added, _pending_file_id}
    end

    test "rematch TV series: all WatchedFiles become PendingFiles" do
      entity = create_entity(%{type: :tv_series, name: "Wrong Show"})
      season = create_season(%{entity_id: entity.id, season_number: 1, number_of_episodes: 2})

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E01.mkv"
      })

      create_episode(%{
        season_id: season.id,
        episode_number: 2,
        name: "Second",
        content_url: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E02.mkv"
      })

      create_identifier(%{entity_id: entity.id, property_id: "tmdb", value: "wrong"})

      create_linked_file(%{
        entity: entity,
        file_path: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E01.mkv",
        watch_dir: "/media/tv"
      })

      create_linked_file(%{
        entity: entity,
        file_path: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E02.mkv",
        watch_dir: "/media/tv"
      })

      assert {:ok, 2} = Rematch.rematch_entity(entity.id)

      # Entity fully destroyed
      assert {:error, _} = Library.get_entity(entity.id)
      assert Library.list_seasons_for_entity!(entity.id) == []
      # Identifiers deleted with entity cascade

      # PendingFiles created
      pending_files = Review.fetch_pending_files()
      assert length(pending_files) == 2

      paths = Enum.map(pending_files, & &1.file_path) |> Enum.sort()

      assert paths == [
               "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E01.mkv",
               "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E02.mkv"
             ]

      # All are TV type with parsed season/episode
      Enum.each(pending_files, fn file ->
        assert file.parsed_type == "tv"
        assert file.season_number == 1
      end)

      # PubSub broadcasts
      assert_received {:entities_changed, [_entity_id]}
      assert_received {:file_added, _}
      assert_received {:file_added, _}
    end

    test "returns {:error, :no_files} when entity has no watched files" do
      entity = create_entity(%{type: :movie, name: "Orphan"})
      assert {:error, :no_files} = Rematch.rematch_entity(entity.id)
    end

    test "returns {:error, :not_found} when entity does not exist" do
      assert {:error, :not_found} = Rematch.rematch_entity(Ash.UUID.generate())
    end
  end
end
