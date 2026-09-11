defmodule MediaCentaurWeb.Components.Title.IntentControlTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Title.IntentControl

  describe "control_form/1 — which form the control takes (UIDR-039)" do
    test "a title with no record, or an ignored one, gets the one verb: Add to watchlist" do
      assert IntentControl.control_form(nil) == :add
      assert IntentControl.control_form(:ignored) == :add
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
