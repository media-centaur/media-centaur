defmodule MediaCentaurWeb.ReviewLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.GroupApproved
  alias MediaCentaur.Review.Events.GroupError

  # `ReviewLive.ensure_loaded/1` defers `Review.fetch_review_groups/0`
  # to an owned `start_async(:review_load, …)` (ADR-049). `render_async/1`
  # awaits it deterministically — no wall-clock sleep.
  defp render_after_async_load(view) do
    render_async(view)
  end

  defp select_first_group(view) do
    view
    |> element("[phx-click='select_item']")
    |> render()
    |> then(&List.last(Regex.run(~r/phx-value-key="([^"]+)"/, &1)))
  end

  describe "GET /review" do
    test "renders without crashing", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/review")
      # Empty-state copy or list section heading.
      assert html =~ "Review" or html =~ "Movies" or html =~ "TV Series"
    end

    test "lists pending files on initial mount", %{conn: conn} do
      _file =
        create_pending_file(%{
          parsed_title: "Initial Mount Pending",
          parsed_type: "movie"
        })

      {:ok, view, _html} = live_async!(conn, "/review")
      assert render_after_async_load(view) =~ "Initial Mount Pending"
    end

    test "first paint (disconnected render) lists pending files, not an empty flash",
         %{conn: conn} do
      # Desktop first-paint correctness: the static HTTP render must already
      # list the review backlog, not an empty placeholder that flashes until
      # the socket connects. `get/2` exercises the disconnected first render.
      _file =
        create_pending_file(%{
          parsed_title: "First Paint Pending File",
          parsed_type: "movie"
        })

      html = conn |> get("/review") |> html_response(200)

      assert html =~ "First Paint Pending File",
             "pending files must render on the disconnected first paint"
    end
  end

  describe "search panel" do
    test "re-selecting the already-selected row keeps an open search panel open",
         %{conn: conn} do
      # Regression: in the real browser, `select_item` for the already-selected
      # row got re-fired during a re-render (observed ~12ms after a search
      # submit, via the spatial-input focus path — exact trigger still under
      # investigation). It reset `search_open: nil` unconditionally, collapsing
      # the open TMDB search panel. The guard is idempotency: re-selecting the
      # row you are already on must be a no-op, whatever re-fired it.
      _file =
        create_pending_file(%{
          parsed_title: "Panel Pending Show",
          parsed_type: "tv",
          season_number: 1,
          episode_number: 1
        })

      {:ok, view, _html} = live_async!(conn, "/review")
      render_after_async_load(view)

      # The group key is on the (always-rendered) list row. The "Search TMDB"
      # button is gated on tmdb_ready (false in tests), so drive the events
      # directly with that key rather than through the hidden button.
      key =
        view
        |> element("[phx-click='select_item']")
        |> render()
        |> then(&List.last(Regex.run(~r/phx-value-key="([^"]+)"/, &1)))

      render_click(view, "open_search", %{"key" => key})
      assert has_element?(view, "form[phx-submit='search']"), "search panel should open"

      # Re-select the row that is already selected — the redundant activation
      # the input system fires on every re-render. Panel must survive.
      render_click(view, "select_item", %{"key" => key})

      assert has_element?(view, "form[phx-submit='search']"),
             "re-selecting the current row must not close the open search panel"
    end
  end

  describe "choosing a match keeps the type it was found under" do
    # Regression: `select_match` stamped every match with the search form's
    # Type select, whatever produced the match. A scored candidate for a TV
    # file was saved as a movie (the select defaults to Movie), and changing
    # the select after a search relabelled results already on screen.

    test "a scored candidate is saved under the file's type", %{conn: conn} do
      file =
        create_pending_file(%{
          file_path: "/media/test/Sample.Show.S01E01.1080p.mkv",
          parsed_title: "Sample Show",
          parsed_type: "tv",
          season_number: 1,
          episode_number: 1,
          tmdb_type: "tv",
          # Two candidates on one score: the chooser only shows for a tie.
          candidates: [
            %{"tmdb_id" => "555", "title" => "Sample Show", "year" => "2010", "score" => 0.7},
            %{"tmdb_id" => "556", "title" => "Sample Show", "year" => "2014", "score" => 0.7}
          ]
        })

      {:ok, view, _html} = live_async!(conn, "/review")
      render_after_async_load(view)

      view
      |> element("[phx-click='select_match'][phx-value-tmdb-id='555']")
      |> render_click()

      saved = MediaCentaur.Repo.get!(MediaCentaur.Review.PendingFile, file.id)
      assert saved.tmdb_id == 555
      assert saved.tmdb_type == "tv"
    end

    test "a search result is saved under the type it was searched as", %{conn: conn} do
      file =
        create_pending_file(%{
          parsed_title: "Movie A",
          parsed_type: "movie",
          tmdb_type: "movie"
        })

      MediaCentaur.TmdbStubs.stub_search_movie([
        %{"id" => 777, "title" => "Movie A", "release_date" => "2001-01-01"}
      ])

      {:ok, view, _html} = live_async!(conn, "/review")
      render_after_async_load(view)
      key = select_first_group(view)

      render_click(view, "open_search", %{"key" => key})

      view
      |> form("form[phx-submit='search']", %{"query" => "Movie A", "type" => "movie"})
      |> render_submit()

      render_until(view, &String.contains?(&1, "review-result-777"))

      # The user flips the Type select after the results arrived.
      view
      |> form("form[phx-submit='search']", %{"query" => "Movie A", "type" => "tv"})
      |> render_change()

      view
      |> element("[phx-click='select_match'][phx-value-tmdb-id='777']")
      |> render_click()

      saved = MediaCentaur.Repo.get!(MediaCentaur.Review.PendingFile, file.id)
      assert saved.tmdb_id == 777
      assert saved.tmdb_type == "movie"
    end
  end

  describe "a multi-file group's file list" do
    # The list is a disclosure in the page's DisclosureState: it opens on
    # its head and stays open while the page re-renders.
    test "opens on its head to list the group's files", %{conn: conn} do
      files =
        for episode <- [1, 2] do
          create_pending_file(%{
            file_path: "/media/test/Sample Show/Season 1/Sample.Show.S01E0#{episode}.mkv",
            parsed_title: "Sample Show",
            parsed_type: "tv",
            season_number: 1,
            episode_number: episode
          })
        end

      {:ok, view, _html} = live_async!(conn, "/review")
      render_after_async_load(view)

      head = "[data-nav-group] > .disclosure-head[aria-controls^='review-files-']"
      assert has_element?(view, head <> "[aria-expanded='false']")
      refute has_element?(view, "#review-file-#{hd(files).id}")

      view |> element(head) |> render_click()

      assert has_element?(view, head <> "[aria-expanded='true']")
      for file <- files, do: assert(has_element?(view, "#review-file-#{file.id}"))
    end
  end

  describe "search task failure" do
    test "a crashed TMDB search clears searching and tells the user", %{conn: conn} do
      create_pending_file(%{
        parsed_title: "Crash Pending Show",
        parsed_type: "tv",
        season_number: 1,
        episode_number: 1
      })

      # The task calls TMDB through its Req.Test stub; a stub that raises
      # crashes the task, which reaches the LiveView as `{:exit, _}`.
      Req.Test.stub(:tmdb, fn _conn -> raise "stub crashed" end)

      {:ok, view, _html} = live_async!(conn, "/review")
      render_after_async_load(view)

      key =
        view
        |> element("[phx-click='select_item']")
        |> render()
        |> then(&List.last(Regex.run(~r/phx-value-key="([^"]+)"/, &1)))

      render_click(view, "open_search", %{"key" => key})

      view
      |> form("form[phx-submit='search']", %{"query" => "Crash Pending Show", "type" => "tv"})
      |> render_submit()

      # The failure copy is produced by the crashed task's `{:exit, _}` reaching
      # the view; wait for it rather than for `render_async/1`'s fixed budget.
      render_until(view, "TMDB search failed")
      refute has_element?(view, "form[phx-submit='search'] button[disabled]")
    end
  end

  describe "dismiss flow (click-to-confirm)" do
    test "Dismiss arms on the first click and fires on the second", %{conn: conn} do
      create_pending_file(%{parsed_title: "Dismissable Show", parsed_type: "tv"})

      {:ok, view, _html} = live_async!(conn, "/review")
      assert render_after_async_load(view) =~ "Dismissable Show"

      key =
        view
        |> element("[phx-click='select_item']")
        |> render()
        |> then(&List.last(Regex.run(~r/phx-value-key="([^"]+)"/, &1)))

      html = render_click(view, "dismiss", %{"key" => key})
      assert html =~ "Click again to dismiss"
      assert length(MediaCentaur.Review.list_pending_files_for_review()) == 1

      render_click(view, "dismiss", %{"key" => key})
      assert MediaCentaur.Review.list_pending_files_for_review() == []
    end
  end

  describe "delete flow (click-to-confirm)" do
    setup do
      media_dir =
        Path.join(System.tmp_dir!(), "review_live_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(media_dir)
      on_exit(fn -> File.rm_rf!(media_dir) end)

      %{media_dir: media_dir}
    end

    test "first click arms confirmation, second click deletes the file and clears the row", %{
      conn: conn,
      media_dir: media_dir
    } do
      path = Path.join(media_dir, "broken.mkv")
      File.write!(path, "garbage")

      _file =
        create_pending_file(%{
          file_path: path,
          media_directory: media_dir,
          parsed_title: "Broken Download"
        })

      {:ok, view, _html} = live_async!(conn, "/review")
      assert render_after_async_load(view) =~ "Broken Download"

      key =
        view
        |> element("[phx-click='select_item']")
        |> render()
        |> then(&List.last(Regex.run(~r/phx-value-key="([^"]+)"/, &1)))

      html = render_click(view, "delete_prompt", %{"key" => key})
      assert html =~ "Click again to delete"
      assert File.exists?(path), "the first click must only arm the confirmation, not delete"

      render_click(view, "delete_prompt", %{"key" => key})

      refute File.exists?(path)
      refute render(view) =~ "Broken Download"
    end

    test "selecting a different item cancels an armed confirmation", %{
      conn: conn,
      media_dir: media_dir
    } do
      path_a = Path.join(media_dir, "a.mkv")
      path_b = Path.join(media_dir, "b.mkv")
      File.write!(path_a, "x")
      File.write!(path_b, "x")

      create_pending_file(%{file_path: path_a, media_directory: media_dir, parsed_title: "AAA"})
      create_pending_file(%{file_path: path_b, media_directory: media_dir, parsed_title: "ZZZ"})

      {:ok, view, _html} = live_async!(conn, "/review")
      render_after_async_load(view)

      [key_a, key_b] =
        view
        |> element("[data-nav-zone='review-list']")
        |> render()
        |> then(&Regex.scan(~r/phx-value-key="([^"]+)"/, &1))
        |> Enum.map(&List.last/1)

      render_click(view, "select_item", %{"key" => key_a})
      html = render_click(view, "delete_prompt", %{"key" => key_a})
      assert html =~ "Click again to delete"

      render_click(view, "select_item", %{"key" => key_b})
      render_click(view, "select_item", %{"key" => key_a})
      html = render(view)

      refute html =~ "Click again to delete"
      assert File.exists?(path_a), "switching away must cancel the arm, not delete"
    end

    test "never deletes a configured media directory root — only the file, for a flat top-level release",
         %{conn: conn, media_dir: media_dir} do
      # A flat file directly in the media root has no meaningful "release
      # folder" of its own — its dirname IS the media root. This is
      # exactly the shape that must fall back to file-only deletion:
      # confirm the whole media directory survives, not just this file.
      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        Map.put(config, :media_dirs, [media_dir])
      )

      path = Path.join(media_dir, "flat_movie.mkv")
      File.write!(path, "x")

      create_pending_file(%{
        file_path: path,
        media_directory: media_dir,
        parsed_title: "Flat Movie"
      })

      {:ok, view, _html} = live_async!(conn, "/review")
      render_after_async_load(view)

      key =
        view
        |> element("[phx-click='select_item']")
        |> render()
        |> then(&List.last(Regex.run(~r/phx-value-key="([^"]+)"/, &1)))

      assert render_click(view, "delete_prompt", %{"key" => key}) =~ "Click again to delete file"

      render_click(view, "delete_prompt", %{"key" => key})

      refute File.exists?(path)
      assert File.dir?(media_dir), "the media directory root itself must never be removed"
    end
  end

  # A yearly special parses as a movie with no season or episode. Matched to
  # its series, it needs the reviewer to say which episode it is before it
  # can be approved; the year offers the one episode it identifies.
  describe "choosing the episode of a series match" do
    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client()

      MediaCentaur.TmdbStubs.stub_routes([
        {"/tv/1396/season/1",
         MediaCentaur.TmdbStubs.season_detail(%{
           "episodes" => [
             %{"episode_number" => 21, "name" => "Sample Special 2024", "air_date" => "2024-12-27"},
             %{"episode_number" => 22, "name" => "Sample Special 2025", "air_date" => "2025-12-26"}
           ]
         })},
        {"/tv/1396",
         MediaCentaur.TmdbStubs.tv_detail(%{
           "seasons" => [%{"season_number" => 1, "name" => "Season 1"}]
         })}
      ])

      special =
        create_pending_file(%{
          file_path: "/media/test/Sample Special 2025/Sample.Special.2025.1080p.WEBRip.mp4",
          media_directory: "/media/test",
          parsed_title: "Sample Special",
          parsed_year: 2025,
          parsed_type: "movie",
          tmdb_id: 1396,
          tmdb_type: "tv",
          match_title: "Sample Show",
          confidence: 1.0
        })

      %{special: special}
    end

    test "offers the episode the year identifies, and Approve places the file there",
         %{conn: conn, special: special} do
      {:ok, view, _html} = live_async!(conn, "/review")
      render_async(view)

      assert has_element?(view, "#episode-picker-#{special.id} option[value='1:22'][selected]")
      placed = MediaCentaur.Repo.get!(MediaCentaur.Review.PendingFile, special.id)
      assert {placed.season_number, placed.episode_number} == {1, 22}

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_matched())
      view |> element("button", "Approve") |> render_click()

      assert_receive {:file_matched, %{season: 1, episode: 22, tmdb_id: 1396}}, 1000
      await_supervised_tasks()
    end

    test "choosing another episode places the file there", %{conn: conn, special: special} do
      {:ok, view, _html} = live_async!(conn, "/review")
      render_async(view)

      view
      |> element("#episode-picker-#{special.id}")
      |> render_change(%{"file_id" => special.id, "episode" => "1:21"})

      placed = MediaCentaur.Repo.get!(MediaCentaur.Review.PendingFile, special.id)
      assert {placed.season_number, placed.episode_number} == {1, 21}
      assert has_element?(view, "#episode-picker-#{special.id} option[value='1:21'][selected]")
    end

    test "Approve waits for an episode when the year identifies none", %{conn: conn} do
      file =
        create_pending_file(%{
          file_path: "/media/test/Sample Special Night/Sample.Special.Night.mp4",
          media_directory: "/media/test",
          parsed_title: "Sample Special Night",
          parsed_type: "movie",
          tmdb_id: 1396,
          tmdb_type: "tv",
          match_title: "Sample Show",
          confidence: 0.1
        })

      {:ok, view, _html} = live_async!(conn, "/review")

      view
      |> element("#review-group-#{:erlang.phash2({"/media/test", "Sample Special Night"})}")
      |> render_click()

      render_async(view)

      assert has_element?(view, "#episode-picker-#{file.id} option[value=''][selected]")
      refute has_element?(view, "button", "Approve")
    end
  end

  describe "live updates from review intake" do
    # The review queue is the user's choke point — every file the
    # auto-matcher couldn't decide on lands here. If the LV doesn't react
    # to file_added in real time, an operator trying to clear a backlog
    # has to refresh constantly to know if new work has landed.

    test "file_added broadcast triggers a debounced reload",
         %{conn: conn} do
      {:ok, view, html} = live_async!(conn, "/review")
      refute html =~ "Newly Arrived File"

      _file =
        create_pending_file(%{
          parsed_title: "Newly Arrived File",
          parsed_type: "movie"
        })

      send(view.pid, {:file_added, %FileAdded{pending_file_id: Ecto.UUID.generate()}})

      # The new file appears only after the 500ms reload_groups debounce fires.
      assert render_until(view, "Newly Arrived File") =~ "Newly Arrived File"
    end

    test "file_reviewed broadcast removes the file from the list",
         %{conn: conn} do
      file =
        create_pending_file(%{
          parsed_title: "Single Review File",
          parsed_type: "movie"
        })

      {:ok, view, _html} = live_async!(conn, "/review")
      assert render_after_async_load(view) =~ "Single Review File"

      send(view.pid, {:file_reviewed, %FileReviewed{pending_file_id: file.id}})

      refute render(view) =~ "Single Review File"
    end

    # Changed 2026-09-29 (campaign `review-closes-on-link`): approval no
    # longer removes the group. It stays, marked as importing, until the
    # library reports each file linked (`file_reviewed`) or returns it with a
    # reason. Removing it at approval is how an approval that linked
    # nothing looked like one that worked.
    test "an approved group stays listed as importing until its files are linked",
         %{conn: conn} do
      file_a =
        create_pending_file(%{
          file_path: "/media/test/Approved Show/S01E01.mkv",
          media_directory: "/media/test",
          parsed_title: "Approved Show",
          parsed_type: "tv"
        })

      file_b =
        create_pending_file(%{
          file_path: "/media/test/Approved Show/S01E02.mkv",
          media_directory: "/media/test",
          parsed_title: "Approved Show",
          parsed_type: "tv"
        })

      {:ok, view, _html} = live_async!(conn, "/review")
      assert render_after_async_load(view) =~ "Approved Show"

      {:ok, _} = MediaCentaur.Review.approve_pending_file(file_a)
      {:ok, _} = MediaCentaur.Review.approve_pending_file(file_b)
      group_key = {file_a.media_directory, "Approved Show"}
      send(view.pid, {:group_approved, %GroupApproved{group_key: group_key, count: 2}})

      html = render(view)
      assert html =~ "Approved Show"
      assert html =~ "Importing"

      send(view.pid, {:file_reviewed, %FileReviewed{pending_file_id: file_a.id}})
      send(view.pid, {:file_reviewed, %FileReviewed{pending_file_id: file_b.id}})

      refute render(view) =~ "Approved Show"
    end

    test "a file returned from the library shows why it was not added", %{conn: conn} do
      create_pending_file(%{
        parsed_title: "Returned File",
        parsed_type: "movie",
        error_message: "Adding it to the library failed. Approve it again to retry."
      })

      {:ok, view, _html} = live_async!(conn, "/review")
      html = render_after_async_load(view)

      assert html =~ "Not added"
      assert html =~ "Adding it to the library failed. Approve it again to retry."
    end

    test "group_error broadcast surfaces a flash without removing the group",
         %{conn: conn} do
      file =
        create_pending_file(%{
          parsed_title: "Errored Group File",
          parsed_type: "movie"
        })

      {:ok, view, _html} = live_async!(conn, "/review")

      group_key = {file.media_directory, "Errored Group File"}
      send(view.pid, {:group_error, %GroupError{group_key: group_key, message: "boom"}})

      html = render(view)
      assert html =~ "boom"
      # Group remains visible — error did not remove it from the list.
      assert html =~ "Errored Group File"
    end
  end
end
