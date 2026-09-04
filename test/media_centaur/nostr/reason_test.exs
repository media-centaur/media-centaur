defmodule MediaCentaur.Nostr.ReasonTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.Reason

  test "transport errors map to the fixed vocabulary" do
    assert Reason.describe(%Mint.TransportError{reason: :econnrefused}) == "connection refused"
    assert Reason.describe(%Mint.TransportError{reason: :nxdomain}) == "host not found"
    assert Reason.describe(%Mint.TransportError{reason: :timeout}) == "timed out"
    assert Reason.describe(%Mint.TransportError{reason: :closed}) == "closed by relay"

    assert Reason.describe(%Mint.TransportError{reason: {:tls_alert, {:unknown_ca, ~c"x"}}}) ==
             "TLS failed"
  end

  test "the connection's own atoms have words" do
    assert Reason.describe(:closed_by_relay) == "closed by relay"
    assert Reason.describe(:unresponsive) == "unresponsive"
  end

  test "a relay's own text passes through" do
    assert Reason.describe("restricted: not a member") == "restricted: not a member"
  end

  test "an upgrade failure names the wrong kind of server" do
    assert Reason.describe(%Mint.WebSocketError{reason: :connection_not_upgraded}) ==
             "not a WebSocket relay"
  end

  test "anything unknown is never inspected into the UI" do
    assert Reason.describe({:some, :tuple}) == "connection failed"
    assert Reason.describe(%Mint.TransportError{reason: :eperm}) == "connection failed"
  end
end
