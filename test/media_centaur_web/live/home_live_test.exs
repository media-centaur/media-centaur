defmodule MediaCentaurWeb.HomeLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Library
  alias MediaCentaur.Playback.{Events, ProgressBroadcaster}
  alias MediaCentaur.Playback.Events.{PlaybackFailed, PlaybackStateChanged}

  test "GET / renders without crashing", %{conn: conn} do
    {:ok, _view, html} = live_async!(conn, "/")
    # The page mounts and renders content — either section headings (when
    # there is data) or the empty-state message (when the test DB is empty).
    assert html =~ "Continue Watching" or html =~ "Your home page will populate"
  end

  describe "watchlist sidebar entry" do
    test "is hidden by default", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/")
      refute has_element?(view, "#sidebar a[href='/watchlist']")
    end

    test "shows when the preference is on, and live-updates on toggle", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/")
      refute has_element?(view, "#sidebar a[href='/watchlist']")

      # The Settings write broadcasts {:setting_changed, "show_watchlist", _};
      # the session-wide SettingAware hook re-assigns without a remount.
      MediaCentaur.Settings.find_or_create_entry!(%{
        key: MediaCentaur.Settings.Preferences.WatchlistVisibility.setting_key(),
        value: %{"enabled" => true}
      })

      render_until(view, fn _html -> has_element?(view, "#sidebar a[href='/watchlist']") end)
    end
  end

  test "renders the Continue Watching row when there is in-progress media", %{conn: conn} do
    movie = create_standalone_movie(%{name: "Sample Movie"})
    _ = create_linked_file(%{movie_id: movie.id})
    create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})

    {:ok, _view, html} = live_async!(conn, "/")

    assert html =~ "Sample Movie"
    assert html =~ "Continue Watching"
  end

  test "first paint (disconnected render) shows real sections, not the empty-state flash",
       %{conn: conn} do
    # Desktop first-paint correctness: the static HTTP render must already
    # carry data, not the empty-state placeholder that flashes until the
    # socket connects. `get/2` exercises the disconnected render the browser
    # paints first.
    movie = create_standalone_movie(%{name: "First Paint Home Movie"})
    _ = create_linked_file(%{movie_id: movie.id})
    create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})

    html = conn |> get("/") |> html_response(200)

    assert html =~ "First Paint Home Movie",
           "continue-watching media must render on the disconnected first paint"
  end

  describe "See all destinations" do
    setup do
      # One in-progress movie populates both Continue Watching and
      # Recently Added, so all four links render.
      movie = create_standalone_movie(%{name: "Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 30.0,
        duration_seconds: 100.0
      })

      :ok
    end

    test "Continue Watching header link targets the Recently Watched sort", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/")

      assert has_element?(
               view,
               ~s|section[data-row="continue-watching"] a[href="/library?sort=watched"]|
             )
    end

    test "Continue Watching row placeholder targets the Recently Watched sort", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/")

      assert has_element?(
               view,
               ~s|[data-component="continue-watching-see-all"][href="/library?sort=watched"]|
             )
    end

    test "Recently Added header link lands on the library default (Recently Added) sort",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/")

      assert has_element?(view, ~s|section[data-row="recently-added"] a[href="/library"]|)
    end

    test "Recently Added row placeholder lands on the library default (Recently Added) sort",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/")

      assert has_element?(view, ~s|[data-component="poster-row-see-all"][href="/library"]|)
    end
  end

  describe "debounce on entities_changed" do
    test "five rapid broadcasts trigger only one reload after the debounce window", %{conn: conn} do
      # Regression guard: rapid :entities_changed messages must be debounced
      # (500ms) rather than triggering assign_all on every message. Five
      # messages in quick succession should result in exactly one :reload_home
      # being processed — verifiable by the page rendering correctly after the
      # window and not crashing from concurrent data loads.
      {:ok, view, _html} = live_async!(conn, "/")

      for _ <- 1..5 do
        send(view.pid, {:entities_changed, %MediaCentaur.Library.Events.EntitiesChanged{entity_ids: []}})
      end

      Process.sleep(600)

      assert render(view) =~ "Continue Watching" or
               render(view) =~ "Your home page will populate"
    end
  end

  describe "drive-recovery image refresh" do
    test "availability_changed bumps image cache-bust on continue-watching URLs",
         %{conn: conn} do
      # Bug: when the app starts before a media dir is mounted, hero and
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

      {:ok, view, html} = live_async!(conn, "/")

      # Initial render: image_version is 0, URLs have no ?v= param.
      assert html =~ "/media-images/#{movie.id}/backdrop.jpg"
      refute html =~ "?v="

      # In production the Continue Watching projection observes
      # `:availability_changed` (it subscribes to `library:availability`),
      # refreshes, and broadcasts `{:library_view_updated, :continue_watching}`
      # — HomeLive bumps :image_version on the source event and schedules
      # the section reload on the derived broadcast. Cache.Worker isn't
      # running under ConnCase, so we simulate by refreshing the projection
      # directly (which emits the same derived broadcast HomeLive listens
      # for) immediately after the source event.
      send(view.pid, {:availability_changed, "/mnt/movies", :available})
      :ok = MediaCentaur.Library.Views.ContinueWatching.refresh_cache()

      # The cache-busted URL (?v=1) appears only after the debounced section
      # reload re-renders with the bumped :image_version — poll for it.
      html_after = render_until(view, "/media-images/#{movie.id}/backdrop.jpg?v=1")
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

      {:ok, _view, html} = live_async!(conn, "/")

      assert html =~ "Coming Up"
      assert html =~ "Slow Mares"
      refute html =~ "Scheduled"
    end

    test "the marquee declares itself the reveal subject", %{conn: conn} do
      # The mosaic's tiles differ in height, so a reveal aimed at an individual
      # tile frames that tile — and moving from the tall primary to a
      # half-height secondary scrolled the page up 129px, because the shorter
      # tile's bottom edge sits higher. `data-nav-reveal` hands the whole
      # composition to `revealItem` instead, giving all three tiles one resting
      # position.
      #
      # Asserted here because the contract spans two layers: the attribute is
      # read by assets/js/input/core/dom_adapter.js, which no Elixir test
      # exercises and no JS test can see this template. Delete the attribute and
      # everything still compiles, renders, and passes — the page just silently
      # jumps again.
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

      {:ok, view, _html} = live_async!(conn, "/")

      assert has_element?(view, "[data-nav-zone='coming_up'][data-nav-reveal]")
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

      {:ok, view, _html} = live_async!(conn, "/")

      view
      |> element(
        ~s|[data-component="continue-watching"] [data-row-item][phx-click="select_entity"]|,
        "Sample Movie"
      )
      |> render_click()

      # Modal opens; the card body still means details — direct play lives
      # on the hover overlay's own button (UIDR-027).
      assert_patched(view, "/?selected=#{movie.id}")
      assert render(view) =~ ~s|data-state="open"|
    end

    test "clicking a Coming Up marquee card with no library entity navigates to /incoming",
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

      {:ok, view, _html} = live_async!(conn, "/")

      assert {:error, {:live_redirect, %{to: "/incoming" <> _}}} =
               view
               |> element(~s|[data-component="coming-up-marquee"] a[data-card="hero"]|)
               |> render_click()
    end

    test "clicking a Recently Added card patches URL and opens modal", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live_async!(conn, "/")

      view
      |> element(
        ~s|[data-component="poster-row"] [data-row-item][phx-click="select_entity"]|,
        "Sample Movie"
      )
      |> render_click()

      assert_patched(view, "/?selected=#{movie.id}")
      assert render(view) =~ ~s|data-state="open"|
    end

    test "the Recently Added row requests the library grid's poster derivative", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})
      create_image(%{movie_id: movie.id, role: "poster", content_url: "#{movie.id}/poster.jpg"})

      # Both surfaces paint a poster at the same size, so they must request
      # the same derivative — one file on disk, and the one URL
      # `ArtworkWarmup` prefetches. A row that names its own width is a
      # guaranteed cache miss. Derived from `poster_src/1` rather than
      # restating the width, so the width has exactly one owner.
      width_marker =
        "/media-images/x/poster.jpg"
        |> MediaCentaurWeb.LiveHelpers.poster_src()
        |> String.split("?")
        |> List.last()

      {:ok, view, _html} = live_async!(conn, "/")

      assert has_element?(
               view,
               ~s|[data-component="poster-row"] img[src*="#{width_marker}"]|
             )
    end

    test "navigating directly to /?selected=UUID mounts modal open", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, _view, html} = live_async!(conn, "/?selected=#{movie.id}")

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
      {:ok, view, html} = live_async!(conn, "/")
      refute html =~ "Newly Started Movie"

      movie = create_standalone_movie(%{name: "Newly Started Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 100.0,
        duration_seconds: 1000.0
      })

      send(view.pid, {:library_view_updated, :continue_watching})

      # The new movie appears only after the debounced Continue Watching reload.
      assert render_until(view, "Newly Started Movie") =~ "Newly Started Movie"
    end

    test "playback_state_changed reloads Continue Watching",
         %{conn: conn} do
      # Play/pause from another device floats the now-playing item to the
      # front of Continue Watching. Without routing playback_state_changed
      # through schedule_section_reloads, the row order would only refresh
      # on the next page navigation.
      {:ok, view, _html} = live_async!(conn, "/")

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

      # The now-playing movie floats into Continue Watching only after the
      # debounced reload — poll for it rather than guessing the settle time.
      assert render_until(view, "Now Playing Movie") =~ "Now Playing Movie"
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

      {:ok, view, html} = live_async!(conn, "/?selected=#{movie.id}")
      refute html =~ "Watch again"

      {:ok, progress} =
        Library.ProgressRecords.find_or_create_for_container(:movie, movie.id, %{
          position_seconds: 100.0,
          duration_seconds: 100.0
        })

      Library.ProgressRecords.mark_completed!(progress)
      ProgressBroadcaster.broadcast(movie.id, nil)

      assert render(view) =~ "Watch again"
    end

    test "playback_failed broadcast renders an error flash",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/")

      Events.broadcast(%PlaybackFailed{
        entity_id: Ecto.UUID.generate(),
        reason: :file_not_found,
        payload: %{reason: :file_not_found, file_path: "/missing.mkv"}
      })

      assert render(view) =~ "flash"
    end
  end

  describe "zone redirects" do
    test "redirects /?zone=upcoming to /incoming", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/incoming"}}} = live_async!(conn, "/?zone=upcoming")
    end

    test "redirects /?zone=library to /library", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/library"}}} = live_async!(conn, "/?zone=library")
    end

    test "/?zone=continue mounts normally (unknown zone is a no-op)", %{conn: conn} do
      # Unknown zone params are ignored — no redirect, page mounts in place
      {:ok, _view, html} = live_async!(conn, "/?zone=continue")

      assert html =~ "Continue Watching" or html =~ "Your home page will populate"
    end
  end

  describe "play in place (UIDR-027)" do
    setup do
      # One in-progress movie with a backdrop and synopsis populates every
      # surface at once: hero (description + backdrop + present file),
      # Continue Watching, and Recently Added.
      movie =
        create_standalone_movie(%{
          name: "Sample Movie",
          description: "A sample synopsis for hero eligibility."
        })

      create_image(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg"
      })

      _ = create_linked_file(%{movie_id: movie.id})
      create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})

      %{movie: movie}
    end

    test "continue-watching card carries a direct play button", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, "/")

      assert has_element?(
               view,
               ~s|#continue-watching-#{movie.id} button[phx-click="play"][phx-value-id="#{movie.id}"]|
             )
    end

    test "recently-added poster card carries a direct play button", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, "/")

      assert has_element?(
               view,
               ~s|#poster-row-#{movie.id} button[phx-click="play"][phx-value-id="#{movie.id}"]|
             )
    end

    test "hero Play plays directly — no modal round-trip", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, "/")

      assert has_element?(
               view,
               ~s|[data-component="hero"] button[phx-click="play"][phx-value-id="#{movie.id}"]|
             )

      view
      |> element(~s|[data-component="hero"] button[phx-click="play"]|)
      |> render_click()

      # Factory file has no bytes on disk → reaching Playback.play/1
      # surfaces the flash; the modal must not have opened on the way.
      assert render(view) =~ "File not available"
      refute has_element?(view, "#detail-modal[data-state='open']")
    end

    test "no surface carries the retired autoplay param", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/")

      refute has_element?(view, "[phx-value-autoplay]")
    end

    test "card_play_button `enabled: false` removes the overlay from both rows — hero Play stays",
         %{conn: conn, movie: movie} do
      {:ok, _} =
        MediaCentaur.Settings.find_or_create_entry(%{
          key: MediaCentaur.Settings.Preferences.CardPlayButton.setting_key(),
          value: %{"enabled" => false}
        })

      {:ok, view, _html} = live_async!(conn, "/")

      refute has_element?(view, ~s|#continue-watching-#{movie.id} button[phx-click="play"]|)
      refute has_element?(view, ~s|#poster-row-#{movie.id} button[phx-click="play"]|)

      # The hero's Play is a standing control, not the hover overlay —
      # the toggle must not touch it.
      assert has_element?(view, ~s|[data-component="hero"] [phx-click="play"]|)
    end
  end
end
