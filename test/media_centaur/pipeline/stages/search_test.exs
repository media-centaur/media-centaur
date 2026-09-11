defmodule MediaCentaur.Pipeline.Stages.SearchTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Pipeline.Stages.Search

  import MediaCentaur.TestFactory
  import MediaCentaur.TmdbStubs

  setup do
    setup_tmdb_client()
  end

  defp payload_with_parsed(overrides \\ %{}) do
    parsed = build_parser_result(overrides)
    %Payload{file_path: parsed.file_path, parsed: parsed}
  end

  # ---------------------------------------------------------------------------
  # High confidence matches
  # ---------------------------------------------------------------------------

  describe "high confidence" do
    test "movie match above threshold returns {:ok, payload}" do
      stub_search_movie([
        movie_search_result(%{
          "id" => 550,
          "title" => "Sample Movie",
          "release_date" => "1999-10-15"
        })
      ])

      payload = payload_with_parsed()

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 550
      assert result.tmdb_type == :movie
      assert result.confidence >= 0.85
      assert result.match_title == "Sample Movie"
    end

    test "TV match above threshold returns {:ok, payload}" do
      stub_search_tv([
        tv_search_result(%{
          "id" => 1396,
          "name" => "Sample Show",
          "first_air_date" => "2008-01-20"
        })
      ])

      payload = payload_with_parsed(%{title: "Sample Show", year: 2008, type: :tv})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 1396
      assert result.tmdb_type == :tv
      assert result.confidence >= 0.85
      assert result.match_title == "Sample Show"
    end

    test "unknown type searches both, picks best match" do
      stub_search_both(
        [
          movie_search_result(%{
            "id" => 550,
            "title" => "Sample Movie",
            "release_date" => "1999-10-15"
          })
        ],
        [tv_search_result(%{"id" => 999, "name" => "Other Show"})]
      )

      payload = payload_with_parsed(%{type: :unknown})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 550
      assert result.tmdb_type == :movie
    end
  end

  # ---------------------------------------------------------------------------
  # Low confidence / no results
  # ---------------------------------------------------------------------------

  describe "needs review" do
    test "low confidence returns {:needs_review, payload}" do
      stub_search_movie([
        movie_search_result(%{"id" => 999, "title" => "Unrelated Title"})
      ])

      payload = payload_with_parsed()

      assert {:needs_review, result} = Search.run(payload)
      assert result.tmdb_id == 999
      assert result.confidence < 0.85
      assert result.candidates != []
    end

    test "no results returns {:needs_review, payload}" do
      # Default stub returns empty results
      payload = payload_with_parsed()

      assert {:needs_review, result} = Search.run(payload)
      assert result.candidates == []
    end
  end

  # ---------------------------------------------------------------------------
  # Year fallback — the parsed year is a disambiguator, never a gatekeeper.
  # A wrongly-parsed year (or an off-by-one release year: festival premiere
  # vs theatrical) must not turn a findable title into a silent miss; the
  # year-less retry surfaces the candidate and the confidence score still
  # carries the mismatch penalty.
  # ---------------------------------------------------------------------------

  describe "year fallback" do
    defp stub_yearless_only(path, results) do
      Req.Test.stub(:tmdb, fn conn ->
        params = URI.decode_query(conn.query_string)
        year_filtered? = params["year"] || params["first_air_date_year"]

        if String.contains?(conn.request_path, path) and is_nil(year_filtered?) do
          Req.Test.json(conn, %{"results" => results})
        else
          Req.Test.json(conn, %{"results" => []})
        end
      end)
    end

    test "movie: a wrong parsed year retries without the year filter" do
      stub_yearless_only("search/movie", [
        movie_search_result(%{
          "id" => 550,
          "title" => "Sample Movie",
          "release_date" => "1999-10-15"
        })
      ])

      payload = payload_with_parsed(%{year: 1997})

      # Exact title + mismatched year scores 0.90 (1.0 − 0.15 + 0.05 top
      # bonus) — still auto-approved. The penalty matters for near-miss
      # titles, not exact ones.
      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 550
      assert result.match_title == "Sample Movie"
    end

    test "TV: a wrong parsed year retries without the year filter" do
      stub_yearless_only("search/tv", [
        tv_search_result(%{
          "id" => 1396,
          "name" => "Sample Show",
          "first_air_date" => "2008-01-20"
        })
      ])

      payload = payload_with_parsed(%{title: "Sample Show", year: 2006, type: :tv})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 1396
      assert result.match_title == "Sample Show"
    end
  end

  # ---------------------------------------------------------------------------
  # Tied scores
  # ---------------------------------------------------------------------------

  describe "tied scores" do
    test "position bonus resolves tied 1.0 scores above threshold" do
      stub_search_tv([
        tv_search_result(%{
          "id" => 295_778,
          "name" => "Sample Show",
          "first_air_date" => "2026-01-15"
        }),
        tv_search_result(%{"id" => 4556, "name" => "Sample Show", "first_air_date" => "2001-10-02"})
      ])

      payload = payload_with_parsed(%{title: "Sample Show", year: nil, type: :tv})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 295_778
    end

    test "single result at 1.0 is still auto-approved" do
      stub_search_tv([
        tv_search_result(%{"id" => 4556, "name" => "Sample Show", "first_air_date" => "2001-10-02"})
      ])

      payload = payload_with_parsed(%{title: "Sample Show", year: nil, type: :tv})

      assert {:ok, result} = Search.run(payload)
      assert result.confidence >= 0.85
    end

    test "tied movie with exact title and matching year auto-approves first result" do
      stub_search_movie([
        movie_search_result(%{
          "id" => 882_598,
          "title" => "Sample Movie Twelve",
          "release_date" => "2022-09-23"
        }),
        movie_search_result(%{
          "id" => 1_051_335,
          "title" => "Sample Movie Twelve",
          "release_date" => "2022-01-01"
        })
      ])

      payload = payload_with_parsed(%{title: "Sample Movie Twelve", year: 2022, type: :movie})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 882_598
    end

    test "position bonus resolves tied movies without parsed year" do
      stub_search_movie([
        movie_search_result(%{
          "id" => 882_598,
          "title" => "Sample Movie Twelve",
          "release_date" => "2022-09-23"
        }),
        movie_search_result(%{
          "id" => 45_824,
          "title" => "Sample Movie Twelve",
          "release_date" => "2005-01-01"
        })
      ])

      payload = payload_with_parsed(%{title: "Sample Movie Twelve", year: nil, type: :movie})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 882_598
    end

    test "tied TV shows with matching year auto-approves first result" do
      stub_search_tv([
        tv_search_result(%{
          "id" => 90_282,
          "name" => "Sample Show Seven",
          "first_air_date" => "2019-11-01"
        }),
        tv_search_result(%{
          "id" => 1230,
          "name" => "Sample Show Seven",
          "first_air_date" => "2019-06-18"
        })
      ])

      payload =
        payload_with_parsed(%{
          title: "Sample Show Seven",
          year: 2019,
          type: :tv,
          season: 2,
          episode: 5
        })

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 90_282
    end

    test "position bonus breaks tie for perfect title matches with no year" do
      stub_search_tv([
        tv_search_result(%{
          "id" => 106_379,
          "name" => "Sample Show",
          "first_air_date" => "2024-04-10"
        }),
        tv_search_result(%{
          "id" => 32_366,
          "name" => "Sample Show",
          "first_air_date" => "2006-04-23"
        })
      ])

      payload =
        payload_with_parsed(%{title: "Sample Show", year: nil, type: :tv, season: 2, episode: 1})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 106_379
    end
  end

  # ---------------------------------------------------------------------------
  # Errors
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Identity the grab asked for
  # ---------------------------------------------------------------------------

  describe "a file whose grab wanted a different film" do
    # The Filipiñana loop's silent half. Acquisition knew it had asked
    # for tmdb 663875; the importer parsed the filename, found a
    # different film with the same folded name, and filed it with no
    # signal — so the want stayed open and the sweep grabbed again.
    defp grab_wanting(release_title, identity_attrs) do
      create_pursuit_with_target(
        Map.merge(
          %{
            recipe_type: "tmdb",
            tmdb_type: "movie",
            status: "succeeded",
            release_title: release_title
          },
          identity_attrs
        )
      )
    end

    test "a matched film contradicting the grab's identity goes to review, not the shelf" do
      grab_wanting("Sample.Film.2026.1080p.WEB-DL-GROUP", %{
        tmdb_id: "663875",
        title: "Sample Film",
        imdb_id: "tt11887594"
      })

      stub_search_movie([
        movie_search_result(%{
          "id" => 1_417_935,
          "title" => "Sample Film",
          "release_date" => "2026-08-26"
        })
      ])

      payload =
        payload_with_parsed(%{
          file_path: "/media/Sample.Film.2026.1080p.WEB-DL-GROUP/Sample.Film.2026.mkv",
          title: "Sample Film",
          year: 2026
        })

      assert {:needs_review, result} = Search.run(payload)
      assert result.tmdb_id == 1_417_935
    end

    test "a matched film agreeing with the grab's identity files normally" do
      grab_wanting("Sample.Film.2026.1080p.WEB-DL-GROUP", %{
        tmdb_id: "550",
        title: "Sample Movie",
        imdb_id: "tt0137523"
      })

      stub_search_movie([
        movie_search_result(%{
          "id" => 550,
          "title" => "Sample Movie",
          "release_date" => "1999-10-15"
        })
      ])

      payload =
        payload_with_parsed(%{
          file_path: "/media/Sample.Film.2026.1080p.WEB-DL-GROUP/Sample.Movie.mkv"
        })

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 550
    end

    test "a grab for a series does not veto a movie sharing its tmdb id" do
      # Movie 550 and series 550 are unrelated works; comparing ids
      # across types would read a coincidence as a fault.
      grab_wanting("Sample.Film.2026.1080p.WEB-DL-GROUP", %{
        tmdb_type: "tv",
        tmdb_id: "999",
        title: "Sample Show"
      })

      stub_search_movie([
        movie_search_result(%{
          "id" => 550,
          "title" => "Sample Movie",
          "release_date" => "1999-10-15"
        })
      ])

      payload =
        payload_with_parsed(%{
          file_path: "/media/Sample.Film.2026.1080p.WEB-DL-GROUP/Sample.Movie.mkv"
        })

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 550
    end

    test "a file no grab of ours accounts for is unaffected" do
      stub_search_movie([
        movie_search_result(%{
          "id" => 550,
          "title" => "Sample Movie",
          "release_date" => "1999-10-15"
        })
      ])

      assert {:ok, result} = Search.run(payload_with_parsed())
      assert result.tmdb_id == 550
    end
  end

  describe "errors" do
    test "TMDB API error returns {:error, reason}" do
      stub_tmdb_error("/search/movie", 500)

      payload = payload_with_parsed()

      assert {:error, _reason} = Search.run(payload)
    end

    test "no parsed title returns {:error, :no_title}" do
      payload = payload_with_parsed(%{title: nil})

      assert {:error, :no_title} = Search.run(payload)
    end
  end

  # ---------------------------------------------------------------------------
  # Extra type routing
  # ---------------------------------------------------------------------------

  describe "extra type" do
    test "extra with season_number searches as TV" do
      stub_search_tv([
        tv_search_result(%{
          "id" => 1396,
          "name" => "Sample Show",
          "first_air_date" => "2008-01-20"
        })
      ])

      payload =
        payload_with_parsed(%{
          type: :extra,
          title: "Behind the Scenes",
          parent_title: "Sample Show",
          parent_year: 2008,
          season: 1
        })

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_type == :tv
      assert result.match_title == "Sample Show"
    end

    test "extra without season_number searches as movie" do
      stub_search_movie([
        movie_search_result(%{
          "id" => 550,
          "title" => "Sample Movie",
          "release_date" => "1999-10-15"
        })
      ])

      payload =
        payload_with_parsed(%{
          type: :extra,
          title: "Deleted Scenes",
          parent_title: "Sample Movie",
          parent_year: 1999,
          season: nil
        })

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_type == :movie
      assert result.match_title == "Sample Movie"
    end
  end
end
