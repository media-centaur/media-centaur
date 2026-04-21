defmodule MediaCentarr.ShowcaseTest do
  @moduledoc """
  Verifies the showcase seeder creates the expected entities, progress,
  tracked items, pending files, and watch events from a stubbed TMDB.

  All TMDB calls go through `TmdbStubs`; image downloads use the
  no-op downloader configured in `config/test.exs`.
  """
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.Review
  alias MediaCentarr.Showcase
  alias MediaCentarr.Showcase.Catalog
  alias MediaCentarr.TmdbStubs
  alias MediaCentarr.WatchHistory

  setup do
    TmdbStubs.setup_tmdb_client(%{})

    # Showcase writes fake media files under the first configured watch_dir.
    # Test env sets :watch_dirs to [] (ADR-016), so override it with a temp
    # dir for the duration of the test.
    tmp_dir = Path.join(System.tmp_dir!(), "showcase-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    config = :persistent_term.get({MediaCentarr.Config, :config})
    :persistent_term.put({MediaCentarr.Config, :config}, Map.put(config, :watch_dirs, [tmp_dir]))

    on_exit(fn ->
      :persistent_term.put({MediaCentarr.Config, :config}, config)
      File.rm_rf!(tmp_dir)
    end)

    # Stub every movie search → a single hit with id derived from title;
    # every TV search → same; every /movie/:id and /tv/:id → minimal detail;
    # every /tv/:id/season/:n → two-episode season.
    Req.Test.stub(:tmdb, fn conn ->
      key = "#{conn.request_path}?#{conn.query_string}"
      Req.Test.json(conn, response_for(conn.request_path, key))
    end)

    :ok
  end

  describe "Showcase.seed!/0" do
    test "creates all catalog entries and related state" do
      summary = Showcase.seed!()

      expected_movies = length(Catalog.movies())
      expected_tv = length(Catalog.tv_series())
      expected_videos = length(Catalog.video_objects())

      assert summary.movies == expected_movies
      assert summary.tv_series == expected_tv
      assert summary.video_objects == expected_videos

      # Each TV series gets its declared seasons (always 1 in the catalog).
      assert summary.seasons == expected_tv

      # Each stubbed season returns 2 episodes.
      assert summary.episodes == expected_tv * 2

      assert summary.watch_progress > 0
      assert summary.tracked_items > 0
      assert summary.pending_files > 0
      assert summary.watch_events > 0

      # Persisted.
      all_movies = Repo.all(Library.Movie)
      assert length(all_movies) == expected_movies

      all_tv = Repo.all(Library.TVSeries)
      assert length(all_tv) == expected_tv

      all_videos = Repo.all(Library.VideoObject)
      assert length(all_videos) == expected_videos

      tracked = ReleaseTracking.list_all_items()
      assert tracked != []

      pending = Review.list_pending_files()
      assert pending != []

      events = WatchHistory.list_events()
      assert events != []
    end
  end

  # Generates a deterministic fake TMDB id from the URL so every request
  # gets a unique but reproducible id.
  defp fake_id(path) do
    :erlang.phash2(path, 100_000) + 1
  end

  # Returns a minimal but structurally-correct TMDB response for any URL path.
  # Search requests return a single result; detail requests return a full
  # metadata object; season requests return a two-episode season.
  defp response_for(path, key) do
    cond do
      String.contains?(path, "/search/movie") ->
        id = fake_id(key)

        %{
          "results" => [
            %{"id" => id, "title" => "Stubbed Movie #{id}", "release_date" => "2000-01-01"}
          ]
        }

      String.contains?(path, "/search/tv") ->
        id = fake_id(key)

        %{
          "results" => [
            %{"id" => id, "name" => "Stubbed TV #{id}", "first_air_date" => "1990-01-01"}
          ]
        }

      String.contains?(path, "/tv/") and String.contains?(path, "/season/") ->
        %{
          "name" => "Season 1",
          "season_number" => 1,
          "episodes" => [
            %{"episode_number" => 1, "name" => "Pilot", "overview" => "First episode.", "runtime" => 30},
            %{
              "episode_number" => 2,
              "name" => "Follow-up",
              "overview" => "Second episode.",
              "runtime" => 30
            }
          ]
        }

      String.contains?(path, "/movie/") ->
        id = fake_id(path)

        %{
          "id" => id,
          "title" => "Stubbed Movie #{id}",
          "overview" => "A publicly-licensed film suitable for screenshots.",
          "release_date" => "2000-01-01",
          "runtime" => 90,
          "genres" => [%{"id" => 1, "name" => "Drama"}],
          "vote_average" => 7.5,
          "poster_path" => "/p#{id}.jpg",
          "backdrop_path" => "/b#{id}.jpg"
        }

      String.contains?(path, "/tv/") ->
        id = fake_id(path)

        %{
          "id" => id,
          "name" => "Stubbed TV #{id}",
          "overview" => "A CC-licensed series.",
          "first_air_date" => "1990-01-01",
          "genres" => [%{"id" => 2, "name" => "Sci-Fi"}],
          "vote_average" => 8.0,
          "number_of_seasons" => 1,
          "poster_path" => "/pt#{id}.jpg",
          "backdrop_path" => "/bt#{id}.jpg"
        }

      true ->
        %{"results" => []}
    end
  end
end
