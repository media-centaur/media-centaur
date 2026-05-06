defmodule MediaCentarr.ConfigUpdateTest do
  @moduledoc """
  Separate file for `Config.update/2` — it persists to Settings (real DB),
  so uses `DataCase` for sandbox ownership. Kept apart from the pure
  `ConfigTest` cases that don't touch the DB.
  """
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Config

  describe "update/2 broadcasts" do
    test "broadcasts {:config_updated, key, value} to subscribers" do
      :ok = Config.subscribe()

      :ok = Config.update(:exclude_dirs, ["/tmp/a", "/tmp/b"])

      assert_receive {:config_updated, :exclude_dirs, ["/tmp/a", "/tmp/b"]}, 500
    end
  end

  describe "runtime_settable_keys/0" do
    test "includes ffprobe_path" do
      assert :ffprobe_path in Config.runtime_settable_keys()
    end

    test "includes setup_wizard_dismissed" do
      assert :setup_wizard_dismissed in Config.runtime_settable_keys()
    end
  end

  describe "update/2 — new keys" do
    setup do
      original = :persistent_term.get({Config, :config})
      on_exit(fn -> :persistent_term.put({Config, :config}, original) end)
      :ok
    end

    test "accepts ffprobe_path" do
      :ok = Config.subscribe()
      :ok = Config.update(:ffprobe_path, "/opt/custom/bin/ffprobe")
      assert_receive {:config_updated, :ffprobe_path, "/opt/custom/bin/ffprobe"}, 500
      assert Config.get(:ffprobe_path) == "/opt/custom/bin/ffprobe"
    end

    test "accepts setup_wizard_dismissed" do
      :ok = Config.subscribe()
      :ok = Config.update(:setup_wizard_dismissed, true)
      assert_receive {:config_updated, :setup_wizard_dismissed, true}, 500
      assert Config.get(:setup_wizard_dismissed) == true
    end
  end
end
