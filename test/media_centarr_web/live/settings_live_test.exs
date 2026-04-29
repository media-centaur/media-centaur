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

  describe "save_tmdb retry hook" do
    # Saving a new TMDB key should re-emit `:file_detected` for any
    # watcher_files row that has no library link yet — recovery from
    # the silent-drop bug where a transient TMDB auth failure left
    # files stranded between watcher detection and pipeline ingestion.
    alias MediaCentarr.Topics
    alias MediaCentarr.Watcher.FilePresence

    test "re-emits file_detected for stranded files when key is updated", %{conn: conn} do
      stranded_path = "/tmp/test/save-tmdb-stranded.mkv"
      watch_dir = "/tmp/test"
      FilePresence.record_file(stranded_path, watch_dir)

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.pipeline_input())

      {:ok, view, _html} = live(conn, ~p"/settings?section=tmdb")

      view
      |> form("form[phx-submit='save_tmdb']", %{
        "tmdb_api_key" => "freshly-rotated-key-123",
        "auto_approve_threshold" => "0.85"
      })
      |> render_submit()

      assert_receive {:file_detected, %{path: ^stranded_path, watch_dir: ^watch_dir}}, 1_500
    end

    test "no re-emit when the key field is left blank (no value change)", %{conn: conn} do
      stranded_path = "/tmp/test/save-tmdb-noop.mkv"
      watch_dir = "/tmp/test"
      FilePresence.record_file(stranded_path, watch_dir)

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.pipeline_input())

      {:ok, view, _html} = live(conn, ~p"/settings?section=tmdb")

      view
      |> form("form[phx-submit='save_tmdb']", %{
        "tmdb_api_key" => "",
        "auto_approve_threshold" => "0.85"
      })
      |> render_submit()

      refute_receive {:file_detected, _}, 500
    end
  end

  describe "image repair button" do
    alias MediaCentarr.Library

    test "renders disabled with no badge when nothing is missing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings?section=danger")

      assert html =~ "Repair missing images"
      assert html =~ "All image files are present on disk"
      # Button is disabled
      assert html =~ ~r/phx-click="repair_missing_images"[^>]*disabled/s
    end

    test "renders enabled with badge when images are missing", %{conn: conn} do
      movie = Library.create_movie!(%{name: "Lost Posters", position: 0})

      Library.create_image!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      {:ok, _view, html} = live(conn, ~p"/settings?section=danger")

      assert html =~ "Repair missing images"
      assert html =~ "1 missing"
      assert html =~ "Finds 1 image file"
    end

    test "dispatch flips to 'Repairing…' and completes with a flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings?section=danger")

      # Hand the LiveView a completion message directly — we don't need the
      # background Task.Supervisor path to prove the state-transition wiring.
      send(
        view.pid,
        {:image_repair_complete, %{enqueued: 0, queue_reused: 0, queue_rebuilt: 0, skipped: 0}}
      )

      html = render(view)
      assert html =~ "No missing images — nothing to repair."
    end
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
