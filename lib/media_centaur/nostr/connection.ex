defmodule MediaCentaur.Nostr.Connection do
  @moduledoc """
  One relay, one WebSocket, kept alive. Speaks NIP-01 frames and the
  NIP-42 `AUTH` handshake; knows nothing about what events mean.

  Started with `url`, an `owner` pid, and a `signer` (`Event.t() ->
  Event.t()`, used only to sign the `AUTH` answer). The owner receives
  `{:nostr, url, message}`:

    * `:connected` / `{:disconnected, reason}`
    * `{:event, sub_id, %Event{}}` — shape-checked and signature-verified
    * `{:eose, sub_id}`, `{:notice, text}`
    * `{:ok, event_id, accepted?, reason}` — the relay's verdict on a publish
    * `{:auth, :ok | {:failed, reason}}`

  Subscriptions live in state and are re-issued after every reconnect
  and after a successful `AUTH` (an allowlist relay refuses `REQ`
  before it). Reconnect backoff doubles from `backoff_ms` (1 s) to
  `max_backoff_ms` (60 s) and resets on connect.
  """

  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Filter

  @auth_kind 22_242

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
    status: :connecting,
    subs: %{},
    backoff_ms: 1_000,
    max_backoff_ms: 60_000,
    current_backoff: nil
  ]

  # --- API ---------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "Sends a signed event to the relay. The verdict arrives as `{:ok, id, accepted?, reason}`."
  @spec publish(GenServer.server(), Event.t()) :: :ok | {:error, :not_connected}
  def publish(server, %Event{} = event), do: GenServer.call(server, {:publish, event})

  @doc "Opens (or replaces) subscription `sub_id`; re-issued on every reconnect."
  @spec subscribe(GenServer.server(), String.t(), [Filter.t()]) :: :ok
  def subscribe(server, sub_id, filters), do: GenServer.call(server, {:subscribe, sub_id, filters})

  @doc "Closes subscription `sub_id` and forgets it."
  @spec unsubscribe(GenServer.server(), String.t()) :: :ok
  def unsubscribe(server, sub_id), do: GenServer.call(server, {:unsubscribe, sub_id})

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
      max_backoff_ms: Keyword.get(opts, :max_backoff_ms, 60_000)
    }

    {:ok, %{state | current_backoff: state.backoff_ms}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: connect(state)

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  def handle_call({:publish, _event}, _from, %{websocket: nil} = state),
    do: {:reply, {:error, :not_connected}, state}

  def handle_call({:publish, event}, _from, state),
    do: {:reply, :ok, send_frame(state, ["EVENT", Event.to_map(event)])}

  def handle_call({:subscribe, sub_id, filters}, _from, state) do
    state = %{state | subs: Map.put(state.subs, sub_id, filters)}
    {:reply, :ok, if(state.websocket, do: send_req(state, sub_id, filters), else: state)}
  end

  def handle_call({:unsubscribe, sub_id}, _from, state) do
    state = %{state | subs: Map.delete(state.subs, sub_id)}
    {:reply, :ok, if(state.websocket, do: send_frame(state, ["CLOSE", sub_id]), else: state)}
  end

  @impl true
  def handle_info(:reconnect, %{conn: conn} = state) when not is_nil(conn), do: {:noreply, state}

  def handle_info(:reconnect, state), do: connect(state)

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

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, uri.host, uri.port, protocols: [:http1]),
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

        resubscribe(%{
          state
          | conn: conn,
            websocket: websocket,
            status: :connected,
            current_backoff: state.backoff_ms
        })

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
  defp handle_frame({:close, _code, _reason}, state), do: lost(state, :closed_by_relay)
  defp handle_frame(_other, state), do: state

  defp handle_relay_message(["EVENT", sub_id, event_map], state) do
    with {:ok, event} <- Event.from_map(event_map),
         :ok <- Event.verify(event) do
      notify(state, {:event, sub_id, event})
    else
      _other -> Log.debug(:nostr, "#{state.url}: dropped invalid event on #{sub_id}")
    end

    state
  end

  defp handle_relay_message(["EOSE", sub_id], state) do
    notify(state, {:eose, sub_id})
    state
  end

  defp handle_relay_message(["NOTICE", text], state) do
    notify(state, {:notice, text})
    state
  end

  defp handle_relay_message(["CLOSED", sub_id, reason], state) do
    notify(state, {:notice, "#{sub_id}: #{reason}"})
    state
  end

  defp handle_relay_message(["OK", event_id, accepted?, reason], %{pending_auth: event_id} = state) do
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

  defp handle_relay_message(["OK", event_id, accepted?, reason], state) do
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

  defp handle_relay_message(_other, state), do: state

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
    if state.status == :connected, do: Log.warning(:nostr, "lost #{state.url}: #{inspect(reason)}")
    notify(state, {:disconnected, reason})
    Process.send_after(self(), :reconnect, state.current_backoff)

    %{
      state
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

  defp notify(state, message) do
    send(state.owner, {:nostr, state.url, message})
    :ok
  end
end
