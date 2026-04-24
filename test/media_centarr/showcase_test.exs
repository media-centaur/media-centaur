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

    :persistent_term.put(
      {MediaCentarr.Config, :config},
      config
      |> Map.put(:watch_dirs, [tmp_dir])
      |> Map.put(:database_path, "priv/showcase/test.db")
    )

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
      assert summary.watch_events >= 15

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

      assert summary.acquisitions == 1

      grabs = Repo.all(MediaCentarr.Acquisition.Grab)
      assert length(grabs) == 1
    end
  end

  describe "fail-loud on silent data loss" do
    # If TMDB can't answer (bad key, network, rate limit), the old seeder
    # caught the error inside `seed_movie!` / `seed_tv_series!`, logged a
    # warning, and returned a stub with `id: nil` — so the summary still
    # counted "14 movies" but zero rows persisted. That produced
    # marketing-grade screenshots full of broken images and took visual
    # inspection to catch. The seeder now raises on the first silent
    # failure so a bad key is obvious immediately.

    test "raises with an actionable message when TMDB search returns no results for a movie" do
      Req.Test.stub(:tmdb, fn conn ->
        Req.Test.json(conn, empty_or_stub_response(conn.request_path))
      end)

      assert_raise RuntimeError, ~r/TMDB/i, fn -> Showcase.seed!() end
    end

    test "raises with an actionable message when TMDB search returns no results for a TV series" do
      Req.Test.stub(:tmdb, fn conn ->
        path = conn.request_path

        if String.contains?(path, "/search/tv") do
          Req.Test.json(conn, %{"results" => []})
        else
          Req.Test.json(conn, response_for(path, "#{path}?#{conn.query_string}"))
        end
      end)

      assert_raise RuntimeError, ~r/TMDB/i, fn -> Showcase.seed!() end
    end
  end

  describe "Showcase.seed!/0 pipeline_image_queue alignment" do
    # Background: in 0.22.5 the seeder bypassed pipeline_image_queue,
    # writing library_images directly. Image-download failures were
    # silently swallowed, leaving rows pointing at files that never
    # landed and no queue row to drive a repair pass. The seeder now
    # writes a queue row first (carrying the TMDB CDN URL), then
    # attempts the inline download. Repair drains anything left
    # :pending. See ImageRepair + Library.ImageHealth.

    alias MediaCentarr.Pipeline.ImageQueueEntry

    test "writes a pipeline_image_queue row for every image referenced" do
      Showcase.seed!()

      queue_rows = Repo.all(ImageQueueEntry)

      # Every queue row should carry a populated source_url and
      # owner_type — the repair feature depends on both.
      assert Enum.all?(queue_rows, fn entry ->
               is_binary(entry.source_url) and entry.source_url != "" and
                 entry.owner_type in ~w(movie tv_series episode movie_series video_object)
             end)

      # We should have at least one queue row per top-level entity
      # that the seeder ran download_images! for (movies + TV series).
      expected_min = length(Catalog.movies()) + length(Catalog.tv_series())
      assert length(queue_rows) >= expected_min
    end

    test "queue rows for episodes use the parent series id as entity_id" do
      Showcase.seed!()

      episode_rows =
        Repo.all(from(e in ImageQueueEntry, where: e.owner_type == "episode", select: e))

      # If any episode rows were written (i.e. TMDB returned still_paths),
      # their entity_id must point at a TV series, not the episode itself.
      Enum.each(episode_rows, fn entry ->
        assert entry.owner_id != entry.entity_id,
               "episode queue row entity_id should be parent series id, not own id"

        assert Repo.get(Library.TVSeries, entry.entity_id),
               "episode queue row entity_id #{entry.entity_id} must reference a TVSeries"
      end)
    end
  end

  describe "safety rail" do
    test "raises when database_path does not look like a showcase path" do
      config = :persistent_term.get({MediaCentarr.Config, :config})

      :persistent_term.put(
        {MediaCentarr.Config, :config},
        Map.put(config, :database_path, "/home/user/.local/share/media-centarr/media-centarr.db")
      )

      on_exit(fn -> :persistent_term.put({MediaCentarr.Config, :config}, config) end)

      assert_raise RuntimeError, ~r/refusing to seed/i, fn ->
        Showcase.seed!()
      end
    end
  end

  # Returns an empty search result for any search URL, otherwise the
  # normal stubbed response. Used by the fail-loud tests to force a
  # TMDB miss and assert the seeder raises loudly.
  defp empty_or_stub_response(path) do
    if String.contains?(path, "/search/") do
      %{"results" => []}
    else
      response_for(path, path)
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
