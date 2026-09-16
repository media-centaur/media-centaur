defmodule MediaCentaur.ReviewTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Review

  setup do
    media_dir = Path.join(System.tmp_dir!(), "review_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(media_dir)
    on_exit(fn -> File.rm_rf!(media_dir) end)

    %{media_dir: media_dir}
  end

  describe "sweep_completed_reviews/0" do
    # A queue row is destroyed when its import finishes
    # (`complete_review/1`, driven by `{:review_completed, id}` from
    # `Pipeline.Import`). PubSub has no replay, so a listener that was not
    # subscribed at that instant loses the message and the row is orphaned
    # at `:approved` forever. 73 such rows were found on a live instance
    # from one bulk approve on 2026-06-08.
    #
    # They are not inert: `file_path` is unique and
    # `find_or_create_pending_file/1` returns a row whatever its status,
    # so a re-match landing on one gets a row the queue does not list —
    # the file leaves the library and cannot be re-reviewed.
    #
    # `:approved` with a linked file is unambiguous: the import finished,
    # so the row should be gone. `:approved` with no link is the
    # legitimate in-flight state and must survive.
    test "deletes an approved row whose file is linked" do
      path = "/media/test/imported.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.approve_pending_file(pending)

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert {:ok, 1} = Review.sweep_completed_reviews()
      assert Review.list_pending_files() == []
    end

    test "keeps an approved row whose file is not linked — the import is outstanding" do
      pending = create_pending_file(%{file_path: "/media/test/in-flight.mkv"})
      {:ok, _} = Review.approve_pending_file(pending)

      assert {:ok, 0} = Review.sweep_completed_reviews()
      assert length(Review.list_pending_files()) == 1
    end

    test "keeps a pending row even when its file is somehow linked" do
      path = "/media/test/awaiting.mkv"
      create_pending_file(%{file_path: path})

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert {:ok, 0} = Review.sweep_completed_reviews()
      assert length(Review.list_pending_files()) == 1
    end

    test "keeps a dismissed row whatever its file's state" do
      path = "/media/test/dismissed.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.dismiss(pending)

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert {:ok, 0} = Review.sweep_completed_reviews()
      assert Review.dismissed?(path)
    end

    test "reports zero on an empty table" do
      assert {:ok, 0} = Review.sweep_completed_reviews()
    end
  end

  describe "find_or_create_pending_file/1 on a terminal row" do
    test "reopens a stale approved row — its import finished, the row should have gone" do
      path = "/media/test/stale.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.approve_pending_file(pending)

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert {:ok, reopened} = Review.find_or_create_pending_file(%{file_path: path})
      assert reopened.status == :pending
      assert length(Review.list_pending_files_for_review()) == 1
    end

    test "leaves an approved row alone while its import is outstanding" do
      path = "/media/test/in-flight.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.approve_pending_file(pending)

      assert {:ok, same} = Review.find_or_create_pending_file(%{file_path: path})
      assert same.status == :approved
      assert Review.list_pending_files_for_review() == []
    end

    test "leaves a dismissed row blocking — that is what dismiss means" do
      path = "/media/test/dismissed.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.dismiss(pending)

      assert {:ok, same} = Review.find_or_create_pending_file(%{file_path: path})
      assert same.status == :dismissed
      assert Review.list_pending_files_for_review() == []
    end
  end

  describe "reopen_for_review/1" do
    # The re-match path. Unlike discovery it is an explicit act on files
    # the user owns, so it supersedes an older decision — including a
    # dismissal, which every automatic path still refuses to reconsider.
    test "reopens a dismissed row" do
      path = "/media/test/dismissed.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.dismiss(pending)

      assert {:ok, reopened} = Review.reopen_for_review(%{file_path: path})
      assert reopened.status == :pending
      refute Review.dismissed?(path)
    end

    test "reopens an approved row" do
      path = "/media/test/approved.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.approve_pending_file(pending)

      assert {:ok, reopened} = Review.reopen_for_review(%{file_path: path})
      assert reopened.status == :pending
    end

    test "creates a row when the path has never been queued" do
      assert {:ok, created} = Review.reopen_for_review(%{file_path: "/media/test/new.mkv"})
      assert created.status == :pending
    end

    test "refreshes the parsed metadata it is handed" do
      path = "/media/test/renamed.mkv"
      pending = create_pending_file(%{file_path: path, parsed_title: "Old Guess"})
      {:ok, _} = Review.dismiss(pending)

      assert {:ok, reopened} = Review.reopen_for_review(%{file_path: path, parsed_title: "New Guess"})
      assert reopened.parsed_title == "New Guess"
    end
  end

  describe "dismissed?/1" do
    # Dismiss is a person deciding the file is not library content, and
    # `find_or_create_pending_file/1` keys on file_path regardless of
    # status — so the decision is terminal whether or not anything reads
    # it. `Pipeline.Discovery` reads it to stop before the parse and the
    # TMDB searches it would then discard.
    test "true for a path dismissed in review" do
      pending = create_pending_file(%{file_path: "/media/test/capture.mkv"})
      {:ok, _} = Review.dismiss(pending)

      assert Review.dismissed?("/media/test/capture.mkv")
    end

    test "false for a path still awaiting review" do
      create_pending_file(%{file_path: "/media/test/awaiting.mkv"})

      refute Review.dismissed?("/media/test/awaiting.mkv")
    end

    test "false for a path that was approved" do
      pending = create_pending_file(%{file_path: "/media/test/approved.mkv"})
      {:ok, _} = Review.approve_pending_file(pending)

      refute Review.dismissed?("/media/test/approved.mkv")
    end

    test "false for a path the queue has never seen" do
      refute Review.dismissed?("/media/test/unknown.mkv")
    end

    test "false once the dismissed row is dropped" do
      pending = create_pending_file(%{file_path: "/media/test/capture.mkv"})
      {:ok, _} = Review.dismiss(pending)
      {:ok, 1} = Review.drop_pending_files(["/media/test/capture.mkv"])

      refute Review.dismissed?("/media/test/capture.mkv")
    end
  end

  describe "clear_all/0" do
    test "destroys every pending file, whatever its status" do
      create_pending_file()
      dismissed = create_pending_file()
      {:ok, _} = Review.dismiss_pending_file(dismissed)

      assert :ok = Review.clear_all()
      assert Review.list_pending_files() == []
    end
  end

  describe "delete_pending_file/1" do
    test "removes the file from disk, its FilePresence row, and the PendingFile row", %{
      media_dir: media_dir
    } do
      path = Path.join(media_dir, "broken_release.mkv")
      File.write!(path, "garbage")
      FilePresence.stamp(path, media_dir)

      pending_file =
        create_pending_file(%{file_path: path, media_directory: media_dir, parsed_title: "Broken"})

      assert {:ok, _} = Review.delete_pending_file(pending_file)

      refute File.exists?(path)
      refute MapSet.member?(FilePresence.list_paths_for_media_dir(media_dir), path)
      assert Review.fetch_pending_file(pending_file.id) == {:error, :not_found}
    end

    test "treats an already-missing file as success — the DB cleanup still runs", %{
      media_dir: media_dir
    } do
      path = Path.join(media_dir, "already_gone.mkv")

      pending_file =
        create_pending_file(%{file_path: path, media_directory: media_dir, parsed_title: "Gone"})

      assert {:ok, _} = Review.delete_pending_file(pending_file)
      assert Review.fetch_pending_file(pending_file.id) == {:error, :not_found}
    end
  end

  describe "delete_group/1" do
    test "deletes every file in the group and reports counts", %{media_dir: media_dir} do
      paths =
        for name <- ["a.mkv", "b.mkv"] do
          path = Path.join(media_dir, name)
          File.write!(path, "x")
          path
        end

      files =
        Enum.map(paths, fn path ->
          create_pending_file(%{file_path: path, media_directory: media_dir, parsed_title: "Group"})
        end)

      assert {2, 0} = Review.delete_group(files)
      assert Enum.all?(paths, &(not File.exists?(&1)))
    end
  end
end
