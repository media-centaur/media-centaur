defmodule MediaCentaurWeb.SettingsLiveAcquisitionTest do
  @moduledoc """
  The Acquisition and TMDB sections as connection rows (UIDR-041): the
  readout shows what is configured with no inputs until Edit; Test asks
  the connection state owner (`IntegrationHealth`) to verify; Save and
  Save-and-test persist what was typed before anything else happens, so
  a failing test never displaces the user's input.

  The owner is started per test with an injected verifier, and each
  case waits for the owner's terminal broadcast before reading the row.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Acquisition.AutoGrabSettings
  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationHealth
  alias MediaCentaur.IntegrationHealth.Status
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Settings.Preferences.PlanningMode

  defmodule OkVerifier do
    @behaviour MediaCentaur.IntegrationHealth.Verifier
    @impl true
    def run(_id), do: :ok
  end

  defmodule RejectVerifier do
    @behaviour MediaCentaur.IntegrationHealth.Verifier
    @impl true
    def run(_id), do: {:error, :rejected}
  end

  setup do
    # Reset Config keys at the START of each test (in the test process,
    # while it owns its DB sandbox connection).
    Config.update(:tmdb_api_key, nil)
    Config.update(:prowlarr_url, nil)
    Config.update(:prowlarr_api_key, nil)
    Config.update(:download_client_type, nil)
    Config.update(:download_client_url, nil)
    Config.update(:download_client_username, nil)
    Config.update(:download_client_password, nil)
    Config.update(:usenet_download_client_type, nil)
    Config.update(:usenet_download_client_url, nil)
    Config.update(:usenet_download_client_api_key, nil)

    Application.put_env(:media_centaur, :integration_health_verifier, OkVerifier)
    on_exit(fn -> Application.delete_env(:media_centaur, :integration_health_verifier) end)
    start_supervised!(IntegrationHealth)
    IntegrationHealth.subscribe()
    :ok
  end

  defp configure_prowlarr do
    Config.update(:prowlarr_url, "http://localhost:9696")
    Config.update(:prowlarr_api_key, "k")
    :ok
  end

  # Waits for the owner's terminal broadcast for `id`, then re-renders.
  defp await_test(view, id) do
    assert_receive {:integration_health_changed, %Status{id: ^id, test_state: state}}
                   when state in [:ok, :error],
                   1_000

    render(view)
  end

  describe "readout" do
    test "a configured install shows rows with no inputs until Edit", %{conn: conn} do
      configure_prowlarr()
      {:ok, view, html} = live_async!(conn, ~p"/settings?section=acquisition")

      assert html =~ "http://localhost:9696"
      assert html =~ "API key set"
      refute has_element?(view, "#connection-prowlarr input")
      refute has_element?(view, "#connection-prowlarr select")
    end

    test "an unconfigured row reads Not configured with Set up", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      assert has_element?(view, "#connection-prowlarr", "Not configured")
      assert has_element?(view, "#connection-prowlarr-setup", "Set up")
    end

    test "Test asks the owner to verify; the row follows and stored values are untouched",
         %{conn: conn} do
      configure_prowlarr()
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view |> element("#connection-prowlarr-test") |> render_click()
      html = await_test(view, :prowlarr)

      assert html =~ "Connected"
      assert Config.get(:prowlarr_url) == "http://localhost:9696"
      assert %{status: :ok} = Capabilities.load_test_result(:prowlarr)
    end
  end

  describe "edit state" do
    setup do
      configure_prowlarr()
    end

    test "Edit opens the form; Cancel closes it with nothing changed", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()
      assert has_element?(view, "#connection-prowlarr-form input[name=prowlarr_url]")

      view |> element("#connection-prowlarr-cancel") |> render_click()
      refute has_element?(view, "#connection-prowlarr-form")
      assert Config.get(:prowlarr_url) == "http://localhost:9696"
    end

    test "opening a second row's form closes the first", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()
      view |> element("#connection-download_client-setup") |> render_click()
      refute has_element?(view, "#connection-prowlarr-form")
      assert has_element?(view, "#connection-download_client-form")
    end

    test "Save persists, closes the form and a connected row reads Not tested", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      # A passing test first, so the save has a result to invalidate.
      view |> element("#connection-prowlarr-test") |> render_click()
      assert await_test(view, :prowlarr) =~ "Connected"

      view |> element("#connection-prowlarr-edit") |> render_click()

      view
      |> form("#connection-prowlarr-form", %{"prowlarr_url" => "http://prowlarr.example.com:9696"})
      |> render_submit(%{"_action" => "save"})

      assert Config.get(:prowlarr_url) == "http://prowlarr.example.com:9696"
      refute has_element?(view, "#connection-prowlarr-form")

      assert_receive {:integration_health_changed, %Status{id: :prowlarr, test_state: :unknown}},
                     1_000

      assert render(view) =~ "Not tested"
      assert Capabilities.load_test_result(:prowlarr) == nil
    end

    test "Save and test persists BEFORE verifying and closes on :ok", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()

      view
      |> form("#connection-prowlarr-form", %{"prowlarr_url" => "http://prowlarr.example.com:9696"})
      |> render_submit(%{"_action" => "test"})

      assert Config.get(:prowlarr_url) == "http://prowlarr.example.com:9696"
      html = await_test(view, :prowlarr)
      refute html =~ "connection-prowlarr-form"
      assert html =~ "Connected"
    end

    test "a failed Save and test keeps the typed values in the open form", %{conn: conn} do
      Application.put_env(:media_centaur, :integration_health_verifier, RejectVerifier)
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()

      view
      |> form("#connection-prowlarr-form", %{"prowlarr_url" => "http://prowlarr.example.com:9696"})
      |> render_submit(%{"_action" => "test"})

      await_test(view, :prowlarr)

      assert has_element?(
               view,
               "#connection-prowlarr-form input[value='http://prowlarr.example.com:9696']"
             )
    end

    test "Escape cancels", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-prowlarr-edit") |> render_click()
      render_keydown(view, "cancel_edit", %{"key" => "Escape"})
      refute has_element?(view, "#connection-prowlarr-form")
    end
  end

  describe "download clients" do
    test "Remove client empties the slot", %{conn: conn} do
      Config.update(:download_client_type, "qbittorrent")
      Config.update(:download_client_url, "http://localhost:8080")
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-download_client-edit") |> render_click()
      view |> element("#connection-download_client-remove") |> render_click()

      assert Config.get(:download_client_type) == nil

      assert_receive {:integration_health_changed, %Status{id: :download_client, configured?: false}},
                     1_000

      assert has_element?(view, "#connection-download_client", "Not configured")
    end

    test "a blank API key on save keeps the stored usenet key", %{conn: conn} do
      Config.update(:usenet_download_client_type, "sabnzbd")
      Config.update(:usenet_download_client_url, "http://localhost:8085")
      Config.update(:usenet_download_client_api_key, "keep-me")
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")
      view |> element("#connection-usenet_download_client-edit") |> render_click()

      view
      |> form("#connection-usenet_download_client-form", %{
        "usenet_download_client_url" => "http://localhost:8085",
        "usenet_download_client_api_key" => ""
      })
      |> render_submit(%{"_action" => "save"})

      assert MediaCentaur.Secret.expose(Config.get(:usenet_download_client_api_key)) == "keep-me"
    end

    test "Detect from Prowlarr puts each client on its row as a pending detection", %{
      conn: conn
    } do
      configure_prowlarr()
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      clients = [
        %{
          name: "qBittorrent",
          type: "qbittorrent",
          url: "http://qbit.detected:8080",
          username: "admin",
          enabled: true
        },
        %{
          name: "SABnzbd",
          type: "sabnzbd",
          url: "http://sab.detected:8085",
          username: nil,
          enabled: true
        }
      ]

      send(view.pid, {:download_client_detect_result, {:ok, clients}})

      assert has_element?(view, "#connection-download_client", "Detected from Prowlarr, not saved")

      assert has_element?(
               view,
               "#connection-usenet_download_client",
               "Detected from Prowlarr, not saved"
             )

      assert Config.get(:download_client_url) == nil

      view |> element("#connection-download_client-review") |> render_click()

      assert has_element?(
               view,
               "#connection-download_client-form input[name=download_client_url][value='http://qbit.detected:8080']"
             )

      view |> element("#connection-usenet_download_client-dismiss") |> render_click()
      refute has_element?(view, "#connection-usenet_download_client", "Detected from Prowlarr")
    end
  end

  describe "gated cards" do
    test "state their prerequisite while Prowlarr is not ready", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      assert has_element?(
               view,
               "#card-download-button",
               "Available once Prowlarr's connection test passes."
             )

      assert has_element?(
               view,
               "#card-auto-acquisition",
               "Available once Prowlarr's connection test passes."
             )

      refute has_element?(view, "#card-auto-acquisition button")
    end
  end

  describe "auto-acquisition rows (Prowlarr ready)" do
    setup do
      configure_prowlarr()
      Capabilities.save_test_result(:prowlarr, :ok)
      :ok
    end

    test "a choice persists on click", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> element("#auto-grab-default_max_quality button[phx-value-choice=hd_1080p]")
      |> render_click()

      assert AutoGrabSettings.load().default_max_quality == "hd_1080p"
    end

    test "a stepper persists its absolute target", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> element("#auto-grab-pack_min_fit button[aria-label='Increase Season packs']")
      |> render_click()

      assert AutoGrabSettings.load().pack_min_fit == 80
    end

    test "the planning mode is a choice row in the button's words", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> element("#planning-mode button[phx-value-choice=auto_select_best_release]")
      |> render_click()

      assert PlanningMode.value() == :auto_select_best_release
    end
  end

  test "the release-tracking interval steps along its ladder", %{conn: conn} do
    {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

    view
    |> element(
      "#release-tracking-interval button[aria-label='Increase Check TMDB for new release dates']"
    )
    |> render_click()

    assert Config.get(:release_tracking_refresh_interval_hours) == 8
  end

  describe "tmdb row" do
    test "Save and test persists the key BEFORE verifying", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=tmdb")
      view |> element("#connection-tmdb-setup") |> render_click()

      view
      |> form("#connection-tmdb-form", %{"tmdb_api_key" => "tmdb-key-123"})
      |> render_submit(%{"_action" => "test"})

      assert MediaCentaur.Secret.expose(Config.get(:tmdb_api_key)) == "tmdb-key-123"
      assert await_test(view, :tmdb) =~ "Connected"
    end
  end
end
