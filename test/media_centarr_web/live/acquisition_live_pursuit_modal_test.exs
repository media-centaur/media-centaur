defmodule MediaCentarrWeb.AcquisitionLivePursuitModalTest do
  @moduledoc """
  Covers the pursuit detail modal on `/download`. The detail used to be
  a separate LiveView at `/download/:pursuit_id`; it is now opened in
  place via the `?selected=<pursuit_id>` URL param and rendered by the
  modal `MediaCentarrWeb.Components.Acquisition.PursuitModal`.

  Three groups:

  - rendering across pursuit states (deep-link via `?selected=`),
  - manual triggers fired from inside the modal,
  - open/close round-trips that preserve the surrounding `?search=` /
    `?filter=` activity-zone params.
  """

  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Prowlarr
  alias MediaCentarr.Acquisition.Pursuits.Event
  alias MediaCentarr.Capabilities
  alias MediaCentarr.Downloads.QueueState
  alias MediaCentarr.Repo
  alias MediaCentarr.Secret

  @queue_cache_key {MediaCentarr.Downloads.QueueMonitor, :state}

  setup do
    # Inline Oban runs PursueTarget synchronously after ChangeTarget. Stub
    # Prowlarr so the worker snoozes cleanly rather than crashing on no
    # client configured.
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    config = :persistent_term.get({MediaCentarr.Config, :config})

    :persistent_term.put(
      {MediaCentarr.Config, :config},
      Map.merge(config, %{
        prowlarr_url: "http://prowlarr.test",
        prowlarr_api_key: Secret.wrap("test-key")
      })
    )

    Capabilities.save_test_result(:prowlarr, :ok)

    on_exit(fn ->
      :persistent_term.put(@queue_cache_key, %QueueState{items: []})
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentarr.Config, :config}, config)
      Capabilities.clear_test_result(:prowlarr)
    end)

    :persistent_term.put(@queue_cache_key, %QueueState{items: []})
    :ok
  end

  describe "rendering across pursuit states" do
    test "renders an Active pursuit with a seeking target in an open modal", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, view, html} = live(conn, "/download?selected=#{pursuit.id}")

      # Modal is open
      assert has_element?(view, "#pursuit-modal[data-state='open']")
      # CurrentAction.verb for a seeking active target reads "Searching".
      assert html =~ "Searching"
    end

    test "renders Done for a satisfied pursuit, no cancel-pursuit affordance", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "satisfied", title: "Sample Movie", status: "acquired"})

      {:ok, view, html} = live(conn, "/download?selected=#{pursuit.id}")

      assert has_element?(view, "#pursuit-modal[data-state='open']")
      assert html =~ "Done"
      refute html =~ "Cancel pursuit"
    end

    test "renders not-found inside the modal for an unknown id", %{conn: conn} do
      {:ok, view, html} = live(conn, "/download?selected=#{Ecto.UUID.generate()}")

      assert has_element?(view, "#pursuit-modal[data-state='open']")
      assert html =~ "Pursuit not found"
    end

    test "clicking a pursuit-group header expands the per-episode rows", %{conn: conn} do
      # Regression: Phase 3 of pursuits-maturation re-keyed group buckets
      # on `{title, state, awaiting?}` (so awaiting-decision pursuits
      # bucket separately), but the `PursuitGroup` component and the
      # `toggle_pursuit_group` handler still only carried `{title, state}`
      # — `MapSet.member?(expanded, {title, state, awaiting?})` never
      # matched what the handler stored, so clicking the header silently
      # toggled the MapSet without ever flipping `expanded?: true` on
      # render. End-to-end click pins the wire contract.
      now = DateTime.utc_now(:second)

      Enum.each(1..2, fn episode ->
        {:ok, pursuit} =
          %MediaCentarr.Acquisition.Pursuits.Pursuit{}
          |> Ecto.Changeset.change(%{
            recipe_type: "tmdb",
            tmdb_id: "group-#{episode}",
            tmdb_type: "tv",
            title: "Sample Show",
            season_number: 1,
            episode_number: episode,
            origin: "auto",
            state: "active",
            inserted_at: now,
            updated_at: now
          })
          |> Repo.insert()

        {:ok, _target} =
          %MediaCentarr.Acquisition.Target{}
          |> Ecto.Changeset.change(%{
            pursuit_id: pursuit.id,
            title: pursuit.title,
            status: "seeking",
            origin: pursuit.origin,
            inserted_at: now,
            updated_at: now
          })
          |> Repo.insert()
      end)

      {:ok, view, html} = live(conn, "/download")

      # The group renders collapsed by default — header visible, no
      # child rows yet. (The chevron is the only signal in the
      # snapshot; expanded? false means hero-chevron-right-mini.)
      assert html =~ "Sample Show"
      assert html =~ "2 episodes"
      assert html =~ "hero-chevron-right-mini"
      refute html =~ "hero-chevron-down-mini"

      # Click the actual rendered header — this exercises whatever
      # `phx-value-*` attrs the component emits, not a hand-crafted
      # event payload.
      expanded_html =
        view
        |> element("[phx-click='toggle_pursuit_group']")
        |> render_click()

      assert expanded_html =~ "hero-chevron-down-mini"
    end

    test "awaiting-decision modal opens without blocking on Prowlarr (ADR-044)", %{conn: conn} do
      # Regression: before ADR-044, the modal-open path issued a
      # synchronous Prowlarr search to populate the decision card —
      # ~500 ms in production, with the LV process blocked on the
      # WebSocket message handler the entire time. The fix renders a
      # `loading?: true` card immediately and dispatches the Prowlarr
      # fetch to a Task.Supervisor child. We pin the contract by
      # giving the Prowlarr stub a 300 ms delay: a regression to
      # synchronous behaviour would push the mount latency past the
      # 150 ms ceiling.
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Show", status: "seeking"})

      {:ok, _} =
        pursuit
        |> Ecto.Changeset.change(awaiting_decision_at: DateTime.utc_now(:second))
        |> Repo.update()

      Req.Test.stub(:prowlarr, fn conn ->
        Process.sleep(300)
        Req.Test.json(conn, [])
      end)

      start_ms = System.monotonic_time(:millisecond)
      {:ok, view, html} = live(conn, "/download?selected=#{pursuit.id}")
      open_ms = System.monotonic_time(:millisecond) - start_ms

      assert open_ms < 150,
             "modal open took #{open_ms} ms — should not block on Prowlarr (ADR-044)"

      assert has_element?(view, "#pursuit-modal[data-state='open']")
      assert html =~ "Searching for alternatives"
    end

    test "no `?selected=` param leaves the modal closed", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/download")

      assert has_element?(view, "#pursuit-modal[data-state='closed']")
    end
  end

  describe "manual triggers fired from inside the modal" do
    test "Cancel pursuit transitions the pursuit to cancelled", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, view, _html} = live(conn, "/download?selected=#{pursuit.id}")
      render_click(view, "cancel_pursuit", %{})

      reloaded = Repo.reload(pursuit)
      assert reloaded.state == "cancelled"
    end

    test "Change target records the target_changed event", %{conn: conn} do
      # `failed` exposes :change_target on the activity card.
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "failed"})

      {:ok, view, _html} = live(conn, "/download?selected=#{pursuit.id}")
      render_click(view, "change_target", %{})

      assert Repo.get_by(Event, pursuit_id: pursuit.id, kind: "target_changed")
    end

    test "Request decision sets awaiting_decision_at on the pursuit", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, view, _html} = live(conn, "/download?selected=#{pursuit.id}")
      render_click(view, "request_decision", %{})

      reloaded = Repo.reload(pursuit)
      assert reloaded.state == "active"
      assert %DateTime{} = reloaded.awaiting_decision_at
    end
  end

  describe "open / close round-trips via push_patch" do
    test "select_pursuit pushes a patch that opens the modal", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, view, _html} = live(conn, "/download")
      assert has_element?(view, "#pursuit-modal[data-state='closed']")

      render_click(view, "select_pursuit", %{"id" => pursuit.id})

      assert has_element?(view, "#pursuit-modal[data-state='open']")
      # URL was patched to include the selection.
      assert assert_patch(view) =~ "selected=#{pursuit.id}"
    end

    test "close_pursuit pushes a patch that closes the modal", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, view, _html} = live(conn, "/download?selected=#{pursuit.id}")
      assert has_element?(view, "#pursuit-modal[data-state='open']")

      render_click(view, "close_pursuit", %{})

      assert has_element?(view, "#pursuit-modal[data-state='closed']")
      # URL was patched back to /download (with the default filter still
      # serialised — see build_pursuit_modal_path).
      patched = assert_patch(view)
      refute patched =~ "selected="
    end

    test "opening the modal preserves the surrounding ?search= and ?filter= params",
         %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, view, _html} = live(conn, "/download?filter=all&search=Sample")

      render_click(view, "select_pursuit", %{"id" => pursuit.id})
      patched = assert_patch(view)

      assert patched =~ "filter=all"
      assert patched =~ "search=Sample"
      assert patched =~ "selected=#{pursuit.id}"
    end
  end
end
