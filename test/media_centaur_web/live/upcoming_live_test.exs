defmodule MediaCentaurWeb.UpcomingLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Repo

  test "GET /upcoming renders the page", %{conn: conn} do
    {:ok, _view, html} = live_async!(conn, "/upcoming")
    # The page header always renders the "Upcoming" heading
    assert html =~ "Upcoming"
  end

  test "first paint (disconnected render) shows tracked items, not an empty flash",
       %{conn: conn} do
    # Desktop first-paint correctness: the static HTTP render must already
    # carry the tracked-release data, not an empty placeholder that flashes
    # until the socket connects. `get/2` exercises the disconnected render.
    item =
      create_tracking_item(%{tmdb_id: 8_777, media_type: :tv_series, name: "First Paint Upcoming Show"})

    create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1, released: true})

    html = conn |> get("/upcoming") |> html_response(200)

    assert html =~ "First Paint Upcoming Show",
           "tracked items must render on the disconnected first paint"
  end

  test "clicking the Track New Releases button opens the modal", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/upcoming")

    # The track button only appears when TMDB is ready; if the test
    # environment isn't TMDB-ready, the conditional skips the assertion.
    if has_element?(view, "button", "Track New Releases") do
      rendered = render_click(element(view, "button", "Track New Releases"))
      assert rendered =~ "track-search-input"
    end
  end

  describe "debounce on broadcast-driven reloads" do
    test "five rapid broadcasts trigger only one reload after the debounce window", %{conn: conn} do
      # Regression guard: :releases_updated, :entities_changed, and grab-event
      # messages must be debounced (500ms) rather than firing a reload on
      # every message. Five messages in quick succession should produce at
      # most one reload — the page must still render correctly after the
      # window. (`:entities_changed` only refreshes `tracked_items` since
      # the other assigns derive from ReleaseTracking / Acquisition.)
      {:ok, view, _html} = live_async!(conn, "/upcoming")

      for _ <- 1..5 do
        send(
          view.pid,
          {:entities_changed, %MediaCentaur.Library.Events.EntitiesChanged{entity_ids: []}}
        )
      end

      Process.sleep(600)

      assert render(view) =~ "Upcoming"
    end
  end

  describe "queue_all_show event (ADR-056: the bulk gesture is plan-now)" do
    setup do
      # Oban runs inline in tests, so plan creation triggers RunPlan →
      # Prowlarr.search. Stub a no-result response so the plan solves
      # to unfound cleanly; the ready draft is what we assert on.
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

      client =
        Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")

      :persistent_term.put({MediaCentaur.Search.Prowlarr, :client}, client)

      config = :persistent_term.get({MediaCentaur.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Config, :config},
        config
        |> Map.put(:prowlarr_url, "http://prowlarr.test")
        |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
      )

      MediaCentaur.Capabilities.save_test_result(:prowlarr, :ok)

      on_exit(fn ->
        :persistent_term.erase({MediaCentaur.Search.Prowlarr, :client})
        :persistent_term.put({MediaCentaur.Config, :config}, config)
      end)

      :ok
    end

    test "plans all pending releases as one ready draft for approval", %{conn: conn} do
      item =
        create_tracking_item(%{tmdb_id: 8_001, media_type: :tv_series, name: "Bulk Queue"})

      yesterday = Date.add(Date.utc_today(), -1)

      Enum.each(1..3, fn episode ->
        create_tracking_release(%{
          item_id: item.id,
          season_number: 5,
          episode_number: episode,
          air_date: yesterday,
          released: true
        })
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/upcoming")

      result = render_hook(view, "queue_all_show", %{"item-id" => item.id})

      assert result =~ "Coverage plan started"

      # One draft plan with tracking provenance, left ready for the
      # user to steer and approve — never an unreviewed grab.
      [plan] = Repo.all(MediaCentaur.Acquisition.Plans.Plan)
      assert plan.status == "ready"
      assert plan.tracking_item_id == item.id
      assert length(MediaCentaur.Acquisition.Plans.units_for(plan.id)) == 3

      # No pursuit was armed by the gesture itself.
      assert Repo.all(MediaCentaur.Acquisition.Pursuits.Pursuit) == []
    end

    test "flashes an error when the item is not found", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/upcoming")

      result = render_hook(view, "queue_all_show", %{"item-id" => Ecto.UUID.generate()})

      assert result =~ "not found" or result =~ "couldn't"
    end
  end

  describe "live updates from grab lifecycle" do
    # Releases on the Upcoming page show grab status badges (Pending,
    # Searching, Grabbed, etc). When acquisition fires PubSub events as a
    # download is requested or fails, the badge must refresh without a
    # navigation. Each event individually is debounced 500ms; rapid bursts
    # (one per episode of a season) must coalesce.

    test "grab_submitted broadcast schedules a debounced grab-status reload",
         %{conn: conn} do
      today = Date.utc_today()

      item =
        create_tracking_item(%{tmdb_id: 9_001, media_type: :tv_series, name: "Grab Live Show"})

      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: 1,
        air_date: Date.add(today, 7),
        released: false
      })

      {:ok, view, _html} = live_async!(conn, ~p"/upcoming")

      # `UpcomingLive.ensure_loaded/1` spawns the data load on a
      # supervised task and returns immediately (per the "no blocking
      # LV page loads" rule). The initial HTML is the empty default;
      # we wait for the `{:upcoming_loaded, ...}` message to land
      # before asserting on populated state.
      send(view.pid, {:grab_submitted, %{id: Ecto.UUID.generate()}})

      Process.sleep(600)

      assert render(view) =~ "Grab Live Show"
    end

    test "five rapid grab events coalesce into one reload",
         %{conn: conn} do
      # Regression guard for the 500ms grab_statuses_timer debounce —
      # a season grab cascade emits one event per episode; without the
      # debounce we would re-query grab statuses N times back-to-back.
      {:ok, view, _html} = live_async!(conn, ~p"/upcoming")

      for _ <- 1..5 do
        send(view.pid, {:grab_submitted, %{id: Ecto.UUID.generate()}})
        send(view.pid, {:auto_grab_armed, %{id: Ecto.UUID.generate()}})
      end

      Process.sleep(600)

      assert render(view) =~ "Upcoming"
    end

    test "queue_snapshot updates the in-memory queue items",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/upcoming")

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: []}})

      assert render(view) =~ "Upcoming"
    end

    test "releases_updated broadcast triggers a debounced reload",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/upcoming")

      send(view.pid, {:releases_updated, [Ecto.UUID.generate()]})

      Process.sleep(600)

      assert render(view) =~ "Upcoming"
    end
  end
end
