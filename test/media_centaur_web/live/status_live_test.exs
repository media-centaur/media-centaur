defmodule MediaCentaurWeb.StatusLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Playback.Events.PlaybackStateChanged
  alias MediaCentaur.Status.Views

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

    # The metadata-activity section requires the `metadata_stats` assign to flow
    # through the activity bundle into the TMDB widget; a missing assign would
    # crash the required-attr render. Asserting the section marker proves the
    # wiring without depending on the shared MetadataStats singleton's volatile
    # contents (the populated states are covered by the storybook variations).
    test "tmdb drill-in renders the metadata-activity section", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status?subsystem=tmdb")
      assert html =~ "metadata-activity"
    end
  end

  describe "connections drill-in" do
    test "pushes a frame for the configured strips and the window from the URL", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=http&window=5h")

      assert has_element?(view, "#traffic[phx-hook='StripChart']")
      assert_push_event(view, "strip_chart:frame", %{id: "traffic", window: "5h", strips: strips})
      ids = Enum.map(strips, & &1.id)
      assert "tmdb" in ids and "tmdb_images" in ids and "github" in ids
      refute "steam" in ids
    end

    test "an unknown window falls back to 1h", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=http&window=2h")
      assert_push_event(view, "strip_chart:frame", %{window: "1h"})
    end

    test "the pill patches the URL and a fresh frame follows", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=http")
      assert_push_event(view, "strip_chart:frame", %{window: "1h"})

      view |> element("[phx-value-window='1w']") |> render_click()
      assert_patch(view, "/status?subsystem=http&window=1w")
      assert_push_event(view, "strip_chart:frame", %{window: "1w"})
    end

    test "frames keep coming on the tick and stop while hidden", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=http")
      assert_push_event(view, "strip_chart:frame", _first)
      assert_push_event(view, "strip_chart:frame", _second, 500)

      view
      |> element("#traffic")
      |> render_hook("strip_chart:visibility", %{"id" => "traffic", "visible" => false})

      drain_frames()
      refute_push_event(view, "strip_chart:frame", _, 300)

      view
      |> element("#traffic")
      |> render_hook("strip_chart:visibility", %{"id" => "traffic", "visible" => true})

      assert_push_event(view, "strip_chart:frame", _resumed, 500)
    end

    test "no frames while another drill-in is open", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=tmdb")
      refute_push_event(view, "strip_chart:frame", _, 300)
    end
  end

  # Frames that arrived before a hide are already in the mailbox; drop
  # them so the refute below speaks only about frames after it.
  defp drain_frames do
    receive do
      {_ref, {:push_event, "strip_chart:frame", _payload}} -> drain_frames()
    after
      0 -> :ok
    end
  end

  describe "first paint from projections (instant-navigation)" do
    # The Status page renders complete, current content on BOTH the dead and
    # connected mounts by reading the Status.Views projections — no skeleton,
    # no async pops (ADR-051; campaigns/instant-navigation.md Phase 1).

    test "dead render includes the primed library overview", %{conn: conn} do
      create_movie(%{name: "Sample Projection Movie"})
      Views.Overview.refresh_cache()

      html = conn |> get("/status?subsystem=library") |> html_response(200)

      assert html =~ "overview-glance"
      refute html =~ "Loading library overview…"
    end

    test "connected first render includes the overview without any async wait", %{conn: conn} do
      create_movie(%{name: "Sample Projection Movie"})
      Views.Overview.refresh_cache()

      {:ok, _view, html} = live(conn, "/status?subsystem=library")

      assert html =~ "overview-glance"
      refute html =~ "Loading library overview…"
    end

    test "dead render includes the primed storage snapshot", %{conn: conn} do
      Views.Storage.refresh_cache()

      html = conn |> get("/status?subsystem=watcher") |> html_response(200)

      # The watcher widget's database-drive card only renders from a
      # populated storage_drives assign.
      assert html =~ "Database"
    end

    test "overview projection refresh live-updates the open page", %{conn: conn} do
      # Recently-added only lists entities with a present file, so link one —
      # the name rendering in the strip is the observable update signal.
      first_movie = create_movie(%{name: "Sample Projection Movie"})
      create_linked_file(%{movie_id: first_movie.id})
      Views.Overview.refresh_cache()

      {:ok, view, _html} = live(conn, "/status?subsystem=library")

      second_movie = create_movie(%{name: "Second Sample Movie"})
      create_linked_file(%{movie_id: second_movie.id})
      Views.Overview.refresh_cache()

      assert render(view) =~ "Second Sample Movie"
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

  describe "playback activity widget" do
    test "idle tile shows the recent feed and lifetime stat figures", %{conn: conn} do
      MediaCentaur.WatchHistory.create_event(%{
        entity_type: :movie,
        title: "Movie A",
        duration_seconds: 3600.0,
        completed_at: ~U[2026-06-09 12:00:00.000000Z]
      })

      {:ok, _view, html} = live_async!(conn, "/status?subsystem=playback")

      assert html =~ "Movie A"
      assert html =~ "Recently watched"
      assert html =~ "Day streak"
    end

    test "a watch_event_created message refreshes the snapshot", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=playback")
      refute render(view) =~ "Movie A"

      {:ok, event} =
        MediaCentaur.WatchHistory.create_event(%{
          entity_type: :movie,
          title: "Movie A",
          duration_seconds: 3600.0,
          completed_at: ~U[2026-06-09 12:00:00.000000Z]
        })

      send(view.pid, {:watch_event_created, event})
      assert render(view) =~ "Movie A"
    end
  end

  describe "at-risk file warning" do
    # Surfaces the silent destruction risk to the user before it
    # happens — the user-facing complement to AbsenceSweeper's TTL
    # filter. We assert on observable text in the rendered page; the
    # formatter shape is unit-tested in StatusHelpersTest.

    test "renders an at-risk row when a configured dir is offline with stale files",
         %{conn: conn} do
      # The media-dirs/storage view lives in the Watcher subsystem's
      # health-board drill-in (?subsystem=watcher), which renders the
      # dir_health rows for media dirs listed in config. Surface an
      # at-risk warning by configuring the test dir, then seeding a
      # Library.FilePresence row whose last_seen_at is older than the
      # TTL threshold.
      put_config(:media_dirs, ["/mnt/cold-storage"])

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
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "status_watcher_narrative_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      put_config(:media_dirs, [tmp_dir])

      MediaCentaur.Watcher.Supervisor.start_watchers()

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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

  describe "system activity widget" do
    test "system drill-in renders the runtime-vitals widget", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status?subsystem=system")
      assert html =~ ~s(data-testid="system-widget")
    end
  end

  describe "downloads activity widget" do
    test "acquisition drill-in renders the connectivity + throughput widget", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status?subsystem=acquisition")

      assert html =~ ~s(data-testid="acquisition-widget")
    end
  end

  describe "updates activity widget" do
    test "self_update drill-in renders after the history enrich", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status?subsystem=self_update")
      assert html =~ "Updates"
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

  describe "social activity widget" do
    @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

    test "the board carries a Social tile", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status")
      assert html =~ "Social"
    end

    test "the drill-in aggregates relays, roster and reviews", %{conn: conn} do
      {:ok, _relay} = MediaCentaur.Social.add_relay("wss://relay-one.example")
      {:ok, _relay} = MediaCentaur.Social.add_relay("wss://relay-two.example")
      {:ok, _friend} = MediaCentaur.Social.add_friend(@friend_pubkey, "Sample Friend")

      {:ok, _view, html} = live_async!(conn, "/status?subsystem=social")

      assert html =~ ~s(data-testid="social-widget")
      # No connections owner runs under :test, so nothing is connected.
      assert html =~ "Connected to 0 of 2 relays"
      assert html =~ "relay-one.example"
      assert html =~ "relay-two.example"
      assert html =~ "Connecting"
      assert html =~ "/settings?section=social"
      assert html =~ "1 friends"
      assert html =~ "0 sent"
      assert html =~ "0 received"
      assert html =~ "/discovery/friends"
    end

    test "a relay fault colours the Social tile and names itself in the drill-in", %{conn: conn} do
      {:ok, _incident} =
        MediaCentaur.ErrorReports.raise_fault(:social, :relays_unreachable, :error,
          message: "No relay reachable",
          display_title: "No relay reachable"
        )

      {:ok, _view, html} = live_async!(conn, "/status?subsystem=social")

      assert html =~ "No relay reachable"

      assert [%{component: :social, state: :error}] =
               Enum.filter(
                 MediaCentaurWeb.StatusLive.HealthBoard.build_board(
                   MediaCentaur.ErrorReports.list_buckets(),
                   MapSet.new()
                 ),
                 &(&1.component == :social)
               )
    end

    test "with nothing configured the widget says so", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status?subsystem=social")

      assert html =~ "No relays configured"
      assert html =~ "0 friends"
    end
  end

  describe "subsystem log panel" do
    alias MediaCentaur.Console
    alias MediaCentaur.Console.Entry
    alias MediaCentaur.Topics

    setup do
      :ok = Console.clear()
      :ok
    end

    test "a drill-in with recent lines opens onto them", %{conn: conn} do
      seed([entry(:watcher, "log panel seed line")])

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=watcher")

      assert has_element?(view, "#subsystem-logs summary", "Technical logs")
      assert panel(view) =~ "log panel seed line"
    end

    test "a subsystem with no lines renders no disclosure at all", %{conn: conn} do
      # `:self_update` logs under `:system` by design, so its panel can never
      # have lines — the deterministic empty case.
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=self_update")

      assert has_element?(view, "#health-drill-in")
      refute has_element?(view, "#subsystem-logs")
    end

    test "a matching broadcast lands newest-first above the lines already shown", %{conn: conn} do
      seed([entry(:watcher, "log panel seed line")])

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=watcher")

      # The broadcast batch is oldest-first; the panel reads newest-first.
      broadcast([entry(:watcher, "log panel alpha"), entry(:watcher, "log panel omega")])

      html = panel(view)

      assert position(html, "log panel omega") < position(html, "log panel alpha")
      assert position(html, "log panel alpha") < position(html, "log panel seed line")
    end

    test "a broadcast from another subsystem's component is ignored", %{conn: conn} do
      seed([entry(:watcher, "log panel seed line")])

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=watcher")

      broadcast([entry(:pipeline, "log panel foreign line")])

      html = panel(view)

      assert html =~ "log panel seed line"
      refute html =~ "log panel foreign line"
    end

    test "closing the drill-in takes the panel with it", %{conn: conn} do
      seed([entry(:watcher, "log panel seed line")])

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=watcher")
      assert has_element?(view, "#subsystem-logs")

      view |> element("#health-drill-in [phx-click='close_subsystem']") |> render_click()

      refute has_element?(view, "#health-drill-in")
      refute has_element?(view, "#subsystem-logs")
    end

    test "switching subsystems never carries the previous panel over", %{conn: conn} do
      seed([entry(:watcher, "log panel seed line")])

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=watcher")
      assert panel(view) =~ "log panel seed line"

      view |> element("#subsystem-tile-self_update") |> render_click()

      refute has_element?(view, "#subsystem-logs")
    end

    test "a single-component subsystem leaves the per-line badge off", %{conn: conn} do
      seed([entry(:watcher, "log panel seed line")])

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=watcher")

      refute has_element?(view, "#subsystem-logs .console-component-badge")
    end

    test "a folded subsystem labels each line with the component it came from", %{conn: conn} do
      seed([entry(:nostr, "log panel relay line")])

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=social")

      assert panel(view) =~ "log panel relay line"
      assert has_element?(view, "#subsystem-logs .console-component-badge")
    end

    # Scoped to the drill-in's own disclosure: the sticky console drawer is
    # mounted on every page and echoes the same entries, so a whole-document
    # `=~` would pass on the drawer's copy.
    defp panel(view), do: view |> element("#subsystem-logs") |> render()

    defp entry(component, message) do
      %Entry{
        id: System.unique_integer([:monotonic, :positive]),
        timestamp: ~U[2026-09-17 10:00:00Z],
        level: :info,
        component: component,
        message: message
      }
    end

    # Seeds the store the way the console handler does, without going through
    # Logger: a `Log.warning` would also mint an ErrorReports incident whose
    # `{:buckets_changed, _}` broadcast lands in whichever test is running when
    # the Buckets server gets to it.
    defp seed(entries) do
      Enum.each(entries, &Console.Buffer.append/1)
      :ok = Console.flush()
    end

    defp broadcast(entries) do
      :ok = Topics.publish(Topics.console_logs(), {:log_entries, entries})
    end

    defp position(html, needle), do: html |> :binary.match(needle) |> elem(0)
  end

  describe "systemd journal panel" do
    # The BEAM runs under no systemd unit in the test environment, so
    # `Console.journal_available?/0` is false and the control never renders.
    # That is the default path on every install that isn't running the
    # service — a laptop `mix phx.server`, a container — and the panel has to
    # stay out of the rail there rather than offer a disclosure onto nothing.
    #
    # The subscribe/unsubscribe transitions are pure and live in
    # `StatusLive.JournalPanel` (journal_panel_test.exs); the refcount and
    # port lifecycle they drive are covered against a named instance in
    # `MediaCentaur.Console.JournalSourceTest`.
    test "the System drill-in offers no journal where no unit is detected", %{conn: conn} do
      refute MediaCentaur.Console.journal_available?()

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=system")

      assert has_element?(view, "#health-drill-in")
      refute has_element?(view, "#subsystem-journal")
    end

    # `journalctl` can die between the render that drew Reconnect and the
    # click on it, so the handler has to answer a *failing* reconnect rather
    # than match on `:ok`. Driving the event directly is the only way to reach
    # it here — the control renders only where a unit exists.
    test "Reconnect is answered where no unit is detected", %{conn: conn} do
      refute MediaCentaur.Console.journal_available?()

      {:ok, view, _html} = live_async!(conn, "/status?subsystem=system")

      assert render_click(view, "journal_reconnect")
      assert has_element?(view, "#health-drill-in")
    end
  end

  defp put_config(key, value) do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
    :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, key, value))
  end
end
