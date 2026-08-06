defmodule MediaCentaur.Library.FileEventHandlerTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{FileEventHandler, FilePresence, PlayableItem}
  alias MediaCentaur.Repo

  describe "cleanup_removed_files/1" do
    test "deletes WatchedFile and standalone movie entity when file removed" do
      movie =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/sample_movie.mkv"
        })

      _file =
        create_linked_file(%{
          movie_id: movie.id,
          file_path: "/media/movies/sample_movie.mkv",
          media_dir: "/media/movies"
        })

      entity_ids = FileEventHandler.cleanup_removed_files(["/media/movies/sample_movie.mkv"])

      assert entity_ids == [movie.id]
      assert Library.Files.list_all() == []
      assert Library.Containers.list(:movie) == []
    end

    test "also deletes the FilePresence row for the removed file" do
      # Regression: leaving the presence row behind after a title is
      # deleted (via the LiveView delete flow, which routes through this
      # function) meant `Watcher.Supervisor.rescan_unlinked/0` would later
      # treat it as "stranded" and resurrect the deleted title from a
      # file that no longer exists.
      movie =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/deleted_movie.mkv"
        })

      _file =
        create_linked_file(%{
          movie_id: movie.id,
          file_path: "/media/movies/deleted_movie.mkv",
          media_dir: "/media/movies"
        })

      assert MapSet.member?(
               FilePresence.list_paths_for_media_dir("/media/movies"),
               "/media/movies/deleted_movie.mkv"
             )

      FileEventHandler.cleanup_removed_files(["/media/movies/deleted_movie.mkv"])

      refute MapSet.member?(
               FilePresence.list_paths_for_media_dir("/media/movies"),
               "/media/movies/deleted_movie.mkv"
             )
    end

    test "deletes episode and keeps TV series when one episode removed" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})

      season =
        create_season(%{
          tv_series_id: tv_series.id,
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
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e01.mkv",
          media_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e02.mkv",
          media_dir: "/media/tv"
        })

      entity_ids = FileEventHandler.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      assert entity_ids == [tv_series.id]

      # Episode 1 is gone
      assert {:error, _} = Library.Episodes.fetch(ep1.id)

      # Episode 2, season, and TV series remain
      remaining_episodes = Library.Episodes.list_all()
      assert length(remaining_episodes) == 1
      assert hd(remaining_episodes).episode_number == 2

      assert {:ok, _} = Library.Seasons.fetch(season.id)
      assert {:ok, _} = Library.Containers.fetch(:tv_series, tv_series.id)

      # Only 1 WatchedFile remains
      assert length(Library.Files.list_all()) == 1
    end

    test "also deletes the removed episode's PlayableItem row" do
      # Regression: partial-deletion (one episode's file removed, season/series
      # survive) destroyed the Episode row but never cleaned up its
      # PlayableItem — unlike full-series destroy (EntityCascade), which
      # already does. 414 orphaned PlayableItem(episode) rows were found
      # live, leaking since May — this is the actual leak, not just
      # resurrection-incident fallout.
      tv_series = create_entity(%{type: :tv_series, name: "PlayableItem Leak Show"})

      season =
        create_season(%{
          tv_series_id: tv_series.id,
          season_number: 1,
          name: "Season 1",
          number_of_episodes: 1
        })

      ep1 =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/media/tv/leak/s01e01.mkv"
        })

      file1 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/leak/s01e01.mkv",
          media_dir: "/media/tv"
        })

      playable_item_id = file1.playable_item_id

      FileEventHandler.cleanup_removed_files(["/media/tv/leak/s01e01.mkv"])

      assert {:error, _} = Library.Episodes.fetch(ep1.id)
      assert Repo.get(PlayableItem, playable_item_id) == nil
    end

    test "deletes episode with recorded watch progress without FK violation" do
      # Regression: deleting one file from a surviving TV series crashed with
      # FOREIGN KEY constraint failed when the removed episode had a row in
      # library_watch_progress. The partial-deletion path did not destroy
      # watch progress before bulk-deleting the episode.
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show Thirteen"})

      season =
        create_season(%{
          tv_series_id: tv_series.id,
          season_number: 1,
          name: "Season 1",
          number_of_episodes: 2
        })

      ep1 =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/media/tv/pluribus/s01e01.mkv"
        })

      _ep2 =
        create_episode(%{
          season_id: season.id,
          episode_number: 2,
          name: "Part Two",
          content_url: "/media/tv/pluribus/s01e02.mkv"
        })

      _file1 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/pluribus/s01e01.mkv",
          media_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/pluribus/s01e02.mkv",
          media_dir: "/media/tv"
        })

      _progress =
        create_watch_progress(%{
          episode_id: ep1.id,
          position_seconds: 120.0,
          duration_seconds: 1800.0
        })

      # Before the fix, this raised Exqlite.Error "FOREIGN KEY constraint failed"
      # on DELETE FROM library_episodes, because library_watch_progress.episode_id
      # still referenced ep1.
      entity_ids =
        FileEventHandler.cleanup_removed_files(["/media/tv/pluribus/s01e01.mkv"])

      assert entity_ids == [tv_series.id]
      assert {:error, _} = Library.Episodes.fetch(ep1.id)
      assert {:error, :not_found} = Library.ProgressRecords.fetch_for_container(:episode, ep1.id)
      assert {:ok, _} = Library.Containers.fetch(:tv_series, tv_series.id)
    end

    test "deletes empty season when all its episodes are removed" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})

      season =
        create_season(%{
          tv_series_id: tv_series.id,
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
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e01.mkv",
          media_dir: "/media/tv"
        })

      # Add a second season to keep the entity alive
      season2 =
        create_season(%{
          tv_series_id: tv_series.id,
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
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s02e01.mkv",
          media_dir: "/media/tv"
        })

      FileEventHandler.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      # Season 1 should be gone (empty), season 2 should remain
      assert {:error, _} = Library.Seasons.fetch(season.id)
      assert {:ok, _} = Library.Seasons.fetch(season2.id)
      assert {:ok, _} = Library.Containers.fetch(:tv_series, tv_series.id)
    end

    test "deletes entire TV series when all files removed" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})

      season =
        create_season(%{
          tv_series_id: tv_series.id,
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
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e01.mkv",
          media_dir: "/media/tv"
        })

      FileEventHandler.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      assert Library.Seasons.list_all() == []
      assert Library.Episodes.list_all() == []
      assert Library.Files.list_all() == []
    end

    test "deletes child movie from movie series, keeps series with 2+ remaining" do
      movie_series = create_entity(%{type: :movie_series, name: "Sample Movie Series"})

      movie1 =
        create_movie(%{
          movie_series_id: movie_series.id,
          name: "Sample Movie One",
          tmdb_id: "272",
          content_url: "/media/movies/sample_movie_one.mkv",
          position: 0
        })

      _movie2 =
        create_movie(%{
          movie_series_id: movie_series.id,
          name: "Sample Movie Two",
          tmdb_id: "155",
          content_url: "/media/movies/sample_movie_two.mkv",
          position: 1
        })

      _movie3 =
        create_movie(%{
          movie_series_id: movie_series.id,
          name: "Sample Movie Three",
          tmdb_id: "49026",
          content_url: "/media/movies/sample_movie_three.mkv",
          position: 2
        })

      _file1 =
        create_linked_file(%{
          movie_series_id: movie_series.id,
          file_path: "/media/movies/sample_movie_one.mkv",
          media_dir: "/media/movies"
        })

      _file2 =
        create_linked_file(%{
          movie_series_id: movie_series.id,
          file_path: "/media/movies/sample_movie_two.mkv",
          media_dir: "/media/movies"
        })

      _file3 =
        create_linked_file(%{
          movie_series_id: movie_series.id,
          file_path: "/media/movies/sample_movie_three.mkv",
          media_dir: "/media/movies"
        })

      FileEventHandler.cleanup_removed_files(["/media/movies/sample_movie_one.mkv"])

      # Movie 1 is gone, series and other movies remain
      assert {:error, _} = Library.Containers.fetch(:movie, movie1.id)
      assert length(Library.Containers.list(:movie)) == 2
      assert {:ok, _} = Library.Containers.fetch(:movie_series, movie_series.id)
    end

    test "deletes extra when its file is removed" do
      movie =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/sample_movie.mkv"
        })

      extra =
        create_extra(%{
          movie_id: movie.id,
          name: "Behind the Scenes",
          content_url: "/media/movies/Extras/bts.mkv"
        })

      _file1 =
        create_linked_file(%{
          movie_id: movie.id,
          file_path: "/media/movies/sample_movie.mkv",
          media_dir: "/media/movies"
        })

      _file2 =
        create_linked_file(%{
          movie_id: movie.id,
          file_path: "/media/movies/Extras/bts.mkv",
          media_dir: "/media/movies"
        })

      FileEventHandler.cleanup_removed_files(["/media/movies/Extras/bts.mkv"])

      # Extra is gone, movie entity remains
      assert {:error, _} = Library.Extras.fetch(extra.id)
      assert {:ok, _} = Library.Containers.fetch(:movie, movie.id)
      assert length(Library.Files.list_all()) == 1
    end

    test "handles batch deletion of multiple files" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})

      season =
        create_season(%{
          tv_series_id: tv_series.id,
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
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e01.mkv",
          media_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e02.mkv",
          media_dir: "/media/tv"
        })

      entity_ids =
        FileEventHandler.cleanup_removed_files([
          "/media/tv/bb/s01e01.mkv",
          "/media/tv/bb/s01e02.mkv"
        ])

      assert entity_ids == [tv_series.id]
      assert Library.Seasons.list_all() == []
      assert Library.Episodes.list_all() == []
      assert Library.Files.list_all() == []
    end

    test "returns empty list when no matching files found" do
      assert FileEventHandler.cleanup_removed_files(["/nonexistent/file.mkv"]) == []
    end

    test "deletes episode images from database" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})

      season =
        create_season(%{
          tv_series_id: tv_series.id,
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
          content_url: "#{ep1.id}/thumb.jpg",
          extension: "jpg"
        })

      _file1 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e01.mkv",
          media_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e02.mkv",
          media_dir: "/media/tv"
        })

      FileEventHandler.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      # Episode image should be gone
      assert Library.Images.list_all() == []
    end
  end

  describe "delete_files/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "delete_files_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      %{tmp_dir: tmp_dir}
    end

    defp seed_movie_file(tmp_dir, name) do
      file_path = Path.join(tmp_dir, name)
      File.write!(file_path, "sample content")

      movie = create_entity(%{type: :movie, name: "Movie #{name}", content_url: file_path})
      create_linked_file(%{movie_id: movie.id, file_path: file_path, media_dir: tmp_dir})

      {movie, file_path}
    end

    test "removes the whole batch with one cleanup pass and one broadcast", %{tmp_dir: tmp_dir} do
      {movie_a, path_a} = seed_movie_file(tmp_dir, "movie_a.mkv")
      {movie_b, path_b} = seed_movie_file(tmp_dir, "movie_b.mkv")

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())

      assert {:ok, entity_ids} = FileEventHandler.delete_files([path_a, path_b])
      assert Enum.sort(entity_ids) == Enum.sort([movie_a.id, movie_b.id])

      refute File.exists?(path_a)
      refute File.exists?(path_b)
      assert Library.Files.list_all() == []
      assert Library.Containers.list(:movie) == []

      # The whole batch lands as a single entities_changed broadcast.
      assert_receive {:entities_changed, %{entity_ids: broadcast_ids}}
      assert Enum.sort(broadcast_ids) == Enum.sort([movie_a.id, movie_b.id])
      refute_receive {:entities_changed, _payload}
    end

    test "treats already-absent files as deleted and still cleans their records", %{
      tmp_dir: tmp_dir
    } do
      absent_path = Path.join(tmp_dir, "already_gone.mkv")
      movie = create_entity(%{type: :movie, name: "Gone Movie", content_url: absent_path})
      create_linked_file(%{movie_id: movie.id, file_path: absent_path, media_dir: tmp_dir})

      assert {:ok, [entity_id]} = FileEventHandler.delete_files([absent_path])
      assert entity_id == movie.id
      assert Library.Files.list_all() == []
    end

    test "reports a real failure but still deletes and cleans the rest of the batch", %{
      tmp_dir: tmp_dir
    } do
      {_movie, good_path} = seed_movie_file(tmp_dir, "deletable.mkv")

      # File.rm on a non-empty directory fails without removing it.
      stubborn_path = Path.join(tmp_dir, "not_a_file")
      File.mkdir_p!(Path.join(stubborn_path, "child"))

      assert {:error, _reason} = FileEventHandler.delete_files([stubborn_path, good_path])

      refute File.exists?(good_path)
      assert File.dir?(stubborn_path)
      # The deletable file's records were cleaned despite the batch failure.
      assert Library.Files.list_all() == []
      assert Library.Containers.list(:movie) == []
    end
  end
end
