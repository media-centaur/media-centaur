defmodule MediaCentaur.Playback.Transport.Remote do
  @moduledoc """
  A remote player's transport: the mpv inside the paired device's app,
  reached over its player channel (`Playback.Remote.Channel`), its files
  media URLs the channel's locators compose.

  `open/2` attaches the session to the channel, sends the session options
  as IPC (`set_property`, and `change-list script-opts append` for the
  profile) and one `loadfile … replace` for the file, and is attached at
  once — the channel is already up, or `new/1` would have said the player
  is offline. A channel that drops detaches the transport; the next
  channel for the same player announces itself and the transport
  reattaches. `quit` on a remote player stops the file and shows the
  device's UI again; the device's mpv lives on for the next viewing.

  File identity goes through `Library.FilePresence`: the host path the
  session holds is the presence row's, the URL names the row's id.
  """

  @behaviour MediaCentaur.Playback.Transport

  # This module defines the behaviour's `send/2`; the Erlang send is spelled out.
  import Kernel, except: [send: 2]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Playback.Remote.{Channel, PlayerRegistry}

  defstruct [:player_id, :channel, :locators, :launch]

  @type t :: %__MODULE__{}

  @doc "A transport for a connected remote player, or `:player_offline` when it has no channel."
  @spec new(String.t()) :: {:ok, t()} | {:error, :player_offline}
  def new(player_id) do
    case PlayerRegistry.lookup(player_id) do
      nil ->
        {:error, :player_offline}

      {channel, locators} ->
        {:ok, %__MODULE__{player_id: player_id, channel: channel, locators: locators}}
    end
  end

  @impl true
  def open(transport, %{reattach?: true} = launch) do
    Channel.attach(transport.channel, self())
    {[{:attached, :reconnected}], %{transport | launch: launch}}
  end

  def open(transport, launch) do
    Channel.attach(transport.channel, self())
    Enum.each(launch.session_options, &Channel.push(transport.channel, option_command(&1)))
    Channel.push(transport.channel, loadfile_command(launch.content_url, launch.start_position))
    {[{:attached, :fresh}], %{transport | launch: launch}}
  end

  @impl true
  def send(%{channel: nil}, _command), do: :ok
  def send(%{channel: channel}, command), do: Channel.push(channel, command)

  @impl true
  def attached?(%{channel: channel}), do: channel != nil

  @impl true
  def locator(transport, content_url) do
    case FilePresence.fetch_by_path(content_url) do
      {:ok, presence} ->
        transport.locators.locate.(presence.id)

      {:error, :not_found} ->
        Log.warning(
          :playback,
          "no presence row for #{Path.basename(content_url)} — the player cannot fetch it"
        )

        content_url
    end
  end

  @impl true
  def identify(transport, reported_path) do
    with presence_id when is_binary(presence_id) <- transport.locators.identify.(reported_path),
         {:ok, presence} <- FilePresence.fetch(presence_id) do
      presence.file_path
    else
      _unknown -> nil
    end
  end

  @impl true
  # The player reports the file stopped or was quit: the viewing is over on
  # a remote player (its mpv lives on for the next one), so the message is
  # followed by the close the session finalises on.
  def handle_message(
        transport,
        {:transport, {:remote, {:message, %{"event" => "end-file", "reason" => reason} = object}}}
      )
      when reason in ["stop", "quit"] do
    {[{:message, object}, {:closed, {:ok, :ended}}], transport}
  end

  def handle_message(transport, {:transport, {:remote, {:message, object}}}),
    do: {[{:message, object}], transport}

  def handle_message(transport, {:transport, {:remote, {:channel_down, reason}}}) do
    {[{:detached, reason}], %{transport | channel: nil}}
  end

  def handle_message(transport, {:transport, {:remote, {:channel_up, channel}}}) do
    Channel.attach(channel, self())

    locators =
      case PlayerRegistry.lookup(transport.player_id) do
        {^channel, locators} -> locators
        _other -> transport.locators
      end

    {[{:attached, :reconnected}], %{transport | channel: channel, locators: locators}}
  end

  def handle_message(_transport, _message), do: :unhandled

  @impl true
  def close(%{channel: nil}, _final?), do: :ok
  def close(%{channel: channel}, _final?), do: Channel.detach(channel, self())

  @impl true
  def describe(transport), do: "player #{Format.short_id(transport.player_id)}"

  # The one option mpv takes as a list edit rather than a value.
  defp option_command({"script-opts-append", value}), do: ["change-list", "script-opts", "append", value]
  defp option_command({name, value}), do: ["set_property", name, value]

  # mpv ≥ 0.38's five-argument form: the index is required before per-file options.
  defp loadfile_command(url, start) when start > 0,
    do: ["loadfile", url, "replace", -1, "start=#{start}"]

  defp loadfile_command(url, _start), do: ["loadfile", url, "replace"]
end
