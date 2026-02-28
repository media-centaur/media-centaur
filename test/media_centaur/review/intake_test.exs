defmodule MediaCentaur.Review.IntakeTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Review.Intake

  defp build_payload(overrides \\ %{}) do
    defaults = %{
      file_path: "/media/movies/Inception.2010.1080p.BluRay.mkv",
      watch_directory: "/media/movies",
      parsed: %MediaCentaur.Parser.Result{
        file_path: "/media/movies/Inception.2010.1080p.BluRay.mkv",
        title: "Inception",
        year: 2010,
        type: :movie,
        season: nil,
        episode: nil
      },
      tmdb_id: 27205,
      tmdb_type: :movie,
      confidence: 0.72,
      match_title: "Inception",
      match_year: "2010",
      match_poster_path: "/9gk7adHYeDvHkCSEhniVJErJ0Gs.jpg",
      candidates: [
        {
          %{
            "id" => 27205,
            "title" => "Inception",
            "release_date" => "2010-07-15",
            "poster_path" => "/9gk7adHYeDvHkCSEhniVJErJ0Gs.jpg",
            "overview" => "A thief who steals corporate secrets..."
          },
          0.72,
          "title"
        }
      ]
    }

    struct(Payload, Map.merge(defaults, overrides))
  end

  describe "create_from_payload/1" do
    test "creates PendingFile from payload with full search results" do
      payload = build_payload()

      assert {:ok, pending_file} = Intake.create_from_payload(payload)

      assert pending_file.file_path == "/media/movies/Inception.2010.1080p.BluRay.mkv"
      assert pending_file.watch_directory == "/media/movies"
      assert pending_file.parsed_title == "Inception"
      assert pending_file.parsed_year == 2010
      assert pending_file.parsed_type == "movie"
      assert pending_file.tmdb_id == 27205
      assert pending_file.tmdb_type == "movie"
      assert pending_file.confidence == 0.72
      assert pending_file.match_title == "Inception"
      assert pending_file.match_year == "2010"
      assert pending_file.match_poster_path == "/9gk7adHYeDvHkCSEhniVJErJ0Gs.jpg"
      assert pending_file.status == :pending
    end

    test "creates PendingFile from payload with no TMDB match" do
      payload =
        build_payload(%{
          tmdb_id: nil,
          tmdb_type: nil,
          confidence: nil,
          match_title: nil,
          match_year: nil,
          match_poster_path: nil,
          candidates: []
        })

      assert {:ok, pending_file} = Intake.create_from_payload(payload)

      assert pending_file.file_path == "/media/movies/Inception.2010.1080p.BluRay.mkv"
      assert pending_file.parsed_title == "Inception"
      assert pending_file.tmdb_id == nil
      assert pending_file.candidates == []
      assert pending_file.status == :pending
    end

    test "normalizes candidates — strips raw TMDB maps, keeps essential fields" do
      payload =
        build_payload(%{
          candidates: [
            {
              %{
                "id" => 27205,
                "title" => "Inception",
                "release_date" => "2010-07-15",
                "poster_path" => "/poster1.jpg",
                "overview" => "Should be stripped",
                "popularity" => 99.9,
                "vote_average" => 8.4
              },
              0.92,
              "title"
            },
            {
              %{
                "id" => 99999,
                "title" => "Other Movie",
                "release_date" => "2015-03-20",
                "poster_path" => "/poster2.jpg",
                "overview" => "Also stripped"
              },
              0.45,
              "title"
            }
          ]
        })

      assert {:ok, pending_file} = Intake.create_from_payload(payload)

      assert length(pending_file.candidates) == 2

      [first, second] = pending_file.candidates

      assert first == %{
               "tmdb_id" => 27205,
               "title" => "Inception",
               "year" => "2010",
               "score" => 0.92,
               "poster_path" => "/poster1.jpg"
             }

      assert second == %{
               "tmdb_id" => 99999,
               "title" => "Other Movie",
               "year" => "2015",
               "score" => 0.45,
               "poster_path" => "/poster2.jpg"
             }
    end

    test "uses find_or_create — second call for same file_path returns existing record" do
      payload = build_payload()

      assert {:ok, first} = Intake.create_from_payload(payload)
      assert {:ok, second} = Intake.create_from_payload(payload)

      assert first.id == second.id
    end

    test "handles extra type — uses parent_title/parent_year from parsed" do
      payload =
        build_payload(%{
          file_path: "/media/tv/Sample Show Eight/Extras/Gag Reel.mkv",
          watch_directory: "/media/tv",
          parsed: %MediaCentaur.Parser.Result{
            file_path: "/media/tv/Sample Show Eight/Extras/Gag Reel.mkv",
            title: "Gag Reel",
            year: nil,
            type: :extra,
            season: nil,
            episode: nil,
            parent_title: "Sample Show Eight",
            parent_year: nil
          },
          tmdb_id: 1396,
          tmdb_type: :tv,
          confidence: 0.65,
          match_title: "Sample Show Eight",
          match_year: "2008",
          match_poster_path: "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
          candidates: [
            {
              %{
                "id" => 1396,
                "name" => "Sample Show Eight",
                "first_air_date" => "2008-01-20",
                "poster_path" => "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg"
              },
              0.65,
              "name"
            }
          ]
        })

      assert {:ok, pending_file} = Intake.create_from_payload(payload)

      assert pending_file.parsed_title == "Sample Show Eight"
      assert pending_file.parsed_type == "extra"
      assert pending_file.tmdb_type == "tv"

      [candidate] = pending_file.candidates
      assert candidate["title"] == "Sample Show Eight"
      assert candidate["year"] == "2008"
    end
  end
end
