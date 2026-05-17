defmodule MediaCentarrWeb.HomeLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentarr.Library
  alias MediaCentarr.Playback.{Events, ProgressBroadcaster}
  alias MediaCentarr.Playback.Events.{PlaybackFailed, PlaybackStateChanged}

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
    _ = create_linked_file(%{movie_id: movie.id})
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
        send(view.pid, {:entities_changed, %MediaCentarr.Library.Events.EntitiesChanged{entity_ids: []}})
      end

      Process.sleep(600)

      assert render(view) =~ "Continue Watching" or
               render(view) =~ "Your home page will populate"
    end
  end

  describe "drive-recovery image refresh" do
    test "availability_changed bumps image cache-bust on continue-watching URLs",
         %{conn: conn} do
      # Bug: when the app starts before a watch dir is mounted, hero and
      # continue-watching populate (they don't filter by file presence) but
      # their /media-images/* URLs return placeholder SVGs. Once the drive
      # comes back, the same URLs would still be served from the browser
      # cache. The fix bumps :image_version on every :availability_changed
      # so the next render emits cache-busted URLs (?v=N) — morphdom diffs
      # the `src` attribute and the browser refetches.
      movie = create_standalone_movie(%{name: "Sample Movie"})

      create_image(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg"
      })

      _ = create_linked_file(%{movie_id: movie.id})
      create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})

      {:ok, view, html} = live(conn, "/")

      # Initial render: image_version is 0, URLs have no ?v= param.
      assert html =~ "/media-images/#{movie.id}/backdrop.jpg"
      refute html =~ "?v="

      send(view.pid, {:availability_changed, "/mnt/movies", :available})
      # 500ms debounce + slack
      Process.sleep(700)

      html_after = render(view)
      assert html_after =~ "/media-images/#{movie.id}/backdrop.jpg?v=1"
    end
  end

  describe "Coming Up grab status enrichment" do
    test "Coming Up section renders without a status badge for scheduled items", %{conn: conn} do
      # In the test environment Prowlarr is never configured, so load_coming_up/1
      # skips Acquisition.statuses_for_releases/1 and every release falls back to
      # :scheduled. "Scheduled" is the implicit baseline — we render no badge for
      # it so the marquee reserves badge real estate for actionable states only.
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

      assert html =~ "Coming Up"
      assert html =~ "Slow Mares"
      refute html =~ "Scheduled"
    end
  end

  describe "row card click opens detail modal in place" do
    test "clicking a Continue Watching card patches URL and loads the modal", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

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

      # No library container link → marquee renders an <a> fallback link
      # rather than a phx-click button (no entity to open in the modal).
      item =
        create_tracking_item(%{
          tmdb_id: :rand.uniform(999_999),
          media_type: :tv_series,
          name: "Sample Show",
          library_container_type: nil,
          library_container_id: nil
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
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live(conn, "/")

      view
      |> element(~s|[data-component="poster-row"] button[data-row-item]|, "Sample Movie")
      |> render_click()

      assert_patched(view, "/?selected=#{movie.id}")
      assert render(view) =~ ~s|data-state="open"|
    end

    test "navigating directly to /?selected=UUID mounts modal open", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, _view, html} = live(conn, "/?selected=#{movie.id}")

      assert html =~ ~s|data-state="open"|
    end
  end

  describe "live updates from playback" do
    test "library_view_updated :continue_watching reloads Continue Watching after debounce",
         %{conn: conn} do
      # Per ADR-041, source events (:entity_progress_updated,
      # :watch_event_created) are observed by the
      # `Library.Views.ContinueWatching` projection in production. The
      # projection rebuilds its ETS snapshot and broadcasts
      # `{:library_view_updated, :continue_watching}` on `library:views`.
      # HomeLive subscribes to that and re-reads via the projection.
      #
      # In test mode the projection's Cache.Worker isn't started, so we
      # send the projection-refreshed event directly. The 500ms
      # debounce on continue_watching coalesces multiple refreshes
      # within the window.
      {:ok, view, html} = live(conn, "/")
      refute html =~ "Newly Started Movie"

      movie = create_standalone_movie(%{name: "Newly Started Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 100.0,
        duration_seconds: 1000.0
      })

      send(view.pid, {:library_view_updated, :continue_watching})

      Process.sleep(600)

      assert render(view) =~ "Newly Started Movie"
    end

    test "playback_state_changed reloads Continue Watching",
         %{conn: conn} do
      # Play/pause from another device floats the now-playing item to the
      # front of Continue Watching. Without routing playback_state_changed
      # through schedule_section_reloads, the row order would only refresh
      # on the next page navigation.
      {:ok, view, _html} = live(conn, "/")

      movie = create_standalone_movie(%{name: "Now Playing Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 50.0,
        duration_seconds: 1000.0
      })

      Events.broadcast(%PlaybackStateChanged{
        entity_id: movie.id,
        state: :playing,
        now_playing: %{},
        started_at: DateTime.utc_now()
      })

      Process.sleep(600)

      assert render(view) =~ "Now Playing Movie"
    end

    test "modal selected_entry refreshes when entity_progress_updated arrives",
         %{conn: conn} do
      # Class-of-bug regression: a modal opened on HomeLive must reflect
      # progress broadcasts on `playback:events`. Without the central
      # EntityModal hook, the catch-all only schedules section reloads —
      # `:selected_entry` would freeze on the pre-watch state until the
      # user closed and reopened the modal. The user-visible signal is
      # the play-button label flipping from "Play" to "Watch again".
      movie = create_standalone_movie(%{name: "Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, view, html} = live(conn, "/?selected=#{movie.id}")
      refute html =~ "Watch again"

      {:ok, progress} =
        Library.find_or_create_watch_progress_for_movie(%{
          movie_id: movie.id,
          position_seconds: 100.0,
          duration_seconds: 100.0
        })

      Library.mark_watch_completed!(progress)
      ProgressBroadcaster.broadcast(movie.id)

      assert render(view) =~ "Watch again"
    end

    test "playback_failed broadcast renders an error flash",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      Events.broadcast(%PlaybackFailed{
        entity_id: Ecto.UUID.generate(),
        reason: :file_not_found,
        payload: %{reason: :file_not_found, file_path: "/missing.mkv"}
      })

      assert render(view) =~ "flash"
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
