defmodule MediaCentarr.Acquisition.Pursuits.ThresholdsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits.Thresholds
  alias MediaCentarr.Settings

  describe "load/0" do
    test "returns built-in defaults when no Settings entries are present" do
      assert %Thresholds{
               max_attempts: 4,
               min_age_days: 6,
               stall_window_hours: 24,
               zero_seeders_window_hours: 6
             } = Thresholds.load()
    end

    test "reads each key from Settings, falling back to defaults for missing ones" do
      Settings.find_or_create_entry!(%{key: "pursuits.max_attempts", value: %{"value" => 10}})
      Settings.find_or_create_entry!(%{key: "pursuits.stall_window_hours", value: %{"value" => 48}})

      assert %Thresholds{
               max_attempts: 10,
               min_age_days: 6,
               stall_window_hours: 48,
               zero_seeders_window_hours: 6
             } = Thresholds.load()
    end

    test "rejects non-positive values (treats them as missing → fallback to default)" do
      Settings.find_or_create_entry!(%{key: "pursuits.max_attempts", value: %{"value" => 0}})
      Settings.find_or_create_entry!(%{key: "pursuits.stall_window_hours", value: %{"value" => -5}})

      assert %Thresholds{max_attempts: 4, stall_window_hours: 24} = Thresholds.load()
    end
  end
end
