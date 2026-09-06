defmodule MediaCentaur.Nostr.ConnectionFramesTest do
  @moduledoc """
  What an inbound relay frame *means* — which owner message it produces,
  and that a malformed or hostile one produces none without taking the
  process down.

  These drive `Connection.__inject_frame_for_test__/2` rather than a
  socket. Frame semantics are independent of the transport that carried
  them, so a real relay adds no coverage here and costs determinism: the
  socket round-trip forces wall-clock `assert_receive` budgets that a
  loaded machine can miss. Injection is synchronous, so every assertion
  below uses `assert_received` / `refute_received` with no timeout at
  all.

  Transport behaviour — the HTTP upgrade, reconnect and re-subscription,
  ping/pong liveness, backoff — lives in `ConnectionTest`, which keeps a
  real socket because that is exactly what it is testing.
  """
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias MediaCentaur.Nostr.Connection
  alias MediaCentaur.Nostr.Event

  @secret_hex String.duplicate("0", 63) <> "3"

  # Nothing listens here, so the connection settles into its backoff and
  # never opens a socket. Frame handling does not consult one.
  @dead_url "ws://127.0.0.1:1/"

  defp secret, do: MediaCentaur.Secret.wrap(@secret_hex)

  defp signed(content, kind \\ 1) do
    Event.sign(
      Event.new(%{created_at: System.os_time(:second), kind: kind, tags: [], content: content}),
      secret()
    )
  end

  setup do
    conn =
      start_supervised!(
        {Connection,
         [
           url: @dead_url,
           owner: self(),
           signer: fn %Event{} = event -> Event.sign(event, secret()) end,
           backoff_ms: 60_000
         ]},
        id: :"frames_conn_#{System.unique_integer([:positive])}"
      )

    # Connecting to a dead port fails immediately, and the attempt runs in
    # the `handle_continue` that precedes any message — so this `call`
    # queues behind it and, once it returns, the one disconnect notice is
    # already in the mailbox. Consuming it here lets the tests below refute
    # on the whole `{:nostr, _, _}` shape rather than frame by frame.
    assert Connection.status(conn) in [:connecting, :disconnected]
    assert_received {:nostr, @dead_url, {:disconnected, _reason, _retry}}

    %{conn: conn}
  end

  defp inject(conn, frame),
    do: :ok = Connection.__inject_frame_for_test__(conn, {:text, Jason.encode!(frame)})

  describe "frames the owner should hear about" do
    test "an EVENT is verified and delivered on its subscription", %{conn: conn} do
      event = signed("hello")
      id = event.id

      inject(conn, ["EVENT", "s", Event.to_map(event)])

      assert_received {:nostr, @dead_url, {:event, "s", %Event{id: ^id, content: "hello"}}}
    end

    test "an EOSE ends the stored run", %{conn: conn} do
      inject(conn, ["EOSE", "s"])

      assert_received {:nostr, @dead_url, {:eose, "s"}}
    end

    test "a CLOSED carries the relay's reason", %{conn: conn} do
      inject(conn, ["CLOSED", "s", "auth-required: not authenticated"])

      assert_received {:nostr, @dead_url, {:closed, "s", "auth-required: not authenticated"}}
    end

    test "a NOTICE is informational, not an error", %{conn: conn} do
      inject(conn, ["NOTICE", "rate limited, slow down"])

      assert_received {:nostr, @dead_url, {:notice, "rate limited, slow down"}}
    end

    test "an accepted OK verdict names the event", %{conn: conn} do
      event = signed("published")
      id = event.id

      inject(conn, ["OK", id, true, ""])

      assert_received {:nostr, @dead_url, {:ok, ^id, true, ""}}
    end

    test "a rejected OK verdict carries the refusal reason", %{conn: conn} do
      event = signed("published")
      id = event.id

      inject(conn, ["OK", id, false, "blocked: not on the allowlist"])

      assert_received {:nostr, @dead_url, {:ok, ^id, false, "blocked: not on the allowlist"}}
    end
  end

  describe "frames the owner should never hear about" do
    test "an EVENT whose shape is wrong is dropped", %{conn: conn} do
      inject(conn, ["EVENT", "s", %{"id" => 1}])

      refute_received {:nostr, @dead_url, {:event, "s", _event}}
      assert Process.alive?(conn)
    end

    test "an EVENT whose signature does not verify is dropped", %{conn: conn} do
      forged = %{signed("bad") | sig: String.duplicate("0", 128)}

      inject(conn, ["EVENT", "s", Event.to_map(forged)])

      refute_received {:nostr, @dead_url, {:event, "s", _event}}
      assert Process.alive?(conn)
    end

    test "frames carrying the wrong types are ignored, and serving continues", %{conn: conn} do
      for frame <- [
            ["EVENT", %{}, %{}],
            ["EOSE", 7],
            ["CLOSED", 1, 2],
            ["OK", 1, "yes", 3],
            ["NOTICE", %{}],
            ["AUTH", 5]
          ] do
        inject(conn, frame)
      end

      refute_received {:nostr, @dead_url, _message}

      # A well-formed frame after them proves the process kept serving.
      inject(conn, ["EOSE", "s"])
      assert_received {:nostr, @dead_url, {:eose, "s"}}
    end

    test "an undecodable payload is dropped", %{conn: conn} do
      :ok = Connection.__inject_frame_for_test__(conn, {:text, "not json at all"})

      refute_received {:nostr, @dead_url, _message}
      assert Process.alive?(conn)
    end
  end
end
