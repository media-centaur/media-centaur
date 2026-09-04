defmodule MediaCentaur.Settings.ServicesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings.Services

  describe "enabled?/2" do
    test "falls back to the default when nothing is persisted" do
      assert Services.enabled?(:start_watchers, true)
      refute Services.enabled?(:start_watchers, false)
    end

    test "a persisted flag wins over the default" do
      Services.set(:start_watchers, false)
      refute Services.enabled?(:start_watchers, true)

      Services.set(:start_watchers, true)
      assert Services.enabled?(:start_watchers, false)
    end
  end

  describe "key/1" do
    test "is namespaced by the running environment" do
      env = Application.get_env(:media_centaur, :environment, :dev)
      assert Services.key(:start_pipeline) == "services:#{env}:start_pipeline"
    end
  end
end
