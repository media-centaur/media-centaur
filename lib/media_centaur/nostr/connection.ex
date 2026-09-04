defmodule MediaCentaur.Nostr.Connection do
  @moduledoc """
  One relay, one WebSocket, kept alive. Speaks NIP-01 frames and the
  NIP-42 `AUTH` handshake; knows nothing about what events mean.

  Started with `url`, an `owner` pid, and a `signer` (`Event.t() ->
  Event.t()`, used only to sign the `AUTH` answer). The owner receives
  `{:nostr, url, message}`:

    * `:connected` / `{:disconnected, reason, retry_in_ms}` — the wait
      before the next attempt rides along, so a status surface can say
      when
    * `:pong` — the relay answered a liveness ping (see below)
    * `{:event, sub_id, %Event{}}` — shape-checked and signature-verified
    * `{:eose, sub_id}`
    * `{:closed, sub_id, reason}` — the relay ended that subscription
    * `{:notice, text}` — a relay's informational notice, not an error
    * `{:ok, event_id, accepted?, reason}` — the relay's verdict on a publish
    * `{:auth, :ok | {:failed, reason}}`

  Every inbound frame is type-guarded before its parts are used: a relay
  is untrusted input, and a frame that does not match falls to a debug
  log rather than a crash.

  Subscriptions live in state and are re-issued after every reconnect
  and after a successful `AUTH` (an allowlist relay refuses `REQ`
  before it). Reconnect backoff doubles from `backoff_ms` (1 s) to
  `max_backoff_ms` (60 s) and resets on connect.

  While connected, a ping goes out every `ping_interval_ms` (30 s); a
  pong that does not arrive within `pong_timeout_ms` (10 s) drops the
  socket with reason `:unresponsive` into the normal backoff. Without
  it a half-open socket — relay host rebooted, NAT entry expired —
  would stay "connected" until the kernel gave up on it.

  The console sees one warning per outage: the loss of a live socket,
  or the first failed attempt after one. Retries are silent; every
  disconnect still reaches the owner.

  `publish/2`, `subscribe/3` and `unsubscribe/2` are casts, so a caller
  is never blocked behind a connect attempt to an unreachable relay.
  """

  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Nostr.Reason

  @auth_kind 22_242

  # Mint's own connect timeout defaults to 30 s; a relay that drops SYN
  # would otherwise hold this process for that long.
  @connect_timeout_ms 5_000

  @type status :: :connecting | :connected | :disconnected | :auth_failed

  defstruct [
    :url,
    :owner,
    :signer,
    :conn,
    :websocket,
    :ref,
    :http_status,
    :resp_headers,
    :pending_auth,
    :ping_timer,
    :pong_deadline,
    status: :connecting,
    subs: %{},
    backoff_ms: 1_000,
    max_backoff_ms: 60_000,
    current_backoff: nil,
    ping_interval_ms: 30_000,
    pong_timeout_ms: 10_000
  ]

  # --- API ---------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc """
  Sends a signed event to the relay. The verdict arrives as `{:ok, id,
  accepted?, reason}`; a publish issued while the socket is down is
  dropped, so callers publish only to relays they have seen reach
  `:connected` (`Connections.Owner` guards on exactly that).
  """
  @spec publish(GenServer.server(), Event.t()) :: :ok
  def publish(server, %Event{} = event), do: GenServer.cast(server, {:publish, event})

  @doc "Opens (or replaces) subscription `sub_id`; re-issued on every reconnect."
  @spec subscribe(GenServer.server(), String.t(), [Filter.t()]) :: :ok
  def subscribe(server, sub_id, filters), do: GenServer.cast(server, {:subscribe, sub_id, filters})

  @doc "Closes subscription `sub_id` and forgets it."
  @spec unsubscribe(GenServer.server(), String.t()) :: :ok
  def unsubscribe(server, sub_id), do: GenServer.cast(server, {:unsubscribe, sub_id})

  @spec status(GenServer.server()) :: status()
  def status(server), do: GenServer.call(server, :status)

  # --- lifecycle ---------------------------------------------------------

  @impl true
  def init(opts) do
    state = %__MODULE__{
      url: Keyword.fetch!(opts, :url),
      owner: Keyword.fetch!(opts, :owner),
      signer: Keyword.fetch!(opts, :signer),
      backoff_ms: Keyword.get(opts, :backoff_ms, 1_000),
      max_backoff_ms: Keyword.get(opts, :max_backoff_ms, 60_000),
      ping_interval_ms: Keyword.get(opts, :ping_interval_ms, 30_000),
      pong_timeout_ms: Keyword.get(opts, :pong_timeout_ms, 10_000)
    }

    {:ok, %{state | current_backoff: state.backoff_ms}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: connect(state)

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  # `send_raw/2` drops the frame when there is no socket, so a publish while
  # disconnected is a no-op rather than a queued write.
  @impl true
  def handle_cast({:publish, event}, state),
    do: {:noreply, send_frame(state, ["EVENT", Event.to_map(event)])}

  def handle_cast({:subscribe, sub_id, filters}, state) do
    state = %{state | subs: Map.put(state.subs, sub_id, filters)}
    {:noreply, if(state.websocket, do: send_req(state, sub_id, filters), else: state)}
  end

  def handle_cast({:unsubscribe, sub_id}, state) do
    state = %{state | subs: Map.delete(state.subs, sub_id)}
    {:noreply, if(state.websocket, do: send_frame(state, ["CLOSE", sub_id]), else: state)}
  end

  @impl true
  def handle_info(:reconnect, %{conn: conn} = state) when not is_nil(conn), do: {:noreply, state}

  def handle_info(:reconnect, state), do: connect(state)

  # Timers from a socket that has since gone are stale: the ping only
  # fires with a live websocket, the deadline only while one is armed.
  def handle_info(:ping, %{websocket: nil} = state), do: {:noreply, state}

  def handle_info(:ping, state) do
    deadline = Process.send_after(self(), :pong_deadline, state.pong_timeout_ms)
    {:noreply, send_raw(%{state | ping_timer: nil, pong_deadline: deadline}, {:ping, ""})}
  end

  def handle_info(:pong_deadline, %{pong_deadline: nil} = state), do: {:noreply, state}
  def handle_info(:pong_deadline, state), do: {:noreply, lost(state, :unresponsive)}

  def handle_info(message, %{conn: conn} = state) when not is_nil(conn) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, responses} ->
        {:noreply, Enum.reduce(responses, %{state | conn: conn}, &handle_response/2)}

      {:error, conn, reason, _responses} ->
        {:noreply, lost(%{state | conn: conn}, reason)}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  # --- connecting --------------------------------------------------------

  defp connect(state) do
    uri = URI.parse(state.url)
    {http_scheme, ws_scheme} = if uri.scheme == "wss", do: {:https, :wss}, else: {:http, :ws}
    path = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")

    opts = [protocols: [:http1], transport_opts: [timeout: @connect_timeout_ms]]

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, uri.host, uri.port, opts),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, path, []) do
      {:noreply, %{state | conn: conn, ref: ref, status: :connecting}}
    else
      {:error, reason} -> {:noreply, lost(state, reason)}
      {:error, conn, reason} -> {:noreply, lost(%{state | conn: conn}, reason)}
    end
  end

  defp handle_response({:status, ref, status}, %{ref: ref} = state), do: %{state | http_status: status}

  defp handle_response({:headers, ref, headers}, %{ref: ref} = state),
    do: %{state | resp_headers: headers}

  defp handle_response({:done, ref}, %{ref: ref} = state) do
    case Mint.WebSocket.new(state.conn, ref, state.http_status, state.resp_headers) do
      {:ok, conn, websocket} ->
        Log.info(:nostr, "connected to #{state.url}")
        notify(state, :connected)

        %{
          state
          | conn: conn,
            websocket: websocket,
            status: :connected,
            current_backoff: state.backoff_ms
        }
        |> schedule_ping()
        |> resubscribe()

      {:error, conn, reason} ->
        lost(%{state | conn: conn}, reason)
    end
  end

  defp handle_response({:data, ref, data}, %{ref: ref, websocket: websocket} = state)
       when not is_nil(websocket) do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        Enum.reduce(frames, %{state | websocket: websocket}, &handle_frame/2)

      {:error, websocket, reason} ->
        lost(%{state | websocket: websocket}, reason)
    end
  end

  defp handle_response(_other, state), do: state

  # --- frames ------------------------------------------------------------

  defp handle_frame({:text, text}, state) do
    case Jason.decode(text) do
      {:ok, frame} ->
        handle_relay_message(frame, state)

      {:error, _reason} ->
        Log.debug(:nostr, "#{state.url}: undecodable frame")
        state
    end
  end

  defp handle_frame({:ping, data}, state), do: send_raw(state, {:pong, data})

  defp handle_frame({:pong, _data}, state) do
    notify(state, :pong)
    state |> cancel_pong_deadline() |> schedule_ping()
  end

  defp handle_frame({:close, _code, _reason}, state), do: lost(state, :closed_by_relay)
  defp handle_frame(_other, state), do: state

  defp handle_relay_message(["EVENT", sub_id, event_map], state)
       when is_binary(sub_id) and is_map(event_map) do
    with {:ok, event} <- Event.from_map(event_map),
         :ok <- Event.verify(event) do
      notify(state, {:event, sub_id, event})
    else
      _other -> Log.debug(:nostr, "#{state.url}: dropped invalid event on #{sub_id}")
    end

    state
  end

  defp handle_relay_message(["EOSE", sub_id], state) when is_binary(sub_id) do
    notify(state, {:eose, sub_id})
    state
  end

  defp handle_relay_message(["NOTICE", text], state) when is_binary(text) do
    notify(state, {:notice, text})
    state
  end

  defp handle_relay_message(["CLOSED", sub_id, reason], state)
       when is_binary(sub_id) and is_binary(reason) do
    notify(state, {:closed, sub_id, reason})
    state
  end

  defp handle_relay_message(["OK", event_id, accepted?, reason], %{pending_auth: event_id} = state)
       when is_binary(event_id) and is_boolean(accepted?) and is_binary(reason) do
    if accepted? do
      Log.info(:nostr, "authenticated with #{state.url}")
      notify(state, {:auth, :ok})
      resubscribe(%{state | pending_auth: nil, status: :connected})
    else
      Log.warning(:nostr, "#{state.url} rejected auth: #{reason}")
      notify(state, {:auth, {:failed, reason}})
      %{state | pending_auth: nil, status: :auth_failed}
    end
  end

  defp handle_relay_message(["OK", event_id, accepted?, reason], state)
       when is_binary(event_id) and is_boolean(accepted?) and is_binary(reason) do
    notify(state, {:ok, event_id, accepted?, reason})
    state
  end

  defp handle_relay_message(["AUTH", challenge], state) when is_binary(challenge) do
    event =
      Event.new(%{
        created_at: System.os_time(:second),
        kind: @auth_kind,
        tags: [["relay", state.url], ["challenge", challenge]],
        content: ""
      })

    signed = state.signer.(event)
    state = send_frame(state, ["AUTH", Event.to_map(signed)])
    %{state | pending_auth: signed.id}
  end

  defp handle_relay_message(other, state) do
    Log.debug(:nostr, "#{state.url}: unhandled frame #{inspect(other)}")
    state
  end

  # --- sending -----------------------------------------------------------

  defp resubscribe(state) do
    Enum.reduce(state.subs, state, fn {sub_id, filters}, acc -> send_req(acc, sub_id, filters) end)
  end

  defp send_req(state, sub_id, filters),
    do: send_frame(state, ["REQ", sub_id | Enum.map(filters, &Filter.to_map/1)])

  defp send_frame(state, term), do: send_raw(state, {:text, Jason.encode!(term)})

  defp send_raw(%{websocket: nil} = state, _frame), do: state

  defp send_raw(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
      %{state | websocket: websocket, conn: conn}
    else
      {:error, %Mint.WebSocket{} = websocket, reason} ->
        lost(%{state | websocket: websocket}, reason)

      {:error, conn, reason} ->
        lost(%{state | conn: conn}, reason)
    end
  end

  # --- loss + backoff ----------------------------------------------------

  defp lost(state, reason) do
    if state.conn, do: Mint.HTTP.close(state.conn)
    log_loss(state, reason)
    notify(state, {:disconnected, reason, state.current_backoff})
    Process.send_after(self(), :reconnect, state.current_backoff)

    %{
      cancel_timers(state)
      | conn: nil,
        websocket: nil,
        ref: nil,
        http_status: nil,
        resp_headers: nil,
        pending_auth: nil,
        status: :disconnected,
        current_backoff: min(state.current_backoff * 2, state.max_backoff_ms)
    }
  end

  # The backoff sits at its floor only before the first failure of an
  # outage, so that attempt gets the line and the retries do not.
  defp log_loss(%{status: :connected} = state, reason),
    do: Log.warning(:nostr, "lost #{state.url}: #{Reason.describe(reason)} (#{inspect(reason)})")

  defp log_loss(%{current_backoff: floor, backoff_ms: floor} = state, reason),
    do:
      Log.warning(
        :nostr,
        "could not connect to #{state.url}: #{Reason.describe(reason)} (#{inspect(reason)})"
      )

  defp log_loss(_state, _reason), do: :ok

  # --- liveness ----------------------------------------------------------

  defp schedule_ping(state) do
    state = cancel_ping(state)
    %{state | ping_timer: Process.send_after(self(), :ping, state.ping_interval_ms)}
  end

  defp cancel_timers(state), do: state |> cancel_ping() |> cancel_pong_deadline()

  defp cancel_ping(%{ping_timer: nil} = state), do: state

  defp cancel_ping(state) do
    Process.cancel_timer(state.ping_timer)
    %{state | ping_timer: nil}
  end

  defp cancel_pong_deadline(%{pong_deadline: nil} = state), do: state

  defp cancel_pong_deadline(state) do
    Process.cancel_timer(state.pong_deadline)
    %{state | pong_deadline: nil}
  end

  defp notify(state, message) do
    send(state.owner, {:nostr, state.url, message})
    :ok
  end
end
