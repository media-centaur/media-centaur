defmodule MediaCentarr.Pipeline.Stages.SearchTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Pipeline.Payload
  alias MediaCentarr.Pipeline.Stages.Search
  alias MediaCentarr.Parser

  import MediaCentarr.TmdbStubs

  setup do
    setup_tmdb_client()
  end

  defp payload_with_parsed(overrides \\ %{}) do
    defaults = %{
      title: "Fight Club",
      year: 1999,
      type: :movie,
      season: nil,
      episode: nil,
      parent_title: nil,
      parent_year: nil,
      file_path: "/media/Fight.Club.1999.mkv",
      episode_title: nil
    }

    parsed = struct(Parser.Result, Map.merge(defaults, overrides))
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
          "title" => "Fight Club",
          "release_date" => "1999-10-15"
        })
      ])

      payload = payload_with_parsed()

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 550
      assert result.tmdb_type == :movie
      assert result.confidence >= 0.85
      assert result.match_title == "Fight Club"
    end

    test "TV match above threshold returns {:ok, payload}" do
      stub_search_tv([
        tv_search_result(%{
          "id" => 1396,
          "name" => "Sample Show Eight",
          "first_air_date" => "2008-01-20"
        })
      ])

      payload = payload_with_parsed(%{title: "Sample Show Eight", year: 2008, type: :tv})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 1396
      assert result.tmdb_type == :tv
      assert result.confidence >= 0.85
      assert result.match_title == "Sample Show Eight"
    end

    test "unknown type searches both, picks best match" do
      stub_search_both(
        [
          movie_search_result(%{
            "id" => 550,
            "title" => "Fight Club",
            "release_date" => "1999-10-15"
          })
        ],
        [tv_search_result(%{"id" => 999, "name" => "Something Else"})]
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
        movie_search_result(%{"id" => 999, "title" => "Completely Different Movie"})
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
  # Tied scores
  # ---------------------------------------------------------------------------

  describe "tied scores" do
    test "position bonus resolves tied 1.0 scores above threshold" do
      stub_search_tv([
        tv_search_result(%{
          "id" => 295_778,
          "name" => "Sample Show One",
          "first_air_date" => "2026-01-15"
        }),
        tv_search_result(%{"id" => 4556, "name" => "Sample Show One", "first_air_date" => "2001-10-02"})
      ])

      payload = payload_with_parsed(%{title: "Sample Show One", year: nil, type: :tv})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 295_778
    end

    test "single result at 1.0 is still auto-approved" do
      stub_search_tv([
        tv_search_result(%{"id" => 4556, "name" => "Sample Show One", "first_air_date" => "2001-10-02"})
      ])

      payload = payload_with_parsed(%{title: "Sample Show One", year: nil, type: :tv})

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
          "id" => 45824,
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
          "name" => "Sample Show Five",
          "first_air_date" => "2024-04-10"
        }),
        tv_search_result(%{
          "id" => 32_366,
          "name" => "Sample Show Five",
          "first_air_date" => "2006-04-23"
        })
      ])

      payload =
        payload_with_parsed(%{title: "Sample Show Five", year: nil, type: :tv, season: 2, episode: 1})

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_id == 106_379
    end
  end

  # ---------------------------------------------------------------------------
  # Errors
  # ---------------------------------------------------------------------------

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
          "name" => "Sample Show Eight",
          "first_air_date" => "2008-01-20"
        })
      ])

      payload =
        payload_with_parsed(%{
          type: :extra,
          title: "Behind the Scenes",
          parent_title: "Sample Show Eight",
          parent_year: 2008,
          season: 1
        })

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_type == :tv
      assert result.match_title == "Sample Show Eight"
    end

    test "extra without season_number searches as movie" do
      stub_search_movie([
        movie_search_result(%{
          "id" => 550,
          "title" => "Fight Club",
          "release_date" => "1999-10-15"
        })
      ])

      payload =
        payload_with_parsed(%{
          type: :extra,
          title: "Deleted Scenes",
          parent_title: "Fight Club",
          parent_year: 1999,
          season: nil
        })

      assert {:ok, result} = Search.run(payload)
      assert result.tmdb_type == :movie
      assert result.match_title == "Fight Club"
    end
  end
end
