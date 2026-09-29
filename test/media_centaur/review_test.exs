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

  describe "reconcile_with_library/0" do
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

      assert %{closed: 1, reopened: 0} = Review.reconcile_with_library()
      assert Review.list_pending_files() == []
    end

    # Changed 2026-09-29 (campaign `review-closes-on-link`): nothing is in
    # flight at startup, so an approved row with no link is an import that
    # did not finish. It used to be kept as "outstanding" — at `:approved`,
    # a status the queue does not list — which is how an approval vanished.
    test "returns an approved row whose file is not linked to the queue, with the reason" do
      pending = create_pending_file(%{file_path: "/media/test/in-flight.mkv"})
      {:ok, _} = Review.approve_pending_file(pending)

      assert %{closed: 0, reopened: 1} = Review.reconcile_with_library()
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

      assert %{closed: 1, reopened: 0} = Review.reconcile_with_library()
      assert Review.list_pending_files() == []
    end

    test "keeps a pending row whose file is not linked — it awaits a decision" do
      create_pending_file(%{file_path: "/media/test/awaiting.mkv"})

      assert %{closed: 0, reopened: 0} = Review.reconcile_with_library()
      assert length(Review.list_pending_files_for_review()) == 1
    end

    test "keeps a dismissed row whatever its file's state" do
      path = "/media/test/dismissed.mkv"
      pending = create_pending_file(%{file_path: path})
      {:ok, _} = Review.dismiss(pending)

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: path, media_dir: "/media/test", movie_id: movie.id})

      assert %{closed: 0, reopened: 0} = Review.reconcile_with_library()
      assert Review.dismissed?(path)
    end

    test "reports zero on an empty table" do
      assert %{closed: 0, reopened: 0} = Review.reconcile_with_library()
    end
  end

  # The library reports every file's link outcome by path; these are the
  # only ways a review item closes or reopens.
  # A series match needs an episode to link the file to. A file whose name
  # carries none gets it from the reviewer, and cannot be approved without
  # it — the library would have nothing to attach it to.
  describe "choosing the episode" do
    test "a series match for a file with no season and episode needs an episode" do
      pending = create_pending_file(%{tmdb_type: "tv", parsed_type: "movie"})

      assert Review.needs_episode?(pending)
    end

    test "a series match whose file names its episode does not" do
      pending =
        create_pending_file(%{
          tmdb_type: "tv",
          parsed_type: "tv",
          season_number: 1,
          episode_number: 3
        })

      refute Review.needs_episode?(pending)
    end

    test "a movie match does not" do
      refute Review.needs_episode?(create_pending_file(%{tmdb_type: "movie"}))
    end

    test "a bonus feature matched to a series does not — it belongs to the series" do
      refute Review.needs_episode?(create_pending_file(%{tmdb_type: "tv", parsed_type: "extra"}))
    end

    # The reviewer chooses the episode for a file whose name does not number
    # it — and can still change the choice once made.
    test "the reviewer chooses the episode of a series match whose name does not number it" do
      pending =
        create_pending_file(%{
          file_path: "/media/test/Sample Special 2025/Sample.Special.2025.1080p.WEBRip.mp4",
          tmdb_type: "tv",
          parsed_type: "movie"
        })

      assert Review.chooses_episode?(pending)
      {:ok, placed} = Review.set_episode(pending, 1, 22)
      assert Review.chooses_episode?(placed)
    end

    test "a file whose name numbers the episode keeps it" do
      pending =
        create_pending_file(%{
          file_path: "/media/test/Sample.Show.S01E05.1080p.mkv",
          tmdb_type: "tv",
          parsed_type: "tv",
          season_number: 1,
          episode_number: 5
        })

      refute Review.chooses_episode?(pending)
    end

    test "set_episode/3 places the file at the chosen episode" do
      pending = create_pending_file(%{tmdb_type: "tv", parsed_type: "movie"})

      assert {:ok, placed} = Review.set_episode(pending, 1, 22)
      assert {placed.season_number, placed.episode_number} == {1, 22}
      refute Review.needs_episode?(placed)
    end

    # A chosen episode belongs to the series it was chosen from.
    test "a new match clears an episode the reviewer chose" do
      pending =
        create_pending_file(%{
          file_path: "/media/test/Sample Special 2025/Sample.Special.2025.1080p.WEBRip.mp4",
          tmdb_id: 1396,
          tmdb_type: "tv",
          parsed_type: "movie"
        })

      {:ok, placed} = Review.set_episode(pending, 1, 22)

      {1, 0} =
        Review.set_group_match([placed], %{
          tmdb_id: "4242",
          tmdb_type: "tv",
          title: "Another Show",
          year: "2019",
          poster_path: nil
        })

      rematched = Repo.get!(Review.PendingFile, pending.id)
      assert rematched.tmdb_id == 4242
      assert {rematched.season_number, rematched.episode_number} == {nil, nil}
    end

    test "approval is refused until the file has an episode" do
      pending = create_pending_file(%{tmdb_type: "tv", parsed_type: "movie"})

      assert {:error, %Ecto.Changeset{}} = Review.approve_pending_file(pending)

      {:ok, placed} = Review.set_episode(pending, 1, 22)
      assert {:ok, %{status: :approved}} = Review.approve_pending_file(placed)
    end
  end

  describe "episode_choices/1" do
    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
    end

    test "lists a series' seasons with their episodes, specials last" do
      MediaCentaur.TmdbStubs.stub_routes([
        {"/tv/1396/season/0",
         MediaCentaur.TmdbStubs.season_detail(%{
           "season_number" => 0,
           "name" => "Specials",
           "episodes" => [%{"episode_number" => 1, "name" => "Sample Extra Night"}]
         })},
        {"/tv/1396/season/1", MediaCentaur.TmdbStubs.season_detail()},
        {"/tv/1396",
         MediaCentaur.TmdbStubs.tv_detail(%{
           "seasons" => [
             %{"season_number" => 0, "name" => "Specials"},
             %{"season_number" => 1, "name" => "Season 1"}
           ]
         })}
      ])

      assert {:ok, [season_one, specials]} = Review.episode_choices(1396)

      assert season_one.season_number == 1
      assert Enum.map(season_one.episodes, & &1.episode_number) == [1, 2]
      assert hd(season_one.episodes).name == "Pilot"
      assert specials.season_number == 0
      assert [%{episode_number: 1, name: "Sample Extra Night"}] = specials.episodes
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
    # A parked file belongs to the reconciliation queue from here on.
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
                 reason: {:ingest_failed, :boom}
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
    test "queues a file that has no item, with the reason" do
      assert :ok =
               Review.file_not_linked(%{
                 file_path: "/media/test/Sample.Show.S01.1080p.mkv",
                 media_dir: "/media/test",
                 reason: :no_episode
               })

      assert [queued] = Review.list_pending_files_for_review()
      assert queued.file_path == "/media/test/Sample.Show.S01.1080p.mkv"
      assert queued.media_directory == "/media/test"
      assert queued.parsed_title == "Sample Show"
      assert queued.error_message =~ "season and episode"
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
          reason: :crashed
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
                 reason: :no_episode
               })

      assert Review.dismissed?("/media/test/dismissed.mkv")
    end

    test "names the reason for each way a link can fail" do
      for {reason, fragment} <- [
            {:no_episode, "season and episode"},
            {{:ingest_failed, :boom}, "Adding it to the library failed"},
            {:crashed, "Adding it to the library failed"},
            {{:import_failed, :insufficient_disk_space}, "disk space"},
            {{:import_failed, {:http_error, 500, "x"}}, "Importing it failed"}
          ] do
        path = "/media/test/#{System.unique_integer([:positive])}.mkv"

        :ok = Review.file_not_linked(%{file_path: path, media_dir: "/media/test", reason: reason})

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
