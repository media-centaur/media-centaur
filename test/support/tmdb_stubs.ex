defmodule MediaCentarr.TmdbStubs do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Shared TMDB API stub helpers for pipeline tests.

  Uses `Req.Test` to intercept HTTP requests and return fixture data.
  Installs a stubbed client into `:persistent_term` so that `TMDB.Client`
  functions use it transparently.
  """

  @doc """
  Sets up a Req.Test-backed TMDB client in persistent_term.
  Call in test setup; cleans up on exit automatically.
  """
  def setup_tmdb_client(context \\ %{}) do
    Req.Test.stub(:tmdb, fn conn -> json_resp(conn, 200, %{"results" => []}) end)
    client = Req.new(plug: {Req.Test, :tmdb}, retry: false)
    :persistent_term.put({MediaCentarr.TMDB.Client, :client}, client)

    ExUnit.Callbacks.on_exit(fn ->
      :persistent_term.erase({MediaCentarr.TMDB.Client, :client})
    end)

    context
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
