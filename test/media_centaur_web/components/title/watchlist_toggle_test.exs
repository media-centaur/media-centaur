defmodule MediaCentaurWeb.Components.Title.WatchlistToggleTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Title.WatchlistToggle

  describe "choice/1 — what a click on the bookmark sets" do
    test "off the list, or ignored: List" do
      assert WatchlistToggle.choice(nil) == "list"
      assert WatchlistToggle.choice(:ignored) == "list"
    end

    test "at List: Off" do
      assert WatchlistToggle.choice(:list) == "off"
    end

    test "at Follow and above: nothing — a marker, because a one-click must not tear down a calendar" do
      for rung <- [:follow, :ask, :grab, :default] do
        assert WatchlistToggle.choice(rung) == nil
      end
    end
  end

  describe "listed?/1 — the filled bookmark" do
    test "only a title at List or above is on the list" do
      refute WatchlistToggle.listed?(nil)
      refute WatchlistToggle.listed?(:ignored)
      for rung <- [:list, :follow, :ask, :grab, :default], do: assert(WatchlistToggle.listed?(rung))
    end
  end

  describe "label/1 — the accessible name says what the click does" do
    test "names the act, or the marker" do
      assert WatchlistToggle.label(nil) == "Add to watchlist"
      assert WatchlistToggle.label(:ignored) == "Add to watchlist"
      assert WatchlistToggle.label(:list) == "On your list — remove"
      assert WatchlistToggle.label(:grab) == "On your list — tracking is set below"
    end
  end
end
