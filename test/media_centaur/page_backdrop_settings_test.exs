defmodule MediaCentaur.PageBackdropSettingsTest do
  @moduledoc """
  Tests for the per-page backdrop typed Settings accessors
  (`LibraryBackdrop`, `IncomingBackdrop`) — both default-on, so the
  ambient artwork band renders until the user turns it off.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IncomingBackdrop
  alias MediaCentaur.LibraryBackdrop
  alias MediaCentaur.Settings

  for {module, key} <- [
        {LibraryBackdrop, "library_backdrop"},
        {IncomingBackdrop, "incoming_backdrop"}
      ] do
    describe "#{inspect(module)}.enabled?/0" do
      test "returns true when no setting entry exists (default-on)" do
        assert {:ok, nil} = Settings.get_by_key(unquote(module).setting_key())
        assert unquote(module).enabled?() == true
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

      test "returns true (default-on) when the stored value is shaped unexpectedly" do
        {:ok, _} =
          Settings.find_or_create_entry(%{
            key: unquote(module).setting_key(),
            value: %{"something_else" => "yes"}
          })

        assert unquote(module).enabled?() == true
      end
    end

    describe "#{inspect(module)}.setting_key/0" do
      test "is the documented Settings key" do
        assert unquote(module).setting_key() == unquote(key)
      end
    end
  end
end
