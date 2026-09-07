defmodule MediaCentaurWeb.Components.Discovery.IntentControlTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Discovery.IntentControl, as: Control

  describe "options/0" do
    test "offers the six rungs, Off first, Default last" do
      assert Enum.map(Control.options(), & &1.rung) == [:off, :list, :follow, :ask, :grab, :default]
      assert Enum.map(Control.options(), & &1.label) == ~w(Off List Follow Ask Grab Default)
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

  describe "description/2" do
    test "Off is the absence of a record, and says so" do
      assert Control.description(nil, "all_releases") == "Not on your list."
    end

    test "List is on the list and nothing more" do
      assert Control.description(:list, "all_releases") =~ "Nothing is watching for releases"
    end

    test "each explicit rung states its consequence, independent of the global default" do
      assert Control.description(:follow, "all_releases") =~ "Nothing downloads"
      assert Control.description(:ask, "off") =~ "waits for your approval"
      assert Control.description(:grab, "off") =~ "downloads when it drops"
    end

    test "Default spells out what the global setting resolves to right now" do
      assert Control.description(:default, "all_releases") =~ "currently Grab."
      assert Control.description(:default, "ask") =~ "currently Ask."
      assert Control.description(:default, "off") =~ "currently Follow."
    end
  end
end
