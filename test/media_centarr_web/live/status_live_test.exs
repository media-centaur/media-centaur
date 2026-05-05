defmodule MediaCentarrWeb.StatusLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Playback.Events.PlaybackStateChanged

  describe "GET /status" do
    test "renders without crashing", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/status")
      assert html =~ "Playback"
    end

    test "shows idle when no sessions are active", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/status")
      assert html =~ "idle" or html =~ "Idle"
    end
  end

  describe "live updates from playback" do
    # The Status page is the operator's at-a-glance view of what the system
    # is doing right now. If playback state and progress don't stream in,
    # the page is a stale snapshot — useless during a live debug session.

    test "playback_state_changed broadcast surfaces the now-playing item",
         %{conn: conn} do
      {:ok, view, html} = live(conn, "/status")
      refute html =~ "Sample Status Movie"

      movie_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:playback_state_changed,
         %PlaybackStateChanged{
           entity_id: movie_id,
           state: :playing,
           now_playing: %{
             entity_id: movie_id,
             movie_id: movie_id,
             movie_name: "Sample Status Movie",
             position_seconds: 100.0,
             duration_seconds: 1000.0
           },
           started_at: DateTime.utc_now()
         }}
      )

      html = render(view)
      assert html =~ "Sample Status Movie"
      assert html =~ "1 active"
    end

    test "entity_progress_updated broadcast updates the position bar",
         %{conn: conn} do
      # Order matters: we first establish the session via
      # :playback_state_changed (which seats the entity into the sessions
      # map), then fire :entity_progress_updated with a matching record so
      # the LV's progress_matches_session? predicate returns true and the
      # in-card progress bar moves.
      {:ok, view, _html} = live(conn, "/status")
      movie_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:playback_state_changed,
         %PlaybackStateChanged{
           entity_id: movie_id,
           state: :playing,
           now_playing: %{
             entity_id: movie_id,
             movie_id: movie_id,
             movie_name: "Position Update Movie",
             position_seconds: 100.0,
             duration_seconds: 1000.0
           },
           started_at: DateTime.utc_now()
         }}
      )

      html = render(view)
      # 100s into 1000s = 900s remaining = 15m
      assert html =~ "15m remaining"

      send(
        view.pid,
        {:entity_progress_updated,
         %{
           entity_id: movie_id,
           summary: %{},
           resume_target: nil,
           changed_record: %{
             episode_id: nil,
             video_object_id: nil,
             movie_id: movie_id,
             position_seconds: 800.0,
             duration_seconds: 1000.0
           },
           last_activity_at: DateTime.utc_now()
         }}
      )

      # 800s into 1000s = 200s remaining → "3m remaining"
      assert render(view) =~ "3m remaining"
    end

    test "playback_state_changed :stopped removes the session",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/status")
      movie_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:playback_state_changed,
         %PlaybackStateChanged{
           entity_id: movie_id,
           state: :playing,
           now_playing: %{
             entity_id: movie_id,
             movie_id: movie_id,
             movie_name: "Soon To Stop Movie",
             position_seconds: 0.0,
             duration_seconds: 1000.0
           },
           started_at: DateTime.utc_now()
         }}
      )

      assert render(view) =~ "Soon To Stop Movie"

      send(
        view.pid,
        {:playback_state_changed,
         %PlaybackStateChanged{
           entity_id: movie_id,
           state: :stopped,
           now_playing: nil,
           started_at: DateTime.utc_now()
         }}
      )

      refute render(view) =~ "Soon To Stop Movie"
    end
  end

  describe "live updates from library" do
    test "watch_event_created triggers a debounced stats refresh",
         %{conn: conn} do
      # The status page renders watch counts from a snapshot loaded at mount.
      # Without the debounced :refresh_stats handler the page would lag
      # behind reality. We pin the contract by sending a watch_event_created
      # message and asserting the page does not crash and re-renders.
      {:ok, view, _html} = live(conn, "/status")

      send(view.pid, {:watch_event_created, %{id: Ecto.UUID.generate()}})

      assert render(view) =~ "Playback"
    end

    test "entities_changed triggers a debounced rerender",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/status")

      send(
        view.pid,
        {:entities_changed,
         %MediaCentarr.Library.Events.EntitiesChanged{entity_ids: [Ecto.UUID.generate()]}}
      )

      assert render(view) =~ "Playback"
    end
  end

  describe "at-risk file warning" do
    # Surfaces the silent destruction risk to the user before it
    # happens — the user-facing complement to AbsencePolicy's TTL
    # filter. We assert on observable text in the rendered page; the
    # formatter shape is unit-tested in StatusHelpersTest.

    test "renders an at-risk row when a configured dir is offline with absent files",
         %{conn: conn} do
      # The status page only renders dir_health rows for watch dirs
      # listed in config; surface an at-risk warning by configuring
      # the test dir, then seeding a KnownFile in :absent state under
      # it. Restore on exit so we don't leak config to other tests.
      original_watch_dirs = :persistent_term.get({MediaCentarr.Config, :config}).watch_dirs

      put_config(:watch_dirs, ["/mnt/cold-storage"])
      on_exit(fn -> put_config(:watch_dirs, original_watch_dirs) end)

      MediaCentarr.Watcher.FilePresence.record_file(
        "/mnt/cold-storage/movie.mkv",
        "/mnt/cold-storage"
      )

      MediaCentarr.Watcher.FilePresence.mark_files_absent(["/mnt/cold-storage/movie.mkv"])

      {:ok, view, _html} = live(conn, "/status")

      # Wait for the async storage + at-risk load (sent from a Task).
      eventually(fn -> render(view) =~ "at risk of TTL purge" end)
    end
  end

  defp put_config(key, value) do
    config = :persistent_term.get({MediaCentarr.Config, :config})
    :persistent_term.put({MediaCentarr.Config, :config}, Map.put(config, key, value))
  end

  defp eventually(fun, attempts \\ 50, delay_ms \\ 20) do
    cond do
      fun.() -> :ok
      attempts > 0 -> Process.sleep(delay_ms) && eventually(fun, attempts - 1, delay_ms)
      true -> flunk("eventually/3 condition never became true")
    end
  end
end
