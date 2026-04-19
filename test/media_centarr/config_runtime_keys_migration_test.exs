defmodule MediaCentarr.ConfigRuntimeKeysMigrationTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Config
  alias MediaCentarr.Settings

  describe "migrate_runtime_keys_from_toml/1" do
    setup do
      original = :persistent_term.get({Config, :config})
      on_exit(fn -> :persistent_term.put({Config, :config}, original) end)
      :ok
    end

    test "imports TOML values into Settings for keys not already persisted" do
      :ok =
        Config.migrate_runtime_keys_from_toml(%{
          auto_approve_threshold: 0.9,
          mpv_path: "/usr/local/bin/mpv",
          recent_changes_days: 7
        })

      assert {:ok, %{value: %{"value" => 0.9}}} =
               Settings.get_by_key("config:auto_approve_threshold")

      assert {:ok, %{value: %{"value" => "/usr/local/bin/mpv"}}} =
               Settings.get_by_key("config:mpv_path")

      assert {:ok, %{value: %{"value" => 7}}} =
               Settings.get_by_key("config:recent_changes_days")
    end

    test "skips keys already present in Settings" do
      :ok = Config.update(:auto_approve_threshold, 0.7)
      :ok = Config.migrate_runtime_keys_from_toml(%{auto_approve_threshold: 0.9})

      assert {:ok, %{value: %{"value" => 0.7}}} =
               Settings.get_by_key("config:auto_approve_threshold")
    end

    test "ignores nil and empty-string TOML values" do
      :ok = Config.migrate_runtime_keys_from_toml(%{tmdb_api_key: nil, prowlarr_url: ""})

      assert {:ok, nil} = Settings.get_by_key("config:tmdb_api_key")
      assert {:ok, nil} = Settings.get_by_key("config:prowlarr_url")
    end

    test "unwraps Secret-wrapped values before persisting" do
      secret = MediaCentarr.Secret.wrap("my-key-abc123")
      :ok = Config.migrate_runtime_keys_from_toml(%{tmdb_api_key: secret})

      assert {:ok, %{value: %{"value" => "my-key-abc123"}}} =
               Settings.get_by_key("config:tmdb_api_key")
    end

    test "ignores unknown keys not in runtime_settable_keys/0" do
      :ok = Config.migrate_runtime_keys_from_toml(%{nonexistent_key: "x"})

      assert {:ok, nil} = Settings.get_by_key("config:nonexistent_key")
    end

    test "is a no-op when given an empty map" do
      :ok = Config.migrate_runtime_keys_from_toml(%{})

      assert {:ok, nil} = Settings.get_by_key("config:auto_approve_threshold")
    end
  end
end
