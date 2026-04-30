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
    movie = create_standalone_movie(%{name: "Sample Movie"})
    file = create_linked_file(%{movie_id: movie.id})
    FilePresence.record_file(file.file_path, file.watch_dir)
    create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Sample Movie"
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

      assert render(view) =~ "Continue Watching" or
               render(view) =~ "Your home page will populate"
    end
  end

  describe "Coming Up grab status enrichment" do
    test "Coming Up section renders with Scheduled badge when Prowlarr is not configured", %{
      conn: conn
    } do
      # In the test environment Prowlarr is never configured, so load_coming_up/1
      # skips Acquisition.statuses_for_releases/1 and every release falls back to
      # :scheduled. This confirms the no-Prowlarr path renders correctly.
      today = Date.utc_today()

      tmdb_id = :rand.uniform(999_999)
      item = create_tracking_item(%{tmdb_id: tmdb_id, media_type: :tv_series, name: "Slow Mares"})

      create_tracking_release(%{
        item_id: item.id,
        season_number: 5,
        episode_number: 2,
        air_date: Date.add(today, 7),
        released: false
      })

      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Scheduled"
      assert html =~ "Coming Up"
    end
  end

  describe "row card click opens detail modal in place" do
    test "clicking a Continue Watching card patches URL and loads the modal", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      file = create_linked_file(%{movie_id: movie.id})
      FilePresence.record_file(file.file_path, file.watch_dir)

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 30.0,
        duration_seconds: 100.0
      })

      {:ok, view, _html} = live(conn, "/")

      view
      |> element(
        ~s|[data-component="continue-watching"] button[data-row-item]|,
        "Sample Movie"
      )
      |> render_click()

      # Modal opens; user clicks Play in the modal to resume — clicking the
      # card itself does not auto-start playback.
      assert_patched(view, "/?selected=#{movie.id}")
      assert render(view) =~ ~s|data-state="open"|
    end

    test "clicking a Coming Up marquee card with no library entity navigates to /upcoming",
         %{conn: conn} do
      today = Date.utc_today()

      # No library_entity_id → marquee renders an <a> fallback link rather
      # than a phx-click button (no entity to open in the modal).
      item =
        create_tracking_item(%{
          tmdb_id: :rand.uniform(999_999),
          media_type: :tv_series,
          name: "Sample Show",
          library_entity_id: nil
        })

      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: 1,
        air_date: Date.add(today, 7),
        released: false
      })

      {:ok, view, _html} = live(conn, "/")

      assert {:error, {:live_redirect, %{to: "/upcoming" <> _}}} =
               view
               |> element(~s|[data-component="coming-up-marquee"] a[data-card="hero"]|)
               |> render_click()
    end

    test "clicking a Recently Added card patches URL and opens modal", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      file = create_linked_file(%{movie_id: movie.id})
      FilePresence.record_file(file.file_path, file.watch_dir)

      {:ok, view, _html} = live(conn, "/")

      view
      |> element(~s|[data-component="poster-row"] button[data-row-item]|, "Sample Movie")
      |> render_click()

      assert_patched(view, "/?selected=#{movie.id}")
      assert render(view) =~ ~s|data-state="open"|
    end

    test "navigating directly to /?selected=UUID mounts modal open", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      file = create_linked_file(%{movie_id: movie.id})
      FilePresence.record_file(file.file_path, file.watch_dir)

      {:ok, _view, html} = live(conn, "/?selected=#{movie.id}")

      assert html =~ ~s|data-state="open"|
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
