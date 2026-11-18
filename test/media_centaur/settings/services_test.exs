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

  # Changed 2026-11-18: the app-env default (`config :media_centaur,
  # :start_x`) and `enabled?/2` are gone. Only config/dev.exs set that
  # default, to false, and a flag added later (start_image_pipeline)
  # inherited it on the daily driver and silently stopped artwork.
  describe "start?/1" do
    setup do
      load_config(true)
    end

    test "every service runs when nothing is persisted" do
      for service <- [:start_watchers, :start_pipeline, :start_image_pipeline, :start_acquisition] do
        assert Services.start?(service), "#{service} should run on an instance that never set it"
      end
    end

    test "a persisted flag decides" do
      Services.set(:start_pipeline, false)
      refute Services.start?(:start_pipeline)

      Services.set(:start_pipeline, true)
      assert Services.start?(:start_pipeline)
    end

    test "is false in an instance without background services, whatever the row says" do
      Services.set(:start_pipeline, true)
      load_config(false)

      refute Services.start?(:start_pipeline)
      refute Services.start?(:start_watchers)
    end
  end

  # Changed 2026-11-18: one instance per database (ADR-084), so a flag is
  # no longer namespaced by the environment.
  describe "key/1" do
    test "is one key per service, the same in every environment" do
      assert Services.key(:start_pipeline) == "services:start_pipeline"
    end
  end
end
