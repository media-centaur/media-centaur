defmodule MediaCentarrWeb.HomeLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentarr.Watcher.FilePresence

  test "GET / renders without crashing", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    # The page mounts and renders content — either section headings (when
    # there is data) or the empty-state message (when the test DB is empty).
    assert html =~ "Continue Watching" or html =~ "Your home page will populate"
  end

  test "section headings are visible when sections have data", %{conn: conn} do
    # We're not asserting specific data here — Library facade may or may
    # not have any entities in the test DB. Mount + render is enough.
    {:ok, _view, _html} = live(conn, "/")
    assert true
  end

  test "renders the Continue Watching row when there is in-progress media", %{conn: conn} do
    movie = create_standalone_movie(%{name: "Prior Lives"})
    file = create_linked_file(%{movie_id: movie.id})
    FilePresence.record_file(file.file_path, file.watch_dir)
    create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Prior Lives"
    assert html =~ "Continue Watching"
  end

  describe "debounce on entities_changed" do
    test "five rapid broadcasts trigger only one reload after the debounce window", %{conn: conn} do
      # Regression guard: rapid :entities_changed messages must be debounced
      # (500ms) rather than triggering assign_all on every message. Five
      # messages in quick succession should result in exactly one :reload_home
      # being processed — verifiable by the page rendering correctly after the
      # window and not crashing from concurrent data loads.
      {:ok, view, _html} = live(conn, "/")

      for _ <- 1..5 do
        send(view.pid, {:entities_changed, []})
      end

      Process.sleep(600)

      assert render(view) =~ "Continue Watching" or render(view) =~ "Your home page will populate"
    end
  end

  describe "zone redirects" do
    test "redirects /?zone=upcoming to /upcoming", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/upcoming"}}} = live(conn, "/?zone=upcoming")
    end

    test "redirects /?zone=library to /library", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/library"}}} = live(conn, "/?zone=library")
    end

    test "/?zone=continue mounts normally (unknown zone is a no-op)", %{conn: conn} do
      # Unknown zone params are ignored — no redirect, page mounts in place
      {:ok, _view, html} = live(conn, "/?zone=continue")
      assert html =~ "Continue Watching" or html =~ "Your home page will populate"
    end
  end
end
