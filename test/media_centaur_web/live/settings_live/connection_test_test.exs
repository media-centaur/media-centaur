defmodule MediaCentaurWeb.Live.SettingsLive.ConnectionTestTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Live.SettingsLive.ConnectionTest

  describe "relative_age/2" do
    test "returns 'just now' for under a minute" do
      now = ~U[2026-04-17 12:00:30Z]
      tested_at = ~U[2026-04-17 12:00:00Z]
      assert ConnectionTest.relative_age(tested_at, now) == "just now"
    end

    test "returns minutes for under an hour" do
      now = ~U[2026-04-17 12:30:00Z]
      tested_at = ~U[2026-04-17 12:00:00Z]
      assert ConnectionTest.relative_age(tested_at, now) == "30 min ago"
    end

    test "uses singular for 1 minute" do
      now = ~U[2026-04-17 12:01:30Z]
      tested_at = ~U[2026-04-17 12:00:00Z]
      assert ConnectionTest.relative_age(tested_at, now) == "1 min ago"
    end

    test "returns hours for under a day" do
      now = ~U[2026-04-17 15:30:00Z]
      tested_at = ~U[2026-04-17 12:00:00Z]
      assert ConnectionTest.relative_age(tested_at, now) == "3 hours ago"
    end

    test "uses singular for 1 hour" do
      now = ~U[2026-04-17 13:00:00Z]
      tested_at = ~U[2026-04-17 12:00:00Z]
      assert ConnectionTest.relative_age(tested_at, now) == "1 hour ago"
    end

    test "returns days for a day or more" do
      now = ~U[2026-04-20 12:00:00Z]
      tested_at = ~U[2026-04-17 12:00:00Z]
      assert ConnectionTest.relative_age(tested_at, now) == "3 days ago"
    end

    test "uses singular for 1 day" do
      now = ~U[2026-04-18 12:00:00Z]
      tested_at = ~U[2026-04-17 12:00:00Z]
      assert ConnectionTest.relative_age(tested_at, now) == "1 day ago"
    end

    test "returns 'in the future' for a tested_at that is later than now" do
      now = ~U[2026-04-17 12:00:00Z]
      tested_at = ~U[2026-04-17 12:05:00Z]
      assert ConnectionTest.relative_age(tested_at, now) == "just now"
    end
  end
end
