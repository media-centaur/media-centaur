defmodule MediaCentaur.UIScaleTest do
  @moduledoc """
  Tests for the `ui_scale` typed Settings accessor — parse/normalize/clamp
  (pure) plus the `scale/0` read and `set/1` write round-trip (DB).
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings
  alias MediaCentaur.UIScale

  describe "normalize/1" do
    test "leaves an in-range float unchanged" do
      assert UIScale.normalize(1.1) == 1.1
    end

    test "clamps a too-small value up to the minimum (100% is the floor)" do
      assert UIScale.normalize(0.1) == 1.0
    end

    test "clamps a below-floor legacy value up to 100%" do
      # 80%/90% were selectable before the floor moved to 100%; a stored
      # legacy value must clamp up rather than survive the picker change.
      assert UIScale.normalize(0.8) == 1.0
      assert UIScale.normalize(0.9) == 1.0
    end

    test "clamps a too-large value down to the maximum" do
      assert UIScale.normalize(9.0) == 2.0
    end

    test "parses a string (the picker submits phx-value-scale as a string)" do
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

  describe "parse/1" do
    test "reads the stored shape" do
      assert UIScale.parse(%{"scale" => 1.1}) == 1.1
    end

    test "clamps an out-of-range stored value" do
      assert UIScale.parse(%{"scale" => 5.0}) == 2.0
    end

    test "defaults for an unrecognized shape" do
      assert UIScale.parse(%{}) == UIScale.default()
      assert UIScale.parse(%{"enabled" => true}) == UIScale.default()
    end
  end

  describe "percent/1" do
    test "formats a factor as an integer percent string" do
      assert UIScale.percent(1.0) == "100%"
      assert UIScale.percent(0.9) == "90%"
      assert UIScale.percent(1.25) == "125%"
    end
  end

  describe "options/0" do
    test "runs 100% through 200% and every option survives normalization unchanged" do
      assert UIScale.options() == [1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
      assert Enum.all?(UIScale.options(), &(UIScale.normalize(&1) == &1))
    end
  end

  describe "choices/0" do
    test "pairs every option with its percent label" do
      assert UIScale.choices() == Enum.map(UIScale.options(), &{&1, UIScale.percent(&1)})
      assert {1.0, "100%"} in UIScale.choices()
    end
  end

  describe "scale/0 and set/1" do
    test "defaults to 1.0 when unset" do
      assert {:ok, nil} = Settings.get_by_key(UIScale.setting_key())
      assert UIScale.scale() == UIScale.default()
    end

    test "round-trips a saved scale" do
      assert UIScale.set("1.25") == 1.25
      assert UIScale.scale() == 1.25
    end

    test "clamps out-of-range input before storing" do
      assert UIScale.set(5.0) == 2.0
      assert UIScale.scale() == 2.0
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
