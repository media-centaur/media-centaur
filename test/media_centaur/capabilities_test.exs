defmodule MediaCentaur.CapabilitiesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Topics

  setup do
    Config.update(:tmdb_api_key, "")
    Config.update(:prowlarr_url, "")
    Config.update(:prowlarr_api_key, "")
    Config.update(:download_client_type, "")
    Config.update(:download_client_url, "")
    Config.update(:download_client_password, "")
    Config.update(:usenet_download_client_type, "")
    Config.update(:usenet_download_client_url, "")
    Config.update(:usenet_download_client_api_key, "")

    :ok
  end

  defp configure_and_pass_usenet_client do
    Config.update(:usenet_download_client_type, "sabnzbd")
    Config.update(:usenet_download_client_url, "http://sab.local")
    Capabilities.save_test_result(:usenet_download_client, :ok)
  end

  describe "tmdb_ready?/0" do
    test "false when API key is missing" do
      refute Capabilities.tmdb_ready?()
    end

    test "false when configured but no test result" do
      Config.update(:tmdb_api_key, "k-123")
      refute Capabilities.tmdb_ready?()
    end

    test "false when configured but last test errored" do
      Config.update(:tmdb_api_key, "k-123")
      Capabilities.save_test_result(:tmdb, :error)
      refute Capabilities.tmdb_ready?()
    end

    test "true when configured and last test succeeded" do
      Config.update(:tmdb_api_key, "k-123")
      Capabilities.save_test_result(:tmdb, :ok)
      assert Capabilities.tmdb_ready?()
    end
  end

  describe "prowlarr_ready?/0" do
    test "false when URL and key are missing" do
      refute Capabilities.prowlarr_ready?()
    end

    test "false when URL set but key missing" do
      Config.update(:prowlarr_url, "http://p.local")
      refute Capabilities.prowlarr_ready?()
    end

    test "false when configured but no test result" do
      Config.update(:prowlarr_url, "http://p.local")
      Config.update(:prowlarr_api_key, "k-prowlarr")
      refute Capabilities.prowlarr_ready?()
    end

    test "true when configured and last test succeeded" do
      Config.update(:prowlarr_url, "http://p.local")
      Config.update(:prowlarr_api_key, "k-prowlarr")
      Capabilities.save_test_result(:prowlarr, :ok)
      assert Capabilities.prowlarr_ready?()
    end
  end

  describe "download_client_ready?/0" do
    test "false when type+URL are missing" do
      refute Capabilities.download_client_ready?()
    end

    test "false when configured but no test result" do
      Config.update(:download_client_type, "qbittorrent")
      Config.update(:download_client_url, "http://dl.local")
      refute Capabilities.download_client_ready?()
    end

    test "true when configured and last test succeeded" do
      Config.update(:download_client_type, "qbittorrent")
      Config.update(:download_client_url, "http://dl.local")
      Capabilities.save_test_result(:download_client, :ok)
      assert Capabilities.download_client_ready?()
    end

    test "true when only the usenet slot is configured and tested — any client counts" do
      configure_and_pass_usenet_client()
      assert Capabilities.download_client_ready?()
    end

    test "a usenet slot without a passing test does not count" do
      Config.update(:usenet_download_client_type, "sabnzbd")
      Config.update(:usenet_download_client_url, "http://sab.local")
      refute Capabilities.download_client_ready?()
    end

    test "the torrent slot's test result does not vouch for the usenet slot" do
      Config.update(:usenet_download_client_type, "sabnzbd")
      Config.update(:usenet_download_client_url, "http://sab.local")
      Capabilities.save_test_result(:download_client, :ok)
      refute Capabilities.download_client_ready?()
    end
  end

  describe "client_ready?/1" do
    test "reports each protocol slot independently" do
      Config.update(:download_client_type, "qbittorrent")
      Config.update(:download_client_url, "http://dl.local")
      Capabilities.save_test_result(:download_client, :ok)

      assert Capabilities.client_ready?(:torrent)
      refute Capabilities.client_ready?(:usenet)

      configure_and_pass_usenet_client()

      assert Capabilities.client_ready?(:usenet)
    end
  end

  describe "acquisition_ready?/0" do
    test "false when neither prowlarr nor download client is ready" do
      refute Capabilities.acquisition_ready?()
    end

    test "false when only prowlarr is ready" do
      Config.update(:prowlarr_url, "http://p.local")
      Config.update(:prowlarr_api_key, "k-prowlarr")
      Capabilities.save_test_result(:prowlarr, :ok)
      refute Capabilities.acquisition_ready?()
    end

    test "false when only download client is ready" do
      Config.update(:download_client_type, "qbittorrent")
      Config.update(:download_client_url, "http://dl.local")
      Capabilities.save_test_result(:download_client, :ok)
      refute Capabilities.acquisition_ready?()
    end

    test "true when both prowlarr and download client are ready" do
      Config.update(:prowlarr_url, "http://p.local")
      Config.update(:prowlarr_api_key, "k-prowlarr")
      Capabilities.save_test_result(:prowlarr, :ok)
      Config.update(:download_client_type, "qbittorrent")
      Config.update(:download_client_url, "http://dl.local")
      Capabilities.save_test_result(:download_client, :ok)
      assert Capabilities.acquisition_ready?()
    end

    test "true when prowlarr is ready and only the usenet client is ready" do
      Config.update(:prowlarr_url, "http://p.local")
      Config.update(:prowlarr_api_key, "k-prowlarr")
      Capabilities.save_test_result(:prowlarr, :ok)
      configure_and_pass_usenet_client()
      assert Capabilities.acquisition_ready?()
    end
  end

  describe "save_test_result/2 & load_test_result/1" do
    test "round-trips :ok and :error results" do
      assert nil == Capabilities.load_test_result(:tmdb)

      Capabilities.save_test_result(:tmdb, :ok)
      assert %{status: :ok, tested_at: %DateTime{}} = Capabilities.load_test_result(:tmdb)

      Capabilities.save_test_result(:tmdb, :error)
      assert %{status: :error} = Capabilities.load_test_result(:tmdb)
    end
  end

  describe "clear_test_result/1" do
    test "removes a previously saved result" do
      Capabilities.save_test_result(:prowlarr, :ok)
      assert %{status: :ok} = Capabilities.load_test_result(:prowlarr)

      Capabilities.clear_test_result(:prowlarr)
      assert nil == Capabilities.load_test_result(:prowlarr)
    end

    test "is a no-op when no result was saved" do
      assert :ok == Capabilities.clear_test_result(:prowlarr)
    end
  end

  describe "relevant?/1" do
    test "accepts :capabilities_changed" do
      assert Capabilities.relevant?(:capabilities_changed)
    end

    test "accepts {:config_updated, key, _} for capability-input keys" do
      assert Capabilities.relevant?({:config_updated, :tmdb_api_key, "x"})
      assert Capabilities.relevant?({:config_updated, :prowlarr_url, "x"})
      assert Capabilities.relevant?({:config_updated, :prowlarr_api_key, "x"})
      assert Capabilities.relevant?({:config_updated, :download_client_type, "x"})
      assert Capabilities.relevant?({:config_updated, :download_client_url, "x"})
      assert Capabilities.relevant?({:config_updated, :usenet_download_client_type, "x"})
      assert Capabilities.relevant?({:config_updated, :usenet_download_client_url, "x"})
    end

    test "rejects {:config_updated, key, _} for keys outside capability inputs" do
      refute Capabilities.relevant?({:config_updated, :mpv_path, "/usr/bin/mpv"})
      refute Capabilities.relevant?({:config_updated, :extras_dirs, []})
      refute Capabilities.relevant?({:config_updated, :setup_wizard_dismissed, true})
    end

    test "rejects unrelated messages" do
      refute Capabilities.relevant?(:something_else)
      refute Capabilities.relevant?({:other_event, :anything})
    end
  end

  describe "boot-order recovery via config_updates" do
    test "config_updated broadcast triggers a Capabilities cache refresh through the Worker" do
      Capabilities.save_test_result(:prowlarr, :ok)
      Capabilities.save_test_result(:download_client, :ok)

      Config.update(:prowlarr_url, "http://prowlarr.boot")
      Config.update(:prowlarr_api_key, "k-boot-prowlarr")
      Config.update(:download_client_type, "qbittorrent")
      Config.update(:download_client_url, "http://qbit.boot")

      :persistent_term.put(
        {Capabilities, :ready_flags},
        %{tmdb: false, prowlarr: false, download_client: false, acquisition: false}
      )

      refute Capabilities.acquisition_ready?()

      assert Capabilities.relevant?({:config_updated, :prowlarr_url, "http://prowlarr.boot"})

      Capabilities.refresh_cache()

      assert Capabilities.acquisition_ready?()
    end
  end

  describe "subscribe/0 and broadcasts" do
    setup do
      Capabilities.subscribe()
      :ok
    end

    test "save_test_result broadcasts :capabilities_changed" do
      Capabilities.save_test_result(:prowlarr, :ok)
      assert_receive :capabilities_changed, 500
    end

    test "clear_test_result broadcasts :capabilities_changed" do
      Capabilities.save_test_result(:prowlarr, :ok)
      # flush the save's broadcast
      assert_receive :capabilities_changed, 500

      Capabilities.clear_test_result(:prowlarr)
      assert_receive :capabilities_changed, 500
    end

    test "subscribe/0 is wired to Topics.capabilities_updates/0" do
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.capabilities_updates(),
        :capabilities_changed
      )

      assert_receive :capabilities_changed, 500
    end
  end
end
