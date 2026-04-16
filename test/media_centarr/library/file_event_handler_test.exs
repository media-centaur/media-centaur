defmodule MediaCentarr.Library.FileEventHandlerTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.FileEventHandler

  describe "cleanup_removed_files/1" do
    test "deletes WatchedFile and standalone movie entity when file removed" do
      movie =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/blade_runner.mkv"
        })

      _file =
        create_linked_file(%{
          movie_id: movie.id,
          file_path: "/media/movies/blade_runner.mkv",
          watch_dir: "/media/movies"
        })

      entity_ids = FileEventHandler.cleanup_removed_files(["/media/movies/blade_runner.mkv"])

      assert entity_ids == [movie.id]
      assert Library.list_watched_files!() == []
      assert Library.list_movies!() == []
    end

    test "deletes episode and keeps TV series when one episode removed" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

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
          watch_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e02.mkv",
          watch_dir: "/media/tv"
        })

      entity_ids = FileEventHandler.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      assert entity_ids == [tv_series.id]

      # Episode 1 is gone
      assert {:error, _} = Library.get_episode(ep1.id)

      # Episode 2, season, and TV series remain
      remaining_episodes = Library.list_episodes!()
      assert length(remaining_episodes) == 1
      assert hd(remaining_episodes).episode_number == 2

      assert {:ok, _} = Library.get_season(season.id)
      assert {:ok, _} = Library.get_tv_series(tv_series.id)

      # Only 1 WatchedFile remains
      assert length(Library.list_watched_files!()) == 1
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
          watch_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/pluribus/s01e02.mkv",
          watch_dir: "/media/tv"
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
      assert {:error, _} = Library.get_episode(ep1.id)
      assert {:error, :not_found} = Library.get_watch_progress_by_fk(:episode_id, ep1.id)
      assert {:ok, _} = Library.get_tv_series(tv_series.id)
    end

    test "deletes empty season when all its episodes are removed" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

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
          watch_dir: "/media/tv"
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
          watch_dir: "/media/tv"
        })

      FileEventHandler.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      # Season 1 should be gone (empty), season 2 should remain
      assert {:error, _} = Library.get_season(season.id)
      assert {:ok, _} = Library.get_season(season2.id)
      assert {:ok, _} = Library.get_tv_series(tv_series.id)
    end

    test "deletes entire TV series when all files removed" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

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
          watch_dir: "/media/tv"
        })

      FileEventHandler.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      assert Library.list_seasons!() == []
      assert Library.list_episodes!() == []
      assert Library.list_watched_files!() == []
    end

    test "deletes child movie from movie series, keeps series with 2+ remaining" do
      movie_series = create_entity(%{type: :movie_series, name: "Dark Knight Trilogy"})

      movie1 =
        create_movie(%{
          movie_series_id: movie_series.id,
          name: "Batman Begins",
          tmdb_id: "272",
          content_url: "/media/movies/batman_begins.mkv",
          position: 0
        })

      _movie2 =
        create_movie(%{
          movie_series_id: movie_series.id,
          name: "The Shadowy Sentinel",
          tmdb_id: "155",
          content_url: "/media/movies/dark_knight.mkv",
          position: 1
        })

      _movie3 =
        create_movie(%{
          movie_series_id: movie_series.id,
          name: "The Shadowy Sentinel Rises",
          tmdb_id: "49026",
          content_url: "/media/movies/dark_knight_rises.mkv",
          position: 2
        })

      _file1 =
        create_linked_file(%{
          movie_series_id: movie_series.id,
          file_path: "/media/movies/batman_begins.mkv",
          watch_dir: "/media/movies"
        })

      _file2 =
        create_linked_file(%{
          movie_series_id: movie_series.id,
          file_path: "/media/movies/dark_knight.mkv",
          watch_dir: "/media/movies"
        })

      _file3 =
        create_linked_file(%{
          movie_series_id: movie_series.id,
          file_path: "/media/movies/dark_knight_rises.mkv",
          watch_dir: "/media/movies"
        })

      FileEventHandler.cleanup_removed_files(["/media/movies/batman_begins.mkv"])

      # Movie 1 is gone, series and other movies remain
      assert {:error, _} = Library.get_movie(movie1.id)
      assert length(Library.list_movies!()) == 2
      assert {:ok, _} = Library.get_movie_series(movie_series.id)
    end

    test "deletes extra when its file is removed" do
      movie =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/blade_runner.mkv"
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
          file_path: "/media/movies/blade_runner.mkv",
          watch_dir: "/media/movies"
        })

      _file2 =
        create_linked_file(%{
          movie_id: movie.id,
          file_path: "/media/movies/Extras/bts.mkv",
          watch_dir: "/media/movies"
        })

      FileEventHandler.cleanup_removed_files(["/media/movies/Extras/bts.mkv"])

      # Extra is gone, movie entity remains
      assert {:error, _} = Library.get_extra(extra.id)
      assert {:ok, _} = Library.get_movie(movie.id)
      assert length(Library.list_watched_files!()) == 1
    end

    test "handles batch deletion of multiple files" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

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
          watch_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e02.mkv",
          watch_dir: "/media/tv"
        })

      entity_ids =
        FileEventHandler.cleanup_removed_files([
          "/media/tv/bb/s01e01.mkv",
          "/media/tv/bb/s01e02.mkv"
        ])

      assert entity_ids == [tv_series.id]
      assert Library.list_seasons!() == []
      assert Library.list_episodes!() == []
      assert Library.list_watched_files!() == []
    end

    test "returns empty list when no matching files found" do
      assert FileEventHandler.cleanup_removed_files(["/nonexistent/file.mkv"]) == []
    end

    test "deletes episode images from database" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show Eight"})

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
          watch_dir: "/media/tv"
        })

      _file2 =
        create_linked_file(%{
          tv_series_id: tv_series.id,
          file_path: "/media/tv/bb/s01e02.mkv",
          watch_dir: "/media/tv"
        })

      FileEventHandler.cleanup_removed_files(["/media/tv/bb/s01e01.mkv"])

      # Episode image should be gone
      assert Library.list_all_images!() == []
    end
  end
end
