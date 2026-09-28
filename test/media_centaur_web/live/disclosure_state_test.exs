defmodule MediaCentaurWeb.Live.DisclosureStateTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Live.DisclosureState

  describe "open?/3" do
    test "an untouched disclosure is open only when it opens by default" do
      toggled = MapSet.new()

      refute DisclosureState.open?(toggled, "logs")
      assert DisclosureState.open?(toggled, "logs", true)
    end

    test "a toggle flips the default" do
      toggled = MapSet.new(["logs"])

      assert DisclosureState.open?(toggled, "logs")
      refute DisclosureState.open?(toggled, "logs", true)
    end
  end

  describe "toggle/2" do
    test "the first toggle records the id, the second forgets it" do
      once = DisclosureState.toggle(MapSet.new(), "logs")
      assert DisclosureState.open?(once, "logs")

      twice = DisclosureState.toggle(once, "logs")
      refute DisclosureState.open?(twice, "logs")
      assert twice == MapSet.new()
    end

    test "toggles are per id" do
      toggled = MapSet.new() |> DisclosureState.toggle("logs") |> DisclosureState.toggle("recent")

      assert DisclosureState.open?(toggled, "logs")
      assert DisclosureState.open?(toggled, "recent")
      refute DisclosureState.open?(toggled, "history-v1")
    end
  end
end
