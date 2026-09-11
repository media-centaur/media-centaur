defmodule MediaCentaurWeb.Components.Title.IntentControlTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Title.IntentControl

  describe "control_form/1 — which form the control takes (UIDR-039)" do
    test "a title with no record shows nothing here — listing is the bookmark's act, in the action strip" do
      assert IntentControl.control_form(nil) == :none
    end

    test "an ignored title shows only the line that says so" do
      assert IntentControl.control_form(:ignored) == :ignored
    end

    test "a title on the list gets the tracking controls" do
      for rung <- [:list, :follow, :ask, :grab, :default] do
        assert IntentControl.control_form(rung) == :controls
      end
    end
  end

  describe "options/0" do
    test "the tracking controls run Ignore · Off · List · Follow · Ask · Grab · Default" do
      assert Enum.map(IntentControl.options(), & &1.rung) ==
               [:ignored, :off, :list, :follow, :ask, :grab, :default]
    end
  end
end
