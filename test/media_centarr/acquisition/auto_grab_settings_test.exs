defmodule MediaCentarr.Acquisition.AutoGrabSettingsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.AutoGrabSettings
  alias MediaCentarr.Settings

  describe "load/0 — defaults when nothing persisted" do
    test "returns built-in defaults when no settings rows exist" do
      settings = AutoGrabSettings.load()

      assert settings.default_mode == "all_releases"
      assert settings.default_min_quality == "hd_1080p"
      assert settings.default_max_quality == "uhd_4k"
      assert settings.patience_hours == 48
      assert settings.max_attempts == 12
    end
  end

  describe "load/0 — values overridden by Settings entries" do
    test "respects mode override" do
      Settings.find_or_create_entry!(%{
        key: "auto_grab.default_mode",
        value: %{"value" => "off"}
      })

      assert %{default_mode: "off"} = AutoGrabSettings.load()
    end

    test "respects integer overrides" do
      Settings.find_or_create_entry!(%{
        key: "auto_grab.4k_patience_hours",
        value: %{"value" => 12}
      })

      Settings.find_or_create_entry!(%{
        key: "auto_grab.max_attempts",
        value: %{"value" => 6}
      })

      settings = AutoGrabSettings.load()
      assert settings.patience_hours == 12
      assert settings.max_attempts == 6
    end
  end

  describe "effective_mode/2" do
    setup do
      {:ok, settings: %AutoGrabSettings{default_mode: "all_releases"}}
    end

    test "returns global default when item mode is 'global'", %{settings: settings} do
      assert AutoGrabSettings.effective_mode("global", settings) == "all_releases"
    end

    test "returns global default when item mode is nil", %{settings: settings} do
      assert AutoGrabSettings.effective_mode(nil, settings) == "all_releases"
    end

    test "returns item override when set", %{settings: settings} do
      assert AutoGrabSettings.effective_mode("off", settings) == "off"
    end
  end

  describe "effective_min_quality/2 + effective_max_quality/2" do
    setup do
      settings = %AutoGrabSettings{
        default_min_quality: "hd_1080p",
        default_max_quality: "uhd_4k"
      }

      {:ok, settings: settings}
    end

    test "nil item value falls through to global default", %{settings: settings} do
      assert AutoGrabSettings.effective_min_quality(nil, settings) == "hd_1080p"
      assert AutoGrabSettings.effective_max_quality(nil, settings) == "uhd_4k"
    end

    test "concrete item value overrides default", %{settings: settings} do
      assert AutoGrabSettings.effective_min_quality("uhd_4k", settings) == "uhd_4k"
      assert AutoGrabSettings.effective_max_quality("hd_1080p", settings) == "hd_1080p"
    end
  end

  describe "effective_patience_hours/2" do
    test "nil item value falls through to global default" do
      settings = %AutoGrabSettings{patience_hours: 48}
      assert AutoGrabSettings.effective_patience_hours(nil, settings) == 48
    end

    test "concrete item value overrides default (including 0 = no patience)" do
      settings = %AutoGrabSettings{patience_hours: 48}
      assert AutoGrabSettings.effective_patience_hours(0, settings) == 0
      assert AutoGrabSettings.effective_patience_hours(72, settings) == 72
    end
  end
end
