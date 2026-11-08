defmodule MediaCentaurWeb.PlayerSocket do
  @moduledoc """
  The WebSocket end of a remote player's channel. Speaks frames only:
  every decision is `Playback.Transport.Remote.Channel`'s, over the state this
  process holds. Opened by `Plugs.PlayerChannel` for a paired player with
  the media URLs for this player: the functions that compose a presence's
  URL (`MediaToken` inside) and read a presence id back out of one.

  The gate's enforcement point for the channel (ADR-079): it subscribes
  to `players:updates` and the settings topic, and its own player's
  removal, or the remote players feature turning off (ADR-081), closes
  the channel through `Channel.removed/1`, the way `Live.PlayerAware`
  drops the player's page. Playback hears of either only as its channel
  closing for good.
  """

  @behaviour WebSock

  alias MediaCentaur.Features
  alias MediaCentaur.Playback.Transport.Remote.Channel
  alias MediaCentaur.Players
  alias MediaCentaur.Players.Events.PlayerRemoved
  alias MediaCentaur.Settings

  @impl true
  def init(%{player_id: player_id, media_urls: media_urls, address: address, device: device}) do
    case Channel.connect(player_id, media_urls) do
      {:ok, state} ->
        :ok = Players.subscribe()
        :ok = Settings.subscribe()
        :ok = Players.record_connect(player_id, %{address: address, device: device})
        {:ok, state}

      {:error, {:already_registered, _pid}} ->
        {:stop, {:shutdown, :already_connected}, %Channel{player_id: player_id}}
    end
  end

  @impl true
  def handle_in({text, opcode: :text}, state), do: Channel.frame_in(state, text)
  def handle_in({_binary, opcode: :binary}, state), do: {:stop, :binary_frame, state}

  @impl true
  def handle_control({_payload, opcode: :pong}, state), do: {:ok, Channel.pong(state)}
  def handle_control(_frame, state), do: {:ok, state}

  @impl true
  # Our player's pairing is gone; another player's removal is nobody's here.
  def handle_info(
        {:player_removed, %PlayerRemoved{id: player_id}},
        %Channel{player_id: player_id} = state
      ), do: Channel.removed(state)

  def handle_info({:setting_changed, key, _value}, state) do
    if key == Features.key(:players) and not Features.enabled?(:players),
      do: Channel.removed(state),
      else: {:ok, state}
  end

  def handle_info(message, state) do
    case Channel.handle_message(state, message) do
      :unhandled -> {:ok, state}
      outcome -> outcome
    end
  end

  @impl true
  def terminate(reason, state) do
    :ok = Channel.closed(state, reason)
    Players.record_disconnect(state.player_id)
  end
end
