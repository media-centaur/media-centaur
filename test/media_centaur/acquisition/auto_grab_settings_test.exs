defmodule MediaCentaur.Acquisition.AutoGrabSettingsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.AutoGrabSettings
  alias MediaCentaur.Settings

  describe "load/0 — defaults when nothing persisted" do
    test "returns built-in defaults when no settings rows exist" do
      settings = AutoGrabSettings.load()

      assert settings.default_max_quality == "uhd_4k"
      assert settings.max_attempts == 12
      assert settings.pack_min_fit == 75
      assert settings.size_preference == "fidelity"
    end

    test "the struct carries no grab mode, floor or patience field" do
      refute Map.has_key?(%AutoGrabSettings{}, :default_mode)
      refute Map.has_key?(%AutoGrabSettings{}, :default_min_quality)
      refute Map.has_key?(%AutoGrabSettings{}, :patience_hours)
    end
  end

  describe "load/0 — values overridden by Settings entries" do
    test "respects integer overrides" do
      Settings.find_or_create_entry!(%{key: "auto_grab.max_attempts", value: %{"value" => 6}})
      assert %{max_attempts: 6} = AutoGrabSettings.load()
    end

    test "respects pack-fit override" do
      Settings.find_or_create_entry!(%{key: "auto_grab.pack_min_fit", value: %{"value" => 50}})
      assert %{pack_min_fit: 50} = AutoGrabSettings.load()
    end

    test "respects size-preference override" do
      Settings.find_or_create_entry!(%{key: "auto_grab.size_preference", value: %{"value" => "space"}})
      assert %{size_preference: "space"} = AutoGrabSettings.load()
    end
  end

  describe "floor/0 and effective_min_quality/1" do
    test "the automatic floor is 1080p" do
      assert AutoGrabSettings.floor() == "hd_1080p"
    end

    test "a title with no acceptance uses the floor" do
      assert AutoGrabSettings.effective_min_quality(nil) == "hd_1080p"
    end

    test "a title's lower-quality acceptance overrides the floor" do
      assert AutoGrabSettings.effective_min_quality("any") == "any"
    end
  end

  describe "put/2 — the one write" do
    test "persists an allowed enum value" do
      assert :ok = AutoGrabSettings.put(:default_max_quality, "hd_1080p")
      assert AutoGrabSettings.load().default_max_quality == "hd_1080p"
    end

    test "persists an integer on its ladder" do
      assert :ok = AutoGrabSettings.put(:pack_min_fit, 80)
      assert :ok = AutoGrabSettings.put(:max_attempts, 3)
      settings = AutoGrabSettings.load()
      assert settings.pack_min_fit == 80
      assert settings.max_attempts == 3
    end

    test "refuses a value outside the enum or off the ladder" do
      assert {:error, :invalid} = AutoGrabSettings.put(:default_mode, "all_releases")
      assert {:error, :invalid} = AutoGrabSettings.put(:pack_min_fit, 77)
      assert {:error, :invalid} = AutoGrabSettings.put(:max_attempts, 0)
      assert {:error, :invalid} = AutoGrabSettings.put(:size_preference, 3)
      assert AutoGrabSettings.load() == %AutoGrabSettings{}
    end

    test "refuses an unknown field" do
      assert {:error, :invalid} = AutoGrabSettings.put(:patience_hours, 24)
    end
  end

  describe "ladders" do
    test "pack fit runs 5–100 by 5; attempts 1–50" do
      assert AutoGrabSettings.pack_fit_ladder() == Enum.to_list(5..100//5)
      assert AutoGrabSettings.attempts_ladder() == Enum.to_list(1..50)
    end
  end
end
