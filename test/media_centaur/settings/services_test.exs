defmodule MediaCentaur.Settings.ServicesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Settings.Services

  # The test env is an inert instance (`background_services: false` in
  # config/test.exs), under which no service may run whatever its row
  # says; these tests look at the toggles themselves, so they load the
  # config of an instance that runs background services. The sandbox
  # restores the app env and the loaded config at exit.
  defp load_config(background_services?) do
    Application.put_env(:media_centaur, :background_services, background_services?)
    :ok = Config.load!()
  end

  describe "enabled?/2" do
    setup do
      load_config(true)
    end

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

    test "is false in an instance without background services, whatever the row says" do
      Services.set(:start_watchers, true)
      load_config(false)

      refute Services.enabled?(:start_watchers, true)
      refute Services.enabled?(:start_pipeline, true)
    end
  end

  describe "key/1" do
    test "is namespaced by the running environment" do
      env = Application.get_env(:media_centaur, :environment, :dev)
      assert Services.key(:start_pipeline) == "services:#{env}:start_pipeline"
    end
  end
end
