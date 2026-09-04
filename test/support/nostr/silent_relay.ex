defmodule MediaCentaur.Nostr.SilentRelay do
  @moduledoc """
  A relay that completes the WebSocket handshake and then never sends
  another byte — not even a pong. `FakeRelay` cannot play this part:
  Bandit answers pings itself before the handler sees them. This is what
  a half-open socket looks like from the client's side, so it is the
  fixture for the liveness ping.

  `greeting: frame` sends one text frame (a term, JSON-encoded) in the
  same TCP write as the 101 response. A relay that speaks first — an
  AUTH challenge on connect — can land its frame in the packet that
  carries the upgrade; Bandit makes that a race, this makes it certain.

  `start/1` returns `%{url: url}` on a loopback port; the acceptor is
  linked to the caller and closes with it.
  """

  @magic "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  @spec start(greeting: term()) :: %{url: String.t()}
  def start(opts \\ []) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listen)
    test_pid = self()
    greeting = if frame = Keyword.get(opts, :greeting), do: text_frame(frame), else: ""

    spawn_link(fn -> accept_loop(listen, test_pid, greeting) end)

    %{url: "ws://127.0.0.1:#{port}/"}
  end

  defp accept_loop(listen, test_pid, greeting) do
    {:ok, socket} = :gen_tcp.accept(listen)
    spawn_link(fn -> handshake(socket, test_pid, greeting) end)
    accept_loop(listen, test_pid, greeting)
  end

  defp handshake(socket, test_pid, greeting) do
    request = read_request(socket, "")
    [_line, key] = Regex.run(~r/Sec-WebSocket-Key:\s*(\S+)/i, request)
    accept = Base.encode64(:crypto.hash(:sha, key <> @magic))

    :ok =
      :gen_tcp.send(
        socket,
        "HTTP/1.1 101 Switching Protocols\r\n" <>
          "Upgrade: websocket\r\nConnection: Upgrade\r\n" <>
          "Sec-WebSocket-Accept: #{accept}\r\n\r\n" <> greeting
      )

    send(test_pid, {:silent_relay, :upgraded})
    hold(socket)
  end

  # One unmasked, unfragmented text frame (RFC 6455 §5.2) — server frames
  # are not masked, and the short-length form covers a greeting.
  defp text_frame(frame) do
    payload = Jason.encode!(frame)
    true = byte_size(payload) < 126
    <<0x81, byte_size(payload)>> <> payload
  end

  defp read_request(socket, acc) do
    {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
    acc = acc <> data
    if String.contains?(acc, "\r\n\r\n"), do: acc, else: read_request(socket, acc)
  end

  # Drain whatever the client sends (pings included) and answer nothing.
  defp hold(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, _data} -> hold(socket)
      {:error, _closed} -> :ok
    end
  end
end
