defmodule MediaCentaur.Acquisition.CoverageGuardTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.CoverageGuard

  describe "can_contain?/2" do
    test "true when the episode aired on or before the release was published" do
      assert CoverageGuard.can_contain?("2024-06-01T00:00:00Z", ~D[2024-05-01])
      assert CoverageGuard.can_contain?("2024-06-01T00:00:00Z", ~D[2024-06-01])
    end

    test "false when the episode aired strictly after the release was published" do
      refute CoverageGuard.can_contain?("2024-06-01T00:00:00Z", ~D[2026-01-16])
    end

    test "accepts a date-only publish string" do
      assert CoverageGuard.can_contain?("2024-06-01", ~D[2024-05-01])
      refute CoverageGuard.can_contain?("2024-06-01", ~D[2024-07-01])
    end

    test "monotonic opt-in — unknown data never blocks" do
      # nil/unparseable publish date, or nil air date → don't trim.
      assert CoverageGuard.can_contain?(nil, ~D[2026-01-16])
      assert CoverageGuard.can_contain?("not-a-date", ~D[2026-01-16])
      assert CoverageGuard.can_contain?("2024-06-01T00:00:00Z", nil)
    end
  end

  describe "coverable_units/2" do
    @units [
      {{1, 1}, ~D[2023-10-01]},
      {{1, 2}, ~D[2024-01-01]},
      {{1, 3}, ~D[2026-01-16]},
      {{1, 4}, nil}
    ]

    test "caps to the units a release published on a date can contain" do
      coverable = CoverageGuard.coverable_units(@units, "2024-06-01T00:00:00Z")

      assert MapSet.equal?(coverable, MapSet.new([{1, 1}, {1, 2}, {1, 4}]))
    end

    test "a nil publish date yields :all (no cap)" do
      assert CoverageGuard.coverable_units(@units, nil) == :all
    end

    test "an unparseable publish date yields :all (no cap)" do
      assert CoverageGuard.coverable_units(@units, "garbage") == :all
    end
  end
end
