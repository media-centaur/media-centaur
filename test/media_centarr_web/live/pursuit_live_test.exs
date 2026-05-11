defmodule MediaCentarrWeb.PursuitLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Prowlarr
  alias MediaCentarr.Acquisition.Pursuits.Event
  alias MediaCentarr.Downloads.QueueState
  alias MediaCentarr.Repo

  @queue_cache_key {MediaCentarr.Downloads.QueueMonitor, :state}

  setup do
    # Inline Oban runs PursueTarget synchronously after ChangeTarget. Stub
    # Prowlarr so the worker snoozes cleanly rather than crashing on no
    # client configured.
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    on_exit(fn ->
      :persistent_term.put(@queue_cache_key, %QueueState{items: []})
      :persistent_term.erase({Prowlarr, :client})
    end)

    :persistent_term.put(@queue_cache_key, %QueueState{items: []})
    :ok
  end

  describe "rendering across states" do
    test "renders an Active pursuit with a seeking target", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, _view, html} = live(conn, "/download/#{pursuit.id}")

      # CurrentAction.verb for a seeking active target reads "Searching".
      assert html =~ "Searching"
    end

    test "renders Done for a satisfied pursuit", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "satisfied", title: "Sample Movie", status: "acquired"})

      {:ok, _view, html} = live(conn, "/download/#{pursuit.id}")

      assert html =~ "Done"
      refute html =~ "Cancel pursuit"
    end

    test "renders not-found for unknown id", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/download/#{Ecto.UUID.generate()}")
      assert html =~ "Pursuit not found"
    end
  end

  describe "manual triggers" do
    test "Cancel pursuit transitions the pursuit to cancelled", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, view, _html} = live(conn, "/download/#{pursuit.id}")
      render_click(view, "cancel_pursuit", %{})

      reloaded = Repo.reload(pursuit)
      assert reloaded.state == "cancelled"
    end

    test "Change target records the target_changed event", %{conn: conn} do
      # Use a target status that exposes the :change_target affordance —
      # e.g. failed (auto-search gave up), so the button is wired up.
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "failed"})

      {:ok, view, _html} = live(conn, "/download/#{pursuit.id}")
      render_click(view, "change_target", %{})

      assert Repo.get_by(Event, pursuit_id: pursuit.id, kind: "target_changed")
    end

    test "Request decision flips the pursuit to needs_decision", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, view, _html} = live(conn, "/download/#{pursuit.id}")
      render_click(view, "request_decision", %{})

      reloaded = Repo.reload(pursuit)
      assert reloaded.state == "needs_decision"
    end
  end
end
