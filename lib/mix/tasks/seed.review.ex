defmodule Mix.Tasks.Seed.Review do
  @shortdoc "Seed review UI with all visual cases"

  @moduledoc """
  Populates PendingFile records covering every review UI state:
  no results, low confidence, tied candidates, single-file, and multi-file groups.

  Idempotent — clears all pending files first, then re-creates seed data.

      mix seed.review
  """
  use Mix.Task

  alias MediaCentarr.Repo
  alias MediaCentarr.Review
  alias MediaCentarr.Review.PendingFile

  @impl true
  def run(_) do
    Mix.Task.run("app.start")

    # Step 1: Clear all pending files
    Repo.delete_all(PendingFile)

    # Step 2: Insert seed data
    records = Enum.map(seed_data(), &Review.create_pending_file!/1)

    # Step 3: Print summary
    count = length(records)
    no_results = Enum.count(records, &is_nil(&1.tmdb_id))
    with_candidates = Enum.count(records, &(is_list(&1.candidates) and &1.candidates != []))
    low_confidence = Enum.count(records, &(not is_nil(&1.confidence) and &1.confidence < 0.80))
    tv = Enum.count(records, &(&1.parsed_type == "tv"))
    movies = Enum.count(records, &(&1.parsed_type == "movie"))

    Mix.shell().info("""
    Seeded #{count} pending files for review:
      No TMDB results: #{no_results}
      Low confidence:  #{low_confidence}
      Tied candidates: #{with_candidates}
      Movies:          #{movies}
      TV episodes:     #{tv}
    """)
  end

  defp seed_data do
    [
      # Single-file — No TMDB results (movie)
      %{
        file_path: "/media/movies/Obscure.Indie.Film.2024.mkv",
        watch_directory: "/media/movies",
        parsed_title: "Obscure Indie Film",
        parsed_year: 2024,
        parsed_type: "movie",
        tmdb_id: nil,
        confidence: nil,
        candidates: []
      },

      # Single-file — Low confidence (movie)
      %{
        file_path: "/media/movies/Sample.Movie.Twelve.2022.1080p.BluRay.mkv",
        watch_directory: "/media/movies",
        parsed_title: "Sample Movie Twelve",
        parsed_year: 2022,
        parsed_type: "movie",
        tmdb_id: 882_598,
        confidence: 0.62,
        match_title: "Sample Movie Twelve",
        match_year: "2022",
        match_poster_path: "/aPqcQwu4VGEewPhagWNncDbJ9Xp.jpg"
      },

      # Single-file — Tied candidates (movie)
      %{
        file_path: "/media/movies/Sample.Movie.Eleven.1986.mkv",
        watch_directory: "/media/movies",
        parsed_title: "Sample Movie Eleven",
        parsed_year: nil,
        parsed_type: "movie",
        tmdb_id: nil,
        confidence: nil,
        candidates: [
          %{
            "tmdb_id" => 9426,
            "title" => "Sample Movie Eleven",
            "year" => "1986",
            "confidence" => 0.85,
            "poster_path" => "/8gZWMhJHRvaXdXsNhERtqNHYpH3.jpg"
          },
          %{
            "tmdb_id" => 11_815,
            "title" => "Sample Movie Eleven",
            "year" => "1958",
            "confidence" => 0.85,
            "poster_path" => "/kXdBcDh2EbgSIf4Oo1dxKapZM2f.jpg"
          }
        ]
      },

      # Multi-file group — TV series, Episode 1: low confidence
      %{
        file_path: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One.S01E01.mkv",
        watch_directory: "/media/tv",
        parsed_title: "Sample Show One",
        parsed_year: 2001,
        parsed_type: "tv",
        season_number: 1,
        episode_number: 1,
        tmdb_id: 4556,
        confidence: 0.55,
        match_title: "Sample Show One",
        match_year: "2001",
        match_poster_path: "/w7ri7byEYLdciSZOwWHj6TUAX7j.jpg"
      },

      # Multi-file group — TV series, Episode 2: no results
      %{
        file_path: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One.S01E02.mkv",
        watch_directory: "/media/tv",
        parsed_title: "Sample Show One",
        parsed_year: 2001,
        parsed_type: "tv",
        season_number: 1,
        episode_number: 2,
        tmdb_id: nil,
        confidence: nil,
        candidates: []
      },

      # Multi-file group — TV series, Episode 3: tied candidates
      %{
        file_path: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One.S01E03.mkv",
        watch_directory: "/media/tv",
        parsed_title: "Sample Show One",
        parsed_year: 2001,
        parsed_type: "tv",
        season_number: 1,
        episode_number: 3,
        tmdb_id: nil,
        confidence: nil,
        candidates: [
          %{
            "tmdb_id" => 4556,
            "title" => "Sample Show One",
            "year" => "2001",
            "confidence" => 0.75,
            "poster_path" => "/w7ri7byEYLdciSZOwWHj6TUAX7j.jpg"
          },
          %{
            "tmdb_id" => 295_778,
            "title" => "Sample Show One",
            "year" => "2026",
            "confidence" => 0.75,
            "poster_path" => "/nNNM50G7p9C3n4vgidCiybsIdHA.jpg"
          }
        ]
      },

      # Multi-file group — TV series, Episode 4: below threshold
      %{
        file_path: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One.S01E04.mkv",
        watch_directory: "/media/tv",
        parsed_title: "Sample Show One",
        parsed_year: 2001,
        parsed_type: "tv",
        season_number: 1,
        episode_number: 4,
        tmdb_id: 4556,
        confidence: 0.78,
        match_title: "Sample Show One",
        match_year: "2001",
        match_poster_path: "/w7ri7byEYLdciSZOwWHj6TUAX7j.jpg"
      },

      # Single-file — Low confidence TV episode (standalone)
      %{
        file_path: "/media/tv/Firefly (2002)/Season 1/Firefly.S01E01.mkv",
        watch_directory: "/media/tv",
        parsed_title: "Firefly",
        parsed_year: 2002,
        parsed_type: "tv",
        season_number: 1,
        episode_number: 1,
        tmdb_id: 1437,
        confidence: 0.71,
        match_title: "Firefly",
        match_year: "2002",
        match_poster_path: "/vZcKsy4sGAvWMVqLluwYuoi11Kj.jpg"
      },

      # Single-file — Very low confidence (garbled release name)
      %{
        file_path: "/media/movies/x264-SPARKS.mkv",
        watch_directory: "/media/movies",
        parsed_title: "x264",
        parsed_type: nil,
        tmdb_id: 728_837,
        confidence: 0.18,
        match_title: "Sparks",
        match_year: "2020",
        match_poster_path: "/h5EK1ajOh5vVNWai0qtviPTobmr.jpg"
      }
    ]
  end
end
