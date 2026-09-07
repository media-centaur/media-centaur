defmodule MediaCentaurWeb.Components.ReleaseTracking.TrackingModeControlTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingModeControl, as: Control

  describe "options/0" do
    test "offers the five modes, Off first, Default last" do
      assert Enum.map(Control.options(), & &1.mode) == [:none, :watch, :ask, :grab, :global]
      assert Enum.map(Control.options(), & &1.label) == ~w(Off Watch Ask Grab Default)
    end
  end

  describe "selected?/2" do
    test "an untracked title reads as Off" do
      assert Control.selected?(nil, :none)
      refute Control.selected?(nil, :watch)
    end

    test "a tracked title's mode is the pressed option" do
      assert Control.selected?(:grab, :grab)
      refute Control.selected?(:grab, :none)
      assert Control.selected?(:none, :none)
    end
  end

  describe "description/2" do
    test "an untracked or disarmed title follows nothing" do
      assert Control.description(nil, "all_releases") == "Not following releases."
      assert Control.description(:none, "all_releases") == "Not following releases."
    end

    test "each explicit mode states its consequence, independent of the global default" do
      assert Control.description(:watch, "all_releases") =~ "Nothing downloads"
      assert Control.description(:ask, "off") =~ "waits for your approval"
      assert Control.description(:grab, "off") =~ "downloads when it drops"
    end

    test "Default spells out what the global setting resolves to right now" do
      assert Control.description(:global, "all_releases") =~ "currently Grab."
      assert Control.description(:global, "ask") =~ "currently Ask."
      assert Control.description(:global, "off") =~ "currently Watch."
    end
  end
end
