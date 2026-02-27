defmodule MediaManager.Pipeline.Stages.SearchTest do
  use ExUnit.Case, async: true

  alias MediaManager.Pipeline.Payload
  alias MediaManager.Pipeline.Stages.Search
  alias MediaManager.Parser

  import MediaManager.TmdbStubs

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
