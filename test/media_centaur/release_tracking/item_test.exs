defmodule MediaCentaur.ReleaseTracking.ItemTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.Item

  describe "lower_quality_accepted?/1" do
    test "true only for the per-title \"any\" acceptance" do
      assert Item.lower_quality_accepted?(%Item{min_quality: "any"})
      refute Item.lower_quality_accepted?(%Item{min_quality: "hd_1080p"})
      refute Item.lower_quality_accepted?(%Item{min_quality: nil})
    end
  end
end
