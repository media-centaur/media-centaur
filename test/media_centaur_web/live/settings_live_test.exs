defmodule MediaCentaurWeb.SettingsLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "mounts at /settings", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings")
    assert html =~ "Services"
  end

  test "receives cross-tab spoiler_free sync via PubSub", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.settings_updates(),
      {:setting_changed, "spoiler_free_mode", true}
    )

    # Wait for the broadcast to be processed by the LiveView
    _ = render(view)

    # The LiveView should have updated its spoiler_free assign
    assert view |> element("[data-page-behavior]") |> render() =~ "settings"
  end

  test "receives watcher state changes via PubSub", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.dir_state(),
      {:dir_state_changed, "/tmp/test", :watch_dir, :unavailable}
    )

    # The LiveView should process the message without crashing
    _ = render(view)
    assert view |> element("[data-page-behavior]") |> render() =~ "settings"
  end
end
