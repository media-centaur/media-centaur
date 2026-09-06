defmodule MediaCentaur.TmdbStubs do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Shared TMDB API stub helpers for pipeline tests.

  Uses `Req.Test` to intercept HTTP requests and return fixture data. The
  test config routes every `TMDB.Client` request through the `:tmdb` stub
  (`MediaCentaur.HttpClient`), so these helpers only register responses.
  """

  @doc """
  Registers a default empty-results `:tmdb` stub. Call in test setup.
  """
  def setup_tmdb_client(context \\ %{}) do
    Req.Test.stub(:tmdb, fn conn -> json_resp(conn, 200, %{"results" => []}) end)
    context
  end

  @doc """
  Points the TMDB artwork cache (`TmdbArtwork`, under `{data_dir}/images/tmdb/`)
  at a per-test tmp dir and stubs the image CDN (`:images`) with a body large
  enough for `ImageFiles.download_raw/3` to accept. A flow that downloads
  artwork off-process — release tracking's `download_images_async/3`,
  `TmdbArtwork.ensure/2` — then lands files there instead of logging a
  failed download. The bytes are not a decodable image: enough for the
  download ledger, not for derivatives. Call in test setup; the config
  term is restored by `GlobalStateSandbox` and the dir is removed on exit.
  The test still drives the download task to completion before it exits
  (`MediaCentaur.TaskAwaits.await_supervised_tasks/0`).
  """
  def setup_artwork_cache(context \\ %{}) do
    data_dir = Path.join(System.tmp_dir!(), "tmdb_artwork_#{System.unique_integer([:positive])}")
    File.mkdir_p!(data_dir)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
    :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, :data_dir, data_dir))
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(data_dir) end)

    Req.Test.stub(:images, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("image/jpeg")
      |> Plug.Conn.send_resp(200, :binary.copy("x", 2048))
    end)

    Map.put(context, :data_dir, data_dir)
  end

  # ---------------------------------------------------------------------------
  # Search stubs
  # ---------------------------------------------------------------------------

  def stub_search_movie(results) when is_list(results) do
    stub_endpoint("/search/movie", %{"results" => results})
  end

  def stub_search_tv(results) when is_list(results) do
    stub_endpoint("/search/tv", %{"results" => results})
  end

  @doc """
  Stubs `/search/multi`. Result maps carry TMDB's `"media_type"`
  discriminator (`"movie"` / `"tv"` / `"person"`) alongside the
  type-specific title/date keys.
  """
  def stub_search_multi(results) when is_list(results) do
    stub_endpoint("/search/multi", %{"results" => results})
  end

  def stub_search_both(movie_results, tv_results) do
    Req.Test.stub(:tmdb, fn conn ->
      data =
        cond do
          String.contains?(conn.request_path, "/search/movie") ->
            %{"results" => movie_results}

          String.contains?(conn.request_path, "/search/tv") ->
            %{"results" => tv_results}

          true ->
            %{"results" => []}
        end

      json_resp(conn, 200, data)
    end)
  end

  # ---------------------------------------------------------------------------
  # Detail stubs
  # ---------------------------------------------------------------------------

  def stub_get_movie(tmdb_id, data) do
    stub_endpoint("/movie/#{tmdb_id}", data)
  end

  def stub_get_tv(tmdb_id, data) do
    stub_endpoint("/tv/#{tmdb_id}", data)
  end

  def stub_get_season(tmdb_id, season_number, data) do
    stub_endpoint("/tv/#{tmdb_id}/season/#{season_number}", data)
  end

  @doc """
  Stubs `/tv/{id}` and its `/tv/{id}/season/{n}` endpoints together.
  Each `stub_*` call replaces the whole `:tmdb` stub, so flows that
  fetch the series and then its seasons in one run (the *Refresh series
  credits* backfill) need both behind a single stub. `seasons` maps
  season number → season payload; unknown paths 404.
  """
  def stub_get_tv_with_seasons(tmdb_id, tv_data, seasons) when is_map(seasons) do
    Req.Test.stub(:tmdb, fn conn ->
      season =
        Enum.find(seasons, fn {number, _data} ->
          String.contains?(conn.request_path, "/tv/#{tmdb_id}/season/#{number}")
        end)

      cond do
        season != nil -> json_resp(conn, 200, elem(season, 1))
        String.contains?(conn.request_path, "/tv/#{tmdb_id}") -> json_resp(conn, 200, tv_data)
        true -> json_resp(conn, 404, %{"status_message" => "Not Found"})
      end
    end)
  end

  @doc """
  The series targeting universe `Acquisition.Targeting.series_selection("246810")`
  reads: Sample Show with season 1 (two aired episodes), season 2 (one
  aired, one far-future) and a specials season the tv payload lists but
  no route serves. Shared by the targeting, plan-title and Discovery
  tests so one fixture describes the show.
  """
  def stub_series_universe_for_targeting do
    # Season routes first — `stub_routes` matches by path substring, and
    # "/tv/246810" would otherwise swallow the season paths.
    stub_routes([
      {"/tv/246810/season/1",
       season_detail(%{
         "season_number" => 1,
         "episodes" => [
           %{"episode_number" => 1, "name" => "Pilot", "air_date" => "2020-01-01"},
           %{"episode_number" => 2, "name" => "Second", "air_date" => "2020-01-08"}
         ]
       })},
      {"/tv/246810/season/2",
       season_detail(%{
         "season_number" => 2,
         "episodes" => [
           %{"episode_number" => 1, "name" => "Return", "air_date" => "2021-01-01"},
           # Far future — not aired.
           %{"episode_number" => 2, "name" => "Finale", "air_date" => "2199-01-01"}
         ]
       })},
      {"/tv/246810",
       tv_detail(%{
         "id" => 246_810,
         "name" => "Sample Show",
         "original_name" => "Beispielserie",
         "origin_country" => ["US"],
         "seasons" => [
           %{"season_number" => 0, "episode_count" => 1},
           %{"season_number" => 1, "episode_count" => 2},
           %{"season_number" => 2, "episode_count" => 2}
         ]
       })}
    ])
  end

  def stub_get_collection(collection_id, data) do
    stub_endpoint("/collection/#{collection_id}", data)
  end

  @doc """
  Stubs multiple TMDB endpoints at once. Routes requests by path prefix.
  `routes` is a list of `{path_prefix, response_data}` tuples.
  """
  def stub_routes(routes) when is_list(routes) do
    Req.Test.stub(:tmdb, fn conn ->
      match =
        Enum.find(routes, fn {path, _data} ->
          String.contains?(conn.request_path, path)
        end)

      case match do
        {_path, {:error, status}} ->
          json_resp(conn, status, %{"status_message" => "Error"})

        {_path, data} ->
          json_resp(conn, 200, data)

        nil ->
          json_resp(conn, 404, %{"status_message" => "Not Found"})
      end
    end)
  end

  @doc "Stub a specific endpoint to return an HTTP error status."
  def stub_tmdb_error(path, status \\ 500) do
    stub_endpoint_error(path, status)
  end

  # ---------------------------------------------------------------------------
  # Fixture data — realistic TMDB JSON responses
  # ---------------------------------------------------------------------------

  def movie_search_result(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 550,
        "title" => "Sample Movie",
        "imdb_id" => "tt0137523",
        "release_date" => "1999-10-15",
        "poster_path" => "/pB8BM7pdSp6B6Ih7QI4S2t0POD5.jpg",
        "overview" => "A sample movie overview."
      },
      overrides
    )
  end

  def tv_search_result(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 1396,
        "name" => "Sample Show",
        "first_air_date" => "2008-01-20",
        "poster_path" => "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
        "overview" => "A sample show overview."
      },
      overrides
    )
  end

  def movie_detail(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 550,
        "title" => "Sample Movie",
        "imdb_id" => "tt0137523",
        "overview" => "A sample movie overview.",
        "release_date" => "1999-10-15",
        "runtime" => 139,
        "vote_average" => 8.433,
        "genres" => [%{"id" => 18, "name" => "Drama"}],
        "poster_path" => "/pB8BM7pdSp6B6Ih7QI4S2t0POD5.jpg",
        "backdrop_path" => "/hZkgoQYus5dXo3H8T7Uef6DNknx.jpg",
        "belongs_to_collection" => nil,
        "credits" => %{
          "crew" => [
            %{"department" => "Directing", "job" => "Director", "name" => "A. Director"}
          ]
        },
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "US",
              "release_dates" => [%{"certification" => "R"}]
            }
          ]
        },
        "images" => %{"logos" => []}
      },
      overrides
    )
  end

  def movie_in_collection_detail(overrides \\ %{}) do
    Map.merge(
      movie_detail(%{
        "id" => 155,
        "title" => "Sample Movie Two",
        "belongs_to_collection" => %{
          "id" => 263,
          "name" => "Sample Movie Collection"
        }
      }),
      overrides
    )
  end

  def collection_detail(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 263,
        "name" => "Sample Movie Collection",
        "overview" => "A sample collection overview.",
        "poster_path" => "/bqS2lMgGkuodIXtDILFWTSWDDpa.jpg",
        "backdrop_path" => "/zuW6fOiusv4X9nnW3paHGfXcSll.jpg",
        "parts" => [
          %{"id" => 272, "title" => "Sample Movie One"},
          %{"id" => 155, "title" => "Sample Movie Two"},
          %{"id" => 49_026, "title" => "Sample Movie Three"}
        ],
        "images" => %{"logos" => []}
      },
      overrides
    )
  end

  def tv_detail(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 1396,
        "name" => "Sample Show",
        "overview" => "A sample show overview.",
        "first_air_date" => "2008-01-20",
        "number_of_seasons" => 5,
        "vote_average" => 8.9,
        "genres" => [%{"id" => 18, "name" => "Drama"}],
        "poster_path" => "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
        "backdrop_path" => "/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg",
        "external_ids" => %{"imdb_id" => "tt0903747", "tvdb_id" => 81_189},
        "images" => %{"logos" => []}
      },
      overrides
    )
  end

  def season_detail(overrides \\ %{}) do
    Map.merge(
      %{
        "season_number" => 1,
        "name" => "Season 1",
        "episodes" => [
          %{
            "episode_number" => 1,
            "name" => "Pilot",
            "overview" => "Sample episode overview.",
            "runtime" => 58,
            "still_path" => "/ydlY3iPfeOAvu8gVqrxPoMvzNCn.jpg"
          },
          %{
            "episode_number" => 2,
            "name" => "Episode Two",
            "overview" => "Sample episode overview.",
            "runtime" => 48,
            "still_path" => "/tjMFMhGOFwyg8acoUMCmjMAdMf3.jpg"
          }
        ]
      },
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp stub_endpoint(path, response_data) do
    Req.Test.stub(:tmdb, fn conn ->
      if String.contains?(conn.request_path, path) do
        json_resp(conn, 200, response_data)
      else
        json_resp(conn, 404, %{"status_message" => "Not Found"})
      end
    end)
  end

  defp stub_endpoint_error(path, status) do
    Req.Test.stub(:tmdb, fn conn ->
      if String.contains?(conn.request_path, path) do
        json_resp(conn, status, %{"status_message" => "Error"})
      else
        json_resp(conn, 404, %{"status_message" => "Not Found"})
      end
    end)
  end

  defp json_resp(conn, status, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, JSON.encode!(data))
  end
end
