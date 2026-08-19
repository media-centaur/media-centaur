defmodule MediaCentaur.Preferences.UIScaleTest do
  @moduledoc """
  Tests for the `ui_scale` typed Settings accessor — parse/normalize/clamp/step
  (pure) plus the `scale/0` read and `set/1` write round-trip (DB).
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings
  alias MediaCentaur.Preferences.UIScale

  describe "bounds and step" do
    test "the range is 70%–200% in 5% steps around a 100% default" do
      assert UIScale.min() == 0.7
      assert UIScale.max() == 2.0
      assert UIScale.step() == 0.05
      assert UIScale.default() == 1.0
    end
  end

  describe "normalize/1" do
    test "leaves an in-range on-grid float unchanged" do
      assert UIScale.normalize(1.1) == 1.1
      assert UIScale.normalize(0.7) == 0.7
      assert UIScale.normalize(2.0) == 2.0
    end

    test "clamps a too-small value up to the minimum" do
      assert UIScale.normalize(0.1) == UIScale.min()
    end

    test "clamps a too-large value down to the maximum" do
      assert UIScale.normalize(9.0) == UIScale.max()
    end

    test "snaps an off-grid value to the nearest 5% step" do
      assert UIScale.normalize(1.37) == 1.35
      assert UIScale.normalize(1.33) == 1.35
      assert UIScale.normalize(1.12) == 1.1
    end

    test "parses a string (the stepper submits phx-value-choice as a string)" do
      assert UIScale.normalize("1.25") == 1.25
    end

    test "coerces an integer to a float" do
      assert UIScale.normalize(1) == 1.0
    end

    test "falls back to the default for non-numeric input" do
      assert UIScale.normalize("abc") == UIScale.default()
      assert UIScale.normalize(nil) == UIScale.default()
    end
  end

  describe "increment/1 and decrement/1" do
    test "steps by 5% from the current value" do
      assert UIScale.increment(1.0) == 1.05
      assert UIScale.decrement(1.0) == 0.95
    end

    test "survives float drift — repeated steps stay on the 5% grid" do
      forty_up = Enum.reduce(1..40, UIScale.min(), fn _n, acc -> UIScale.increment(acc) end)
      assert forty_up == UIScale.max()

      forty_down = Enum.reduce(1..40, UIScale.max(), fn _n, acc -> UIScale.decrement(acc) end)
      assert forty_down == UIScale.min()
    end

    test "clamps at the bounds" do
      assert UIScale.increment(UIScale.max()) == UIScale.max()
      assert UIScale.decrement(UIScale.min()) == UIScale.min()
    end

    test "normalizes an out-of-range input before stepping" do
      assert UIScale.increment(9.0) == UIScale.max()
      assert UIScale.decrement(0.1) == UIScale.min()
    end
  end

  describe "parse/1" do
    test "reads the stored shape" do
      assert UIScale.parse(%{"scale" => 1.1}) == 1.1
    end

    test "clamps an out-of-range stored value" do
      assert UIScale.parse(%{"scale" => 5.0}) == UIScale.max()
    end

    test "defaults for an unrecognized shape" do
      assert UIScale.parse(%{}) == UIScale.default()
      assert UIScale.parse(%{"enabled" => true}) == UIScale.default()
    end
  end

  describe "percent/1" do
    test "formats a factor as an integer percent string" do
      assert UIScale.percent(1.0) == "100%"
      assert UIScale.percent(0.7) == "70%"
      assert UIScale.percent(1.25) == "125%"
    end
  end

  describe "scale/0 and set/1" do
    test "defaults to 1.0 when unset" do
      assert Settings.get_by_key(UIScale.setting_key()) == nil
      assert UIScale.scale() == UIScale.default()
    end

    test "round-trips a saved scale" do
      assert UIScale.set("1.25") == 1.25
      assert UIScale.scale() == 1.25
    end

    test "round-trips a below-100% scale" do
      assert UIScale.set("0.85") == 0.85
      assert UIScale.scale() == 0.85
    end

    test "clamps out-of-range input before storing" do
      assert UIScale.set(5.0) == UIScale.max()
      assert UIScale.scale() == UIScale.max()
    end
  end

  describe "cached_scale/0" do
    test "returns the default on a cold cache without touching the database" do
      # The settings persistent_term cache is unset in the test env, so this is
      # the render-path's guaranteed-DB-free read. It must not observe writes
      # that only reached the DB (and not the cold cache).
      UIScale.set("1.5")
      assert UIScale.cached_scale() == UIScale.default()
    end
  end
end
