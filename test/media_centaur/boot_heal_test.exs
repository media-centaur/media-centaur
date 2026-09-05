defmodule MediaCentaur.BootHealTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.BootHeal

  # Every heal is skipped under :test — a boot-spawned task would write to
  # the DB outside the sandbox-owned process. Each sweep is tested directly
  # (ExtraRederiveTest, Library.Files.backfill_extras/0, MediaInfo.probe_missing/0).
  describe "in the test environment" do
    test "heal_extra_names/1 is skipped" do
      assert BootHeal.heal_extra_names(:test) == :skipped
    end

    test "backfill_extra_files/1 is skipped" do
      assert BootHeal.backfill_extra_files(:test) == :skipped
    end

    test "probe_media_info/1 is skipped" do
      assert BootHeal.probe_media_info(:test) == :skipped
    end
  end
end
