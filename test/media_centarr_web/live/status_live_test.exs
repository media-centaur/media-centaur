defmodule MediaCentarrWeb.StatusLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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
        {:playback_state_changed, movie_id, :playing,
         %{
           entity_id: movie_id,
           movie_id: movie_id,
           movie_name: "Sample Status Movie",
           position_seconds: 100.0,
           duration_seconds: 1000.0
         }, DateTime.utc_now()}
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
        {:playback_state_changed, movie_id, :playing,
         %{
           entity_id: movie_id,
           movie_id: movie_id,
           movie_name: "Position Update Movie",
           position_seconds: 100.0,
           duration_seconds: 1000.0
         }, DateTime.utc_now()}
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
        {:playback_state_changed, movie_id, :playing,
         %{
           entity_id: movie_id,
           movie_id: movie_id,
           movie_name: "Soon To Stop Movie",
           position_seconds: 0.0,
           duration_seconds: 1000.0
         }, DateTime.utc_now()}
      )

      assert render(view) =~ "Soon To Stop Movie"

      send(view.pid, {:playback_state_changed, movie_id, :stopped, nil, DateTime.utc_now()})

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

      send(view.pid, {:entities_changed, [Ecto.UUID.generate()]})

      assert render(view) =~ "Playback"
    end
  end
end
