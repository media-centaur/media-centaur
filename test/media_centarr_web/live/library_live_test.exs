defmodule MediaCentarrWeb.LibraryLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentarr.Watcher.FilePresence

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
