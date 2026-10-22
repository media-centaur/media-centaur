defmodule MediaCentaurWeb.Plugs.PlayerChannel do
  @moduledoc """
  Opens a remote player's channel: `GET /players/channel`, upgraded to a
  WebSocket handled by `PlayerSocket`. Sits behind the gate, so the
  request already carries its verdict: only a paired `Players.Player` may
  open a channel — the host has no channel, its mpv is local — and an
  `Origin` header, when a browser sends one, must be this install's own.
  A player reconnecting evicts its earlier channel first.

  The locators handed to the channel close over the address the device
  used to reach us (the request's `Host`), so every media URL the host
  composes for this player points where the device can fetch it.
  """

  @behaviour Plug

  import Plug.Conn

  alias MediaCentaur.Players.Player
  alias MediaCentaur.Playback.Remote.{Channel, PlayerRegistry}
  alias MediaCentaurWeb.MediaToken
  alias MediaCentaurWeb.PlayerSocket

  @max_frame_size 1_048_576

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["players", "channel"], method: "GET"} = conn, _opts) do
    with %Player{id: player_id} <- conn.assigns[:player],
         :ok <- origin_ok(conn),
         :ok <- upgrade_requested(conn) do
      evict_existing(player_id)

      conn
      |> WebSockAdapter.upgrade(
        PlayerSocket,
        %{player_id: player_id, locators: locators(conn, player_id)},
        timeout: 60_000,
        max_frame_size: @max_frame_size,
        compress: false
      )
      |> halt()
    else
      :no_upgrade -> conn |> send_resp(426, "Upgrade Required") |> halt()
      _not_a_remote_player -> conn |> send_resp(403, "Only a paired player opens a channel.") |> halt()
    end
  end

  def call(%Plug.Conn{path_info: ["players", "channel"]} = conn, _opts),
    do: conn |> send_resp(405, "") |> halt()

  def call(conn, _opts), do: conn

  @doc "The locators a channel from `conn` gets: URLs at the address the device reached us by."
  @spec locators(Plug.Conn.t(), String.t()) :: PlayerRegistry.locators()
  def locators(conn, player_id) do
    base = base_url(conn)

    %{
      locate: fn presence_id ->
        "#{base}/media/#{presence_id}?t=#{MediaToken.sign(player_id, presence_id)}"
      end,
      locate_subtitle: fn presence_id, basename ->
        "#{base}/media/#{presence_id}/subtitles/#{URI.encode(basename, &URI.char_unreserved?/1)}?t=#{MediaToken.sign(player_id, presence_id)}"
      end,
      identify: fn url ->
        case URI.parse(url) do
          %URI{path: "/media/" <> presence_id} when presence_id != "" ->
            if !String.contains?(presence_id, "/"), do: presence_id

          _other ->
            nil
        end
      end
    }
  end

  defp base_url(conn), do: "#{conn.scheme}://#{conn.host}:#{conn.port}"

  defp origin_ok(conn) do
    case get_req_header(conn, "origin") do
      [] -> :ok
      [origin] -> if origin == base_url(conn), do: :ok, else: :bad_origin
    end
  end

  defp upgrade_requested(conn) do
    conn
    |> get_req_header("upgrade")
    |> Enum.any?(&(String.downcase(&1) == "websocket"))
    |> if(do: :ok, else: :no_upgrade)
  end

  defp evict_existing(player_id) do
    case PlayerRegistry.lookup(player_id) do
      {pid, _locators} -> Channel.replace(pid)
      nil -> :ok
    end
  end
end
