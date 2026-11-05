defmodule MediaCentaur.ReviewTest do
  use MediaCentaur.DataCase, async: false
  use Oban.Testing, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Review

  setup do
    media_dir = Path.join(System.tmp_dir!(), "review_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(media_dir)
    on_exit(fn -> File.rm_rf!(media_dir) end)

    %{media_dir: media_dir}
  end

  describe "settle_with_library/1" do
    # A queue row closes on the library's link outcome for its file
    # (`file_linked/1`, `file_not_linked/1`). PubSub has no replay, so a
    # listener that was not subscribed at that instant loses the message.
    # 73 rows orphaned at `:approved` were found on a live instance from one
    # bulk approve on 2026-06-08.
    #
    # They are not inert: `file_path` is unique and
    # `add_pending_file/1` keeps a decided row whatever discovery found,
    # so a re-match landing on one gets a row the queue does not list —
    # the file leaves the library and cannot be re-reviewed.
    #
    # A linked file's row is done, and an approved row whose file is not
    # linked is an import that did not finish — re-sent to Import (campaign
    # durable-work, F1). At startup nothing is in flight; the periodic pass
    # (`Review.SettleJob`) leaves approvals younger than its cutoff alone.
    test "deletes an approved row whose file is linked" do
      path = "/media/test/imported.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, 1} = Review.approve([pending.id])

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert %{closed: 1, resent: 0} = Review.settle_with_library()
      assert Review.list_pending_files() == []
    end

    # Changed 2026-09-30 (campaign `durable-work`, F1): an approval is a
    # person's decision, stored. An import lost on the way used to be undone
    # here — the row went back to the queue as "didn't finish" and the person
    # had to approve again. It is now carried out: the file is re-sent to
    # Import and the row stays approved until its link outcome closes it.
    test "re-sends an approved row whose file is not linked to Import; it stays approved" do
      pending =
        create_pending_file(%{file_path: "/media/test/in-flight.mkv"})

      {:ok, 1} = Review.approve([pending.id])
      MediaCentaur.Topics.subscribe(MediaCentaur.Topics.pipeline_matched())

      assert %{closed: 0, resent: 1} = Review.settle_with_library()

      assert_receive {:file_matched, %{file_path: "/media/test/in-flight.mkv"}}
      assert Repo.reload!(pending).status == :approved
    end

    test "an approval younger than the cutoff may still be in flight and is left alone" do
      pending = create_pending_file(%{file_path: "/media/test/in-flight.mkv"})
      {:ok, 1} = Review.approve([pending.id])
      MediaCentaur.Topics.subscribe(MediaCentaur.Topics.pipeline_matched())

      cutoff = DateTime.add(DateTime.utc_now(), -15 * 60, :second)

      assert %{closed: 0, resent: 0} = Review.settle_with_library(approved_before: cutoff)
      refute_received {:file_matched, _}
    end

    # Changed 2026-09-29 (campaign `review-closes-on-link`): a linked file is
    # in the library, so there is nothing left to review, whatever the row's
    # status. It used to be kept.
    test "deletes a pending row whose file is linked" do
      path = "/media/test/awaiting.mkv"
      create_pending_file(%{file_path: path})

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert %{closed: 1, resent: 0} = Review.settle_with_library()
      assert Review.list_pending_files() == []
    end

    test "keeps a pending row whose file is not linked — it awaits a decision" do
      create_pending_file(%{file_path: "/media/test/awaiting.mkv"})

      assert %{closed: 0, resent: 0} = Review.settle_with_library()
      assert length(Enum.filter(Review.list_queue(), &(&1.status == :pending))) == 1
    end

    test "keeps a dismissed row whatever its file's state" do
      path = "/media/test/dismissed.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, 1} = Review.dismiss([pending.id])

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert %{closed: 0, resent: 0} = Review.settle_with_library()
      assert Review.dismissed?(path)
    end

    # 2026-09-29: the rows changed with no broadcast, so the Review badge
    # kept its old count until the next review event.
    test "tells review subscribers what it closed, and Import what it re-sent" do
      linked = create_pending_file(%{file_path: "/media/test/linked.mkv"})
      movie = create_movie(%{name: "Sample Movie"})

      create_linked_file(%{
        file_path: "/media/test/linked.mkv",
        media_dir: "/media/test",
        movie_id: movie.id
      })

      unfinished = create_pending_file(%{file_path: "/media/test/unfinished.mkv"})
      {:ok, 1} = Review.approve([unfinished.id])

      Review.subscribe()
      MediaCentaur.Topics.subscribe(MediaCentaur.Topics.pipeline_matched())
      Review.settle_with_library()

      linked_id = linked.id
      assert_receive {:file_reviewed, %Review.Events.FileReviewed{pending_file_id: ^linked_id}}
      assert_receive {:file_matched, %{file_path: "/media/test/unfinished.mkv"}}
    end

    test "reports zero on an empty table" do
      assert %{closed: 0, resent: 0} = Review.settle_with_library()
    end
  end

  describe "Review.SettleJob — the periodic pass" do
    test "re-sends an approval older than its cutoff, and not a fresh one" do
      old = create_pending_file(%{file_path: "/media/test/old.mkv"})
      {:ok, 1} = Review.approve([old.id])
      backdate(old, :updated_at, DateTime.add(DateTime.utc_now(:second), -30 * 60, :second))

      fresh = create_pending_file(%{file_path: "/media/test/fresh.mkv"})
      {:ok, 1} = Review.approve([fresh.id])

      MediaCentaur.Topics.subscribe(MediaCentaur.Topics.pipeline_matched())

      assert :ok = perform_job(Review.SettleJob, %{})

      assert_receive {:file_matched, %{file_path: "/media/test/old.mkv"}}
      refute_received {:file_matched, %{file_path: "/media/test/fresh.mkv"}}
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

      assert {:ok, 1} = Review.approve([pending.id])
    end
  end

  # The review page's selection is the unit of decision (campaign
  # `review-bulk-match`): a person ticks any set of items and names one
  # title for them. Six episodes that arrived in six release folders are
  # one decision, not six.
  describe "match/2" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_matched())
      :ok
    end

    defp chosen_title(overrides \\ %{}) do
      Map.merge(
        %{
          tmdb_id: 4242,
          tmdb_type: "tv",
          title: "Sample Show",
          year: "1995",
          poster_path: "/sample.jpg"
        },
        overrides
      )
    end

    defp unmatched_episode(path, episode) do
      create_pending_file(%{
        file_path: path,
        media_directory: "/media/test",
        parsed_title: "Sample Show Signed",
        parsed_type: "tv",
        parsed_season: 1,
        parsed_episode: episode,
        tmdb_id: nil,
        tmdb_type: nil,
        confidence: nil,
        match_title: nil
      })
    end

    test "matches files from different release folders to the chosen title and sends each to Import" do
      first = unmatched_episode("/media/test/Sample.Show.Signed.S01E01-GROUP/a.mkv", 1)
      second = unmatched_episode("/media/test/Sample.Show.Signed.S01E02-GROUP/b.mkv", 2)

      assert {:ok, 2} = Review.match([first.id, second.id], chosen_title())

      assert_receive {:file_matched,
                      %{
                        file_path: "/media/test/Sample.Show.Signed.S01E01-GROUP/a.mkv",
                        tmdb_id: 4242,
                        tmdb_type: "tv"
                      }}

      assert_receive {:file_matched,
                      %{
                        file_path: "/media/test/Sample.Show.Signed.S01E02-GROUP/b.mkv",
                        tmdb_id: 4242,
                        tmdb_type: "tv"
                      }}

      for file <- Review.list_pending_files() do
        assert file.status == :approved
        assert file.match_title == "Sample Show"
        assert file.match_year == "1995"
        assert file.match_poster_path == "/sample.jpg"
      end
    end

    test "accepts a TMDB id handed over as a string, as a page sends it" do
      file = unmatched_episode("/media/test/Sample Show/S01E01.mkv", 1)

      assert {:ok, 1} = Review.match([file.id], chosen_title(%{tmdb_id: "4242"}))
      assert_receive {:file_matched, %{tmdb_id: 4242}}
    end

    # 2026-09-29 regression, re-aimed from `approve_group/1`: a file without
    # an identity was published with `tmdb_type: nil`, and the Import
    # producer raised on it. A match without a type is refused whole.
    test "refuses a title with no type, and sends nothing" do
      file = unmatched_episode("/media/test/Sample Show/S01E01.mkv", 1)

      assert {:error, :no_identity} = Review.match([file.id], chosen_title(%{tmdb_type: nil}))
      refute_receive {:file_matched, _}
      assert [%{status: :pending}] = Review.list_pending_files()
    end

    test "matches waiting items only — an importing or dismissed one is left alone" do
      importing = unmatched_episode("/media/test/Sample Show/S01E01.mkv", 1)
      {:ok, 1} = Review.match([importing.id], chosen_title(%{tmdb_id: 1}))
      assert_receive {:file_matched, _}

      dismissed = unmatched_episode("/media/test/Sample Show/S01E02.mkv", 2)
      {:ok, 1} = Review.dismiss([dismissed.id])
      waiting = unmatched_episode("/media/test/Sample Show/S01E03.mkv", 3)

      assert {:ok, 1} = Review.match([importing.id, dismissed.id, waiting.id], chosen_title())

      assert_receive {:file_matched, %{file_path: "/media/test/Sample Show/S01E03.mkv"}}
      refute_receive {:file_matched, _}
    end

    test "matching a not-added item clears its reason" do
      file = unmatched_episode("/media/test/Sample Show/S01E01.mkv", 1)
      force_attrs(file, %{error_message: "Importing it failed. Approve it again to retry."})

      assert {:ok, 1} = Review.match([file.id], chosen_title())
      assert [%{error_message: nil}] = Review.list_pending_files()
    end

    test "tells review subscribers which files were approved" do
      file = unmatched_episode("/media/test/Sample Show/S01E01.mkv", 1)
      Review.subscribe()

      assert {:ok, 1} = Review.match([file.id], chosen_title())

      file_id = file.id

      assert_receive {:files_approved,
                      %MediaCentaur.Review.Events.FilesApproved{pending_file_ids: [^file_id]}}
    end
  end

  # Several unsure items whose best guesses are right — three films, each
  # its own title — are accepted in one press, each under its own guess.
  describe "approve/1" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_matched())
      :ok
    end

    test "approves each waiting item under its own best guess" do
      first =
        create_pending_file(%{file_path: "/media/test/Movie.A.mkv", tmdb_id: 1, tmdb_type: "movie"})

      second =
        create_pending_file(%{file_path: "/media/test/Movie.B.mkv", tmdb_id: 2, tmdb_type: "movie"})

      assert {:ok, 2} = Review.approve([first.id, second.id])

      assert_receive {:file_matched, %{file_path: "/media/test/Movie.A.mkv", tmdb_id: 1}}
      assert_receive {:file_matched, %{file_path: "/media/test/Movie.B.mkv", tmdb_id: 2}}
    end

    # 2026-09-29 regression, re-aimed from `approve_group/1`: an item with
    # no identity reached Import with no type. It is skipped and stays.
    test "skips an item without a best guess, and sends nothing for it" do
      guessed =
        create_pending_file(%{file_path: "/media/test/Movie.A.mkv", tmdb_id: 1, tmdb_type: "movie"})

      unguessed =
        create_pending_file(%{file_path: "/media/test/Movie.B.mkv", tmdb_id: nil, tmdb_type: nil})

      assert {:ok, 1} = Review.approve([guessed.id, unguessed.id])

      assert_receive {:file_matched, %{file_path: "/media/test/Movie.A.mkv"}}
      refute_receive {:file_matched, _}
      assert {:ok, %{status: :pending}} = Review.fetch_pending_file(unguessed.id)
    end
  end

  # 2026-09-29: an item closed only when its file's link outcome arrived,
  # over PubSub with no replay. One that was dropped left a linked file
  # listed until the next restart. Membership now follows the library.
  describe "a file the library has linked" do
    test "is not listed or counted, even before its link outcome arrives" do
      path = "/media/test/linked.mkv"
      create_pending_file(%{file_path: path})
      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert Review.list_queue() == []
      assert Review.count_pending() == 0
      refute MapSet.member?(Review.pending_file_paths(), path)
    end
  end

  describe "list_queue/0" do
    # Every open item — waiting, importing and dismissed — in one list
    # ordered by how the files were named, so files the parser read the
    # same way sit together whatever folder they came from.
    test "lists waiting, approved and dismissed items ordered by parsed title, season and episode" do
      create_pending_file(%{
        file_path: "/media/test/Second/e2.mkv",
        parsed_title: "sample show",
        parsed_season: 1,
        parsed_episode: 2
      })

      approved =
        create_pending_file(%{
          file_path: "/media/test/First/e1.mkv",
          parsed_title: "Sample Show",
          parsed_season: 1,
          parsed_episode: 1
        })

      {:ok, 1} = Review.approve([approved.id])

      dismissed = create_pending_file(%{file_path: "/media/test/Movie.A.mkv", parsed_title: "Movie A"})
      {:ok, 1} = Review.dismiss([dismissed.id])

      assert ["/media/test/Movie.A.mkv", "/media/test/First/e1.mkv", "/media/test/Second/e2.mkv"] =
               Enum.map(Review.list_queue(), & &1.file_path)
    end
  end

  describe "file_linked/1" do
    test "removes an approved item and tells review subscribers" do
      Review.subscribe()
      pending = create_pending_file(%{file_path: "/media/test/linked.mkv"})
      {:ok, 1} = Review.approve([pending.id])

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
      {:ok, 1} = Review.approve([pending.id])

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
          parsed_season: 1,
          parsed_episode: 22,
          match_title: "Sample Show"
        })

      {:ok, 1} = Review.approve([pending.id])

      assert :ok =
               Review.file_not_linked(%{
                 file_path: "/media/test/special.mp4",
                 media_dir: "/media/test",
                 reason: {:ingest_failed, :boom},
                 match: %{tmdb_id: 1396, tmdb_type: :tv}
               })

      reopened = hd(Enum.filter(Review.list_queue(), &(&1.status == :pending)))
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

      assert [queued] = Enum.filter(Review.list_queue(), &(&1.status == :pending))
      assert {queued.tmdb_id, queued.tmdb_type} == {550, "movie"}
      assert {:ok, 1} = Review.approve([queued.id])
    end

    test "queues a file that has no item, with the reason" do
      assert :ok =
               Review.file_not_linked(%{
                 file_path: "/media/test/Sample.Show.S01.1080p.mkv",
                 media_dir: "/media/test",
                 reason: {:import_failed, :insufficient_disk_space},
                 match: nil
               })

      assert [queued] = Enum.filter(Review.list_queue(), &(&1.status == :pending))
      assert queued.file_path == "/media/test/Sample.Show.S01.1080p.mkv"
      assert queued.media_directory == "/media/test"
      assert queued.parsed_title == "Sample Show"
      assert queued.error_message =~ "disk space"
    end

    # Approving a returned item is the retry: the old reason no longer
    # describes it, and showing it beside "Importing" reads as a failure.
    test "approving a returned item clears its reason" do
      pending = create_pending_file(%{file_path: "/media/test/retry.mkv"})
      {:ok, 1} = Review.approve([pending.id])

      :ok =
        Review.file_not_linked(%{
          file_path: "/media/test/retry.mkv",
          media_dir: "/media/test",
          reason: :crashed,
          match: nil
        })

      returned = Repo.get_by!(Review.PendingFile, file_path: "/media/test/retry.mkv")
      assert returned.error_message

      assert {:ok, 1} = Review.approve([returned.id])
      assert {:ok, %{error_message: nil}} = Review.fetch_pending_file(returned.id)
    end

    test "leaves a dismissed item dismissed" do
      pending = create_pending_file(%{file_path: "/media/test/dismissed.mkv"})
      {:ok, 1} = Review.dismiss([pending.id])

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

  describe "add_pending_file/1 on a decided item" do
    # Changed 2026-09-29 (campaign `review-coherence`): this reopened the
    # row, because a leftover approved row hid its path from the queue for
    # good. The queue now reads membership from the library: the row of a
    # linked file is simply not listed, and nothing needs reopening.
    test "leaves a leftover approved row of a linked file alone — the queue does not list it" do
      path = "/media/test/stale.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, 1} = Review.approve([pending.id])

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert {:ok, %{status: :approved}} = Review.add_pending_file(%{file_path: path})
      assert Review.list_queue() == []
    end

    test "leaves an approved row alone while its import is outstanding" do
      path = "/media/test/in-flight.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, 1} = Review.approve([pending.id])

      assert {:ok, same} = Review.add_pending_file(%{file_path: path})
      assert same.status == :approved
      assert Enum.filter(Review.list_queue(), &(&1.status == :pending)) == []
    end

    test "leaves a dismissed row blocking — that is what dismiss means" do
      path = "/media/test/dismissed.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, 1} = Review.dismiss([pending.id])

      assert {:ok, same} = Review.add_pending_file(%{file_path: path})
      assert same.status == :dismissed
      assert Enum.filter(Review.list_queue(), &(&1.status == :pending)) == []
    end
  end

  # Discovery runs again on a waiting file at startup and from Settings →
  # rescan. The item used to keep the parse it was created with, so a parser
  # fix never reached the queue: six episodes stayed "Sample Show Signed"
  # after the parser learned the tag (campaign `review-bulk-match`).
  describe "add_pending_file/1 on a waiting item — re-discovery" do
    test "refreshes the parse and the best guess" do
      path = "/media/test/Sample.Show.Signed.S01E01.mkv"

      create_pending_file(%{
        file_path: path,
        parsed_title: "Sample Show Signed",
        tmdb_id: nil,
        tmdb_type: nil,
        confidence: nil,
        match_title: nil
      })

      assert {:ok, refreshed} =
               Review.add_pending_file(%{
                 file_path: path,
                 parsed_title: "Sample Show",
                 parsed_type: "tv",
                 tmdb_id: 4242,
                 tmdb_type: "tv",
                 confidence: 0.7,
                 match_title: "Sample Show",
                 candidates: [%{"tmdb_id" => 4242}]
               })

      assert refreshed.status == :pending
      assert refreshed.parsed_title == "Sample Show"

      assert {refreshed.tmdb_id, refreshed.confidence, refreshed.match_title} ==
               {4242, 0.7, "Sample Show"}

      assert refreshed.candidates == [%{"tmdb_id" => 4242}]
    end

    # Owner decision 2026-11-05: a not-added item keeps the match the
    # person chose and the reason it failed, so the reader still sees what
    # went wrong; only the parse is refreshed.
    test "a not-added item keeps its match and reason; only the parse is refreshed" do
      path = "/media/test/Movie.A.Signed.1999.mkv"

      returned =
        create_pending_file(%{
          file_path: path,
          parsed_title: "Movie A Signed",
          tmdb_id: 550,
          tmdb_type: "movie"
        })

      force_attrs(returned, %{error_message: "Importing it failed. Approve it again to retry."})

      assert {:ok, refreshed} =
               Review.add_pending_file(%{
                 file_path: path,
                 parsed_title: "Movie A",
                 parsed_year: 1999,
                 tmdb_id: 999,
                 tmdb_type: "movie",
                 confidence: 0.4
               })

      assert {refreshed.parsed_title, refreshed.parsed_year} == {"Movie A", 1999}
      assert {refreshed.tmdb_id, refreshed.tmdb_type} == {550, "movie"}
      assert refreshed.error_message =~ "Importing it failed"
    end
  end

  describe "reopen_for_review/1" do
    # The re-match path. Unlike discovery it is an explicit act on files
    # the user owns, so it supersedes an older decision — including a
    # dismissal, which every automatic path still refuses to reconsider.
    test "reopens a dismissed row" do
      path = "/media/test/dismissed.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, 1} = Review.dismiss([pending.id])

      assert {:ok, reopened} = Review.reopen_for_review(%{file_path: path})
      assert reopened.status == :pending
      refute Review.dismissed?(path)
    end

    test "reopens an approved row" do
      path = "/media/test/approved.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, 1} = Review.approve([pending.id])

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
      {:ok, 1} = Review.dismiss([pending.id])

      assert {:ok, reopened} = Review.reopen_for_review(%{file_path: path, parsed_title: "New Guess"})
      assert reopened.parsed_title == "New Guess"
    end
  end

  # 2026-09-29: a dismissal could not be undone from the UI — the only way
  # back was a rematch, and Discovery never searches a dismissed file again.
  describe "restore/1" do
    test "restore returns a dismissed file to the queue, keeping its match" do
      dismissed = create_pending_file(%{file_path: "/media/test/dismissed.mkv", tmdb_id: 550})
      {:ok, 1} = Review.dismiss([dismissed.id])
      Review.subscribe()

      assert {:ok, 1} = Review.restore([dismissed.id])
      {:ok, restored} = Review.fetch_pending_file(dismissed.id)

      assert restored.status == :pending
      assert restored.tmdb_id == 550
      refute Review.dismissed?("/media/test/dismissed.mkv")
      assert [%{id: listed}] = Enum.filter(Review.list_queue(), &(&1.status == :pending))
      assert listed == dismissed.id

      restored_id = dismissed.id
      assert_receive {:file_added, %Review.Events.FileAdded{pending_file_id: ^restored_id}}
    end

    test "restore leaves a file that is not dismissed as it is" do
      open = create_pending_file(%{file_path: "/media/test/open.mkv"})

      assert {:ok, 0} = Review.restore([open.id, Ecto.UUID.generate()])
      assert {:ok, %{status: :pending}} = Review.fetch_pending_file(open.id)
    end
  end

  describe "dismissed?/1" do
    # Dismiss is a person deciding the file is not library content, and
    # `add_pending_file/1` keys on file_path regardless of
    # status — so the decision is terminal whether or not anything reads
    # it. `Pipeline.Discovery` reads it to stop before the parse and the
    # TMDB searches it would then discard.
    test "true for a path dismissed in review" do
      pending = create_pending_file(%{file_path: "/media/test/capture.mkv"})
      {:ok, 1} = Review.dismiss([pending.id])

      assert Review.dismissed?("/media/test/capture.mkv")
    end

    test "false for a path still awaiting review" do
      create_pending_file(%{file_path: "/media/test/awaiting.mkv"})

      refute Review.dismissed?("/media/test/awaiting.mkv")
    end

    test "false for a path that was approved" do
      pending = create_pending_file(%{file_path: "/media/test/approved.mkv"})
      {:ok, 1} = Review.approve([pending.id])

      refute Review.dismissed?("/media/test/approved.mkv")
    end

    test "false for a path the queue has never seen" do
      refute Review.dismissed?("/media/test/unknown.mkv")
    end

    test "false once the dismissed row is dropped" do
      pending = create_pending_file(%{file_path: "/media/test/capture.mkv"})
      {:ok, 1} = Review.dismiss([pending.id])
      {:ok, 1} = Review.drop_pending_files(["/media/test/capture.mkv"])

      refute Review.dismissed?("/media/test/capture.mkv")
    end
  end

  describe "clear_all/0" do
    test "destroys every pending file, whatever its status" do
      create_pending_file()
      dismissed = create_pending_file()
      {:ok, 1} = Review.dismiss([dismissed.id])

      assert :ok = Review.clear_all()
      assert Review.list_pending_files() == []
    end
  end

  describe "delete_files/1" do
    test "removes the file from disk, its FilePresence row, and the PendingFile row", %{
      media_dir: media_dir
    } do
      path = Path.join(media_dir, "broken_release.mkv")
      File.write!(path, "garbage")
      FilePresence.stamp(path, media_dir)

      pending_file =
        create_pending_file(%{file_path: path, media_directory: media_dir, parsed_title: "Broken"})

      assert {1, 0} = Review.delete_files([pending_file.id])

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

      assert {1, 0} = Review.delete_files([pending_file.id])
      assert Review.fetch_pending_file(pending_file.id) == {:error, :not_found}
    end
  end

  describe "delete_files/1 — several files" do
    test "deletes every file and reports counts", %{media_dir: media_dir} do
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

      assert {2, 0} = Review.delete_files(Enum.map(files, & &1.id))
      assert Enum.all?(paths, &(not File.exists?(&1)))
    end
  end
end
