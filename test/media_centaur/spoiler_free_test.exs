defmodule MediaCentaur.SpoilerFreeTest do
  @moduledoc """
  The fourth boolean Settings accessor. `LibraryCardInfo` and the two page
  backdrops each had their polarity pinned; `SpoilerFree` did not, which
  left the only default-on flag and two of the three default-off ones
  covered — and the shared `BooleanSetting` macro now generates all four
  from one clause pair, so an untested polarity is an untested branch of
  every flag.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings
  alias MediaCentaur.SpoilerFree

  describe "enabled?/0" do
    test "returns false when no setting entry exists (default-off)" do
      assert Settings.get_by_key(SpoilerFree.setting_key()) == nil
      assert SpoilerFree.enabled?() == false
    end

    test "returns true when the stored value is enabled: true" do
      store(%{"enabled" => true})

      assert SpoilerFree.enabled?() == true
    end

    test "returns false when the stored value is enabled: false" do
      store(%{"enabled" => false})

      assert SpoilerFree.enabled?() == false
    end

    test "returns false (default-off) when the stored value is shaped unexpectedly" do
      store(%{"something_else" => "yes"})

      assert SpoilerFree.enabled?() == false
    end

    test "returns false (default-off) when enabled is a string rather than a boolean" do
      store(%{"enabled" => "true"})

      assert SpoilerFree.enabled?() == false
    end
  end

  describe "setting_key/0" do
    test "is the documented Settings key" do
      assert SpoilerFree.setting_key() == "spoiler_free_mode"
    end
  end

  defp store(value) do
    {:ok, _entry} =
      Settings.find_or_create_entry(%{key: SpoilerFree.setting_key(), value: value})
  end
end
