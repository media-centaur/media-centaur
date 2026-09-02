defmodule MediaCentaur.TMDB.TitleSearchTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.TMDB.{Title, TitleSearch}

  describe "search/1" do
    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      :ok
    end

    test "carries the full release date through — the upcoming/released filter needs it" do
      MediaCentaur.TmdbStubs.stub_search_multi([
        %{
          "id" => 100,
          "media_type" => "movie",
          "title" => "Dated Movie",
          "release_date" => "2026-07-01"
        },
        %{
          "id" => 200,
          "media_type" => "tv",
          "name" => "Dated Show",
          "first_air_date" => "2025-01-15"
        },
        %{
          "id" => 101,
          "media_type" => "movie",
          "title" => "Undated Movie"
        }
      ])

      assert [
               %Title{tmdb_id: 100, release_date: ~D[2026-07-01]},
               %Title{tmdb_id: 200, release_date: ~D[2025-01-15]},
               %Title{tmdb_id: 101, release_date: nil}
             ] = TitleSearch.search("dated")
    end

    test "preserves TMDB's relevance order across movie and TV results" do
      # The multi endpoint ranks across types — a TV show may outrank
      # every movie. The merge must not regroup by type (the old
      # movies-then-tv concatenation starved TV out of the capped
      # dropdown entirely).
      MediaCentaur.TmdbStubs.stub_search_multi([
        %{
          "id" => 200,
          "media_type" => "tv",
          "name" => "Test Show",
          "first_air_date" => "2025-01-01",
          "poster_path" => "/t.jpg"
        },
        %{
          "id" => 100,
          "media_type" => "movie",
          "title" => "Test Movie",
          "release_date" => "2026-07-01",
          "poster_path" => "/m.jpg",
          "overview" => "A test movie overview."
        },
        %{
          "id" => 201,
          "media_type" => "tv",
          "name" => "Test Show Two",
          "first_air_date" => "2021-01-01",
          "poster_path" => nil
        }
      ])

      results = TitleSearch.search("test")

      assert [
               %Title{tmdb_id: 200, media_type: :tv_series, name: "Test Show", year: "2025"},
               %Title{tmdb_id: 100, media_type: :movie, name: "Test Movie", year: "2026"},
               %Title{tmdb_id: 201, media_type: :tv_series, name: "Test Show Two", year: "2021"}
             ] = results

      assert hd(results).poster_path == "/t.jpg"
      assert Enum.at(results, 1).overview == "A test movie overview."
    end

    test "carries each result's backdrop path for the plan flow's cinematic shell" do
      MediaCentaur.TmdbStubs.stub_search_multi([
        %{
          "id" => 100,
          "media_type" => "movie",
          "title" => "Test Movie",
          "release_date" => "2026-07-01",
          "poster_path" => "/m.jpg",
          "backdrop_path" => "/m-backdrop.jpg"
        },
        %{
          "id" => 200,
          "media_type" => "tv",
          "name" => "Test Show",
          "first_air_date" => "2025-01-01",
          "poster_path" => "/t.jpg",
          "backdrop_path" => "/t-backdrop.jpg"
        }
      ])

      assert [movie, show] = TitleSearch.search("test")
      assert movie.backdrop_path == "/m-backdrop.jpg"
      assert show.backdrop_path == "/t-backdrop.jpg"
    end

    test "drops person results from the multi search" do
      MediaCentaur.TmdbStubs.stub_search_multi([
        %{"id" => 999, "media_type" => "person", "name" => "Test Actor"},
        %{
          "id" => 100,
          "media_type" => "movie",
          "title" => "Test Movie",
          "release_date" => "2026-07-01",
          "poster_path" => "/m.jpg"
        }
      ])

      assert [%Title{tmdb_id: 100, media_type: :movie}] = TitleSearch.search("test")
    end

    test "returns empty list for no results" do
      MediaCentaur.TmdbStubs.stub_search_multi([])
      assert TitleSearch.search("xyznonexistent") == []
    end

    test "drops a hit with a blank title and keeps the rest" do
      MediaCentaur.TmdbStubs.stub_search_multi([
        %{"id" => 1, "media_type" => "movie", "title" => "", "release_date" => "2020-01-01"},
        %{"id" => 2, "media_type" => "movie", "title" => "Sample Movie", "release_date" => "2020-01-01"},
        %{"id" => nil, "media_type" => "tv", "name" => "Sample Show"}
      ])

      assert [%Title{tmdb_id: 2, name: "Sample Movie"}] = TitleSearch.search("sample")
    end

    test "returns an empty list when TMDB errors" do
      MediaCentaur.TmdbStubs.stub_tmdb_error("/search/multi")
      assert TitleSearch.search("sample") == []
    end
  end

  describe "search/1 — trailing year in the query" do
    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      :ok
    end

    # The multi endpoint matches the whole query string against titles —
    # "Test Movie 1999" matches nothing. A trailing year must instead be
    # sent as the year filter of the per-type endpoints.
    defp stub_year_search(movie_results, tv_results, multi_results) do
      Req.Test.stub(:tmdb, fn conn ->
        params = URI.decode_query(conn.query_string)

        cond do
          String.contains?(conn.request_path, "search/movie") ->
            if params["year"],
              do: Req.Test.json(conn, %{"results" => movie_results}),
              else: Req.Test.json(conn, %{"results" => []})

          String.contains?(conn.request_path, "search/tv") ->
            if params["first_air_date_year"],
              do: Req.Test.json(conn, %{"results" => tv_results}),
              else: Req.Test.json(conn, %{"results" => []})

          String.contains?(conn.request_path, "search/multi") ->
            Req.Test.json(conn, %{"results" => multi_results})

          true ->
            Req.Test.json(conn, %{"results" => []})
        end
      end)
    end

    test "a trailing year routes to the year-filtered movie and tv searches" do
      stub_year_search(
        [%{"id" => 100, "title" => "Test Movie", "release_date" => "1999-07-01", "popularity" => 5.0}],
        [],
        []
      )

      assert [%Title{tmdb_id: 100, media_type: :movie, year: "1999"}] =
               TitleSearch.search("Test Movie 1999")
    end

    test "a parenthesized trailing year is treated the same" do
      stub_year_search(
        [%{"id" => 100, "title" => "Test Movie", "release_date" => "1999-07-01", "popularity" => 5.0}],
        [],
        []
      )

      assert [%Title{tmdb_id: 100, media_type: :movie}] =
               TitleSearch.search("Test Movie (1999)")
    end

    test "movie and tv year results merge by TMDB popularity" do
      stub_year_search(
        [%{"id" => 100, "title" => "Test Movie", "release_date" => "1999-07-01", "popularity" => 5.0}],
        [%{"id" => 200, "name" => "Test Show", "first_air_date" => "1999-01-01", "popularity" => 10.0}],
        []
      )

      assert [
               %Title{tmdb_id: 200, media_type: :tv_series},
               %Title{tmdb_id: 100, media_type: :movie}
             ] = TitleSearch.search("Test 1999")
    end

    test "falls back to a year-less multi search of the stripped title when the year filter finds nothing" do
      Req.Test.stub(:tmdb, fn conn ->
        params = URI.decode_query(conn.query_string)

        # Only the stripped title may reach the multi fallback — the
        # full "Test Movie 1997" string would match no TMDB title.
        if String.contains?(conn.request_path, "search/multi") and params["query"] == "Test Movie" do
          Req.Test.json(conn, %{
            "results" => [
              %{
                "id" => 100,
                "media_type" => "movie",
                "title" => "Test Movie",
                "release_date" => "2000-07-01",
                "poster_path" => "/m.jpg"
              }
            ]
          })
        else
          Req.Test.json(conn, %{"results" => []})
        end
      end)

      assert [%Title{tmdb_id: 100, media_type: :movie, year: "2000"}] =
               TitleSearch.search("Test Movie 1997")
    end

    test "a bare year is a plain query, not a year filter" do
      Req.Test.stub(:tmdb, fn conn ->
        if String.contains?(conn.request_path, "search/multi") do
          Req.Test.json(conn, %{
            "results" => [
              %{
                "id" => 300,
                "media_type" => "movie",
                "title" => "1999",
                "release_date" => "2009-01-01",
                "poster_path" => nil
              }
            ]
          })
        else
          Req.Test.json(conn, %{"results" => []})
        end
      end)

      assert [%Title{tmdb_id: 300, media_type: :movie}] = TitleSearch.search("1999")
    end
  end
end
