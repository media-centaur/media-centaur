defmodule MediaCentaurWeb.ReviewLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.GroupApproved
  alias MediaCentaur.Review.Events.GroupError

  # `ReviewLive.ensure_loaded/1` defers `Review.fetch_pending_groups/0`
  # to an owned `start_async(:review_load, …)` (ADR-049). `render_async/1`
  # awaits it deterministically — no wall-clock sleep.
  defp render_after_async_load(view) do
    render_async(view)
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

      html = render_async(view)

      assert html =~ "TMDB search failed"
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

      on_exit(fn -> :persistent_term.put({MediaCentaur.Settings.Config, :config}, config) end)

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

    test "group_approved broadcast removes the whole group from the list",
         %{conn: conn} do
      file_a =
        create_pending_file(%{
          file_path: "/media/test/Approved Show/S01E01.mkv",
          media_directory: "/media/test",
          parsed_title: "Approved Show",
          parsed_type: "tv"
        })

      _file_b =
        create_pending_file(%{
          file_path: "/media/test/Approved Show/S01E02.mkv",
          media_directory: "/media/test",
          parsed_title: "Approved Show",
          parsed_type: "tv"
        })

      {:ok, view, _html} = live_async!(conn, "/review")
      assert render_after_async_load(view) =~ "Approved Show"

      group_key = {file_a.media_directory, "Approved Show"}
      send(view.pid, {:group_approved, %GroupApproved{group_key: group_key, count: 2}})

      refute render(view) =~ "Approved Show"
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
