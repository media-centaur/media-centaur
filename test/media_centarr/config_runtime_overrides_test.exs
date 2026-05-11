defmodule MediaCentarr.ConfigRuntimeOverridesTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Config
  alias MediaCentarr.Settings
  alias MediaCentarr.Topics

  setup do
    original = :persistent_term.get({Config, :config})
    on_exit(fn -> :persistent_term.put({Config, :config}, original) end)
    :ok
  end

  describe "load_runtime_overrides/0 broadcasts" do
    test "broadcasts {:config_updated, key, value} for each overlaid runtime key" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.config_updates())

      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: "config:prowlarr_url",
          value: %{"value" => "http://prowlarr.local"}
        })

      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: "config:download_client_type",
          value: %{"value" => "qbittorrent"}
        })

      :ok = Config.load_runtime_overrides()

      assert_receive {:config_updated, :prowlarr_url, "http://prowlarr.local"}, 200
      assert_receive {:config_updated, :download_client_type, "qbittorrent"}, 200
    end

    test "does not broadcast for keys without a stored override" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.config_updates())

      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: "config:tmdb_api_key",
          value: %{"value" => "k-tmdb"}
        })

      :ok = Config.load_runtime_overrides()

      assert_receive {:config_updated, :tmdb_api_key, "k-tmdb"}, 200
      refute_receive {:config_updated, :prowlarr_url, _}, 50
      refute_receive {:config_updated, :download_client_type, _}, 50
    end

    test "applies the override to :persistent_term before broadcasting" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.config_updates())

      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: "config:prowlarr_url",
          value: %{"value" => "http://prowlarr.broadcast-test"}
        })

      :ok = Config.load_runtime_overrides()

      assert_receive {:config_updated, :prowlarr_url, "http://prowlarr.broadcast-test"}, 200
      assert Config.get(:prowlarr_url) == "http://prowlarr.broadcast-test"
    end
  end
end
