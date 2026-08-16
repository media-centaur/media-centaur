defmodule MediaCentaurWeb.SettingsLiveUpdateAutomationTest do
  @moduledoc """
  Integration tests for the update-automation controls on the Settings >
  System Updates card: the "automatically check" toggle, the poll-interval
  form (with floor clamping), and the "install automatically" toggle.

  The Updates card only renders when `SelfUpdate.enabled?()` (prod), so these
  tests flip the environment to :prod and pre-seed a fresh release cache so
  the section's on-mount check takes the cached branch — no network,
  no async task.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Config
  alias MediaCentaur.SelfUpdate.UpdateChecker

  setup do
    config_snapshot = :persistent_term.get({Config, :config})
    Application.put_env(:media_centaur, :environment, :prod)

    UpdateChecker.cache_result(
      {:ok,
       %{
         version: "55.0.0",
         tag: "v55.0.0",
         published_at: ~U[2050-01-01 00:00:00Z],
         html_url: "https://example.test/releases/v55.0.0",
         body: ""
       }}
    )

    on_exit(fn ->
      Application.put_env(:media_centaur, :environment, :test)
      :persistent_term.put({Config, :config}, config_snapshot)
      UpdateChecker.clear_cache()
    end)

    :ok
  end

  test "renders both automation controls with self-evaluable help copy", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings?section=system")

    assert html =~ "Automatically check for updates"
    assert html =~ "Install updates automatically"
    # The rate-limit rationale must be present so the user can evaluate the choice.
    assert html =~ "60 unauthenticated requests"
    # The deferral guarantee must be present for the auto-install choice.
    assert html =~ "waits until playback ends"
  end

  test "the retired ?section=updates address lands on System", %{conn: conn} do
    # The Updates section merged into System; old bookmarks and stale
    # Status-page links must keep resolving to the automation controls.
    {:ok, view, html} = live(conn, ~p"/settings?section=updates")

    assert html =~ "Automatically check for updates"

    assert has_element?(
             view,
             "[data-nav-zone='sections'] a.menu-item-active[href='/settings?section=system']"
           )
  end

  test "the System card shows the check cadence and a loose next-check time", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings?section=system")

    assert html =~ "Checks automatically every"
    refute html =~ "second"
  end

  test "toggling auto-install persists to Config", %{conn: conn} do
    refute Config.get(:auto_update_enabled)

    {:ok, view, _html} = live(conn, ~p"/settings?section=system")
    render_click(view, "toggle_auto_update", %{})

    assert Config.get(:auto_update_enabled) == true
  end

  test "toggling background checking persists to Config", %{conn: conn} do
    assert Config.get(:update_check_enabled) == true

    {:ok, view, _html} = live(conn, ~p"/settings?section=system")
    render_click(view, "toggle_update_check", %{})

    assert Config.get(:update_check_enabled) == false
  end

  test "saving the interval persists a valid value", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?section=system")
    render_submit(view, "save_update_interval", %{"interval_minutes" => "30"})

    assert Config.update_check_interval_minutes() == 30
  end

  test "saving an interval below the floor clamps it up", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?section=system")
    render_submit(view, "save_update_interval", %{"interval_minutes" => "5"})

    assert Config.update_check_interval_minutes() == 15
  end
end
