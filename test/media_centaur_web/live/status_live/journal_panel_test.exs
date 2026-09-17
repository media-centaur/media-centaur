defmodule MediaCentaurWeb.StatusLive.JournalPanelTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.StatusLive.JournalPanel

  describe "open_on?/2" do
    test "the panel stays open on the System drill-in" do
      assert JournalPanel.open_on?(true, :system)
    end

    test "any other drill-in takes the panel away" do
      refute JournalPanel.open_on?(true, :watcher)
    end

    test "closing the drill-in takes the panel away" do
      refute JournalPanel.open_on?(true, nil)
    end

    test "a collapsed panel stays collapsed on System" do
      refute JournalPanel.open_on?(false, :system)
    end
  end

  describe "action/2" do
    test "expanding subscribes" do
      assert JournalPanel.action(false, true) == :subscribe
    end

    test "collapsing unsubscribes" do
      assert JournalPanel.action(true, false) == :unsubscribe
    end

    test "an unchanged panel owes nothing" do
      assert JournalPanel.action(false, false) == :none
      assert JournalPanel.action(true, true) == :none
    end
  end

  describe "leaving the drill-in with the journal expanded" do
    # The leak that keeps `journalctl -f` running for the life of the VM:
    # the refcount only drops when the page unsubscribes, and nothing else
    # on the page is watching for the drill-in going away.
    test "closing the drill-in unsubscribes" do
      assert JournalPanel.action(true, JournalPanel.open_on?(true, nil)) == :unsubscribe
    end

    test "moving to another subsystem unsubscribes" do
      assert JournalPanel.action(true, JournalPanel.open_on?(true, :pipeline)) == :unsubscribe
    end

    test "opening an incident on the same drill-in keeps the subscription" do
      assert JournalPanel.action(true, JournalPanel.open_on?(true, :system)) == :none
    end
  end
end
