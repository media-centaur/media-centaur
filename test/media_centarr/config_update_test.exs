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
end
