defmodule MediaCentaurWeb.ReviewLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

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

      send(view.pid, {:file_added, Ecto.UUID.generate()})

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

      send(view.pid, {:file_reviewed, file.id})

      refute render(view) =~ "Single Review File"
    end

    test "group_approved broadcast removes the whole group from the list",
         %{conn: conn} do
      file_a =
        create_pending_file(%{
          file_path: "/media/test/Approved Show/S01E01.mkv",
          watch_directory: "/media/test",
          parsed_title: "Approved Show",
          parsed_type: "tv"
        })

      _file_b =
        create_pending_file(%{
          file_path: "/media/test/Approved Show/S01E02.mkv",
          watch_directory: "/media/test",
          parsed_title: "Approved Show",
          parsed_type: "tv"
        })

      {:ok, view, _html} = live_async!(conn, "/review")
      assert render_after_async_load(view) =~ "Approved Show"

      group_key = {file_a.watch_directory, "Approved Show"}
      send(view.pid, {:group_approved, group_key, 2})

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

      group_key = {file.watch_directory, "Errored Group File"}
      send(view.pid, {:group_error, group_key, "boom"})

      html = render(view)
      assert html =~ "boom"
      # Group remains visible — error did not remove it from the list.
      assert html =~ "Errored Group File"
    end
  end
end
