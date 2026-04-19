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

  describe "detect download client from Prowlarr" do
    # Prowlarr returns URLs exactly as configured inside Prowlarr. Those
    # hostnames (typically Docker service names like `qbittorrent`) are
    # rarely reachable from the host running media-centarr. The detect
    # flow must therefore pre-fill the form without persisting — the user
    # reviews the URL and confirms with Save. See ADR-037.
    alias MediaCentarr.Config

    test "pre-fills form with detected values but does not persist until save",
         %{conn: conn} do
      # Capture the saved URL before detection so we can assert it is
      # untouched afterwards.
      saved_url_before = Config.get(:download_client_url)

      {:ok, view, _html} = live(conn, ~p"/settings?section=acquisition")

      detected = %{
        name: "qBittorrent",
        type: "qbittorrent",
        url: "http://qbittorrent:8080",
        username: "admin",
        enabled: true
      }

      send(view.pid, {:download_client_detect_result, {:ok, [detected]}})

      html = render(view)

      # Form shows the detected URL as the input value.
      assert html =~ ~s(value="http://qbittorrent:8080")
      assert html =~ ~s(value="admin")

      # Config is NOT updated — the user hasn't clicked Save.
      assert Config.get(:download_client_url) == saved_url_before

      # A flash instructs the user to review and save.
      assert html =~ "review" or html =~ "Review"
    end

    test "empty result shows no clients configured", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings?section=acquisition")

      send(view.pid, {:download_client_detect_result, {:ok, []}})

      html = render(view)
      assert html =~ "no download clients" or html =~ "No download clients"
    end

    test "error result shows connection failure", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings?section=acquisition")

      send(view.pid, {:download_client_detect_result, {:error, :timeout}})

      html = render(view)
      assert html =~ "Couldn&#39;t reach Prowlarr" or html =~ "couldn&#39;t reach Prowlarr"
    end
  end
end
