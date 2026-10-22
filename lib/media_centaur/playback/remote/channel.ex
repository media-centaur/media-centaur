defmodule MediaCentaur.Playback.Remote.Channel do
  @moduledoc """
  The player channel's protocol, as functions over the state of the
  process that owns the WebSocket (`MediaCentaurWeb.PlayerSocket`, which
  delegates every callback here and only speaks frames).

  One channel per connected remote player (`PlayerRegistry`). Frames carry
  mpv IPC JSON objects, one per text frame, both ways:

    * **Inbound** — an object with a `request_id` the channel asked for
      answers the waiting caller (`request/3`, used by recovery); any other
      object is an mpv event or an unsolicited reply and goes to the
      attached session's transport as `{:transport, {:remote, {:message, object}}}`.
    * **Outbound** — `push/2` sends a command; the session's
      `Transport.Remote` is the usual caller.

  A session **attaches** to the channel (`attach/2`) to receive its events
  and is told when the channel goes (`{:channel_down, reason}`); a new
  channel for a player with a live session announces itself to that
  session (`{:channel_up, pid}`) so the transport reattaches.

  Liveness: the handler pings every `ping_interval_ms/0`; a client whose
  last pong is older than `pong_grace_ms/0` at the next ping is closed.
  """

  alias MediaCentaur.Playback.Remote.PlayerRegistry
  alias MediaCentaur.Playback.SessionRegistry

  @ping_interval_ms 15_000
  @pong_grace_ms 30_000

  defstruct [
    :player_id,
    :locators,
    session: nil,
    session_ref: nil,
    pending: %{},
    next_request_id: 1,
    last_pong_at: nil
  ]

  @type t :: %__MODULE__{}
  @type outcome ::
          {:ok, t()} | {:push, {:text, String.t()} | {:ping, binary()}, t()} | {:stop, term(), t()}

  def ping_interval_ms, do: @ping_interval_ms
  def pong_grace_ms, do: @pong_grace_ms

  # --- The handler's side ---

  @doc """
  Opens the channel for `player_id` from the calling process: registers it,
  schedules the first ping, and tells the player's live sessions, if any,
  that their channel is up. A second channel for a player must evict the
  first with `replace/1` before connecting.
  """
  @spec connect(String.t(), PlayerRegistry.locators()) ::
          {:ok, t()} | {:error, {:already_registered, pid()}}
  def connect(player_id, locators) do
    with :ok <- PlayerRegistry.register(player_id, locators) do
      for {_key, session} <- SessionRegistry.on_player(player_id) do
        send(session, {:transport, {:remote, {:channel_up, self()}}})
      end

      Process.send_after(self(), {:channel, :ping}, @ping_interval_ms)
      {:ok, %__MODULE__{player_id: player_id, locators: locators, last_pong_at: now()}}
    end
  end

  @doc "One text frame from the player."
  @spec frame_in(t(), binary()) :: outcome()
  def frame_in(state, text) do
    case Jason.decode(text) do
      {:ok, %{"request_id" => request_id} = object} when is_map_key(state.pending, request_id) ->
        {{from, ref}, pending} = Map.pop(state.pending, request_id)
        send(from, {ref, object})
        {:ok, %{state | pending: pending}}

      {:ok, object} when is_map(object) ->
        if state.session, do: send(state.session, {:transport, {:remote, {:message, object}}})
        {:ok, state}

      _malformed ->
        {:stop, :malformed_frame, state}
    end
  end

  @doc "A pong from the player."
  @spec pong(t()) :: t()
  def pong(state), do: %{state | last_pong_at: now()}

  @doc "A message delivered to the handler process."
  @spec handle_message(t(), term()) :: outcome() | :unhandled
  def handle_message(state, {:channel, {:attach, session}}) do
    if state.session_ref, do: Process.demonitor(state.session_ref, [:flush])
    {:ok, %{state | session: session, session_ref: Process.monitor(session)}}
  end

  def handle_message(%{session: session} = state, {:channel, {:detach, session}}) do
    if state.session_ref, do: Process.demonitor(state.session_ref, [:flush])
    {:ok, %{state | session: nil, session_ref: nil}}
  end

  def handle_message(state, {:channel, {:detach, _other}}), do: {:ok, state}

  def handle_message(state, {:channel, {:push, command}}) do
    {:push, {:text, Jason.encode!(%{"command" => command})}, state}
  end

  def handle_message(state, {:channel, {:request, from, ref, command}}) do
    request_id = state.next_request_id
    json = Jason.encode!(%{"command" => command, "request_id" => request_id})

    {:push, {:text, json},
     %{state | pending: Map.put(state.pending, request_id, {from, ref}), next_request_id: request_id + 1}}
  end

  def handle_message(state, {:channel, :ping}) do
    if now() - state.last_pong_at > @pong_grace_ms do
      {:stop, :pong_overdue, state}
    else
      Process.send_after(self(), {:channel, :ping}, @ping_interval_ms)
      {:push, {:ping, ""}, state}
    end
  end

  def handle_message(state, {:channel, :replaced}), do: {:stop, :replaced, state}

  def handle_message(%{session_ref: ref} = state, {:DOWN, ref, :process, _pid, _reason}),
    do: {:ok, %{state | session: nil, session_ref: nil}}

  def handle_message(_state, _message), do: :unhandled

  @doc "The channel is closing: its session, if any, is told."
  @spec closed(t(), term()) :: :ok
  def closed(%{session: nil}, _reason), do: :ok

  def closed(%{session: session}, reason) do
    send(session, {:transport, {:remote, {:channel_down, reason}}})
    :ok
  end

  # --- Other processes' side ---

  @doc "Sends one IPC command down the channel. Fire and forget."
  @spec push(pid(), list()) :: :ok
  def push(channel, command) do
    send(channel, {:channel, {:push, command}})
    :ok
  end

  @doc "Sends one IPC command and waits for its reply object, correlated by `request_id`."
  @spec request(pid(), list(), timeout()) :: {:ok, map()} | {:error, :timeout}
  def request(channel, command, timeout \\ 5_000) do
    ref = make_ref()
    send(channel, {:channel, {:request, self(), ref, command}})

    receive do
      {^ref, object} -> {:ok, object}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc "Makes `session` the process the channel forwards mpv's objects to."
  @spec attach(pid(), pid()) :: :ok
  def attach(channel, session) do
    send(channel, {:channel, {:attach, session}})
    :ok
  end

  @doc "Undoes `attach/2`."
  @spec detach(pid(), pid()) :: :ok
  def detach(channel, session) do
    send(channel, {:channel, {:detach, session}})
    :ok
  end

  @doc "Closes an older channel for a player whose new one is connecting; waits for it to go."
  @spec replace(pid(), timeout()) :: :ok
  def replace(channel, timeout \\ 1_000) do
    ref = Process.monitor(channel)
    send(channel, {:channel, :replaced})

    receive do
      {:DOWN, ^ref, :process, ^channel, _reason} -> :ok
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        :ok
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
