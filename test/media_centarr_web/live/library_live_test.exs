defmodule MediaCentarrWeb.LibraryLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentarr.{Library, Watcher.FilePresence}

  describe "zone tabs removed" do
    test "library page has no zone tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")

      refute html =~ "data-nav-zone=\"zone-tabs\""
      refute html =~ "data-zone-tab"
      refute html =~ "Continue Watching"
    end

    test "library page renders the catalog grid section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "id=\"browse\""
    end

    test "catalog grid populates with entities on initial mount", %{conn: conn} do
      # Regression: zone-stripping in Phase 4.5 broke the stream-population
      # path. handle_params now must reset the stream when entries are
      # loaded for the first time, not only when tab/sort/filter change.
      movie = create_standalone_movie(%{name: "Initial Mount Fixture"})
      file = create_linked_file(%{movie_id: movie.id})
      FilePresence.record_file(file.file_path, file.watch_dir)

      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "Initial Mount Fixture"
    end
  end

  describe "in_progress filter" do
    setup do
      # Movie the user has started but not finished
      in_progress_movie = create_standalone_movie(%{name: "In Progress Movie"})
      file1 = create_linked_file(%{movie_id: in_progress_movie.id})
      FilePresence.record_file(file1.file_path, file1.watch_dir)

      create_watch_progress(%{
        movie_id: in_progress_movie.id,
        position_seconds: 100.0,
        duration_seconds: 1000.0
      })

      # Movie the user has fully completed
      finished_movie = create_standalone_movie(%{name: "Finished Movie"})
      file2 = create_linked_file(%{movie_id: finished_movie.id})
      FilePresence.record_file(file2.file_path, file2.watch_dir)

      progress =
        create_watch_progress(%{
          movie_id: finished_movie.id,
          position_seconds: 1000.0,
          duration_seconds: 1000.0
        })

      Library.mark_watch_completed!(progress)

      # Movie the user has never touched
      untouched_movie = create_standalone_movie(%{name: "Untouched Movie"})
      file3 = create_linked_file(%{movie_id: untouched_movie.id})
      FilePresence.record_file(file3.file_path, file3.watch_dir)

      :ok
    end

    test "?in_progress=1 only shows entities with in-progress watch progress", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library?in_progress=1")

      assert html =~ "In Progress Movie"
      refute html =~ "Finished Movie"
      refute html =~ "Untouched Movie"
    end

    test "?in_progress=1 shows the active-filter indicator chip", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library?in_progress=1")
      assert html =~ "In progress"
    end

    test "/library (no param) shows all entities — no in-progress filter", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "In Progress Movie"
      assert html =~ "Finished Movie"
      assert html =~ "Untouched Movie"
    end
  end

  describe "detail modal dismissal" do
    # Regression: clicking inside a sibling overlay (e.g. Console drawer)
    # must not dismiss the detail modal. The dismiss mechanism must
    # therefore be backdrop-scoped, not document-scoped (no phx-click-away
    # on the panel). These tests pin that wiring.

    setup do
      movie = create_standalone_movie(%{name: "Dismiss Fixture"})
      file = create_linked_file(%{movie_id: movie.id})
      FilePresence.record_file(file.file_path, file.watch_dir)
      {:ok, movie: movie}
    end

    test "clicking the backdrop closes the modal", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")

      view |> element("#detail-modal") |> render_click()

      refute has_element?(view, "#detail-modal[data-state='open']")
    end

    test "the modal panel has no document-scoped dismiss handler", %{
      conn: conn,
      movie: movie
    } do
      # Structural invariant: nothing inside the detail modal may use
      # phx-click-away. That handler is document-scoped, so any sibling
      # overlay (Console drawer, future popover, toast) would dismiss
      # the modal when clicked. Dismissal lives on the backdrop instead.
      {:ok, view, _html} = live(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")
      refute has_element?(view, "#detail-modal [phx-click-away]")
    end
  end
end
