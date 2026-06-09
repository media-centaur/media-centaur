defmodule MediaCentaurWeb.StatusLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Playback.Events.PlaybackStateChanged

  describe "GET /status" do
    test "renders without crashing", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status")
      assert html =~ "Status"
    end

    # Playback now lives in the Playback subsystem's health-board drill-in
    # (?subsystem=playback) — the M3b fold of the flat status sections into
    # per-subsystem Activity widgets.
    test "shows idle when no sessions are active", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status?subsystem=playback")
      assert html =~ "idle" or html =~ "Idle"
    end
  end

  describe "live updates from playback" do
    # The Status page is the operator's at-a-glance view of what the system
    # is doing right now. If playback state and progress don't stream in,
    # the page is a stale snapshot — useless during a live debug session.

    test "playback_state_changed broadcast surfaces the now-playing item",
         %{conn: conn} do
      {:ok, view, html} = live_async!(conn, "/status?subsystem=playback")
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
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=playback")
      movie_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:playback_state_changed,
         %PlaybackStateChanged{
           entity_id: movie_id,
           state: :playing,
           now_playing: %{
             entity_id: movie_id,
             entity_name: "Position Update Movie",
             position_seconds: 100.0,
             duration_seconds: 1000.0
           },
           started_at: DateTime.utc_now()
         }}
      )

      html = render(view)
      # 100s into 1000s = 900s remaining = 15m
      assert html =~ "15m remaining"

      # `progress_matches_session?/2` compares the progress record's
      # synthesised `playable_item.container_id` against the session's
      # `now_playing.entity_id` (both container UUIDs).
      send(
        view.pid,
        {:entity_progress_updated,
         %{
           entity_id: movie_id,
           summary: %{},
           resume_target: nil,
           changed_record: %{
             playable_item: %{container_type: :movie, container_id: movie_id},
             playable_item_id: Ecto.UUID.generate(),
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
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=playback")
      movie_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:playback_state_changed,
         %PlaybackStateChanged{
           entity_id: movie_id,
           state: :playing,
           now_playing: %{
             entity_id: movie_id,
             entity_name: "Soon To Stop Movie",
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

  # NOTE: the "live updates from library" tests were removed when the
  # pending-review count (the only consumer of library broadcasts on /status)
  # was dropped — the page no longer subscribes to Library events.

  describe "at-risk file warning" do
    # Surfaces the silent destruction risk to the user before it
    # happens — the user-facing complement to AbsenceSweeper's TTL
    # filter. We assert on observable text in the rendered page; the
    # formatter shape is unit-tested in StatusHelpersTest.

    test "renders an at-risk row when a configured dir is offline with stale files",
         %{conn: conn} do
      # The watch-dirs/storage view lives in the Watcher subsystem's
      # health-board drill-in (?subsystem=watcher), which renders the
      # dir_health rows for watch dirs listed in config. Surface an
      # at-risk warning by configuring the test dir, then seeding a
      # Library.FilePresence row whose last_seen_at is older than the
      # TTL threshold. Restore config on exit so we don't leak.
      original_watch_dirs = :persistent_term.get({MediaCentaur.Config, :config}).watch_dirs

      put_config(:watch_dirs, ["/mnt/cold-storage"])
      on_exit(fn -> put_config(:watch_dirs, original_watch_dirs) end)

      # Stamp a stale presence row (15 days old; TTL default is 30 so
      # this is still within TTL and shows up in the at-risk summary
      # for the offline drive — exactly the user-facing warning case).
      stale_at = DateTime.add(DateTime.utc_now(), -15, :day)

      MediaCentaur.Library.FilePresence.stamp(
        "/mnt/cold-storage/movie.mkv",
        "/mnt/cold-storage",
        stale_at
      )

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=watcher")

      # Wait for the async storage + at-risk load (sent from a Task).
      eventually(fn -> render(view) =~ "at risk of TTL purge" end)
    end
  end

  describe "watcher activity narrative" do
    # End-to-end wiring proof the storybook variations can't give us: a real
    # watcher reaching :watching feeds Supervisor.statuses/0, a scan telemetry
    # event feeds Supervisor.scan_stats/0, and both flow through the activity
    # bundle into the widget's "Last scan …" line. If any seam in that chain
    # breaks the line silently vanishes — this catches that. The per-piece
    # formatting is unit-tested in StatusHelpersTest.
    test "renders the last-scan line for a watching dir", %{conn: conn} do
      original_watch_dirs = :persistent_term.get({MediaCentaur.Config, :config}).watch_dirs

      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "status_watcher_narrative_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      put_config(:watch_dirs, [tmp_dir])

      MediaCentaur.Watcher.Supervisor.stop_watchers()
      MediaCentaur.Watcher.Supervisor.start_watchers()

      on_exit(fn ->
        MediaCentaur.Watcher.Supervisor.stop_watchers()
        put_config(:watch_dirs, original_watch_dirs)
        File.rm_rf!(tmp_dir)
      end)

      # 1. Wait for the watcher to attach to the (real, existing) temp dir.
      eventually(fn ->
        Enum.any?(MediaCentaur.Watcher.Supervisor.statuses(), fn status ->
          status.dir == tmp_dir and status.state == :watching
        end)
      end)

      # 2. Let the one-shot startup scan land in ScanStats first, then emit a
      #    scan event with known counts as the final recorded scan for this dir.
      eventually(fn -> MediaCentaur.Watcher.ScanStats.last_scan(tmp_dir) != nil end)

      :telemetry.execute(
        [:media_centaur, :watcher, :scan, :stop],
        %{duration: 1_000},
        %{dir: tmp_dir, total_video_files: 1_432, known: 1_429, dispatched: 3, relinked: 0}
      )

      eventually(fn -> match?(%{new: 3}, MediaCentaur.Watcher.ScanStats.last_scan(tmp_dir)) end)

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=watcher")

      eventually(fn ->
        html = render(view)
        html =~ "Last scan" and html =~ "1,432 files · 3 new"
      end)
    end
  end

  describe "Updates drill-in — upgrade history" do
    test "lists recorded versions in the Updates activity widget", %{conn: conn} do
      :ok = MediaCentaur.SelfUpdate.History.record_boot_version("0.81.0")
      :ok = MediaCentaur.SelfUpdate.History.record_boot_version("0.82.0")

      {:ok, _view, html} = live_async!(conn, "/status?subsystem=self_update")

      assert html =~ "update-history"
      assert html =~ "v0.82.0"
      assert html =~ "v0.81.0"
    end
  end

  defp put_config(key, value) do
    config = :persistent_term.get({MediaCentaur.Config, :config})
    :persistent_term.put({MediaCentaur.Config, :config}, Map.put(config, key, value))
  end

  defp eventually(fun, attempts \\ 50, delay_ms \\ 20) do
    cond do
      fun.() -> :ok
      attempts > 0 -> Process.sleep(delay_ms) && eventually(fun, attempts - 1, delay_ms)
      true -> flunk("eventually/3 condition never became true")
    end
  end
end
