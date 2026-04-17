defmodule MediaCentarrWeb.Live.SettingsLive.ConnectionTestTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Live.SettingsLive.ConnectionTest

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

  describe "stale?/2" do
    test "returns false for results tested within the threshold" do
      now = ~U[2026-04-17 12:05:00Z]
      tested_at = ~U[2026-04-17 12:00:00Z]
      refute ConnectionTest.stale?(tested_at, now)
    end

    test "returns true once past the threshold (default 24h)" do
      now = ~U[2026-04-18 13:00:00Z]
      tested_at = ~U[2026-04-17 12:00:00Z]
      assert ConnectionTest.stale?(tested_at, now)
    end
  end

  describe "parse/1" do
    test "parses a stored map with ISO8601 string" do
      parsed =
        ConnectionTest.parse(%{
          "status" => "ok",
          "tested_at" => "2026-04-17T12:00:00Z"
        })

      assert %{status: :ok, tested_at: %DateTime{}} = parsed
    end

    test "returns nil for a missing/invalid map" do
      assert ConnectionTest.parse(nil) == nil
      assert ConnectionTest.parse(%{}) == nil
      assert ConnectionTest.parse(%{"status" => "ok"}) == nil
      assert ConnectionTest.parse(%{"status" => "unknown", "tested_at" => "2026-04-17T12:00:00Z"}) == nil
    end

    test "accepts :error status" do
      parsed =
        ConnectionTest.parse(%{
          "status" => "error",
          "tested_at" => "2026-04-17T12:00:00Z"
        })

      assert parsed.status == :error
    end
  end

  describe "serialize/1" do
    test "produces a map suitable for JSON storage" do
      tested_at = ~U[2026-04-17 12:00:00Z]
      result = ConnectionTest.serialize(%{status: :ok, tested_at: tested_at})

      assert result == %{"status" => "ok", "tested_at" => "2026-04-17T12:00:00Z"}
    end

    test "round-trips through parse" do
      info = %{status: :error, tested_at: ~U[2026-04-17 12:00:00Z]}
      assert info == info |> ConnectionTest.serialize() |> ConnectionTest.parse()
    end
  end
end
