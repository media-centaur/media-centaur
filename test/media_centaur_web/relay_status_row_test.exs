defmodule MediaCentaurWeb.RelayStatusRowTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.RelayStatusRow

  @now ~U[2026-09-04 12:00:00Z]

  defp entry(state, opts \\ []) do
    %{
      state: state,
      last_error: Keyword.get(opts, :last_error),
      since: Keyword.get(opts, :since, ~U[2026-09-04 09:00:00Z]),
      last_heard_at: Keyword.get(opts, :last_heard_at),
      retry_at: Keyword.get(opts, :retry_at)
    }
  end

  describe "host/1" do
    test "drops the scheme and the trailing slash, keeps a non-default port and a path" do
      assert RelayStatusRow.host("wss://relay.example.org/") == "relay.example.org"
      assert RelayStatusRow.host("ws://localhost:7777/") == "localhost:7777"
      assert RelayStatusRow.host("wss://relay.example.org:443/") == "relay.example.org"
      assert RelayStatusRow.host("wss://relay.example.org/nostr") == "relay.example.org/nostr"
    end
  end

  describe "state_label/1" do
    test "one word per state, and an absent entry reads as not connected" do
      assert RelayStatusRow.state_label(entry(:connecting)) == "Connecting"
      assert RelayStatusRow.state_label(entry(:connected)) == "Connected"
      assert RelayStatusRow.state_label(entry(:synced)) == "Synced"
      assert RelayStatusRow.state_label(entry(:auth_failed)) == "Rejected"
      assert RelayStatusRow.state_label(entry(:disconnected)) == "Not connected"
      assert RelayStatusRow.state_label(nil) == "Not connected"
    end
  end

  describe "build/3" do
    test "a synced relay says how long and when it was last heard" do
      row =
        RelayStatusRow.build(
          "wss://relay.example.org/",
          entry(:synced, last_heard_at: ~U[2026-09-04 11:58:00Z]),
          @now
        )

      assert row.host == "relay.example.org"
      assert row.label == "Synced"
      assert row.details == ["for 3h", "heard 2m ago"]
    end

    test "a lost relay says how long, why, and when it retries" do
      row =
        RelayStatusRow.build(
          "ws://localhost:7777/",
          entry(:disconnected,
            last_error: "connection refused",
            since: ~U[2026-09-04 09:00:00Z],
            retry_at: ~U[2026-09-04 12:00:42Z]
          ),
          @now
        )

      assert row.label == "Not connected"
      assert row.details == ["for 3h", "connection refused", "retry in 42s"]
    end

    test "a rejected relay carries the relay's own words and no retry" do
      row =
        RelayStatusRow.build(
          "wss://private.example/",
          entry(:auth_failed, last_error: "restricted: this key is not a member of this relay"),
          @now
        )

      assert row.label == "Rejected"
      assert row.details == ["for 3h", "restricted: this key is not a member of this relay"]
    end

    test "a relay still connecting has nothing to add" do
      row = RelayStatusRow.build("wss://relay.example.org/", entry(:connecting, since: @now), @now)
      assert row.details == []
    end

    test "a connected relay with a stale feed error keeps the complaint beside the heard time" do
      row =
        RelayStatusRow.build(
          "wss://relay.example.org/",
          entry(:connected, last_error: "error: overloaded", last_heard_at: ~U[2026-09-04 11:59:30Z]),
          @now
        )

      assert row.details == ["for 3h", "error: overloaded", "heard 30s ago"]
    end
  end
end
