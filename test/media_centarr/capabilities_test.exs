defmodule MediaCentarr.CapabilitiesTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Capabilities
  alias MediaCentarr.Config
  alias MediaCentarr.Topics

  setup do
    original = :persistent_term.get({Config, :config})
    on_exit(fn -> :persistent_term.put({Config, :config}, original) end)

    Config.update(:tmdb_api_key, "")
    Config.update(:prowlarr_url, "")
    Config.update(:prowlarr_api_key, "")
    Config.update(:download_client_type, "")
    Config.update(:download_client_url, "")
    Config.update(:download_client_password, "")

    :ok
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
        MediaCentarr.PubSub,
        Topics.capabilities_updates(),
        :capabilities_changed
      )

      assert_receive :capabilities_changed, 500
    end
  end
end
