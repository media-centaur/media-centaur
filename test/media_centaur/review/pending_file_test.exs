defmodule MediaCentaur.Review.PendingFileTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Review

  @valid_attrs %{
    file_path: "/media/movies/Sample.Movie.2010.1080p.BluRay.mkv",
    media_directory: "/media/movies",
    parsed_title: "Sample Movie",
    parsed_year: 2010,
    parsed_type: "movie",
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
        "poster_path" => "/9gk7adHYeDvHkCSEhniVJErJ0Gs.jpg"
      }
    ]
  }

  describe ":create action" do
    test "creates a PendingFile with full attributes" do
      pending_file = Review.create_pending_file!(@valid_attrs)

      assert pending_file.file_path == @valid_attrs.file_path
      assert pending_file.media_directory == "/media/movies"
      assert pending_file.parsed_title == "Sample Movie"
      assert pending_file.parsed_year == 2010
      assert pending_file.parsed_type == "movie"
      assert pending_file.tmdb_id == 27_205
      assert pending_file.tmdb_type == "movie"
      assert pending_file.confidence == 0.72
      assert pending_file.match_title == "Sample Movie"
      assert pending_file.match_year == "2010"
      assert pending_file.status == :pending
      assert length(pending_file.candidates) == 1
    end
  end

  describe "add_pending_file/1" do
    test "returns the existing record for the same file_path" do
      {:ok, first} = Review.add_pending_file(@valid_attrs)
      {:ok, second} = Review.add_pending_file(@valid_attrs)

      assert first.id == second.id
    end
  end

  describe "approve/1" do
    test "transitions status from :pending to :approved" do
      pending_file = Review.create_pending_file!(@valid_attrs)

      assert {:ok, 1} = Review.approve([pending_file.id])
      assert {:ok, %{status: :approved}} = Review.fetch_pending_file(pending_file.id)
    end

    test "approving an approved item again approves nothing" do
      pending_file = Review.create_pending_file!(@valid_attrs)

      {:ok, 1} = Review.approve([pending_file.id])

      assert {:ok, 0} = Review.approve([pending_file.id])
    end
  end

  describe "dismiss/1" do
    test "transitions status from :pending to :dismissed" do
      pending_file = Review.create_pending_file!(@valid_attrs)

      assert {:ok, 1} = Review.dismiss([pending_file.id])
      assert {:ok, %{status: :dismissed}} = Review.fetch_pending_file(pending_file.id)
    end
  end

  describe ":destroy action" do
    test "removes the record" do
      pending_file = Review.create_pending_file!(@valid_attrs)

      assert :ok = Review.destroy_pending_file!(pending_file)
      assert Review.list_pending_files() == []
    end
  end

  describe "count_pending/0" do
    test "counts only files still awaiting review" do
      assert Review.count_pending() == 0

      first = Review.create_pending_file!(@valid_attrs)

      dismissed =
        Review.create_pending_file!(%{
          file_path: "/media/dismissed-count.mkv",
          parsed_title: "Dismissed"
        })

      {:ok, 1} = Review.dismiss([dismissed.id])

      approved =
        Review.create_pending_file!(%{
          file_path: "/media/approved-count.mkv",
          parsed_title: "Approved",
          tmdb_id: 27_205,
          tmdb_type: "movie"
        })

      {:ok, 1} = Review.approve([approved.id])

      assert Review.count_pending() == 1
      assert :ok = Review.destroy_pending_file!(first)
      assert Review.count_pending() == 0
    end
  end

  describe "parsed_attrs/1" do
    test "maps a parsed episode onto the parsed_* columns" do
      parsed = MediaCentaur.Parser.parse("/media/tv/Sample Show/Season 01/Sample.Show.S01E02.1080p.mkv")

      assert Review.PendingFile.parsed_attrs(parsed) == %{
               parsed_title: "Sample Show",
               parsed_year: nil,
               parsed_type: "tv",
               parsed_season: 1,
               parsed_episode: 2
             }
    end

    test "an extra is filed under its parent title" do
      parsed = MediaCentaur.Parser.parse("/media/movies/Sample Movie (2010)/Featurettes/Making Of.mkv")

      assert %{parsed_title: "Sample Movie", parsed_year: 2010, parsed_type: "extra"} =
               Review.PendingFile.parsed_attrs(parsed)
    end
  end
end
