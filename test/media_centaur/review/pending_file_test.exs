defmodule MediaCentaur.Review.PendingFileTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Review.PendingFile

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
      pending_file =
        PendingFile
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create!()

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
      first =
        PendingFile
        |> Ash.Changeset.for_create(:find_or_create, @valid_attrs)
        |> Ash.create!()

      second =
        PendingFile
        |> Ash.Changeset.for_create(:find_or_create, @valid_attrs)
        |> Ash.create!()

      assert first.id == second.id
    end
  end

  describe ":approve action" do
    test "transitions status from :pending to :approved" do
      pending_file =
        PendingFile
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create!()

      approved =
        pending_file
        |> Ash.Changeset.for_update(:approve, %{})
        |> Ash.update!()

      assert approved.status == :approved
    end

    test "rejects non-pending status" do
      pending_file =
        PendingFile
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create!()

      approved =
        pending_file
        |> Ash.Changeset.for_update(:approve, %{})
        |> Ash.update!()

      assert {:error, _} =
               approved
               |> Ash.Changeset.for_update(:approve, %{})
               |> Ash.update()
    end
  end

  describe ":dismiss action" do
    test "transitions status from :pending to :dismissed" do
      pending_file =
        PendingFile
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create!()

      dismissed =
        pending_file
        |> Ash.Changeset.for_update(:dismiss, %{})
        |> Ash.update!()

      assert dismissed.status == :dismissed
    end
  end

  describe ":set_tmdb_match action" do
    test "updates match fields while keeping status :pending" do
      pending_file =
        PendingFile
        |> Ash.Changeset.for_create(:create, %{
          file_path: "/media/movies/Unknown.mkv",
          parsed_title: "Unknown"
        })
        |> Ash.create!()

      updated =
        pending_file
        |> Ash.Changeset.for_update(:set_tmdb_match, %{
          tmdb_id: 12345,
          tmdb_type: "movie",
          confidence: 1.0,
          match_title: "The Unknown Movie",
          match_year: "2020",
          match_poster_path: "/poster.jpg"
        })
        |> Ash.update!()

      assert updated.status == :pending
      assert updated.tmdb_id == 12345
      assert updated.match_title == "The Unknown Movie"
      assert updated.confidence == 1.0
    end
  end

  describe ":pending read action" do
    test "returns only :pending records sorted by inserted_at" do
      first =
        PendingFile
        |> Ash.Changeset.for_create(:create, %{
          file_path: "/media/first.mkv",
          parsed_title: "First"
        })
        |> Ash.create!()

      _dismissed =
        PendingFile
        |> Ash.Changeset.for_create(:create, %{
          file_path: "/media/dismissed.mkv",
          parsed_title: "Dismissed"
        })
        |> Ash.create!()
        |> Ash.Changeset.for_update(:dismiss, %{})
        |> Ash.update!()

      second =
        PendingFile
        |> Ash.Changeset.for_create(:create, %{
          file_path: "/media/second.mkv",
          parsed_title: "Second"
        })
        |> Ash.create!()

      pending = Ash.read!(PendingFile, action: :pending)

      assert length(pending) == 2
      assert Enum.map(pending, & &1.id) == [first.id, second.id]
    end
  end

  describe ":destroy action" do
    test "removes the record" do
      pending_file =
        PendingFile
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create!()

      assert :ok = Ash.destroy!(pending_file)
      assert Ash.read!(PendingFile) == []
    end
  end
end
