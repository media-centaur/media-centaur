defmodule MediaCentaur.Review.PendingFileTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Review

  @valid_attrs %{
    file_path: "/media/movies/Inception.2010.1080p.BluRay.mkv",
    watch_directory: "/media/movies",
    parsed_title: "Inception",
    parsed_year: 2010,
    parsed_type: "movie",
    tmdb_id: 27205,
    tmdb_type: "movie",
    confidence: 0.72,
    match_title: "Inception",
    match_year: "2010",
    match_poster_path: "/9gk7adHYeDvHkCSEhniVJErJ0Gs.jpg",
    candidates: [
      %{
        "tmdb_id" => 27205,
        "title" => "Inception",
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
      assert pending_file.watch_directory == "/media/movies"
      assert pending_file.parsed_title == "Inception"
      assert pending_file.parsed_year == 2010
      assert pending_file.parsed_type == "movie"
      assert pending_file.tmdb_id == 27205
      assert pending_file.tmdb_type == "movie"
      assert pending_file.confidence == 0.72
      assert pending_file.match_title == "Inception"
      assert pending_file.match_year == "2010"
      assert pending_file.status == :pending
      assert length(pending_file.candidates) == 1
    end
  end

  describe ":find_or_create action" do
    test "returns existing record for same file_path" do
      first = Review.find_or_create_pending_file!(@valid_attrs)
      second = Review.find_or_create_pending_file!(@valid_attrs)

      assert first.id == second.id
    end
  end

  describe ":approve action" do
    test "transitions status from :pending to :approved" do
      pending_file = Review.create_pending_file!(@valid_attrs)

      {:ok, approved} = Review.approve_pending_file(pending_file)

      assert approved.status == :approved
    end

    test "rejects non-pending status" do
      pending_file = Review.create_pending_file!(@valid_attrs)

      {:ok, approved} = Review.approve_pending_file(pending_file)

      assert {:error, _} = Review.approve_pending_file(approved)
    end
  end

  describe ":dismiss action" do
    test "transitions status from :pending to :dismissed" do
      pending_file = Review.create_pending_file!(@valid_attrs)

      {:ok, dismissed} = Review.dismiss_pending_file(pending_file)

      assert dismissed.status == :dismissed
    end
  end

  describe ":set_tmdb_match action" do
    test "updates match fields while keeping status :pending" do
      pending_file =
        Review.create_pending_file!(%{
          file_path: "/media/movies/Unknown.mkv",
          parsed_title: "Unknown"
        })

      {:ok, updated} =
        Review.set_pending_file_match(pending_file, %{
          tmdb_id: 12345,
          tmdb_type: "movie",
          confidence: 1.0,
          match_title: "The Unknown Movie",
          match_year: "2020",
          match_poster_path: "/poster.jpg"
        })

      assert updated.status == :pending
      assert updated.tmdb_id == 12345
      assert updated.match_title == "The Unknown Movie"
      assert updated.confidence == 1.0
    end
  end

  describe ":pending read action" do
    test "returns only :pending records sorted by inserted_at" do
      first =
        Review.create_pending_file!(%{
          file_path: "/media/first.mkv",
          parsed_title: "First"
        })

      dismissed_file =
        Review.create_pending_file!(%{
          file_path: "/media/dismissed.mkv",
          parsed_title: "Dismissed"
        })

      {:ok, _dismissed} = Review.dismiss_pending_file(dismissed_file)

      second =
        Review.create_pending_file!(%{
          file_path: "/media/second.mkv",
          parsed_title: "Second"
        })

      pending = Review.list_pending_files_for_review!()

      assert length(pending) == 2
      assert Enum.map(pending, & &1.id) == [first.id, second.id]
    end
  end

  describe ":destroy action" do
    test "removes the record" do
      pending_file = Review.create_pending_file!(@valid_attrs)

      assert :ok = Review.destroy_pending_file!(pending_file)
      assert Review.list_pending_files!() == []
    end
  end
end
