defmodule MediaCentarr.Review.IntakeTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Review.Intake
  alias MediaCentarr.TestFactory
  alias MediaCentarr.Topics

  defp build_attrs(overrides \\ %{}) do
    defaults = %{
      file_path: "/media/movies/Sample.Movie.2010.1080p.BluRay.mkv",
      watch_directory: "/media/movies",
      parsed_title: "Sample Movie",
      parsed_year: 2010,
      parsed_type: "movie",
      season_number: nil,
      episode_number: nil,
      tmdb_id: 27_205,
      tmdb_type: "movie",
      confidence: 0.72,
      match_title: "Sample Movie",
      match_year: "2010",
      match_poster_path: "/9gk7adHYeDvHkCSEhniVJErJ0Gs.jpg",
      candidates: [
        %{
          "tmdb_id" => 27_205,
          "title" => "Sample Movie",
          "year" => "2010",
          "score" => 0.72,
          "poster_path" => "/9gk7adHYeDvHkCSEhniVJErJ0Gs.jpg",
          "overview" => "A thief who steals corporate secrets..."
        }
      ]
    }

    Map.merge(defaults, overrides)
  end

  describe "create_pending_file/1" do
    test "creates PendingFile from plain map attrs" do
      attrs = build_attrs()

      assert {:ok, pending_file} = Intake.create_pending_file(attrs)

      assert pending_file.file_path == "/media/movies/Sample.Movie.2010.1080p.BluRay.mkv"
      assert pending_file.watch_directory == "/media/movies"
      assert pending_file.parsed_title == "Sample Movie"
      assert pending_file.parsed_year == 2010
      assert pending_file.parsed_type == "movie"
      assert pending_file.tmdb_id == 27_205
      assert pending_file.tmdb_type == "movie"
      assert pending_file.confidence == 0.72
      assert pending_file.match_title == "Sample Movie"
      assert pending_file.match_year == "2010"
      assert pending_file.match_poster_path == "/9gk7adHYeDvHkCSEhniVJErJ0Gs.jpg"
      assert pending_file.status == :pending
    end

    test "creates PendingFile with nil TMDB fields" do
      attrs =
        build_attrs(%{
          tmdb_id: nil,
          tmdb_type: nil,
          confidence: nil,
          match_title: nil,
          match_year: nil,
          match_poster_path: nil,
          candidates: []
        })

      assert {:ok, pending_file} = Intake.create_pending_file(attrs)

      assert pending_file.file_path == "/media/movies/Sample.Movie.2010.1080p.BluRay.mkv"
      assert pending_file.parsed_title == "Sample Movie"
      assert pending_file.tmdb_id == nil
      assert pending_file.candidates == []
      assert pending_file.status == :pending
    end

    test "pre-normalized candidates pass through correctly" do
      candidates = [
        %{
          "tmdb_id" => 27_205,
          "title" => "Sample Movie",
          "year" => "2010",
          "score" => 0.92,
          "poster_path" => "/poster1.jpg",
          "overview" => "A dream heist movie"
        },
        %{
          "tmdb_id" => 99_999,
          "title" => "Other Movie",
          "year" => "2015",
          "score" => 0.45,
          "poster_path" => "/poster2.jpg",
          "overview" => "Another movie"
        }
      ]

      attrs = build_attrs(%{candidates: candidates})

      assert {:ok, pending_file} = Intake.create_pending_file(attrs)

      assert length(pending_file.candidates) == 2
      [first, second] = pending_file.candidates

      assert first == %{
               "tmdb_id" => 27_205,
               "title" => "Sample Movie",
               "year" => "2010",
               "score" => 0.92,
               "poster_path" => "/poster1.jpg",
               "overview" => "A dream heist movie"
             }

      assert second == %{
               "tmdb_id" => 99_999,
               "title" => "Other Movie",
               "year" => "2015",
               "score" => 0.45,
               "poster_path" => "/poster2.jpg",
               "overview" => "Another movie"
             }
    end

    test "find_or_create idempotency — same file_path returns same record" do
      attrs = build_attrs()

      assert {:ok, first} = Intake.create_pending_file(attrs)
      assert {:ok, second} = Intake.create_pending_file(attrs)

      assert first.id == second.id
    end

    test "broadcasts {:file_added, id} to review:updates" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.review_updates())

      attrs = build_attrs()
      assert {:ok, pending_file} = Intake.create_pending_file(attrs)

      assert_receive {:file_added, id}
      assert id == pending_file.id
    end

    test "extra type uses correct parsed_title" do
      attrs =
        build_attrs(%{
          file_path: "/media/tv/Sample Show/Extras/Gag Reel.mkv",
          watch_directory: "/media/tv",
          parsed_title: "Sample Show",
          parsed_type: "extra",
          parsed_year: nil,
          tmdb_id: 1396,
          tmdb_type: "tv",
          confidence: 0.65,
          match_title: "Sample Show",
          match_year: "2008",
          match_poster_path: "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
          candidates: [
            %{
              "tmdb_id" => 1396,
              "title" => "Sample Show",
              "year" => "2008",
              "score" => 0.65,
              "poster_path" => "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
              "overview" => nil
            }
          ]
        })

      assert {:ok, pending_file} = Intake.create_pending_file(attrs)

      assert pending_file.parsed_title == "Sample Show"
      assert pending_file.parsed_type == "extra"
      assert pending_file.tmdb_type == "tv"

      [candidate] = pending_file.candidates
      assert candidate["title"] == "Sample Show"
      assert candidate["year"] == "2008"
    end
  end

  describe "receive_files_for_review/1" do
    test "parses file paths and creates PendingFiles with metadata" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.review_updates())

      files = [
        %{file_path: "/media/movies/Sample Movie 2049 (2017).mkv", watch_dir: "/media/movies"}
      ]

      assert {:ok, 1} = Intake.receive_files_for_review(files)

      [pending] = MediaCentarr.Review.list_pending_files_for_review()
      assert pending.file_path == "/media/movies/Sample Movie 2049 (2017).mkv"
      assert pending.watch_directory == "/media/movies"
      assert pending.parsed_title == "Sample Movie"
      assert pending.parsed_year == 2049
      assert pending.parsed_type == "movie"

      assert_received {:file_added, _}
    end

    test "handles multiple files from a TV series rematch" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.review_updates())

      files = [
        %{
          file_path: "/media/tv/Sitcom (2001)/Season 1/Sitcom S01E01.mkv",
          watch_dir: "/media/tv"
        },
        %{file_path: "/media/tv/Sitcom (2001)/Season 1/Sitcom S01E02.mkv", watch_dir: "/media/tv"}
      ]

      assert {:ok, 2} = Intake.receive_files_for_review(files)

      pending_files = MediaCentarr.Review.list_pending_files_for_review()
      assert length(pending_files) == 2

      Enum.each(pending_files, fn file ->
        assert file.parsed_type == "tv"
        assert file.season_number == 1
      end)

      assert_received {:file_added, _}
      assert_received {:file_added, _}
    end

    test "idempotent — same file path returns same record" do
      files = [
        %{file_path: "/media/movies/Sample Movie (2010).mkv", watch_dir: "/media/movies"}
      ]

      assert {:ok, 1} = Intake.receive_files_for_review(files)
      assert {:ok, 1} = Intake.receive_files_for_review(files)

      # Still only one PendingFile
      assert length(MediaCentarr.Review.list_pending_files_for_review()) == 1
    end
  end

  describe "complete_review/1" do
    test "destroys PendingFile and broadcasts {:file_reviewed, id}" do
      pending_file = TestFactory.create_pending_file()
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.review_updates())

      assert :ok = Intake.complete_review(pending_file.id)

      assert_receive {:file_reviewed, id}
      assert id == pending_file.id

      assert {:error, :not_found} = MediaCentarr.Review.get_pending_file(pending_file.id)
    end

    test "handles already-removed PendingFile gracefully" do
      assert :ok = Intake.complete_review(Ecto.UUID.generate())
    end
  end
end
