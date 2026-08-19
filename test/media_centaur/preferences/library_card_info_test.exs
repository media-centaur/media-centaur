defmodule MediaCentaur.Preferences.LibraryCardInfoTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Preferences.LibraryCardInfo
  alias MediaCentaur.Settings

  describe "enabled?/0" do
    test "returns true when no setting entry exists (default-on)" do
      assert Settings.get_by_key(LibraryCardInfo.setting_key()) == nil
      assert LibraryCardInfo.enabled?() == true
    end

    test "returns true when the stored value is enabled: true" do
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: LibraryCardInfo.setting_key(),
          value: %{"enabled" => true}
        })

      assert LibraryCardInfo.enabled?() == true
    end

    test "returns false when the stored value is enabled: false" do
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: LibraryCardInfo.setting_key(),
          value: %{"enabled" => false}
        })

      assert LibraryCardInfo.enabled?() == false
    end

    test "returns true (default-on) when the stored value is shaped unexpectedly" do
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: LibraryCardInfo.setting_key(),
          value: %{"something_else" => "yes"}
        })

      assert LibraryCardInfo.enabled?() == true
    end
  end

  describe "setting_key/0" do
    test "is the documented Settings key" do
      assert LibraryCardInfo.setting_key() == "library_show_card_info"
    end
  end
end
