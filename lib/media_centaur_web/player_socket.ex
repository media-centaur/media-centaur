defmodule MediaCentaurWeb.PlayerSocket do
  @moduledoc """
  The WebSocket end of a remote player's channel. Speaks frames only:
  every decision is `Playback.Remote.Channel`'s, over the state this
  process holds. Opened by `Plugs.PlayerChannel` for a paired player with
  the locators that turn a presence id into a media URL for this player
  (`MediaToken` inside) and a URL back into the id.
  """

  @behaviour WebSock

  alias MediaCentaur.Playback
  alias MediaCentaur.Playback.Remote.Channel
  alias MediaCentaur.Playback.SessionRegistry

  @impl true
  def init(%{player_id: player_id, locators: locators}) do
    case Channel.connect(player_id, locators) do
      {:ok, state} ->
        # A channel for a player no session holds may belong to an mpv that
        # outlived its session (a host restart): ask it, off this process.
        if SessionRegistry.on_player(player_id) == [], do: Playback.recover_player(player_id)
        {:ok, state}

      {:error, {:already_registered, _pid}} ->
        {:stop, :already_connected, %Channel{player_id: player_id}}
    end
  end

  @impl true
  def handle_in({text, opcode: :text}, state), do: reply(Channel.frame_in(state, text))
  def handle_in({_binary, opcode: :binary}, state), do: {:stop, :binary_frame, state}

  @impl true
  def handle_control({_payload, opcode: :pong}, state), do: {:ok, Channel.pong(state)}
  def handle_control(_frame, state), do: {:ok, state}

  @impl true
  def handle_info(message, state) do
    case Channel.handle_message(state, message) do
      :unhandled -> {:ok, state}
      outcome -> reply(outcome)
    end
  end

  @impl true
  def terminate(reason, state), do: Channel.closed(state, reason)

  defp reply({:ok, state}), do: {:ok, state}
  defp reply({:push, frame, state}), do: {:push, frame, state}
  defp reply({:stop, reason, state}), do: {:stop, reason, state}
  defp reply({:stop, reason, close, frames, state}), do: {:stop, reason, close, frames, state}
end
