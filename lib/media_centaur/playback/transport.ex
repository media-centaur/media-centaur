defmodule MediaCentaur.Playback.Transport do
  @moduledoc """
  How a playback session reaches an mpv, and how that mpv names a file.

  `MpvSession` is one observer over mpv's property model; a transport is
  the one thing that differs between an mpv the host spawns
  (`Transport.Local`: a Unix socket, a host path) and an mpv on a paired
  player (`Transport.Remote`: the player channel, a media URL). The
  session holds a transport struct in its state and never touches a
  socket, a port or a channel itself. The transport module also knows how
  to find its player's mpvs that outlived their session (`recover/1`).

  A transport is a struct whose module implements this behaviour. It
  runs inside the session process: raw Erlang messages the session does
  not recognise go to `handle_message/2`, which folds them into
  **transport events** the session understands:

    * `{:attached, :fresh | :reconnected}` — an mpv is reachable; the
      session (re)sends its property observations.
    * `{:message, ipc_object}` — one decoded mpv IPC object.
    * `{:detached, reason}` — the mpv is unreachable for now; a remote
      player's channel dropped. The session stops persisting and waits
      for a reattach, then gives up after its window.
    * `{:closed, {:ok, :ended}}` — the mpv is gone for good: the session
      finalises.
    * `{:closed, {:error, reason, message}}` — it never started, or
      failed on the way; the session broadcasts the failure and finalises.

  Commands flow the other way through `send/2`, fire and forget; a
  transport that is not attached drops them. How this mpv is told to
  append the chain's successor is the transport's too (`queue/3`): a
  spawned process carries the session options for its life, a remote
  player's instance carries nothing and gets them on every file.
  `draws_subtitles?/1` says whether the mpv renders subtitles at all; a
  remote player draws nothing, so bitmap tracks are never enforced on it.
  `holds_one_viewing?/1` says whether this mpv holds one viewing at a
  time: a remote player runs one libmpv for its app's life, so a new
  viewing there replaces the one running (`Sessions.play/2`); the host
  spawns a process per viewing. Everything that differs between the two
  kinds of player beyond how they are reached is a question the transport
  answers, so the player's kind is read in one place: `Sessions`, to
  choose the transport.

  File identity: the session keeps the host path (`content_url`) as the
  identity of what plays. `locator/2` turns that identity into what mpv
  is told to load (the path itself, or a media URL), or says why it
  cannot — a file the player could not fetch is never handed to it;
  `identify/2` turns the path mpv reports back into the identity, or
  `nil` for a file this install did not hand it.
  """

  @type t :: struct()
  @type event ::
          {:attached, :fresh | :reconnected}
          | {:message, map()}
          | {:detached, term()}
          | {:closed, {:ok, :ended} | {:error, atom(), String.t()}}

  @typedoc "What a session hands its transport to start an mpv on a file."
  @type launch :: %{
          session_options: [MediaCentaur.Playback.LaunchFlags.option()],
          content_url: String.t(),
          start_position: number(),
          profile_id: String.t(),
          reattach?: boolean()
        }

  @doc """
  Starts reaching an mpv for `launch`. Later progress arrives as messages to
  the session process. `reattach?` says the mpv already plays this file
  (recovery): observe it, do not load.
  """
  @callback open(t(), launch()) :: {[event()], t()}

  @doc "Sends one IPC command (a list, as mpv's `command` array). Dropped when not attached."
  @callback send(t(), command :: list()) :: :ok

  @doc "Whether an mpv is reachable right now."
  @callback attached?(t()) :: boolean()

  @doc "What mpv is told to load for the file identified by the host path, or why this player cannot be told."
  @callback locator(t(), content_url :: String.t()) :: {:ok, String.t()} | {:error, atom()}

  @doc "The host path identified by what mpv reports as its `path`, or nil."
  @callback identify(t(), reported_path :: String.t()) :: String.t() | nil

  @doc "The command that appends the chain's successor (`locator`, from `start_position`) with this session's options."
  @callback queue(t(), locator :: String.t(), start_position :: number()) :: list()

  @doc "Whether this mpv renders subtitles; a player that draws nothing cannot show a bitmap track."
  @callback draws_subtitles?(t()) :: boolean()

  @doc "Whether this mpv holds one viewing at a time, so a new viewing on its player replaces the one running."
  @callback holds_one_viewing?(t()) :: boolean()

  @doc "Folds a raw message delivered to the session into transport events; `:unhandled` for one that is not the transport's."
  @callback handle_message(t(), message :: term()) :: {[event()], t()} | :unhandled

  @doc "Releases what the transport holds. `final?` says the mpv has ended, so nothing is kept for recovery."
  @callback close(t(), final? :: boolean()) :: :ok

  @doc "A short name for logs."
  @callback describe(t()) :: String.t()

  @doc "A transport for `player` and one viewing's params; `:player_offline` when a remote player has no channel."
  @callback for_player(MediaCentaur.Playback.player(), params :: map()) :: {:ok, t()} | {:error, :player_offline}

  @doc """
  The mpvs on `player` that outlived their session (ADR-023), as the
  params `Sessions.resume/2` reattaches with: this transport finds them
  and reads their properties, `SessionRecovery.reattach_params/4` does the
  rest. `Sessions.recover/1` calls it: for the host at boot, for a remote
  player when its channel connects and no session holds it.
  """
  @callback recover(MediaCentaur.Playback.player()) :: [map()]

  def open(%module{} = transport, launch), do: module.open(transport, launch)
  def send(%module{} = transport, command), do: module.send(transport, command)
  def attached?(%module{} = transport), do: module.attached?(transport)
  def locator(%module{} = transport, content_url), do: module.locator(transport, content_url)
  def identify(%module{} = transport, reported_path), do: module.identify(transport, reported_path)
  def queue(%module{} = transport, locator, start), do: module.queue(transport, locator, start)
  def draws_subtitles?(%module{} = transport), do: module.draws_subtitles?(transport)
  def holds_one_viewing?(%module{} = transport), do: module.holds_one_viewing?(transport)
  def handle_message(%module{} = transport, message), do: module.handle_message(transport, message)
  def close(%module{} = transport, final?), do: module.close(transport, final?)
  def describe(%module{} = transport), do: module.describe(transport)
end
