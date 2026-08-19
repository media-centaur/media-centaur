defmodule MediaCentaur.Preferences.PageBackdropSettingsTest do
  @moduledoc """
  Tests for the per-page backdrop typed Settings accessors
  (`LibraryBackdrop`, `IncomingBackdrop`) — both default-off, so the
  ambient artwork band only renders once the user turns it on. Existing
  installs that were on the default-on regime are seeded an explicit
  `enabled: true` row by the `SeedBackdropDefaultsForExistingInstalls`
  migration (which skips fresh databases).
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Preferences.IncomingBackdrop
  alias MediaCentaur.Preferences.LibraryBackdrop
  alias MediaCentaur.Settings

  for {module, key} <- [
        {LibraryBackdrop, "library_backdrop"},
        {IncomingBackdrop, "incoming_backdrop"}
      ] do
    describe "#{inspect(module)}.enabled?/0" do
      test "returns false when no setting entry exists (default-off)" do
        assert Settings.get_by_key(unquote(module).setting_key()) == nil
        assert unquote(module).enabled?() == false
      end

      test "returns true when the stored value is enabled: true" do
        {:ok, _} =
          Settings.find_or_create_entry(%{
            key: unquote(module).setting_key(),
            value: %{"enabled" => true}
          })

        assert unquote(module).enabled?() == true
      end

      test "returns false when the stored value is enabled: false" do
        {:ok, _} =
          Settings.find_or_create_entry(%{
            key: unquote(module).setting_key(),
            value: %{"enabled" => false}
          })

        assert unquote(module).enabled?() == false
      end

      test "returns false (default-off) when the stored value is shaped unexpectedly" do
        {:ok, _} =
          Settings.find_or_create_entry(%{
            key: unquote(module).setting_key(),
            value: %{"something_else" => "yes"}
          })

        assert unquote(module).enabled?() == false
      end
    end

    describe "#{inspect(module)}.setting_key/0" do
      test "is the documented Settings key" do
        assert unquote(module).setting_key() == unquote(key)
      end
    end
  end
end
