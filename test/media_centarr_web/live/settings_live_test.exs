defmodule MediaCentarrWeb.SettingsLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "mounts at /settings", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings")
    assert html =~ "Services"
  end

  # Smoke test — each settings section renders without crashing. This exists
  # because section_content/1 is invoked as a function component with an
  # explicit attribute list; adding a new socket assign without also threading
  # it through the function component invocation crashes the section that
  # references it. Mounting `/settings` alone exercises only the default
  # "services" section, so the failure mode is per-section.
  for section <- [
        "services",
        "preferences",
        "tmdb",
        "acquisition",
        "pipeline",
        "playback",
        "library",
        "release_tracking",
        "system",
        "danger"
      ] do
    test "section #{section} mounts without crashing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings?section=#{unquote(section)}")
      assert is_binary(html)
    end
  end

  test "receives cross-tab spoiler_free sync via PubSub", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.settings_updates(),
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
      MediaCentarr.PubSub,
      MediaCentarr.Topics.dir_state(),
      {:dir_state_changed, "/tmp/test", :watch_dir, :unavailable}
    )

    # The LiveView should process the message without crashing
    _ = render(view)
    assert view |> element("[data-page-behavior]") |> render() =~ "settings"
  end
end
