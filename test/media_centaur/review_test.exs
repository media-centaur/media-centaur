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

  describe "settle_with_library/0" do
    # A queue row closes on the library's link outcome for its file
    # (`file_linked/1`, `file_not_linked/1`). PubSub has no replay, so a
    # listener that was not subscribed at that instant loses the message.
    # 73 rows orphaned at `:approved` were found on a live instance from one
    # bulk approve on 2026-06-08.
    #
    # They are not inert: `file_path` is unique and
    # `find_or_create_pending_file/1` returns a row whatever its status,
    # so a re-match landing on one gets a row the queue does not list —
    # the file leaves the library and cannot be re-reviewed.
    #
    # Run at startup, before anything is in flight: a linked file's row is
    # done, and an approved row whose file is not linked is an import that
    # did not finish.
    test "deletes an approved row whose file is linked" do
      path = "/media/test/imported.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.approve_pending_file(pending)

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert %{closed: 1, reopened: 0} = Review.settle_with_library()
      assert Review.list_pending_files() == []
    end

    # Changed 2026-09-29 (campaign `review-closes-on-link`): nothing is in
    # flight at startup, so an approved row with no link is an import that
    # did not finish. It used to be kept as "outstanding" — at `:approved`,
    # a status the queue does not list — which is how an approval vanished.
    test "returns an approved row whose file is not linked to the queue, with the reason" do
      pending = create_pending_file(%{file_path: "/media/test/in-flight.mkv"})
      {:ok, _} = Review.approve_pending_file(pending)

      assert %{closed: 0, reopened: 1} = Review.settle_with_library()
      assert [reopened] = Review.list_pending_files_for_review()
      assert reopened.id == pending.id
      assert reopened.error_message =~ "didn't finish"
    end

    # Changed 2026-09-29 (campaign `review-closes-on-link`): a linked file is
    # in the library, so there is nothing left to review, whatever the row's
    # status. It used to be kept.
    test "deletes a pending row whose file is linked" do
      path = "/media/test/awaiting.mkv"
      create_pending_file(%{file_path: path})

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert %{closed: 1, reopened: 0} = Review.settle_with_library()
      assert Review.list_pending_files() == []
    end

    test "keeps a pending row whose file is not linked — it awaits a decision" do
      create_pending_file(%{file_path: "/media/test/awaiting.mkv"})

      assert %{closed: 0, reopened: 0} = Review.settle_with_library()
      assert length(Review.list_pending_files_for_review()) == 1
    end

    test "keeps a dismissed row whatever its file's state" do
      path = "/media/test/dismissed.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.dismiss(pending)

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert %{closed: 0, reopened: 0} = Review.settle_with_library()
      assert Review.dismissed?(path)
    end

    # 2026-09-29: the rows changed with no broadcast, so the Review badge
    # kept its old count until the next review event.
    test "tells review subscribers what it closed and reopened" do
      linked = create_pending_file(%{file_path: "/media/test/linked.mkv"})
      movie = create_movie(%{name: "Sample Movie"})

      create_linked_file(%{
        file_path: "/media/test/linked.mkv",
        media_dir: "/media/test",
        movie_id: movie.id
      })

      unfinished = create_pending_file(%{file_path: "/media/test/unfinished.mkv"})
      {:ok, _} = Review.approve_pending_file(unfinished)

      Review.subscribe()
      Review.settle_with_library()

      linked_id = linked.id
      unfinished_id = unfinished.id
      assert_receive {:file_reviewed, %Review.Events.FileReviewed{pending_file_id: ^linked_id}}
      assert_receive {:file_added, %Review.Events.FileAdded{pending_file_id: ^unfinished_id}}
    end

    test "reports zero on an empty table" do
      assert %{closed: 0, reopened: 0} = Review.settle_with_library()
    end
  end

  # The library reports every file's link outcome by path; these are the
  # only ways a review item closes or reopens.
  # Replaces "choosing the episode" and "episode_choices/1" (2026-09-29,
  # campaign `review-coherence`): Review chose the episode of a series match
  # whose name numbered none, and refused approval until it had one. A
  # position is now decided only in episode mapping, which Import sends such
  # a file to (`pipeline_test.exs`), so Review approves the identity alone.
  describe "a series match whose name numbers no episode" do
    test "is approved on its identity; the position is episode mapping's" do
      pending =
        create_pending_file(%{
          file_path: "/media/test/Sample Special 2025/Sample.Special.2025.1080p.WEBRip.mp4",
          parsed_type: "movie",
          tmdb_id: 1396,
          tmdb_type: "tv"
        })

      assert {:ok, 1} = Review.approve_group([pending.id])
    end
  end

  # 2026-09-29 regression: the approve button checked only the group's first
  # file, and approval required no identity. A sibling without a match was
  # published with `tmdb_type: nil`; the Import producer raised on it and lost
  # every import queued behind it, leaving those items "Importing" until a
  # restart. Approval also ran on an unmonitored task that reported back by
  # broadcast; it is now one synchronous call.
  describe "approve_group/1" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_matched())
      :ok
    end

    defp matched_file(path, overrides \\ %{}) do
      create_pending_file(
        Map.merge(
          %{
            file_path: path,
            media_directory: "/media/test",
            parsed_type: "tv",
            season_number: 1,
            episode_number: 1,
            tmdb_id: 4242,
            tmdb_type: "tv",
            confidence: 0.6
          },
          overrides
        )
      )
    end

    test "approves the group's pending files and sends each match to Import" do
      first = matched_file("/media/test/Sample Show/S01E01.mkv")
      second = matched_file("/media/test/Sample Show/S01E02.mkv", %{episode_number: 2})

      assert {:ok, 2} = Review.approve_group([first.id, second.id])

      assert_receive {:file_matched, %{file_path: "/media/test/Sample Show/S01E01.mkv", tmdb_id: 4242}}
      assert_receive {:file_matched, %{file_path: "/media/test/Sample Show/S01E02.mkv", tmdb_id: 4242}}
      assert Enum.all?(Review.list_pending_files(), &(&1.status == :approved))
    end

    test "refuses a group with a file that has no identity, and sends nothing" do
      matched = matched_file("/media/test/Sample Show/S01E01.mkv")

      unmatched =
        matched_file("/media/test/Sample Show/S01E02.mkv", %{tmdb_id: nil, tmdb_type: nil})

      assert {:error, :no_identity} = Review.approve_group([matched.id, unmatched.id])

      refute_receive {:file_matched, _}
      assert Enum.all?(Review.list_pending_files(), &(&1.status == :pending))
    end

    test "refuses a group whose files carry different identities" do
      first = matched_file("/media/test/Sample Show/S01E01.mkv")
      second = matched_file("/media/test/Sample Show/S01E02.mkv", %{tmdb_id: 9999})

      assert {:error, :mixed_identities} = Review.approve_group([first.id, second.id])
      refute_receive {:file_matched, _}
    end

    test "approves only the files still pending — an importing sibling is left alone" do
      importing = matched_file("/media/test/Sample Show/S01E01.mkv")
      {:ok, _} = Review.approve_pending_file(importing)
      pending = matched_file("/media/test/Sample Show/S01E02.mkv", %{episode_number: 2})

      assert {:ok, 1} = Review.approve_group([importing.id, pending.id])

      assert_receive {:file_matched, %{file_path: "/media/test/Sample Show/S01E02.mkv"}}
      refute_receive {:file_matched, _}
    end

    test "tells review subscribers which files were approved" do
      file = matched_file("/media/test/Sample Show/S01E01.mkv")
      Review.subscribe()

      assert {:ok, 1} = Review.approve_group([file.id])

      file_id = file.id

      assert_receive {:files_approved,
                      %MediaCentaur.Review.Events.FilesApproved{pending_file_ids: [^file_id]}}
    end

    test "a single file without an identity cannot be approved" do
      unmatched =
        create_pending_file(%{
          file_path: "/media/test/Movie.A.mkv",
          parsed_type: "movie",
          tmdb_id: nil,
          tmdb_type: nil
        })

      assert {:error, changeset} = Review.approve_pending_file(unmatched)
      assert %{tmdb_id: _} = errors_on(changeset)
    end
  end

  describe "group_identity/1" do
    test "is the one identity the files share" do
      files = [
        build_pending_file(%{tmdb_id: 4242, tmdb_type: "tv"}),
        build_pending_file(%{tmdb_id: 4242, tmdb_type: "tv"})
      ]

      assert {:ok, {4242, "tv"}} = Review.group_identity(files)
    end

    test "reports a missing identity before a mixed one" do
      files = [
        build_pending_file(%{tmdb_id: 4242, tmdb_type: "tv"}),
        build_pending_file(%{tmdb_id: nil, tmdb_type: nil}),
        build_pending_file(%{tmdb_id: 9999, tmdb_type: "tv"})
      ]

      assert {:error, :no_identity} = Review.group_identity(files)
    end

    test "reports different identities" do
      files = [
        build_pending_file(%{tmdb_id: 4242, tmdb_type: "tv"}),
        build_pending_file(%{tmdb_id: 4242, tmdb_type: "movie"})
      ]

      assert {:error, :mixed_identities} = Review.group_identity(files)
    end
  end

  describe "fetch_review_groups/0 — the representative" do
    # 2026-09-29: the group's state was read from its first file. A file that
    # joined a group still importing was hidden behind "Importing", with no
    # action, until its siblings finished.
    test "is a pending file when the group has one" do
      importing =
        create_pending_file(%{file_path: "/media/test/Sample Show/S01E01.mkv"})

      {:ok, _} = Review.approve_pending_file(importing)

      pending =
        create_pending_file(%{file_path: "/media/test/Sample Show/S01E02.mkv"})

      assert [%{representative: representative}] = Review.fetch_review_groups()
      assert representative.id == pending.id
    end
  end

  describe "fetch_review_groups/0" do
    # An approved item waits in the queue for its file's link outcome, so
    # the review page lists it (as importing) alongside the open items.
    test "lists pending and approved items, not dismissed ones" do
      create_pending_file(%{file_path: "/media/test/Open/open.mkv", media_directory: "/media/test"})

      approved =
        create_pending_file(%{file_path: "/media/test/Approved/a.mkv", media_directory: "/media/test"})

      {:ok, _} = Review.approve_pending_file(approved)

      dismissed =
        create_pending_file(%{file_path: "/media/test/Dismissed/d.mkv", media_directory: "/media/test"})

      {:ok, _} = Review.dismiss(dismissed)

      roots = Enum.map(Review.fetch_review_groups(), fn %{key: {_dir, root}} -> root end)
      assert Enum.sort(roots) == ["Approved", "Open"]
    end
  end

  describe "file_linked/1" do
    test "removes an approved item and tells review subscribers" do
      Review.subscribe()
      pending = create_pending_file(%{file_path: "/media/test/linked.mkv"})
      {:ok, _} = Review.approve_pending_file(pending)

      assert :ok = Review.file_linked("/media/test/linked.mkv")

      assert Review.list_pending_files() == []
      pending_id = pending.id
      assert_receive {:file_reviewed, %Review.Events.FileReviewed{pending_file_id: ^pending_id}}
    end

    test "removes a pending item — a confident re-run linked it" do
      create_pending_file(%{file_path: "/media/test/rerun.mkv"})

      assert :ok = Review.file_linked("/media/test/rerun.mkv")

      assert Review.list_pending_files() == []
    end

    test "does nothing for a file with no item" do
      assert :ok = Review.file_linked("/media/test/never-queued.mkv")
    end
  end

  describe "file_parked/1" do
    # A parked file belongs to the episode-mapping queue from here on.
    test "removes the item" do
      pending = create_pending_file(%{file_path: "/media/test/parked.mkv"})
      {:ok, _} = Review.approve_pending_file(pending)

      assert :ok = Review.file_parked("/media/test/parked.mkv")

      assert Review.list_pending_files() == []
    end
  end

  describe "file_not_linked/1" do
    test "returns an approved item to the queue with the reason, keeping the chosen match" do
      Review.subscribe()

      pending =
        create_pending_file(%{
          file_path: "/media/test/special.mp4",
          tmdb_id: 1396,
          tmdb_type: "tv",
          season_number: 1,
          episode_number: 22,
          match_title: "Sample Show"
        })

      {:ok, _} = Review.approve_pending_file(pending)

      assert :ok =
               Review.file_not_linked(%{
                 file_path: "/media/test/special.mp4",
                 media_dir: "/media/test",
                 reason: {:ingest_failed, :boom},
                 match: %{tmdb_id: 1396, tmdb_type: :tv}
               })

      reopened = hd(Review.list_pending_files_for_review())
      assert reopened.id == pending.id
      assert reopened.error_message =~ "Adding it to the library failed"
      assert reopened.tmdb_id == 1396
      assert reopened.match_title == "Sample Show"

      pending_id = pending.id
      assert_receive {:file_added, %Review.Events.FileAdded{pending_file_id: ^pending_id}}
    end

    # An automatic match that links nothing used to leave no trace at all:
    # no review item, and the file re-searched on every restart.
    test "queues a file that has no item with the match it was imported under" do
      assert :ok =
               Review.file_not_linked(%{
                 file_path: "/media/test/Movie.A.2010.mkv",
                 media_dir: "/media/test",
                 reason: {:import_failed, :insufficient_disk_space},
                 match: %{tmdb_id: 550, tmdb_type: :movie}
               })

      assert [queued] = Review.list_pending_files_for_review()
      assert {queued.tmdb_id, queued.tmdb_type} == {550, "movie"}
      assert {:ok, 1} = Review.approve_group([queued.id])
    end

    test "queues a file that has no item, with the reason" do
      assert :ok =
               Review.file_not_linked(%{
                 file_path: "/media/test/Sample.Show.S01.1080p.mkv",
                 media_dir: "/media/test",
                 reason: {:import_failed, :insufficient_disk_space},
                 match: nil
               })

      assert [queued] = Review.list_pending_files_for_review()
      assert queued.file_path == "/media/test/Sample.Show.S01.1080p.mkv"
      assert queued.media_directory == "/media/test"
      assert queued.parsed_title == "Sample Show"
      assert queued.error_message =~ "disk space"
    end

    # Approving a returned item is the retry: the old reason no longer
    # describes it, and showing it beside "Importing" reads as a failure.
    test "approving a returned item clears its reason" do
      pending = create_pending_file(%{file_path: "/media/test/retry.mkv"})
      {:ok, _} = Review.approve_pending_file(pending)

      :ok =
        Review.file_not_linked(%{
          file_path: "/media/test/retry.mkv",
          media_dir: "/media/test",
          reason: :crashed,
          match: nil
        })

      returned = Repo.get_by!(Review.PendingFile, file_path: "/media/test/retry.mkv")
      assert returned.error_message

      assert {:ok, approved} = Review.approve_pending_file(returned)
      assert approved.error_message == nil
    end

    test "leaves a dismissed item dismissed" do
      pending = create_pending_file(%{file_path: "/media/test/dismissed.mkv"})
      {:ok, _} = Review.dismiss(pending)

      assert :ok =
               Review.file_not_linked(%{
                 file_path: "/media/test/dismissed.mkv",
                 media_dir: "/media/test",
                 reason: :crashed,
                 match: nil
               })

      assert Review.dismissed?("/media/test/dismissed.mkv")
    end

    test "names the reason for each way a link can fail" do
      for {reason, fragment} <- [
            {{:ingest_failed, :boom}, "Adding it to the library failed"},
            {:crashed, "Adding it to the library failed"},
            {{:import_failed, :insufficient_disk_space}, "disk space"},
            {{:import_failed, {:http_error, 500, "x"}}, "Importing it failed"}
          ] do
        path = "/media/test/#{System.unique_integer([:positive])}.mkv"

        :ok =
          Review.file_not_linked(%{
            file_path: path,
            media_dir: "/media/test",
            reason: reason,
            match: nil
          })

        assert Repo.get_by!(Review.PendingFile, file_path: path).error_message =~ fragment
      end
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
