defmodule MediaCentaur.Library.FileTrackerTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library.{
    Entity,
    Episode,
    Extra,
    FileTracker,
    Image,
    Movie,
    Season,
    WatchedFile
  }

  describe "cleanup_removed_files/1" do
    test "deletes WatchedFile and standalone movie entity when file removed" do
      entity =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/blade_runner.mkv"
        })

      _file =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/movies/blade_runner.mkv",
          watch_dir: "/media/movies"
        })

      entity_ids = FileTracker.cleanup_removed_files(["/media/movies/blade_runner.mkv"])

      assert entity_ids == [entity.id]
      assert Ash.read!(WatchedFile) == []
      assert Ash.read!(Entity) == []
    end

    test "deletes episode and keeps TV series when one episode removed" do
      entity = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

      season =
        create_season(%{
          entity_id: entity.id,
          season_number: 1,
          name: "Season 1",
          number_of_episodes: 2
        })

      ep1 =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/media/tv/bb/s01e01.mkv"
        })

      _ep2 =
        create_episode(%{
          season_id: season.id,
          episode_number: 2,
          name: "Cat's in the Bag",
          content_url: "/media/tv/bb/s01e02.mkv"
        })

      _file1 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/tv/bb/s01e01.mkv",
          watch_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/tv/bb/s01e02.mkv",
          watch_dir: "/media/tv"
        })

      entity_ids = FileTracker.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      assert entity_ids == [entity.id]

      # Episode 1 is gone
      assert {:error, _} = Ash.get(Episode, ep1.id)

      # Episode 2, season, and entity remain
      remaining_episodes = Ash.read!(Episode)
      assert length(remaining_episodes) == 1
      assert hd(remaining_episodes).episode_number == 2

      assert {:ok, _} = Ash.get(Season, season.id)
      assert {:ok, _} = Ash.get(Entity, entity.id)

      # Only 1 WatchedFile remains
      assert length(Ash.read!(WatchedFile)) == 1
    end

    test "deletes empty season when all its episodes are removed" do
      entity = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

      season =
        create_season(%{
          entity_id: entity.id,
          season_number: 1,
          name: "Season 1",
          number_of_episodes: 1
        })

      _ep =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/media/tv/bb/s01e01.mkv"
        })

      _file =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/tv/bb/s01e01.mkv",
          watch_dir: "/media/tv"
        })

      # Add a second season to keep the entity alive
      season2 =
        create_season(%{
          entity_id: entity.id,
          season_number: 2,
          name: "Season 2",
          number_of_episodes: 1
        })

      _ep2 =
        create_episode(%{
          season_id: season2.id,
          episode_number: 1,
          name: "Seven Thirty-Seven",
          content_url: "/media/tv/bb/s02e01.mkv"
        })

      _file2 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/tv/bb/s02e01.mkv",
          watch_dir: "/media/tv"
        })

      FileTracker.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      # Season 1 should be gone (empty), season 2 should remain
      assert {:error, _} = Ash.get(Season, season.id)
      assert {:ok, _} = Ash.get(Season, season2.id)
      assert {:ok, _} = Ash.get(Entity, entity.id)
    end

    test "deletes entire TV series when all files removed" do
      entity = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

      season =
        create_season(%{
          entity_id: entity.id,
          season_number: 1,
          name: "Season 1",
          number_of_episodes: 1
        })

      _ep =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/media/tv/bb/s01e01.mkv"
        })

      _file =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/tv/bb/s01e01.mkv",
          watch_dir: "/media/tv"
        })

      FileTracker.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      assert Ash.read!(Entity) == []
      assert Ash.read!(Season) == []
      assert Ash.read!(Episode) == []
      assert Ash.read!(WatchedFile) == []
    end

    test "deletes child movie from movie series, keeps series with 2+ remaining" do
      entity = create_entity(%{type: :movie_series, name: "Dark Knight Trilogy"})

      movie1 =
        create_movie(%{
          entity_id: entity.id,
          name: "Batman Begins",
          tmdb_id: "272",
          content_url: "/media/movies/batman_begins.mkv",
          position: 0
        })

      _movie2 =
        create_movie(%{
          entity_id: entity.id,
          name: "The Shadowy Sentinel",
          tmdb_id: "155",
          content_url: "/media/movies/dark_knight.mkv",
          position: 1
        })

      _movie3 =
        create_movie(%{
          entity_id: entity.id,
          name: "The Shadowy Sentinel Rises",
          tmdb_id: "49026",
          content_url: "/media/movies/dark_knight_rises.mkv",
          position: 2
        })

      _file1 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/movies/batman_begins.mkv",
          watch_dir: "/media/movies"
        })

      _file2 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/movies/dark_knight.mkv",
          watch_dir: "/media/movies"
        })

      _file3 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/movies/dark_knight_rises.mkv",
          watch_dir: "/media/movies"
        })

      FileTracker.cleanup_removed_files(["/media/movies/batman_begins.mkv"])

      # Movie 1 is gone, series and other movies remain
      assert {:error, _} = Ash.get(Movie, movie1.id)
      assert length(Ash.read!(Movie)) == 2
      assert {:ok, _} = Ash.get(Entity, entity.id)
    end

    test "deletes extra when its file is removed" do
      entity =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/blade_runner.mkv"
        })

      extra =
        create_extra(%{
          entity_id: entity.id,
          name: "Behind the Scenes",
          content_url: "/media/movies/Extras/bts.mkv"
        })

      _file1 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/movies/blade_runner.mkv",
          watch_dir: "/media/movies"
        })

      _file2 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/movies/Extras/bts.mkv",
          watch_dir: "/media/movies"
        })

      FileTracker.cleanup_removed_files(["/media/movies/Extras/bts.mkv"])

      # Extra is gone, movie entity remains
      assert {:error, _} = Ash.get(Extra, extra.id)
      assert {:ok, _} = Ash.get(Entity, entity.id)
      assert length(Ash.read!(WatchedFile)) == 1
    end

    test "handles batch deletion of multiple files" do
      entity = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

      season =
        create_season(%{
          entity_id: entity.id,
          season_number: 1,
          name: "Season 1",
          number_of_episodes: 2
        })

      _ep1 =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/media/tv/bb/s01e01.mkv"
        })

      _ep2 =
        create_episode(%{
          season_id: season.id,
          episode_number: 2,
          name: "Cat's in the Bag",
          content_url: "/media/tv/bb/s01e02.mkv"
        })

      _file1 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/tv/bb/s01e01.mkv",
          watch_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/tv/bb/s01e02.mkv",
          watch_dir: "/media/tv"
        })

      entity_ids =
        FileTracker.cleanup_removed_files([
          "/media/tv/bb/s01e01.mkv",
          "/media/tv/bb/s01e02.mkv"
        ])

      assert entity_ids == [entity.id]
      assert Ash.read!(Entity) == []
      assert Ash.read!(Season) == []
      assert Ash.read!(Episode) == []
      assert Ash.read!(WatchedFile) == []
    end

    test "returns empty list when no matching files found" do
      assert FileTracker.cleanup_removed_files(["/nonexistent/file.mkv"]) == []
    end

    test "deletes episode images from database" do
      entity = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

      season =
        create_season(%{
          entity_id: entity.id,
          season_number: 1,
          name: "Season 1",
          number_of_episodes: 2
        })

      ep1 =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/media/tv/bb/s01e01.mkv"
        })

      _ep2 =
        create_episode(%{
          season_id: season.id,
          episode_number: 2,
          name: "Cat's in the Bag",
          content_url: "/media/tv/bb/s01e02.mkv"
        })

      _thumb =
        create_image(%{
          episode_id: ep1.id,
          role: "thumb",
          url: "https://image.tmdb.org/t/p/original/thumb.jpg",
          extension: "jpg"
        })

      _file1 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/tv/bb/s01e01.mkv",
          watch_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/tv/bb/s01e02.mkv",
          watch_dir: "/media/tv"
        })

      FileTracker.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      # Episode image should be gone
      assert Ash.read!(Image) == []
    end
  end

  describe "mark_absent_for_watch_dir/1" do
    test "marks all complete files for a watch dir as absent" do
      entity = create_entity()

      _file1 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/drive1/movie1.mkv",
          watch_dir: "/media/drive1"
        })

      _file2 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/drive1/movie2.mkv",
          watch_dir: "/media/drive1"
        })

      _file3 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/drive2/movie3.mkv",
          watch_dir: "/media/drive2"
        })

      entity_ids = FileTracker.mark_absent_for_watch_dir("/media/drive1")

      assert entity_ids == [entity.id]

      files = Ash.read!(WatchedFile)
      drive1_files = Enum.filter(files, &(&1.watch_dir == "/media/drive1"))
      drive2_files = Enum.filter(files, &(&1.watch_dir == "/media/drive2"))

      assert Enum.all?(drive1_files, &(&1.state == :absent))
      assert Enum.all?(drive1_files, &(not is_nil(&1.absent_since)))
      assert Enum.all?(drive2_files, &(&1.state == :complete))
    end

    test "returns empty list when no files match" do
      assert FileTracker.mark_absent_for_watch_dir("/nonexistent") == []
    end
  end

  describe "restore_present_files/2" do
    test "restores absent files found on disk" do
      entity = create_entity()

      file1 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/drive1/movie1.mkv",
          watch_dir: "/media/drive1"
        })

      file2 =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/drive1/movie2.mkv",
          watch_dir: "/media/drive1"
        })

      # Mark both absent
      Enum.each([file1, file2], fn file ->
        file
        |> Ash.Changeset.for_update(:mark_absent, %{})
        |> Ash.update!()
      end)

      # Only movie1 is back on disk
      entity_ids =
        FileTracker.restore_present_files("/media/drive1", ["/media/drive1/movie1.mkv"])

      assert entity_ids == [entity.id]

      files = Ash.read!(WatchedFile)
      restored = Enum.find(files, &(&1.file_path == "/media/drive1/movie1.mkv"))
      still_absent = Enum.find(files, &(&1.file_path == "/media/drive1/movie2.mkv"))

      assert restored.state == :complete
      assert is_nil(restored.absent_since)
      assert still_absent.state == :absent
    end

    test "returns empty list when no absent files match" do
      entity = create_entity()

      _file =
        create_linked_file(%{
          entity: entity,
          file_path: "/media/drive1/movie1.mkv",
          watch_dir: "/media/drive1"
        })

      assert FileTracker.restore_present_files("/media/drive1", ["/media/drive1/movie1.mkv"]) ==
               []
    end

    test "returns empty list with empty paths" do
      assert FileTracker.restore_present_files("/media/drive1", []) == []
    end
  end
end
