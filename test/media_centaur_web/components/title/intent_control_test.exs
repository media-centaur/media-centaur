defmodule MediaCentaurWeb.Components.Title.IntentControlTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Title.IntentControl, as: Control

  describe "options/0" do
    test "offers the seven rungs, Ignore first, Off beside it, Default last" do
      assert Enum.map(Control.options(), & &1.rung) ==
               [:ignored, :off, :list, :follow, :ask, :grab, :default]

      assert Enum.map(Control.options(), & &1.label) == ~w(Ignore Off List Follow Ask Grab Default)
    end
  end

  describe "selected?/2" do
    test "a title with no record reads as Off" do
      assert Control.selected?(nil, :off)
      refute Control.selected?(nil, :list)
      refute Control.selected?(nil, :follow)
    end

    test "the title's rung is the pressed option" do
      assert Control.selected?(:grab, :grab)
      refute Control.selected?(:grab, :off)
      assert Control.selected?(:list, :list)
    end
  end

  describe "segment_label/2" do
    test "Default carries what the global setting resolves to; the rest are their names" do
      default = %{rung: :default, label: "Default"}
      assert Control.segment_label(default, "all_releases") == "Default · Grab"
      assert Control.segment_label(default, "ask") == "Default · Ask"
      assert Control.segment_label(default, "off") == "Default · Follow"
      assert Control.segment_label(%{rung: :follow, label: "Follow"}, "all_releases") == "Follow"
    end
  end

  describe "description/1" do
    test "Off is the absence of a record, and says so" do
      assert Control.description(nil) == "Not on your list."
    end

    test "Ignored is hidden from Recommendations and nothing more" do
      assert Control.description(:ignored) =~ "Hidden from the Feed"
      assert Control.description(:ignored) =~ "Nothing is watching for releases"
    end

    test "List is on the list and nothing more" do
      assert Control.description(:list) =~ "Nothing is watching for releases"
    end

    test "each explicit rung states its consequence" do
      assert Control.description(:follow) =~ "Nothing downloads"
      assert Control.description(:ask) =~ "waits for your approval"
      assert Control.description(:grab) =~ "downloads when it drops"
    end

    test "Default says what it follows; the segment says what that resolves to" do
      assert Control.description(:default) =~ "auto-grab setting"
    end
  end
end
