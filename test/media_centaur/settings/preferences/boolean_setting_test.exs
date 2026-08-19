defmodule MediaCentaur.Settings.Preferences.BooleanSettingTest do
  @moduledoc """
  The macro's own contract, as opposed to the four flags it generates
  (covered in `SpoilerFreeTest`, `LibraryCardInfoTest` and
  `PageBackdropSettingsTest`).

  Only `default:` is worth a test of its own. It is the one option whose
  misuse is silent — a flag generated with the wrong polarity still
  compiles, still returns a boolean, and simply inverts the user's setting.
  The compile-time raise is what turns that into a build failure, so it is
  exercised against an actual violation rather than assumed to work.
  """
  use ExUnit.Case, async: true

  test "a non-boolean default is a compile error, not a silently inverted flag" do
    assert_raise ArgumentError, ~r/expects a literal boolean `default:`/, fn ->
      Code.compile_string("""
      defmodule MediaCentaur.Settings.Preferences.BooleanSettingTest.StringDefault do
        use MediaCentaur.Settings.Preferences.BooleanSetting, key: "probe", default: "true"
      end
      """)
    end
  end

  test "a missing default is a compile error" do
    assert_raise KeyError, fn ->
      Code.compile_string("""
      defmodule MediaCentaur.Settings.Preferences.BooleanSettingTest.NoDefault do
        use MediaCentaur.Settings.Preferences.BooleanSetting, key: "probe"
      end
      """)
    end
  end

  test "a missing key is a compile error" do
    assert_raise KeyError, fn ->
      Code.compile_string("""
      defmodule MediaCentaur.Settings.Preferences.BooleanSettingTest.NoKey do
        use MediaCentaur.Settings.Preferences.BooleanSetting, default: false
      end
      """)
    end
  end
end
