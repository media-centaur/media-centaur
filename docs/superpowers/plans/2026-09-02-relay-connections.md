# Relay Connections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Long-lived, authenticated connections to the user's relays: `Nostr.Connection` (one WebSocket per relay, NIP-42 auth, publish/subscribe, reconnect), `Friends.Relay` (the configured relay list), `Friends.Connections` (one connection per relay row, status, live re-broadcast), a test-only in-process fake relay, and the relay block on the Friends tab.

**Architecture:** `Nostr.Connection` is a GenServer over `Mint.WebSocket` that knows the protocol frames (`EVENT`, `REQ`, `CLOSE`, `AUTH`, `OK`, `EOSE`, `NOTICE`) and nothing else; it reports to an `owner` pid and signs `AUTH` challenges through a `signer` fun. `Friends.Connections` is a context-owned supervisor (Registry + DynamicSupervisor + an owner GenServer, Watcher-shaped) that reconciles connections against `relays` rows on boot and on `RelayAdded`/`RelayRemoved`/`IdentityChanged` events, and re-broadcasts connection messages on `friends:connections`. The owner process is gated off under `:test` (like the watchers); tests drive `Nostr.Connection` directly against `FakeRelay`, a `WebSock` handler under Bandit on an ephemeral port.

**Tech Stack:** `mint_web_socket ~> 1.0` (new), `websock_adapter ~> 0.5` (made explicit), `bandit`/`thousand_island` (present), Ecto/SQLite, `MediaCentaur.Nostr` (layer 2), `MediaCentaur.Friends` (layer 3).

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` — Architecture › `Nostr.Connection`, `Friends.Relay`, `Friends.Connections`, topics `friends:connections`/`friends:updates`; decision 4 (private first, NIP-42); decision 8 (long-lived connection per relay); Runtime behavior; UI › Friends tab › Relays; Testing › fake relay. Layer 4.

**Decisions fixed by this plan:**
- Connection state atoms: `:connecting | :connected | :disconnected | :auth_failed`. Owner messages: `{:nostr, url, msg}` with `msg` one of `:connected`, `{:disconnected, reason}`, `{:event, sub_id, %Event{}}`, `{:eose, sub_id}`, `{:closed, sub_id, reason}`, `{:ok, event_id, accepted?, reason}`, `{:notice, text}`, `{:auth, :ok | {:failed, reason}}`. Every inbound frame is type-guarded before its parts are used; anything else is debug-logged with `inspect/1`. `{:auth, :ok}` clears `last_error`, `{:closed, _, reason}` sets it, and a `{:notice, _}` is informational — it never becomes an error. `publish/2`, `subscribe/3` and `unsubscribe/2` are casts (only `status/1` is a call), so nothing blocks behind a connect attempt; a publish issued while the socket is down is dropped, and `Connections.Owner` publishes only to relays it has seen reach `:connected`. `Mint.HTTP.connect/4` gets `transport_opts: [timeout: 5_000]`.
- Backoff: 1 s doubling to a 60 s cap, reset on `:connected`. Subscriptions are kept in state and re-issued after every reconnect; `AUTH` is answered whenever the relay challenges, and the subscriptions are (re)issued after a successful auth as well, since an allowlist relay may refuse `REQ` before auth.
- NIP-42 auth event: kind 22242, tags `[["relay", url], ["challenge", challenge]]`, `created_at` now, empty content, signed by `signer.(event)`.
- Relay URL validation: scheme `ws` or `wss`, non-empty host, no userinfo; stored normalized (lowercase scheme and host, path defaults to `/`). Errors surface as a flash: **"Relay addresses start with wss:// or ws://"**.
- Removing a relay needs no confirmation (trivially reversible, MC0027 treatment (a)).
- Relay block copy: heading **Relays**; body **"The servers your recommendations are published to and read from. Your group's own relay first; public relays are more entries."**; input placeholder `wss://relay.example`; button **Add relay**; per-row status words **Connected** / **Connecting** / **Not connected** / **Rejected** (auth failed) with the last error as quiet text; row action **Remove**.
- In `:test`, `Friends.Connections.status/0` returns `%{}` when the owner is not running; the LiveView renders rows as **Not connected** then.
- Logging component tag `:friends` (connections) and `:nostr` (protocol frames), via `MediaCentaur.Log`.

**House rules:** test-first; zero warnings; `mix format`; `mix credo --strict` (MC0003 context subscribe facade, MC0025 `Topics.publish` only in `Friends.Events`, MC0024 selectors in LiveView tests, MC0027 no `data-confirm`, event chokepoint); `GlobalStateSandbox` disposition for the new top-level child; no network in tests except loopback to the fake relay; commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`; no push, no tag.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `mix.exs` | `{:mint_web_socket, "~> 1.0"}`, `{:websock_adapter, "~> 0.5"}` |
| Create | `lib/media_centaur/nostr/connection.ex` | the relay WebSocket GenServer |
| Modify | `lib/media_centaur/nostr.ex` | export `Connection` |
| Create | `test/support/nostr/fake_relay.ex` | `WebSock` handler + Plug + `start/1` helper |
| Create | `test/media_centaur/nostr/connection_test.exs` | |
| Create | `priv/repo/migrations/20260902160000_add_relays.exs` | `relays` table |
| Create | `lib/media_centaur/friends/relay.ex` | schema + URL validation |
| Modify | `lib/media_centaur/friends.ex`, `lib/media_centaur/friends/events.ex`, `lib/media_centaur/topics.ex` | `add_relay/1`, `remove_relay/1`, `list_relays/0`; `RelayAdded`/`RelayRemoved`; `friends_connections/0` |
| Create | `lib/media_centaur/friends/connections.ex` | Supervisor: Registry + DynamicSupervisor + owner |
| Create | `lib/media_centaur/friends/connections/owner.ex` | reconcile, status, re-broadcast |
| Modify | `lib/media_centaur/application.ex`, `config/test.exs`, `test/support/global_state_sandbox.ex` | child + gate + disposition |
| Create | `test/media_centaur/friends/relay_test.exs`, `test/media_centaur/friends/connections_test.exs` | |
| Create | `lib/media_centaur_web/live/discovery_live/relay_block.ex` | relay list + add form |
| Modify | `lib/media_centaur_web/live/discovery_live.ex`, `test/media_centaur_web/live/discovery_live_test.exs` | |

---

### Task 1: `Nostr.Connection` + `FakeRelay`

**Files:** `mix.exs`, `lib/media_centaur/nostr/connection.ex`, `lib/media_centaur/nostr.ex`, `test/support/nostr/fake_relay.ex`, `test/media_centaur/nostr/connection_test.exs`

- [ ] **Step 1: Dependencies** — add `{:mint_web_socket, "~> 1.0"}` and `{:websock_adapter, "~> 0.5"}` to `mix.exs`; `mix deps.get`; `mix deps.audit` clean. Read `deps/mint_web_socket/lib/mint/web_socket.ex` for the exact signatures of `upgrade/4`, `stream/2`, `new/4`, `decode/2`, `encode/2`, `stream_request_body/3` before writing the GenServer, and `deps/bandit/lib/bandit.ex` `start_link/1` (the returned pid is the ThousandIsland supervisor, so `ThousandIsland.listener_info(pid)` yields `{:ok, {_ip, port}}` for `port: 0`).

- [ ] **Step 2: The fake relay (test support)**

`test/support/nostr/fake_relay.ex`:

```elixir
defmodule MediaCentaur.Nostr.FakeRelay do
  @moduledoc """
  An in-process Nostr relay for tests: a `WebSock` handler under Bandit
  on an ephemeral loopback port. Speaks the subset `Nostr.Connection`
  uses — `EVENT` → `OK`, `REQ` → stored matches then `EOSE`, `CLOSE`,
  `AUTH` (optional challenge on connect; `REQ`/`EVENT` refused until a
  valid kind-22242 answer) — and forwards every inbound frame to the
  test process as `{:relay_in, decoded}`. `push/2` sends any frame to
  the connected client; `drop/1` closes the socket (reconnect tests).

      {:ok, relay} = FakeRelay.start(auth: false, events: [])
      relay.url            # "ws://127.0.0.1:PORT/"
  """

  defmodule State do
    @moduledoc false
    defstruct [:test_pid, :name, auth: false, authed?: false, challenge: nil, events: [], accept: true, reason: ""]
  end

  @behaviour WebSock

  # --- lifecycle ---------------------------------------------------------

  @doc """
  Starts a relay under the test supervisor. Options: `auth: boolean`
  (issue an AUTH challenge on connect and gate REQ/EVENT on it),
  `events: [Event.t()]` (stored events served to matching REQs),
  `accept: boolean` / `reason: String.t()` (the OK verdict for EVENT).
  Returns `%{url: String.t(), name: atom()}`.
  """
  def start(opts \\ []) do
    name = :"fake_relay_#{System.unique_integer([:positive])}"
    Agent.start_link(fn -> Map.new(opts) |> Map.put(:test_pid, self()) |> Map.put(:clients, []) end, name: name)

    {:ok, pid} =
      ExUnit.Callbacks.start_supervised(
        {Bandit, plug: {__MODULE__.Plug, name}, port: 0, ip: {127, 0, 0, 1}, scheme: :http, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    %{url: "ws://127.0.0.1:#{port}/", name: name}
  end

  @doc "Sends a raw frame (an Elixir term, JSON-encoded) to every connected client."
  def push(%{name: name}, frame) do
    for pid <- Agent.get(name, & &1.clients), do: send(pid, {:push, frame})
    :ok
  end

  @doc "Closes every client socket (the relay stays up, so the client can reconnect)."
  def drop(%{name: name}) do
    for pid <- Agent.get(name, & &1.clients), do: send(pid, :drop)
    :ok
  end

  # --- WebSock -----------------------------------------------------------

  @impl true
  def init(name) do
    cfg = Agent.get(name, & &1)
    Agent.update(name, &%{&1 | clients: [self() | &1.clients]})
    state = %State{test_pid: cfg.test_pid, name: name, auth: cfg[:auth] || false, events: cfg[:events] || [], accept: Map.get(cfg, :accept, true), reason: cfg[:reason] || ""}

    if state.auth do
      challenge = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      {:push, {:text, Jason.encode!(["AUTH", challenge])}, %{state | challenge: challenge}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    frame = Jason.decode!(text)
    send(state.test_pid, {:relay_in, frame})
    handle_frame(frame, state)
  end

  @impl true
  def handle_info({:push, frame}, state), do: {:push, {:text, Jason.encode!(frame)}, state}
  def handle_info(:drop, state), do: {:stop, :normal, state}
  def handle_info(_other, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    Agent.update(state.name, &%{&1 | clients: List.delete(&1.clients, self())})
    :ok
  end

  # --- frames ------------------------------------------------------------

  defp handle_frame(["AUTH", event_map], state) do
    with {:ok, event} <- MediaCentaur.Nostr.Event.from_map(event_map),
         :ok <- MediaCentaur.Nostr.Event.verify(event),
         22242 <- event.kind,
         true <- MediaCentaur.Nostr.Event.tag_value(event, "challenge") == state.challenge do
      {:push, {:text, Jason.encode!(["OK", event.id, true, ""])}, %{state | authed?: true}}
    else
      _ -> {:push, {:text, Jason.encode!(["OK", event_map["id"] || "", false, "auth-required: bad challenge"])}, state}
    end
  end

  defp handle_frame([kind | _] = frame, %{auth: true, authed?: false} = state) when kind in ["REQ", "EVENT"] do
    reply =
      case frame do
        ["EVENT", %{"id" => id}] -> ["OK", id, false, "auth-required: not authenticated"]
        ["REQ", sub_id | _] -> ["CLOSED", sub_id, "auth-required: not authenticated"]
      end

    {:push, {:text, Jason.encode!(reply)}, state}
  end

  defp handle_frame(["EVENT", %{"id" => id} = event_map], state) do
    stored =
      case MediaCentaur.Nostr.Event.from_map(event_map) do
        {:ok, event} when state.accept -> [event | state.events]
        _ -> state.events
      end

    {:push, {:text, Jason.encode!(["OK", id, state.accept, state.reason])}, %{state | events: stored}}
  end

  defp handle_frame(["REQ", sub_id | filters], state) do
    matches = Enum.filter(state.events, fn event -> Enum.any?(filters, &matches?(event, &1)) end)
    frames = Enum.map(matches, &{:text, Jason.encode!(["EVENT", sub_id, MediaCentaur.Nostr.Event.to_map(&1)])})
    {:push, frames ++ [{:text, Jason.encode!(["EOSE", sub_id])}], state}
  end

  defp handle_frame(["CLOSE", _sub_id], state), do: {:ok, state}
  defp handle_frame(_other, state), do: {:ok, state}

  # authors / kinds / ids / #d only — enough for the tests
  defp matches?(event, filter) do
    Enum.all?(filter, fn
      {"authors", list} -> event.pubkey in list
      {"kinds", list} -> event.kind in list
      {"ids", list} -> event.id in list
      {"#" <> tag, list} -> MediaCentaur.Nostr.Event.tag_value(event, tag) in list
      _other -> true
    end)
  end

  defmodule Plug do
    @moduledoc false
    @behaviour Elixir.Plug
    def init(name), do: name

    def call(conn, name) do
      conn
      |> WebSockAdapter.upgrade(MediaCentaur.Nostr.FakeRelay, name, timeout: 60_000)
      |> Elixir.Plug.Conn.halt()
    end
  end
end
```

Check the `WebSock` `handle_in/2` message shape in `deps/websock/lib/websock.ex` (`{binary(), opcode: :text}` keyword) and `handle_info/2` return forms; `{:push, [frames], state}` accepts a list. Ensure `test/support` is in `elixirc_paths(:test)` (it is — `test/support/*.ex` compiles today). If `Agent.start_link` under the test process is a problem for cleanup, use `start_supervised` for the Agent too.

- [ ] **Step 3: Failing tests**

`test/media_centaur/nostr/connection_test.exs`:

```elixir
defmodule MediaCentaur.Nostr.ConnectionTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.{Connection, Event, FakeRelay, Filter, Keys}

  @secret_hex String.duplicate("0", 63) <> "3"

  defp secret, do: MediaCentaur.Secret.wrap(@secret_hex)
  defp signer, do: fn %Event{} = event -> Event.sign(event, secret()) end

  defp start_connection(relay, opts \\ []) do
    ExUnit.Callbacks.start_supervised!(
      {Connection, [url: relay.url, owner: self(), signer: signer()] ++ opts},
      id: :"conn_#{System.unique_integer([:positive])}"
    )
  end

  defp signed(content, kind \\ 1) do
    Event.sign(Event.new(%{created_at: System.os_time(:second), kind: kind, tags: [], content: content}), secret())
  end

  test "connects and reports :connected; status reflects it" do
    relay = FakeRelay.start()
    conn = start_connection(relay)
    url = relay.url

    assert_receive {:nostr, ^url, :connected}, 2_000
    assert Connection.status(conn) == :connected
  end

  test "publishes an event and relays the OK verdict" do
    relay = FakeRelay.start()
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    event = signed("hello")
    :ok = Connection.publish(conn, event)
    id = event.id

    assert_receive {:relay_in, ["EVENT", %{"id" => ^id}]}, 2_000
    assert_receive {:nostr, ^url, {:ok, ^id, true, ""}}, 2_000
  end

  test "reports a rejected publish" do
    relay = FakeRelay.start(accept: false, reason: "blocked: not on the allowlist")
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    event = signed("hello")
    :ok = Connection.publish(conn, event)
    id = event.id
    assert_receive {:nostr, ^url, {:ok, ^id, false, "blocked: not on the allowlist"}}, 2_000
  end

  test "subscribes, receives stored events, then EOSE; live pushes arrive too" do
    stored = signed("stored", 32160)
    relay = FakeRelay.start(events: [stored])
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    :ok = Connection.subscribe(conn, "feed", [Filter.new(kinds: [32160])])
    assert_receive {:relay_in, ["REQ", "feed", %{"kinds" => [32160]}]}, 2_000
    assert_receive {:nostr, ^url, {:event, "feed", %Event{content: "stored"}}}, 2_000
    assert_receive {:nostr, ^url, {:eose, "feed"}}, 2_000

    live = signed("live", 32160)
    FakeRelay.push(relay, ["EVENT", "feed", Event.to_map(live)])
    assert_receive {:nostr, ^url, {:event, "feed", %Event{content: "live"}}}, 2_000

    :ok = Connection.unsubscribe(conn, "feed")
    assert_receive {:relay_in, ["CLOSE", "feed"]}, 2_000
  end

  test "answers an AUTH challenge with a signed kind-22242 event and then subscribes" do
    relay = FakeRelay.start(auth: true)
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    assert_receive {:relay_in, ["AUTH", %{"kind" => 22242, "tags" => tags}]}, 2_000
    assert ["relay", ^url] = Enum.find(tags, &(hd(&1) == "relay"))
    assert Enum.any?(tags, &(hd(&1) == "challenge"))
    assert_receive {:nostr, ^url, {:auth, :ok}}, 2_000

    :ok = Connection.subscribe(conn, "s", [Filter.new(kinds: [1])])
    assert_receive {:nostr, ^url, {:eose, "s"}}, 2_000
  end

  test "reconnects after the relay drops the socket and re-issues subscriptions" do
    relay = FakeRelay.start()
    conn = start_connection(relay, backoff_ms: 50)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    :ok = Connection.subscribe(conn, "s", [Filter.new(kinds: [1])])
    assert_receive {:relay_in, ["REQ", "s", _]}, 2_000

    FakeRelay.drop(relay)
    assert_receive {:nostr, ^url, {:disconnected, _reason}}, 2_000
    assert_receive {:nostr, ^url, :connected}, 5_000
    assert_receive {:relay_in, ["REQ", "s", _]}, 2_000
    assert Connection.status(conn) == :connected
  end

  test "a relay that is not listening stays :connecting and keeps retrying" do
    conn = start_connection(%{url: "ws://127.0.0.1:1/"}, backoff_ms: 50)
    url = "ws://127.0.0.1:1/"
    assert_receive {:nostr, ^url, {:disconnected, _reason}}, 2_000
    assert Connection.status(conn) in [:connecting, :disconnected]
    assert_receive {:nostr, ^url, {:disconnected, _reason}}, 2_000
  end

  test "a malformed inbound EVENT is dropped, not crashed on" do
    relay = FakeRelay.start()
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000
    :ok = Connection.subscribe(conn, "s", [Filter.new(kinds: [1])])
    assert_receive {:nostr, ^url, {:eose, "s"}}, 2_000

    FakeRelay.push(relay, ["EVENT", "s", %{"id" => 1}])
    FakeRelay.push(relay, ["EVENT", "s", Event.to_map(%{signed("bad") | sig: String.duplicate("0", 128)})])
    refute_receive {:nostr, ^url, {:event, "s", _}}, 300
    assert Process.alive?(conn)
    assert Connection.status(conn) == :connected
  end
end
```

Run: fails (modules undefined).

- [ ] **Step 4: `Nostr.Connection`**

`lib/media_centaur/nostr/connection.ex`:

```elixir
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

  alias MediaCentaur.Nostr.{Event, Filter}

  @type status :: :connecting | :connected | :disconnected | :auth_failed

  defstruct [
    :url, :owner, :signer, :conn, :websocket, :ref, :http_status, :resp_headers,
    status: :connecting, subs: %{}, backoff_ms: 1_000, max_backoff_ms: 60_000, current_backoff: nil,
    pending_auth: nil
  ]

  # --- API ---------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @spec publish(GenServer.server(), Event.t()) :: :ok | {:error, :not_connected}
  def publish(server, %Event{} = event), do: GenServer.call(server, {:publish, event})

  @spec subscribe(GenServer.server(), String.t(), [Filter.t()]) :: :ok
  def subscribe(server, sub_id, filters), do: GenServer.call(server, {:subscribe, sub_id, filters})

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

  def handle_call({:publish, event}, _from, %{websocket: nil} = state), do: {:reply, {:error, :not_connected}, state}

  def handle_call({:publish, event}, _from, state) do
    {:reply, :ok, send_frame(state, ["EVENT", Event.to_map(event)])}
  end

  def handle_call({:subscribe, sub_id, filters}, _from, state) do
    state = %{state | subs: Map.put(state.subs, sub_id, filters)}
    {:reply, :ok, if(state.websocket, do: send_req(state, sub_id, filters), else: state)}
  end

  def handle_call({:unsubscribe, sub_id}, _from, state) do
    state = %{state | subs: Map.delete(state.subs, sub_id)}
    {:reply, :ok, if(state.websocket, do: send_frame(state, ["CLOSE", sub_id]), else: state)}
  end

  @impl true
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

  defp handle_response({:status, ref, status}, %{ref: ref} = s), do: %{s | http_status: status}
  defp handle_response({:headers, ref, headers}, %{ref: ref} = s), do: %{s | resp_headers: headers}

  defp handle_response({:done, ref}, %{ref: ref} = s) do
    case Mint.WebSocket.new(s.conn, ref, s.http_status, s.resp_headers) do
      {:ok, conn, websocket} ->
        Log.info(:nostr, "connected to #{s.url}")
        notify(s, :connected)
        s = %{s | conn: conn, websocket: websocket, status: :connected, current_backoff: s.backoff_ms}
        resubscribe(s)

      {:error, conn, reason} ->
        lost(%{s | conn: conn}, reason)
    end
  end

  defp handle_response({:data, ref, data}, %{ref: ref, websocket: ws} = s) when not is_nil(ws) do
    case Mint.WebSocket.decode(ws, data) do
      {:ok, websocket, frames} -> Enum.reduce(frames, %{s | websocket: websocket}, &handle_frame/2)
      {:error, websocket, reason} -> lost(%{s | websocket: websocket}, reason)
    end
  end

  defp handle_response(_other, s), do: s

  # --- frames ------------------------------------------------------------

  defp handle_frame({:text, text}, s) do
    case Jason.decode(text) do
      {:ok, frame} -> handle_relay_message(frame, s)
      {:error, _} -> Log.debug(:nostr, "#{s.url}: undecodable frame"); s
    end
  end

  defp handle_frame({:ping, data}, s), do: send_raw(s, {:pong, data})
  defp handle_frame({:close, _code, _reason}, s), do: lost(s, :closed_by_relay)
  defp handle_frame(_other, s), do: s

  defp handle_relay_message(["EVENT", sub_id, event_map], s) do
    with {:ok, event} <- Event.from_map(event_map),
         :ok <- Event.verify(event) do
      notify(s, {:event, sub_id, event})
    else
      _ -> Log.debug(:nostr, "#{s.url}: dropped invalid event on #{sub_id}")
    end

    s
  end

  defp handle_relay_message(["EOSE", sub_id], s), do: notify(s, {:eose, sub_id}); s |> then(& &1)
  defp handle_relay_message(["NOTICE", text], s), do: notify(s, {:notice, text}); s
  defp handle_relay_message(["CLOSED", sub_id, reason], s), do: notify(s, {:notice, "#{sub_id}: #{reason}"}); s

  defp handle_relay_message(["OK", event_id, accepted?, reason], %{pending_auth: event_id} = s) do
    if accepted? do
      Log.info(:nostr, "authenticated with #{s.url}")
      notify(s, {:auth, :ok})
      resubscribe(%{s | pending_auth: nil, status: :connected})
    else
      Log.warning(:nostr, "#{s.url} rejected auth: #{reason}")
      notify(s, {:auth, {:failed, reason}})
      %{s | pending_auth: nil, status: :auth_failed}
    end
  end

  defp handle_relay_message(["OK", event_id, accepted?, reason], s) do
    notify(s, {:ok, event_id, accepted?, reason})
    s
  end

  defp handle_relay_message(["AUTH", challenge], s) when is_binary(challenge) do
    event =
      Event.new(%{
        created_at: System.os_time(:second),
        kind: 22242,
        tags: [["relay", s.url], ["challenge", challenge]],
        content: ""
      })

    signed = s.signer.(event)
    s = send_frame(s, ["AUTH", Event.to_map(signed)])
    %{s | pending_auth: signed.id}
  end

  defp handle_relay_message(_other, s), do: s

  # --- sending -----------------------------------------------------------

  defp resubscribe(s), do: Enum.reduce(s.subs, s, fn {sub_id, filters}, acc -> send_req(acc, sub_id, filters) end)

  defp send_req(s, sub_id, filters), do: send_frame(s, ["REQ", sub_id | Enum.map(filters, &Filter.to_map/1)])

  defp send_frame(s, term), do: send_raw(s, {:text, Jason.encode!(term)})

  defp send_raw(%{websocket: nil} = s, _frame), do: s

  defp send_raw(s, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(s.websocket, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(s.conn, s.ref, data) do
      %{s | websocket: websocket, conn: conn}
    else
      {:error, %Mint.WebSocket{} = websocket, reason} -> lost(%{s | websocket: websocket}, reason)
      {:error, conn, reason} -> lost(%{s | conn: conn}, reason)
    end
  end

  # --- loss + backoff ----------------------------------------------------

  defp lost(s, reason) do
    if s.conn, do: Mint.HTTP.close(s.conn)
    if s.status == :connected, do: Log.warning(:nostr, "lost #{s.url}: #{inspect(reason)}")
    notify(s, {:disconnected, reason})
    Process.send_after(self(), :reconnect, s.current_backoff)

    %{
      s
      | conn: nil, websocket: nil, ref: nil, http_status: nil, resp_headers: nil, pending_auth: nil,
        status: :disconnected, current_backoff: min(s.current_backoff * 2, s.max_backoff_ms)
    }
  end

  defp notify(s, message), do: send(s.owner, {:nostr, s.url, message})
end
```

Fix the sketch's two sloppy lines while implementing: `handle_relay_message(["EOSE", ...])` and the `NOTICE`/`CLOSED` clauses should be plain two-line bodies (`notify(...)` then `s`), no `then`. Also `lost/2` must not double-close: only call `Mint.HTTP.close/1` when `s.conn` is not nil, and guard against a `:reconnect` arriving while already connected (ignore it: `def handle_info(:reconnect, %{conn: conn} = s) when not is_nil(conn), do: {:noreply, s}` before the generic clause). Verify every `Mint.WebSocket` call against the dep source. `Log.debug/3` exists (added in the title-convergence work).

Export `Connection` from `lib/media_centaur/nostr.ex` (`exports: [Connection, Event, Filter, Keys]`).

- [ ] **Step 5: Run, format, credo, commit** — `mix test test/media_centaur/nostr && mix compile --warnings-as-errors && mix format && mix credo --strict`. If a reconnect test is timing-sensitive, raise the `assert_receive` timeout rather than sleeping. Commit `feat(nostr): Connection — one authenticated relay WebSocket per URL, with a fake relay for tests`.

---

### Task 2: `Friends.Relay` + events + `friends:connections` topic

**Files:** `priv/repo/migrations/20260902160000_add_relays.exs`, `lib/media_centaur/friends/relay.ex`, `lib/media_centaur/friends.ex`, `lib/media_centaur/friends/events.ex`, `lib/media_centaur/topics.ex`, `test/media_centaur/friends/relay_test.exs`

- [ ] **Step 1: Failing tests**

```elixir
defmodule MediaCentaur.Friends.RelayTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Events.{RelayAdded, RelayRemoved}
  alias MediaCentaur.Friends.Relay

  describe "add_relay/1" do
    test "stores a ws/wss URL, normalized, and broadcasts" do
      Friends.subscribe()
      assert {:ok, %Relay{url: "wss://relay.example/"}} = Friends.add_relay("wss://relay.example/")
      assert_receive {:relay_added, %RelayAdded{url: "wss://relay.example/"}}, 500
      assert {:ok, %Relay{url: "ws://127.0.0.1:7777/"}} = Friends.add_relay("  ws://127.0.0.1:7777  ")
      assert [%Relay{url: "ws://127.0.0.1:7777/"}, %Relay{url: "wss://relay.example/"}] = Friends.list_relays()
    end

    test "is idempotent on the same URL" do
      {:ok, a} = Friends.add_relay("wss://relay.example")
      {:ok, b} = Friends.add_relay("wss://relay.example/")
      assert a.id == b.id
      assert length(Friends.list_relays()) == 1
    end

    test "rejects non-websocket or hostless URLs" do
      for bad <- ["https://relay.example", "relay.example", "wss://", "wss://user:pw@relay.example", ""] do
        assert {:error, %Ecto.Changeset{}} = Friends.add_relay(bad), bad
      end
    end
  end

  describe "remove_relay/1" do
    test "removes by URL and broadcasts; absent is a no-op" do
      {:ok, _} = Friends.add_relay("wss://relay.example")
      Friends.subscribe()
      assert :ok = Friends.remove_relay("wss://relay.example/")
      assert_receive {:relay_removed, %RelayRemoved{url: "wss://relay.example/"}}, 500
      assert Friends.list_relays() == []
      assert :ok = Friends.remove_relay("wss://relay.example/")
      refute_receive {:relay_removed, _}, 100
    end
  end
end
```

- [ ] **Step 2: Migration**

```elixir
defmodule MediaCentaur.Repo.Migrations.AddRelays do
  @moduledoc "The user's Nostr relay list. Connection state is runtime, never a column."
  use Ecto.Migration

  def change do
    create table(:relays, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :url, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:relays, [:url])
  end
end
```

- [ ] **Step 3: Schema**

```elixir
defmodule MediaCentaur.Friends.Relay do
  @moduledoc """
  One configured relay: a `ws://` or `wss://` URL, normalized (trimmed,
  no userinfo, path defaults to `/`). Connection state is runtime
  (`Friends.Connections.status/0`), never stored.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "relays" do
    field :url, :string
    timestamps()
  end

  @type t :: %__MODULE__{}

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:url])
    |> update_change(:url, &normalize/1)
    |> validate_required([:url])
    |> validate_change(:url, fn :url, url -> if valid?(url), do: [], else: [url: "must start with wss:// or ws://"] end)
    |> unique_constraint(:url)
  end

  @doc "Trims and canonicalizes a relay URL; returns the input unchanged when it does not parse."
  @spec normalize(String.t()) :: String.t()
  def normalize(url) when is_binary(url) do
    trimmed = String.trim(url)

    case URI.parse(trimmed) do
      %URI{scheme: scheme, host: host} = uri when scheme in ["ws", "wss"] and is_binary(host) and host != "" ->
        URI.to_string(%{uri | path: uri.path || "/"})

      _ ->
        trimmed
    end
  end

  defp valid?(url) do
    case URI.parse(url) do
      %URI{scheme: s, host: h, userinfo: nil} when s in ["ws", "wss"] and is_binary(h) and h != "" -> true
      _ -> false
    end
  end
end
```

- [ ] **Step 4: Context, events, topic**

`friends/events.ex`: add `RelayAdded{url}` and `RelayRemoved{url}` structs (same shape as `IdentityChanged`), `@type t` union, `broadcast/1` clauses publishing `{:relay_added, event}` / `{:relay_removed, event}`.

`friends.ex`: `exports` add `Relay, Events.RelayAdded, Events.RelayRemoved, Connections`; add

```elixir
  alias MediaCentaur.Friends.{Events, Relay}
  alias MediaCentaur.Repo
  import Ecto.Query

  @doc "Adds a relay URL (idempotent on the normalized URL)."
  @spec add_relay(String.t()) :: {:ok, Relay.t()} | {:error, Ecto.Changeset.t()}
  def add_relay(url) when is_binary(url) do
    normalized = Relay.normalize(url)

    case Repo.get_by(Relay, url: normalized) do
      %Relay{} = existing -> {:ok, existing}
      nil ->
        case Repo.insert(Relay.create_changeset(%{url: url})) do
          {:ok, relay} ->
            Events.broadcast(%Events.RelayAdded{url: relay.url})
            {:ok, relay}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            if Enum.any?(errors, fn {_f, {_m, meta}} -> meta[:constraint] == :unique end),
              do: {:ok, Repo.get_by!(Relay, url: normalized)},
              else: {:error, changeset}
        end
    end
  end

  @spec remove_relay(String.t()) :: :ok
  def remove_relay(url) when is_binary(url) do
    case Repo.get_by(Relay, url: Relay.normalize(url)) do
      nil -> :ok
      relay ->
        Repo.delete!(relay)
        Events.broadcast(%Events.RelayRemoved{url: relay.url})
        :ok
    end
  end

  @spec list_relays() :: [Relay.t()]
  def list_relays, do: Repo.all(from(r in Relay, order_by: r.url))
```

The Friends Boundary gains `deps: [MediaCentaur.Nostr]` only; `Repo` is top-level (check how `Discovery` declares it — if `MediaCentaur.Repo` must be listed, list it).

`topics.ex`: add `def friends_connections, do: "friends:connections"` and a moduledoc row: `friends:connections` | `Friends.Connections.Owner` — `{:relay_connection, url, message}` re-broadcast of `Nostr.Connection` owner messages.

- [ ] **Step 5:** `mix test test/media_centaur/friends && mix compile --warnings-as-errors && mix format && mix credo --strict`; then `mix ecto.migrate` on the dev DB. Commit `feat(friends): Relay — the configured relay list, with typed events`.

---

### Task 3: `Friends.Connections`

**Files:** `lib/media_centaur/friends/connections.ex`, `lib/media_centaur/friends/connections/owner.ex`, `lib/media_centaur/application.ex`, `config/test.exs`, `test/support/global_state_sandbox.ex`, `test/media_centaur/friends/connections_test.exs`

- [ ] **Step 1: Failing tests** — the owner is not started under `:test`; tests start one by hand against fake relays.

```elixir
defmodule MediaCentaur.Friends.ConnectionsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.{Connections, Identity}
  alias MediaCentaur.Nostr.FakeRelay

  setup do
    Identity.ensure()
    owner = start_supervised!({Connections.Owner, backoff_ms: 50})
    Connections.Owner.__sync_for_test__(owner)
    %{owner: owner}
  end

  test "connects to every relay row at boot and reports status" do
    relay = FakeRelay.start()
    {:ok, _} = Friends.add_relay(relay.url)
    # the add broadcast reaches the owner; give it a sync point
    Connections.Owner.__sync_for_test__()
    Friends.subscribe_connections()
    assert_receive {:relay_connection, url, :connected}, 3_000
    assert url == relay.url
    assert %{^url => %{state: :connected}} = Connections.status()
  end

  test "removing a relay stops its connection" do
    relay = FakeRelay.start()
    {:ok, _} = Friends.add_relay(relay.url)
    Friends.subscribe_connections()
    assert_receive {:relay_connection, _url, :connected}, 3_000

    :ok = Friends.remove_relay(relay.url)
    Connections.Owner.__sync_for_test__()
    refute Map.has_key?(Connections.status(), relay.url)
  end

  test "an auth-required relay is authenticated with the identity" do
    relay = FakeRelay.start(auth: true)
    {:ok, _} = Friends.add_relay(relay.url)
    Friends.subscribe_connections()
    assert_receive {:relay_connection, _url, {:auth, :ok}}, 3_000
    assert_receive {:relay_in, ["AUTH", %{"pubkey" => pubkey}]}, 3_000
    assert pubkey == Identity.pubkey()
  end

  test "identity replacement restarts the connections" do
    relay = FakeRelay.start()
    {:ok, _} = Friends.add_relay(relay.url)
    Friends.subscribe_connections()
    assert_receive {:relay_connection, _url, :connected}, 3_000

    :ok = Identity.import_nsec(MediaCentaur.Nostr.Keys.to_nsec(MediaCentaur.Nostr.Keys.generate()))
    Connections.Owner.__sync_for_test__()
    assert_receive {:relay_connection, _url, :connected}, 3_000
  end

  test "status/0 is empty when no owner runs" do
    stop_supervised!(Connections.Owner)
    assert Connections.status() == %{}
  end

  test "a relay that rejects publishes surfaces the reason as last_error" do
    relay = FakeRelay.start(accept: false, reason: "blocked: not on the allowlist")
    {:ok, _} = Friends.add_relay(relay.url)
    Friends.subscribe_connections()
    assert_receive {:relay_connection, url, :connected}, 3_000

    event = MediaCentaur.Nostr.Event.sign(MediaCentaur.Nostr.Event.new(%{created_at: 1, kind: 1, tags: [], content: "x"}), Identity.secret())
    Connections.publish(event)
    assert_receive {:relay_connection, ^url, {:ok, _id, false, "blocked: not on the allowlist"}}, 3_000
    assert %{^url => %{last_error: "blocked: not on the allowlist"}} = Connections.status()
  end
end
```

The `FakeRelay.start/1` helper registers the *test* process as the frame recipient; in these tests the owner is the connection's owner, so `{:relay_in, …}` still arrives at the test (the fake relay sends to `test_pid`) — that is why the auth test can see the AUTH frame.

- [ ] **Step 2: Supervisor + owner**

`lib/media_centaur/friends/connections.ex`:

```elixir
defmodule MediaCentaur.Friends.Connections do
  @moduledoc """
  One `Nostr.Connection` per configured relay, kept in step with the
  `relays` table: a Registry (keyed by URL), a DynamicSupervisor, and
  an owner process (`Connections.Owner`) that reconciles on boot and on
  `RelayAdded` / `RelayRemoved` / `IdentityChanged`, receives every
  connection's messages, and re-broadcasts them on `friends:connections`.

  Under `:test` the owner is not started (`:start_relay_connections`
  is false); tests start it by hand against `Nostr.FakeRelay`.
  """
  use Supervisor

  alias MediaCentaur.Friends.Connections.Owner

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    owner = if Application.get_env(:media_centaur, :start_relay_connections, true), do: [Owner], else: []

    children =
      [
        {Registry, keys: :unique, name: __MODULE__.Registry},
        {DynamicSupervisor, name: __MODULE__.DynamicSupervisor, strategy: :one_for_one}
      ] ++ owner

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 5, max_seconds: 60)
  end

  @doc "`%{url => %{state: Nostr.Connection.status(), last_error: String.t() | nil}}`; empty when no owner runs."
  @spec status() :: %{optional(String.t()) => %{state: atom(), last_error: String.t() | nil}}
  def status, do: Owner.status()

  @doc "Publishes a signed event to every connected relay."
  @spec publish(MediaCentaur.Nostr.Event.t()) :: :ok
  def publish(event), do: Owner.publish(event)

  @doc "Subscribes every connection with the same filters under `sub_id` (re-applied to connections started later)."
  @spec subscribe_all(String.t(), [MediaCentaur.Nostr.Filter.t()]) :: :ok
  def subscribe_all(sub_id, filters), do: Owner.subscribe_all(sub_id, filters)

  @doc "Publishes to one relay; a no-op unless that relay is connected."
  @spec publish(String.t(), MediaCentaur.Nostr.Event.t()) :: :ok
  def publish(url, event), do: Owner.publish(url, event)

  @doc "Subscribes one relay under `sub_id` (per-relay; re-applied if that connection restarts)."
  @spec subscribe(String.t(), String.t(), [MediaCentaur.Nostr.Filter.t()]) :: :ok
  def subscribe(url, sub_id, filters), do: Owner.subscribe(url, sub_id, filters)

  def via(url), do: {:via, Registry, {__MODULE__.Registry, url}}
end
```

The per-relay `publish/2` and `subscribe/3` exist for the recommendations sync (layer 6): after a relay's own-events `EOSE`, the sync publishes only what **that** relay lacks, so fan-out is wrong there. The owner keeps two subscription maps — `subs` (global, from `subscribe_all/2`) and `relay_subs` (`%{url => %{sub_id => filters}}`, from `subscribe/3`) — and re-applies both when a connection (re)starts. `Nostr.Connection` itself stores subscriptions and issues them on connect, so subscribing a not-yet-connected relay is safe; publishing to one is not, hence the connected-only guard on both `publish/1` and `publish/2`. Add the corresponding `Owner.publish/2`, `Owner.subscribe/3` (`GenServer.cast`), their `handle_cast` clauses, the `relay_subs` field, and the re-apply in `start/2`; and a test in `connections_test.exs`:

```elixir
  test "publish/2 and subscribe/3 address one relay" do
    a = FakeRelay.start()
    b = FakeRelay.start()
    {:ok, _} = Friends.add_relay(a.url)
    {:ok, _} = Friends.add_relay(b.url)
    Friends.subscribe_connections()
    assert_receive {:relay_connection, _, :connected}, 3_000
    assert_receive {:relay_connection, _, :connected}, 3_000

    Connections.subscribe(a.url, "only-a", [MediaCentaur.Nostr.Filter.new(kinds: [1])])
    assert_receive {:relay_in, ["REQ", "only-a", _]}, 2_000
    refute_receive {:relay_in, ["REQ", "only-a", _]}, 300

    event = MediaCentaur.Nostr.Event.sign(MediaCentaur.Nostr.Event.new(%{created_at: 1, kind: 1, tags: [], content: "x"}), Identity.secret())
    Connections.publish(b.url, event)
    assert_receive {:relay_in, ["EVENT", %{"content" => "x"}]}, 2_000
    refute_receive {:relay_in, ["EVENT", _]}, 300
  end
```

(Both fake relays forward frames to the same test pid; the `refute_receive` after each positive assertion proves exactly one relay saw the frame.)

`lib/media_centaur/friends/connections/owner.ex`:

```elixir
defmodule MediaCentaur.Friends.Connections.Owner do
  @moduledoc false
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.{Connections, Identity}
  alias MediaCentaur.Nostr.{Connection, Event}
  alias MediaCentaur.Topics

  defstruct status: %{}, subs: %{}, backoff_ms: 1_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def status do
    case GenServer.whereis(__MODULE__) do
      nil -> %{}
      pid -> GenServer.call(pid, :status)
    end
  end

  def publish(%Event{} = event), do: GenServer.cast(__MODULE__, {:publish, event})
  def subscribe_all(sub_id, filters), do: GenServer.cast(__MODULE__, {:subscribe_all, sub_id, filters})

  @doc false
  def __sync_for_test__(server \\ __MODULE__), do: GenServer.call(server, :sync)

  @impl true
  def init(opts) do
    Friends.subscribe()
    {:ok, %__MODULE__{backoff_ms: Keyword.get(opts, :backoff_ms, 1_000)}, {:continue, :boot}}
  end

  @impl true
  def handle_continue(:boot, state), do: {:noreply, reconcile(state)}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_cast({:publish, event}, state) do
    for {url, %{state: :connected}} <- state.status, do: Connection.publish(Connections.via(url), event)
    {:noreply, state}
  end

  def handle_cast({:subscribe_all, sub_id, filters}, state) do
    for url <- Map.keys(state.status), do: Connection.subscribe(Connections.via(url), sub_id, filters)
    {:noreply, %{state | subs: Map.put(state.subs, sub_id, filters)}}
  end

  @impl true
  def handle_info({:relay_added, _}, state), do: {:noreply, reconcile(state)}
  def handle_info({:relay_removed, _}, state), do: {:noreply, reconcile(state)}
  def handle_info({:identity_changed, _}, state), do: {:noreply, state |> stop_all() |> reconcile()}

  def handle_info({:nostr, url, message}, state) do
    Topics.publish(Topics.friends_connections(), {:relay_connection, url, message})
    {:noreply, %{state | status: Map.update(state.status, url, entry(message), &apply_message(&1, message))}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # --- reconcile ---------------------------------------------------------

  defp reconcile(state) do
    wanted = if Identity.present?(), do: MapSet.new(Friends.list_relays(), & &1.url), else: MapSet.new()
    running = MapSet.new(Registry.select(Connections.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}]))

    for url <- MapSet.difference(running, wanted), do: stop(url)
    for url <- MapSet.difference(wanted, running), do: start(url, state)

    status =
      state.status
      |> Map.take(MapSet.to_list(wanted))
      |> then(fn s -> Enum.reduce(wanted, s, fn url, acc -> Map.put_new(acc, url, %{state: :connecting, last_error: nil}) end) end)

    %{state | status: status}
  end

  defp start(url, state) do
    spec = {Connection, url: url, owner: self(), signer: &sign/1, backoff_ms: state.backoff_ms, name: Connections.via(url)}

    case DynamicSupervisor.start_child(Connections.DynamicSupervisor, spec) do
      {:ok, pid} ->
        for {sub_id, filters} <- state.subs, do: Connection.subscribe(pid, sub_id, filters)
        :ok

      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> Log.warning(:friends, "could not start relay connection #{url}: #{inspect(reason)}")
    end
  end

  defp stop(url) do
    case Registry.lookup(Connections.Registry, url) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Connections.DynamicSupervisor, pid)
      [] -> :ok
    end
  end

  defp stop_all do
    for {url, _} <- status_map_from_registry(), do: stop(url)
  end
  # (write `stop_all/1` taking and returning state with `status: %{}`; the sketch above is shape only)

  defp sign(%Event{} = event), do: Event.sign(event, Identity.secret())

  # --- status bookkeeping ------------------------------------------------

  defp entry(message), do: apply_message(%{state: :connecting, last_error: nil}, message)

  defp apply_message(entry, :connected), do: %{entry | state: :connected, last_error: nil}
  defp apply_message(entry, {:disconnected, reason}), do: %{entry | state: :disconnected, last_error: format(reason)}
  defp apply_message(entry, {:auth, :ok}), do: %{entry | state: :connected}
  defp apply_message(entry, {:auth, {:failed, reason}}), do: %{entry | state: :auth_failed, last_error: reason}
  defp apply_message(entry, {:ok, _id, false, reason}), do: %{entry | last_error: reason}
  defp apply_message(entry, {:notice, text}), do: %{entry | last_error: text}
  defp apply_message(entry, _other), do: entry

  defp format(reason) when is_binary(reason), do: reason
  defp format(reason), do: inspect(reason)
end
```

Write `stop_all/1` properly (iterate the Registry, terminate each, return `%{state | status: %{}}`). `Registry.select/2` match spec: confirm the tuple shape `{key, pid, value}` in the Registry docs. The owner's `reconcile/1` reads the DB (`Friends.list_relays/0`) in `handle_continue` — after Repo is up. `Friends.subscribe_connections/0` facade: add to `friends.ex` (`Topics.subscribe(Topics.friends_connections())`).

- [ ] **Step 3: Wire into the app**

- `application.ex`: add `MediaCentaur.Friends.Connections` to the children after `{Task.Supervisor, …}` (near `Watcher.Supervisor`); add `MediaCentaur.Friends` to the application Boundary `deps:` list.
- `config/test.exs`: `config :media_centaur, :start_relay_connections, false` next to `:start_watchers`.
- `test/support/global_state_sandbox.ex` `@dispositions`: `MediaCentaur.Friends.Connections => {:stateless, "relay connections are not started under :test"}`.
- Boundary: `Friends` deps become `[MediaCentaur.Nostr]` (+ `MediaCentaur.Repo` if needed); `Friends.Connections`/`Owner` are inside the Friends boundary and use `Topics` (top-level, no dep needed — confirm).

- [ ] **Step 4:** `mix test test/media_centaur/friends test/media_centaur/global_state_sandbox_test.exs && mix compile --warnings-as-errors && mix format && mix credo --strict && mix boundaries`. Commit `feat(friends): Connections — one relay connection per row, reconciled on boot and on change`.

---

### Task 4: Relay block on the Friends tab

**Files:** `lib/media_centaur_web/live/discovery_live/relay_block.ex`, `lib/media_centaur_web/live/discovery_live.ex`, `test/media_centaur_web/live/discovery_live_test.exs`

- [ ] **Step 1: Failing tests** (add to the `friends tab` describe):

```elixir
    test "lists relays with their connection state, adds by URL, and removes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")

      view |> form("#add-relay-form", %{"url" => "wss://relay.example"}) |> render_submit()
      assert has_element?(view, "#relay-wss-relay-example", "wss://relay.example/")
      assert has_element?(view, "#relay-wss-relay-example", "Not connected")
      assert [%{url: "wss://relay.example/"}] = Friends.list_relays()

      view |> element("#relay-wss-relay-example button", "Remove") |> render_click()
      refute has_element?(view, "#relay-wss-relay-example")
      assert Friends.list_relays() == []
    end

    test "an invalid relay address is refused with a flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      view |> form("#add-relay-form", %{"url" => "https://relay.example"}) |> render_submit()
      assert render(view) =~ "Relay addresses start with wss:// or ws://"
      assert Friends.list_relays() == []
    end

    test "connection state updates live from friends:connections", %{conn: conn} do
      {:ok, _} = Friends.add_relay("wss://relay.example")
      {:ok, view, _html} = live(conn, "/discovery/friends")
      assert has_element?(view, "#relay-wss-relay-example", "Not connected")

      # Simulate the owner's re-broadcast (the owner itself is not running under :test).
      MediaCentaur.Topics.publish(MediaCentaur.Topics.friends_connections(), {:relay_connection, "wss://relay.example/", :connected})
      render_until(view, fn _ -> has_element?(view, "#relay-wss-relay-example", "Connected") end)

      MediaCentaur.Topics.publish(MediaCentaur.Topics.friends_connections(), {:relay_connection, "wss://relay.example/", {:auth, {:failed, "not on the allowlist"}}})
      render_until(view, fn _ -> has_element?(view, "#relay-wss-relay-example", "Rejected") end)
      assert has_element?(view, "#relay-wss-relay-example", "not on the allowlist")
    end
```

(`Topics.publish` from a test is fine; MC0025 targets `lib/`. If the check covers tests too, publish through a tiny test helper that the check exempts, or via `Friends.Events`-style helper — read the check.) The element id is derived from the URL: `"relay-" <> (url |> String.replace(~r/[^a-z0-9]+/i, "-") |> String.trim("-"))` — write `RelayBlock.dom_id/1` and use it in tests via the same function.

- [ ] **Step 2: LiveView** — `discovery_live.ex`:
- mount: `Friends.subscribe_connections()` under `connected?`; assigns `relays: []`, `relay_status: %{}`.
- `handle_params` for `:friends`: also `assign(relays: Friends.list_relays(), relay_status: Connections.status())`.
- events: `"add_relay"` with `%{"url" => url}` → `Friends.add_relay(url)`; `{:ok, _}` → reload `relays`; `{:error, _}` → flash `"Relay addresses start with wss:// or ws://"`. `"remove_relay"` with `%{"url" => url}` → `Friends.remove_relay(url)`; reload.
- `handle_info({:relay_added, _} | {:relay_removed, _}, socket)` → reload relays (when on `:friends`). `handle_info({:relay_connection, url, message}, socket)` → update `relay_status[url]` with the same `apply_message/2` rules as the owner — put that function in `Friends.Connections` as a public `apply_message/2` (owner and LiveView share it; no duplication) and export it.
- render the friends pane: identity block, then `<RelayBlock.relay_block relays={@relays} status={@relay_status} />`.

- [ ] **Step 3: Component** — `lib/media_centaur_web/live/discovery_live/relay_block.ex`:

```elixir
defmodule MediaCentaurWeb.DiscoveryLive.RelayBlock do
  @moduledoc "The Friends tab's relay block: the list with live state, add by URL, remove. Iteration-phase component (no story yet)."
  use MediaCentaurWeb, :html

  alias MediaCentaur.Friends.Relay

  attr :relays, :list, required: true, doc: "`Relay.t()` in URL order"
  attr :status, :map, required: true, doc: "`Friends.Connections.status/0` — `%{url => %{state, last_error}}`"

  def relay_block(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-5 space-y-4" data-component="relay-block">
      <div class="space-y-1">
        <h2 class="text-sm font-semibold">Relays</h2>
        <p class="text-xs text-base-content/50">
          The servers your recommendations are published to and read from. Your group's own relay first; public relays are more entries.
        </p>
      </div>

      <ul class="space-y-2">
        <li :for={relay <- @relays} id={dom_id(relay.url)} class="flex items-center gap-3 rounded-md bg-base-content/5 px-3 py-2">
          <code class="min-w-0 flex-1 truncate text-xs">{relay.url}</code>
          <span class="shrink-0 text-xs text-base-content/60">{state_label(@status[relay.url])}</span>
          <span :if={last_error(@status[relay.url])} class="min-w-0 truncate text-xs text-base-content/40">{last_error(@status[relay.url])}</span>
          <button type="button" class="shrink-0 cursor-pointer text-xs text-base-content/30 hover:text-base-content/60" phx-click="remove_relay" phx-value-url={relay.url}>
            Remove
          </button>
        </li>
      </ul>

      <form id="add-relay-form" phx-submit="add_relay" class="flex items-center gap-2">
        <input type="text" name="url" placeholder="wss://relay.example" class="library-filter min-w-0 flex-1" autocomplete="off" />
        <.button type="submit" variant="neutral" size="sm">Add relay</.button>
      </form>
    </section>
    """
  end

  @doc "A DOM id for a relay URL."
  def dom_id(url), do: "relay-" <> (url |> String.replace(~r/[^a-z0-9]+/i, "-") |> String.trim("-") |> String.downcase())

  defp state_label(%{state: :connected}), do: "Connected"
  defp state_label(%{state: :connecting}), do: "Connecting"
  defp state_label(%{state: :auth_failed}), do: "Rejected"
  defp state_label(_absent_or_disconnected), do: "Not connected"

  defp last_error(%{last_error: error}) when is_binary(error), do: error
  defp last_error(_), do: nil
end
```

Check `Relay` is exported from the Friends boundary and that `library-filter` is the input class Settings uses (`settings_live.ex` media-dir form); MC0011/`no_phx_value_value` and `raw_button_class` checks — read them if credo flags the raw `<button>`; use `<.button variant="dismiss" size="xs">` if the raw class is forbidden.

- [ ] **Step 4:** `mix format && mix compile --warnings-as-errors && mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/page_smoke_test.exs && mix credo --strict && mix boundaries`. Real-browser check of `/discovery/friends` via `page-shot`. Commit `feat(discovery): relay block on the Friends tab`.

---

### Task 5: Precommit + campaign

- [ ] `mix precommit` PASSED (the fake relay binds loopback ports in tests; if the suite's parallelism produces port exhaustion or a flake in `connection_test.exs`, mark that module `async: false` and report).
- [ ] `campaigns/friends-recommendations.md` Status: "Layer 4 (relay connections: `Nostr.Connection`, `FakeRelay`, `Friends.Relay`, `Friends.Connections`, relay block) landed 2026-09-02; next: layer 5 (roster)." Next steps: add "**Status page Friends section** (layer 7) reads `Friends.Connections.status/0` — health + counts only."
- [ ] Commit `docs(campaign): relay connections landed; next = friend roster`.

---

## Self-review

**Spec coverage:** `Nostr.Connection` API + owner messages + NIP-42 + backoff + resubscribe → Task 1; `Friends.Relay` schema/API → Task 2; `Friends.Connections` (Registry+DynamicSupervisor+owner, boot reconcile, add/remove/identity reaction, `status/0`, `friends:connections` re-broadcast) → Task 3; Friends tab relay block with per-relay state + last error, add/remove → Task 4; fake relay → Task 1; no connections without an identity (`reconcile/1` checks `Identity.present?/0`) → Task 3.

**Type consistency:** `Connection.start_link/1` opts `url, owner, signer, backoff_ms, max_backoff_ms, name`; `publish/2`, `subscribe/3`, `unsubscribe/2`, `status/1`; owner messages as listed; `FakeRelay.start/1 :: %{url, name}`, `push/2`, `drop/1`; `Friends.add_relay/1`, `remove_relay/1`, `list_relays/0`, `subscribe_connections/0`; `Connections.status/0`, `publish/1`, `subscribe_all/2`, `via/1`, `apply_message/2`; `Owner.__sync_for_test__/1`; events `RelayAdded{url}`/`RelayRemoved{url}` as `{:relay_added, e}`/`{:relay_removed, e}`; topic `friends:connections` messages `{:relay_connection, url, message}`; LiveView events `add_relay`, `remove_relay`; `RelayBlock.dom_id/1`.

**Placeholders:** the Owner sketch flags two functions to write out properly (`stop_all/1`, the `Registry.select` shape); everything else is complete.
