defmodule MediaCentaur.Playback.Transport.Remote do
  @moduledoc """
  A remote player's transport: the mpv inside the paired device's app,
  reached over its player channel (`Playback.Transport.Remote.Channel`), its
  files the media URLs the channel composes.

  `open/2` attaches the session to the channel and sends one
  `loadfile … replace` whose options argument carries the session options
  and the resume position (`LaunchFlags.per_file_options/2`): the device's
  mpv lives for the app's life, so nothing is set on its instance and mpv
  restores it at the file's end; the successor the session queues carries
  the same options. The transport is attached at
  once — the channel is already up, or `new/1` would have said the player
  is offline. A channel that drops detaches the transport; the next
  channel for the same player announces itself and the transport
  reattaches — unless the channel closed because the player was removed,
  which ends the viewing at once. `quit` on a remote player stops the file and shows the
  device's UI again; the device's mpv lives on for the next viewing.

  File identity goes through `Library.FilePresence`: the host path the
  session holds is the presence row's, the URL names the row's id.
  `recover/1` reads the same way back: when a channel connects and no
  session holds the player, the device's mpv is asked what it plays, the
  URL names the presence, the presence's path names the entity, and
  `SessionRecovery` reads the position and the profile.

  The desktop's mpv autoloads the sidecar subtitles beside a local file;
  a remote mpv plays a URL and sees no directory, so the transport stands
  in for the autoload: once mpv has reported both the file's `path` and
  `file-loaded` — libmpv delivers the two in either order — it adds each
  of that file's sidecars (`Subtitles.sidecars_for_presence/1`) with
  `sub-add <url> auto <name> [<lang>]` from the media URLs' sidecar function,
  once per file; `start-file` forgets both for the next one. The session
  hears of the tracks as it does of any, through `track-list`.

  The device's mpv draws nothing (`vo=mediacodec_embed`): the host's page
  is its OSD, so `draws_subtitles?/1` is false and the session never
  selects a bitmap subtitle track on it.

  The stream is the transport's delivery, so its options ride on each
  `loadfile` beside the session's: FFmpeg's HTTP reconnect, which resumes
  the Range after a dropped connection — a host restart or a network
  blip — instead of taking the short read for the file's end.

  A `loadfile … replace` on an mpv that still holds a file (a viewing
  replacing another, or one that ended on `keep-open`) makes mpv end that
  file before it starts ours, and the device's bridge cannot know the
  reason. So an `end-file` that arrives before our file's `start-file` is
  the replaced file's and is dropped (`started?`); a reattaching session's
  file has started already.
  """

  @behaviour MediaCentaur.Playback.Transport

  # This module defines the behaviour's `send/2`; the Erlang send is spelled out.
  import Kernel, except: [send: 2]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Playback.{LaunchFlags, SessionRecovery}
  alias MediaCentaur.Playback.Transport.Remote.{Channel, PlayerRegistry}
  alias MediaCentaur.Subtitles

  defstruct [
    :player_id,
    :channel,
    :media_urls,
    :launch,
    :presence_id,
    started?: true,
    loaded?: false,
    sidecars_added?: false
  ]

  @type t :: %__MODULE__{}

  @doc "A transport for a connected remote player, or `:player_offline` when it has no channel."
  @spec new(String.t()) :: {:ok, t()} | {:error, :player_offline}
  def new(player_id) do
    case PlayerRegistry.lookup(player_id) do
      nil ->
        {:error, :player_offline}

      {channel, media_urls} ->
        {:ok, %__MODULE__{player_id: player_id, channel: channel, media_urls: media_urls}}
    end
  end

  @impl true
  def for_player(player_id, _params), do: new(player_id)

  @impl true
  # Runs off the channel's process: the reader waits on the channel's replies.
  def recover(player_id) do
    case PlayerRegistry.lookup(player_id) do
      nil ->
        []

      {channel, media_urls} ->
        reader = fn name ->
          case Channel.request(channel, ["get_property", name]) do
            {:ok, %{"error" => "success", "data" => data}} -> {:ok, data}
            {:ok, %{"error" => error}} -> {:error, error}
            {:error, reason} -> {:error, reason}
          end
        end

        with {:ok, path} when is_binary(path) <- reader.("path"),
             presence_id when is_binary(presence_id) <- media_urls.presence_id.(path),
             {:ok, presence} <- FilePresence.fetch(presence_id),
             entity_id when is_binary(entity_id) <- SessionRecovery.entity_id_for_path(presence.file_path),
             {:ok, params} <-
               SessionRecovery.reattach_params(reader, entity_id, presence.file_path, "player #{player_id}") do
          [params]
        else
          _nothing_to_recover ->
            Log.info(:playback, "recovery: nothing to recover on player #{Format.short_id(player_id)}")
            []
        end
    end
  end

  @impl true
  def open(transport, %{reattach?: true} = launch) do
    Channel.attach(transport.channel, self())
    {[{:attached, :reconnected}], %{transport | launch: launch, started?: true}}
  end

  def open(transport, launch) do
    Channel.attach(transport.channel, self())

    Channel.push(
      transport.channel,
      loadfile(launch, launch.content_url, "replace", launch.start_position)
    )

    {[{:attached, :fresh}], %{transport | launch: launch, started?: false}}
  end

  @impl true
  def send(%{channel: nil}, _command), do: :ok
  def send(%{channel: channel}, command), do: Channel.push(channel, command)

  @impl true
  def attached?(%{channel: channel}), do: channel != nil

  @impl true
  # A file with no presence row has no media URL: the player could not
  # fetch a host path, so it is not handed one.
  def locator(transport, content_url) do
    case FilePresence.fetch_by_path(content_url) do
      {:ok, presence} -> {:ok, transport.media_urls.for_file.(presence.id)}
      {:error, :not_found} -> {:error, :no_presence}
    end
  end

  @impl true
  def identify(transport, reported_path) do
    with presence_id when is_binary(presence_id) <- transport.media_urls.presence_id.(reported_path),
         {:ok, presence} <- FilePresence.fetch(presence_id) do
      presence.file_path
    else
      _unknown -> nil
    end
  end

  @impl true
  def queue(%{launch: launch}, locator, start), do: loadfile(launch, locator, "append", start)

  @impl true
  def draws_subtitles?(_transport), do: false

  @impl true
  # One libmpv for the app's life: a `loadfile … replace` takes the file
  # from under any other viewing on this player.
  def holds_one_viewing?(_transport), do: true

  @impl true
  # Our file has started: from here every end-file is about our viewing.
  def handle_message(
        transport,
        {:transport, {:remote, {:message, %{"event" => "start-file"} = object}}}
      ),
      do:
        {[{:message, object}],
         %{transport | started?: true, presence_id: nil, loaded?: false, sidecars_added?: false}}

  # The file mpv held before ours ended; not our end.
  def handle_message(
        %{started?: false} = transport,
        {:transport, {:remote, {:message, %{"event" => "end-file"}}}}
      ), do: {[], transport}

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

  # The file mpv holds now, as the presence its URL names.
  def handle_message(
        transport,
        {:transport,
         {:remote, {:message, %{"event" => "property-change", "name" => "path", "data" => url} = object}}}
      )
      when is_binary(url) do
    transport = add_sidecars(%{transport | presence_id: transport.media_urls.presence_id.(url)})
    {[{:message, object}], transport}
  end

  # mpv has the file: what its autoload would find beside a local one, the
  # transport adds by URL.
  def handle_message(
        transport,
        {:transport, {:remote, {:message, %{"event" => "file-loaded"} = object}}}
      ) do
    {[{:message, object}], add_sidecars(%{transport | loaded?: true})}
  end

  def handle_message(transport, {:transport, {:remote, {:message, object}}}),
    do: {[{:message, object}], transport}

  # The player was removed: it is not coming back, so the viewing ends now
  # rather than waiting out a reattach window.
  def handle_message(transport, {:transport, {:remote, {:channel_down, {:shutdown, :removed}}}}) do
    {[{:closed, {:ok, :ended}}], %{transport | channel: nil}}
  end

  def handle_message(transport, {:transport, {:remote, {:channel_down, reason}}}) do
    {[{:detached, reason}], %{transport | channel: nil}}
  end

  def handle_message(transport, {:transport, {:remote, {:channel_up, channel}}}) do
    Channel.attach(channel, self())

    media_urls =
      case PlayerRegistry.lookup(transport.player_id) do
        {^channel, media_urls} -> media_urls
        _other -> transport.media_urls
      end

    {[{:attached, :reconnected}], %{transport | channel: channel, media_urls: media_urls, started?: true}}
  end

  def handle_message(_transport, _message), do: :unhandled

  @impl true
  def close(%{channel: nil}, _final?), do: :ok
  def close(%{channel: channel}, _final?), do: Channel.detach(channel, self())

  @impl true
  def describe(transport), do: "player #{Format.short_id(transport.player_id)}"

  # Once per file, when both the presence and the load are known.
  defp add_sidecars(%{presence_id: presence_id, loaded?: true, sidecars_added?: false} = transport)
       when is_binary(presence_id) do
    for track <- Subtitles.sidecars_for_presence(presence_id) do
      Channel.push(transport.channel, sub_add(transport, presence_id, track))
    end

    %{transport | sidecars_added?: true}
  end

  defp add_sidecars(transport), do: transport

  defp sub_add(transport, presence_id, %{source: source, language: language}) do
    basename = Path.basename(source)
    url = transport.media_urls.for_sidecar.(presence_id, basename)
    ["sub-add", url, "auto", basename] ++ List.wrap(language)
  end

  # mpv ≥ 0.38's five-argument form: the index is required before the options.
  # The stream's own options ride on the file beside the session's. A host
  # restart (an update, say) or a network blip ends the TCP stream early,
  # and FFmpeg's HTTP reader takes a short read for the file's end — the
  # Sony sat on `eof-reached` at 84 s of 2543 (2026-10-23). `reconnect`
  # resumes the Range from its offset after an early EOF and
  # `reconnect_on_network_error` keeps trying while the host is still
  # down, both with FFmpeg's backoff and caps (120 s between tries, 256 s
  # in all). mpv ignores a key a build lacks.
  @stream_options [{"stream-lavf-o", "reconnect=1,reconnect_on_network_error=1"}]

  defp loadfile(launch, url, mode, start) do
    [
      "loadfile",
      url,
      mode,
      -1,
      LaunchFlags.per_file_options(@stream_options ++ launch.session_options, start)
    ]
  end
end
