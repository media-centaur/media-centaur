defmodule MediaCentarrWeb.LibraryLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentarr.Library
  alias MediaCentarr.Playback.{Events, ProgressBroadcaster}
  alias MediaCentarr.Playback.Events.{PlaybackFailed, PlaybackStateChanged}

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
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "Initial Mount Fixture"
    end
  end

  describe "in_progress filter" do
    setup do
      # Movie the user has started but not finished
      in_progress_movie = create_standalone_movie(%{name: "In Progress Movie"})
      _ = create_linked_file(%{movie_id: in_progress_movie.id})

      create_watch_progress(%{
        movie_id: in_progress_movie.id,
        position_seconds: 100.0,
        duration_seconds: 1000.0
      })

      # Movie the user has fully completed
      finished_movie = create_standalone_movie(%{name: "Finished Movie"})
      _ = create_linked_file(%{movie_id: finished_movie.id})

      progress =
        create_watch_progress(%{
          movie_id: finished_movie.id,
          position_seconds: 1000.0,
          duration_seconds: 1000.0
        })

      Library.mark_watch_completed!(progress)

      # Movie the user has never touched
      untouched_movie = create_standalone_movie(%{name: "Untouched Movie"})
      _ = create_linked_file(%{movie_id: untouched_movie.id})

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
      _ = create_linked_file(%{movie_id: movie.id})
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

    test "More info button opens the credits view via ?view=credits URL", %{
      conn: conn,
      movie: movie
    } do
      # Regression: build_modal_path/2 must encode `view=credits` into
      # the URL, not just `view=info`. Without this the toggle handler
      # round-trips through `parse_view` and lands on `:main`, making
      # the More info button look broken.
      {:ok, view, _html} = live(conn, ~p"/library?selected=#{movie.id}")

      view |> element("button[phx-click='toggle_credits_view']") |> render_click()

      assert_patched(view, ~p"/library?selected=#{movie.id}&view=credits")
    end
  end

  describe "live updates from playback" do
    setup do
      movie = create_standalone_movie(%{name: "Live Update Movie"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "entity_progress_updated broadcast paints the progress bar without remount",
         %{conn: conn, movie: movie} do
      # Pin the live-update contract: when MpvSession persists progress and
      # ProgressBroadcaster fires, the LibraryLive grid card must reflect
      # the new progress without the user reloading the page. Without this,
      # users start a movie and the catalog still shows it as untouched.
      {:ok, view, html} = live(conn, "/library")
      assert html =~ "Live Update Movie"
      refute html =~ "progress-fill"

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 600.0,
        duration_seconds: 1000.0
      })

      ProgressBroadcaster.broadcast(movie.id)

      html = render(view)
      assert html =~ "progress-fill"
      assert html =~ "width: 60"
    end

    test "playback_state_changed broadcast surfaces the now-playing pulse",
         %{conn: conn, movie: movie} do
      # The pulse dot in the top-right of the card is a high-signal "this
      # is playing right now" indicator. It must light up the moment another
      # device reports playback, not on the next page load.
      {:ok, view, html} = live(conn, "/library")
      refute html =~ "animate-pulse"

      Events.broadcast(%PlaybackStateChanged{
        entity_id: movie.id,
        state: :playing,
        now_playing: %{},
        started_at: DateTime.utc_now()
      })

      assert render(view) =~ "animate-pulse"
    end

    test "playback_failed broadcast renders an error flash",
         %{conn: conn, movie: movie} do
      {:ok, view, _html} = live(conn, "/library")

      Events.broadcast(%PlaybackFailed{
        entity_id: movie.id,
        reason: :file_not_found,
        payload: %{reason: :file_not_found, file_path: "/missing.mkv"}
      })

      assert render(view) =~ "flash"
    end
  end

  describe "toggle_watched updates the modal in real time" do
    # Regression: the watched-toggle on a TV episode wrote to the DB
    # but the modal didn't reflect the change without a reload, because
    # the broadcast's `changed_record` lacked the synthesised
    # `:playable_item` association that subscribers key by. This test
    # exercises the full path — click → DB write → broadcast → hook
    # merge → re-render — and asserts the episode flips state without
    # the user navigating away.

    setup do
      tv_series = create_tv_series(%{name: "Toggle Live Update Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/toggle-show/s01e01.mkv"
        })

      {:ok, tv_series: tv_series, episode: episode}
    end

    test "clicking the toggle flips the episode to watched without remount",
         %{conn: conn, tv_series: tv_series, episode: episode} do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.playback_events())

      {:ok, view, html} = live(conn, ~p"/library?selected=#{tv_series.id}")

      assert html =~ "Mark watched"
      refute html =~ "Mark unwatched"

      view
      |> element(~s|button[phx-click="toggle_watched"][phx-value-episode="#{episode.episode_number}"]|)
      |> render_click()

      # The handler dispatches the DB write to a Task; wait for the
      # broadcast so we know the task has run before we render the LV.
      assert_receive {:entity_progress_updated, %{entity_id: entity_id}}, 1000
      assert entity_id == tv_series.id

      html = render(view)
      assert html =~ "Mark unwatched"
    end

    test "clicking again flips back to unwatched without remount",
         %{conn: conn, tv_series: tv_series, episode: episode} do
      # Seed an already-completed progress so the modal opens in the
      # `:watched` state and the toggle goes :watched → :unwatched.
      _ =
        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 0.0,
          duration_seconds: 0.0,
          completed: true
        })

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.playback_events())

      {:ok, view, html} = live(conn, ~p"/library?selected=#{tv_series.id}")

      assert html =~ "Mark unwatched"

      view
      |> element(~s|button[phx-click="toggle_watched"][phx-value-episode="#{episode.episode_number}"]|)
      |> render_click()

      assert_receive {:entity_progress_updated, _payload}, 1000

      html = render(view)
      assert html =~ "Mark watched"
    end
  end

  describe "live updates from availability" do
    test "availability_changed broadcast does not crash and re-renders",
         %{conn: conn} do
      # When a watch dir goes offline (USB unplug, NFS drop), the LV must
      # consume the broadcast and re-render. The banner itself depends on
      # Availability GenServer state mutations that the LV does not own,
      # so this test pins the LV-side contract: subscribe + handle_info
      # without crashing and with a clean re-render.
      movie = create_standalone_movie(%{name: "Availability Movie"})
      file = create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live(conn, "/library")

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        "library:availability",
        {:availability_changed, file.watch_dir, :unavailable}
      )

      assert render(view) =~ "Availability Movie"
    end
  end
end
