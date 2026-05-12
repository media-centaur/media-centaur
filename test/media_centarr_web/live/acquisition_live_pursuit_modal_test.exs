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

    test "Request decision flips the pursuit to needs_decision", %{conn: conn} do
      {pursuit, _target} =
        create_pursuit_with_target(%{state: "active", title: "Sample Movie", status: "seeking"})

      {:ok, view, _html} = live(conn, "/download?selected=#{pursuit.id}")
      render_click(view, "request_decision", %{})

      reloaded = Repo.reload(pursuit)
      assert reloaded.state == "needs_decision"
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
