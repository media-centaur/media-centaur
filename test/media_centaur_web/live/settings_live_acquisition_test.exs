defmodule MediaCentaurWeb.SettingsLiveAcquisitionTest do
  @moduledoc """
  The Acquisition section (Prowlarr + Download Client) and TMDB section
  share a discipline: any value the user types in is persisted, even if
  a connection test fails. Clicking "Test connection" must save the
  current form values *before* running the test — otherwise a failing
  test would re-render the form against stale config and clobber what
  the user just typed.

  These tests exercise that contract end-to-end via form submission.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Config

  setup do
    # Reset Config keys at the START of each test (in the test process,
    # while it owns its DB sandbox connection). The earlier on_exit
    # cleanup ran in ExUnit.OnExitHandler — a different process without
    # sandbox ownership — and was a flake under concurrent-test load.
    # Resetting before each test instead of after the previous one
    # produces the same hermetic effect with deterministic ownership.
    Config.update(:prowlarr_url, nil)
    Config.update(:prowlarr_api_key, nil)
    Config.update(:download_client_type, nil)
    Config.update(:download_client_url, nil)
    Config.update(:download_client_username, nil)
    Config.update(:download_client_password, nil)
    Config.update(:usenet_download_client_type, nil)
    Config.update(:usenet_download_client_url, nil)
    Config.update(:usenet_download_client_api_key, nil)

    :ok
  end

  describe "test buttons are wired as form submits, not standalone clicks" do
    # The bug: a `phx-click="test_*"` button fires its handler without
    # any form params. The typed-in URL/key never reaches the server.
    # When the test result comes back and re-renders the form, morphdom
    # overwrites the user's typed values with whatever's in @config —
    # what the user perceives as a confusing "default values reset".
    # Fix: each test button is a form submit (`name="_action" value="test"`)
    # so save+test happen in one server round-trip.

    test "acquisition section: prowlarr + download client test buttons submit the form",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=acquisition")

      refute has_element?(view, "#settings-prowlarr button[phx-click='test_prowlarr']"),
             "Prowlarr test button must not be a standalone phx-click — typed values would be lost"

      refute has_element?(
               view,
               "#settings-download-client button[phx-click='test_download_client']"
             ),
             "Download-client test button must not be a standalone phx-click"

      assert has_element?(
               view,
               "#settings-prowlarr button[type='submit'][name='_action'][value='test']"
             )

      assert has_element?(
               view,
               "#settings-download-client button[type='submit'][name='_action'][value='test']"
             )
    end

    test "tmdb section: test button submits the form", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=tmdb")

      refute has_element?(view, "#settings-tmdb button[phx-click='test_tmdb']"),
             "TMDB test button must not be a standalone phx-click"

      assert has_element?(
               view,
               "#settings-tmdb button[type='submit'][name='_action'][value='test']"
             )
    end
  end

  describe "prowlarr form" do
    test "save persists form values", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-prowlarr", %{
        "prowlarr_url" => "http://prowlarr.example.com:9696",
        "prowlarr_api_key" => "secret-key-123"
      })
      |> render_submit(%{"_action" => "save"})

      assert Config.get(:prowlarr_url) == "http://prowlarr.example.com:9696"
    end

    test "test action persists values BEFORE running the test", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-prowlarr", %{
        "prowlarr_url" => "http://prowlarr.example.com:9696",
        "prowlarr_api_key" => "secret-key-123"
      })
      |> render_submit(%{"_action" => "test"})

      # Saved BEFORE the async test fires.
      assert Config.get(:prowlarr_url) == "http://prowlarr.example.com:9696"
    end

    test "failed test does not revert the typed-in URL", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-prowlarr", %{
        "prowlarr_url" => "http://typed-by-user.example.com:9696",
        "prowlarr_api_key" => "user-typed-key"
      })
      |> render_submit(%{"_action" => "test"})

      send(view.pid, {:prowlarr_test_result, :error})
      html = render(view)

      # The typed-in URL must still be the input's `value=` after the
      # failure — that's what survives morphdom on re-render.
      assert html =~ ~s(value="http://typed-by-user.example.com:9696")
    end
  end

  describe "download client form" do
    test "save persists form values", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-download-client", %{
        "download_client_type" => "qbittorrent",
        "download_client_url" => "http://qb.example.com:8080",
        "download_client_username" => "shawn",
        "download_client_password" => "pw"
      })
      |> render_submit(%{"_action" => "save"})

      assert Config.get(:download_client_url) == "http://qb.example.com:8080"
      assert Config.get(:download_client_username) == "shawn"
    end

    test "test action persists values BEFORE running the test", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-download-client", %{
        "download_client_type" => "qbittorrent",
        "download_client_url" => "http://qb.example.com:8080",
        "download_client_username" => "shawn",
        "download_client_password" => "pw"
      })
      |> render_submit(%{"_action" => "test"})

      assert Config.get(:download_client_url) == "http://qb.example.com:8080"
    end

    test "failed test does not revert the typed-in URL", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-download-client", %{
        "download_client_type" => "qbittorrent",
        "download_client_url" => "http://typed-by-user.example.com:8080",
        "download_client_username" => "shawn",
        "download_client_password" => "pw"
      })
      |> render_submit(%{"_action" => "test"})

      send(view.pid, {:download_client_test_result, :error})
      html = render(view)

      assert html =~ ~s(value="http://typed-by-user.example.com:8080")
    end
  end

  describe "usenet client form" do
    test "test button is wired as a form submit", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=acquisition")

      refute has_element?(
               view,
               "#settings-usenet-client button[phx-click='test_usenet_client']"
             ),
             "Usenet-client test button must not be a standalone phx-click"

      assert has_element?(
               view,
               "#settings-usenet-client button[type='submit'][name='_action'][value='test']"
             )
    end

    test "save persists form values", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-usenet-client", %{
        "usenet_download_client_type" => "sabnzbd",
        "usenet_download_client_url" => "http://sab.example.com:8085",
        "usenet_download_client_api_key" => "sab-api-key"
      })
      |> render_submit(%{"_action" => "save"})

      assert Config.get(:usenet_download_client_type) == "sabnzbd"
      assert Config.get(:usenet_download_client_url) == "http://sab.example.com:8085"
      assert MediaCentaur.Secret.present?(Config.get(:usenet_download_client_api_key))
    end

    test "a blank API key on save keeps the stored key", %{conn: conn} do
      Config.update(:usenet_download_client_api_key, "already-stored")
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-usenet-client", %{
        "usenet_download_client_type" => "sabnzbd",
        "usenet_download_client_url" => "http://sab.example.com:8085",
        "usenet_download_client_api_key" => ""
      })
      |> render_submit(%{"_action" => "save"})

      assert MediaCentaur.Secret.expose(Config.get(:usenet_download_client_api_key)) ==
               "already-stored"
    end

    test "test action persists values BEFORE running the test", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-usenet-client", %{
        "usenet_download_client_type" => "sabnzbd",
        "usenet_download_client_url" => "http://sab.example.com:8085",
        "usenet_download_client_api_key" => "sab-api-key"
      })
      |> render_submit(%{"_action" => "test"})

      assert Config.get(:usenet_download_client_url) == "http://sab.example.com:8085"
    end

    test "failed test does not revert the typed-in URL", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("#settings-usenet-client", %{
        "usenet_download_client_type" => "sabnzbd",
        "usenet_download_client_url" => "http://typed-by-user.example.com:8085",
        "usenet_download_client_api_key" => "sab-api-key"
      })
      |> render_submit(%{"_action" => "test"})

      send(view.pid, {:usenet_client_test_result, :error})
      html = render(view)

      assert html =~ ~s(value="http://typed-by-user.example.com:8085")
    end
  end

  describe "detect from Prowlarr routes clients to their protocol slots" do
    test "a qbittorrent and a sabnzbd client pre-fill their own forms", %{conn: conn} do
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
      html = render(view)

      assert html =~ ~s(value="http://qbit.detected:8080")
      assert html =~ ~s(value="http://sab.detected:8085")
    end
  end

  describe "tmdb form" do
    test "test action persists API key BEFORE running the test", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=tmdb")

      view
      |> form("#settings-tmdb", %{
        "tmdb_api_key" => "tmdb-key-from-user",
        "auto_approve_threshold" => "0.85"
      })
      |> render_submit(%{"_action" => "test"})

      # Persistence assertion via the present? flag — the raw key never
      # round-trips through assigns (see SettingsLive.load_config/0).
      assert MediaCentaur.Secret.present?(Config.get(:tmdb_api_key))
    end
  end
end
