defmodule MediaCentaurWeb.Components.Title.WatchlistToggleTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Title.WatchlistToggle

  describe "choice/1 — what a click on the bookmark sets" do
    test "off the list, or ignored: List" do
      assert WatchlistToggle.choice(nil) == "list"
      assert WatchlistToggle.choice(:ignored) == "list"
    end

    test "on the list at any rung: Off — removing from the watchlist is one act" do
      for rung <- [:list, :follow, :grab], do: assert(WatchlistToggle.choice(rung) == "off")
    end
  end

  describe "listed?/1 — the filled bookmark" do
    test "only a title at List or above is on the list" do
      refute WatchlistToggle.listed?(nil)
      refute WatchlistToggle.listed?(:ignored)
      for rung <- [:list, :follow, :grab], do: assert(WatchlistToggle.listed?(rung))
    end
  end

  describe "label/0 — the accessible name and the tooltip" do
    test "is one name whatever the state; aria-pressed carries the state" do
      assert WatchlistToggle.label() == "Toggle on watchlist"
    end
  end
end
