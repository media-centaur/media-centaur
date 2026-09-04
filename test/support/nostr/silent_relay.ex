defmodule MediaCentaur.Nostr.SilentRelay do
  @moduledoc """
  A relay that completes the WebSocket handshake and then never sends
  another byte — not even a pong. `FakeRelay` cannot play this part:
  Bandit answers pings itself before the handler sees them. This is what
  a half-open socket looks like from the client's side, so it is the
  fixture for the liveness ping.

  `start/0` returns `%{url: url}` on a loopback port; the acceptor is
  linked to the caller and closes with it.
  """

  @magic "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  @spec start() :: %{url: String.t()}
  def start do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listen)
    test_pid = self()

    spawn_link(fn -> accept_loop(listen, test_pid) end)

    %{url: "ws://127.0.0.1:#{port}/"}
  end

  defp accept_loop(listen, test_pid) do
    {:ok, socket} = :gen_tcp.accept(listen)
    spawn_link(fn -> handshake(socket, test_pid) end)
    accept_loop(listen, test_pid)
  end

  defp handshake(socket, test_pid) do
    request = read_request(socket, "")
    [_line, key] = Regex.run(~r/Sec-WebSocket-Key:\s*(\S+)/i, request)
    accept = Base.encode64(:crypto.hash(:sha, key <> @magic))

    :ok =
      :gen_tcp.send(
        socket,
        "HTTP/1.1 101 Switching Protocols\r\n" <>
          "Upgrade: websocket\r\nConnection: Upgrade\r\n" <>
          "Sec-WebSocket-Accept: #{accept}\r\n\r\n"
      )

    send(test_pid, {:silent_relay, :upgraded})
    hold(socket)
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
