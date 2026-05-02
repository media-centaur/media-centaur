defmodule MediaCentarrWeb.LibraryLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentarr.{Library, Watcher.FilePresence}
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

  describe "live updates from playback" do
    setup do
      movie = create_standalone_movie(%{name: "Live Update Movie"})
      file = create_linked_file(%{movie_id: movie.id})
      FilePresence.record_file(file.file_path, file.watch_dir)
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
      FilePresence.record_file(file.file_path, file.watch_dir)

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
