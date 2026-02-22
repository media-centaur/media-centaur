defmodule MediaManager.Library.WatchedFileReviewTest do
  use MediaManager.DataCase

  alias MediaManager.Library.WatchedFile

  describe ":approve action" do
    test "transitions :pending_review to :approved" do
      file = create_pending_review_file(%{tmdb_id: "12345", confidence_score: 0.6})

      {:ok, approved} =
        file
        |> Ash.Changeset.for_update(:approve, %{})
        |> Ash.update()

      assert approved.state == :approved
    end

    test "rejects non-pending_review files" do
      file = create_watched_file()
      assert file.state == :detected

      assert {:error, _} =
               file
               |> Ash.Changeset.for_update(:approve, %{})
               |> Ash.update()
    end
  end

  describe ":dismiss action" do
    test "transitions :pending_review to :dismissed" do
      file = create_pending_review_file()

      {:ok, dismissed} =
        file
        |> Ash.Changeset.for_update(:dismiss, %{})
        |> Ash.update()

      assert dismissed.state == :dismissed
    end

    test "rejects non-pending_review files" do
      file = create_watched_file()
      assert file.state == :detected

      assert {:error, _} =
               file
               |> Ash.Changeset.for_update(:dismiss, %{})
               |> Ash.update()
    end
  end

  describe ":set_tmdb_match action" do
    test "updates match fields without changing state" do
      file = create_pending_review_file()

      {:ok, matched} =
        file
        |> Ash.Changeset.for_update(:set_tmdb_match, %{
          tmdb_id: "99999",
          match_title: "New Movie",
          match_year: "2024",
          match_poster_path: "/new_poster.jpg",
          confidence_score: 1.0
        })
        |> Ash.update()

      assert matched.state == :pending_review
      assert matched.tmdb_id == "99999"
      assert matched.match_title == "New Movie"
      assert matched.match_year == "2024"
      assert matched.match_poster_path == "/new_poster.jpg"
      assert matched.confidence_score == 1.0
    end

    test "rejects non-pending_review files" do
      file = create_watched_file()

      assert {:error, _} =
               file
               |> Ash.Changeset.for_update(:set_tmdb_match, %{tmdb_id: "12345"})
               |> Ash.update()
    end
  end

  describe ":pending_review_files read action" do
    test "returns only pending_review files sorted by inserted_at asc" do
      _detected = create_watched_file(%{file_path: "/media/detected.mkv"})
      pending_a = create_pending_review_file(%{file_path: "/media/pending_a.mkv"})

      Process.sleep(10)
      pending_b = create_pending_review_file(%{file_path: "/media/pending_b.mkv"})

      files = Ash.read!(WatchedFile, action: :pending_review_files)

      assert length(files) == 2
      assert Enum.map(files, & &1.id) == [pending_a.id, pending_b.id]
    end
  end
end
