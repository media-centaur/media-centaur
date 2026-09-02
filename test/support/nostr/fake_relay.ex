defmodule MediaCentaur.Nostr.FakeRelay do
  @moduledoc """
  An in-process Nostr relay for tests: a `WebSock` handler under Bandit
  on an ephemeral loopback port. Speaks the subset `Nostr.Connection`
  uses — `EVENT` → `OK`, `REQ` → stored matches then `EOSE`, `CLOSE`,
  `AUTH` (optional challenge on connect; `REQ`/`EVENT` refused until a
  valid kind-22242 answer) — and forwards every inbound frame to the
  test process as `{:relay_in, decoded}`. `push/2` sends any frame to
  the connected client; `drop/1` closes the socket (reconnect tests).

      relay = FakeRelay.start(auth: false, events: [])
      relay.url            # "ws://127.0.0.1:PORT/"

  `push/2` and `drop/1` are called from the test process right after it
  observes `:connected`, which races Bandit's own bookkeeping: the 101
  upgrade response goes out, and `Connection` reports `:connected`,
  before this handler's `init/1` has registered the socket pid in the
  Agent. Both functions poll for at least one registered client (up to
  2s, 10ms steps) before sending, and raise if none shows up in time.
  """

  alias MediaCentaur.Nostr.Event

  defmodule State do
    @moduledoc false
    defstruct [
      :test_pid,
      :name,
      auth: false,
      authed?: false,
      challenge: nil,
      events: [],
      accept: true,
      reason: ""
    ]
  end

  @behaviour WebSock

  @type t :: %{url: String.t(), name: atom()}

  # --- lifecycle ---------------------------------------------------------

  @doc """
  Starts a relay under the test supervisor. Options: `auth: boolean`
  (issue an AUTH challenge on connect and gate REQ/EVENT on it),
  `events: [Event.t()]` (stored events served to matching REQs),
  `accept: boolean` / `reason: String.t()` (the OK verdict for EVENT).
  Returns `%{url: String.t(), name: atom()}`.

  Must be called from the test process — the relay's lifetime is the
  test's, and inbound frames are forwarded to the caller.
  """
  @spec start(keyword()) :: t()
  def start(opts \\ []) do
    name = :"fake_relay_#{System.unique_integer([:positive])}"
    config = opts |> Map.new() |> Map.merge(%{test_pid: self(), clients: []})

    ExUnit.Callbacks.start_supervised!(%{
      id: {__MODULE__, :agent, name},
      start: {Agent, :start_link, [fn -> config end, [name: name]]}
    })

    bandit =
      {Bandit,
       plug: {__MODULE__.Plug, name}, port: 0, ip: {127, 0, 0, 1}, scheme: :http, startup_log: false}

    {:ok, pid} =
      ExUnit.Callbacks.start_supervised(Supervisor.child_spec(bandit, id: {__MODULE__, :bandit, name}))

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    %{url: "ws://127.0.0.1:#{port}/", name: name}
  end

  @doc "Sends a raw frame (an Elixir term, JSON-encoded) to every connected client."
  @spec push(t(), term()) :: :ok
  def push(relay, frame) do
    for pid <- await_clients(relay), do: send(pid, {:push, frame})
    :ok
  end

  @doc "Closes every client socket (the relay stays up, so the client can reconnect)."
  @spec drop(t()) :: :ok
  def drop(relay) do
    for pid <- await_clients(relay), do: send(pid, :drop)
    :ok
  end

  @await_client_timeout_ms 2_000
  @await_client_interval_ms 10

  # `init/1` registers the socket pid asynchronously relative to the test
  # process observing `:connected` — see moduledoc. Poll instead of trusting
  # `clients` to be populated yet.
  defp await_clients(%{name: name}) do
    poll_clients(name, System.monotonic_time(:millisecond) + @await_client_timeout_ms)
  end

  defp poll_clients(name, deadline) do
    case Agent.get(name, & &1.clients) do
      [] -> retry_or_raise(name, deadline)
      clients -> clients
    end
  end

  defp retry_or_raise(name, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(@await_client_interval_ms)
      poll_clients(name, deadline)
    else
      raise "FakeRelay: no client registered within #{@await_client_timeout_ms}ms"
    end
  end

  # --- WebSock -----------------------------------------------------------

  @impl true
  def init(name) do
    config = Agent.get(name, & &1)
    # `Agent.update/2` runs the fun inside the Agent, so `self()` there is the
    # Agent — capture this socket's pid out here.
    socket = self()
    Agent.update(name, &%{&1 | clients: [socket | &1.clients]})

    state = %State{
      test_pid: config.test_pid,
      name: name,
      auth: Map.get(config, :auth, false),
      events: Map.get(config, :events, []),
      accept: Map.get(config, :accept, true),
      reason: Map.get(config, :reason, "")
    }

    if state.auth do
      challenge = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      {:push, text(["AUTH", challenge]), %{state | challenge: challenge}}
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
  def handle_info({:push, frame}, state), do: {:push, text(frame), state}
  def handle_info(:drop, state), do: {:stop, :normal, state}
  def handle_info(_other, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    socket = self()

    if Process.whereis(state.name) do
      Agent.update(state.name, &%{&1 | clients: List.delete(&1.clients, socket)})
    end

    :ok
  end

  # --- frames ------------------------------------------------------------

  defp handle_frame(["AUTH", event_map], state) do
    with {:ok, event} <- Event.from_map(event_map),
         :ok <- Event.verify(event),
         22_242 <- event.kind,
         true <- Event.tag_value(event, "challenge") == state.challenge do
      {:push, text(["OK", event.id, true, ""]), %{state | authed?: true}}
    else
      _other ->
        id = if is_map(event_map), do: Map.get(event_map, "id", ""), else: ""
        {:push, text(["OK", id, false, "auth-required: bad challenge"]), state}
    end
  end

  defp handle_frame([kind | _rest] = frame, %State{auth: true, authed?: false} = state)
       when kind in ["REQ", "EVENT"] do
    reply =
      case frame do
        ["EVENT", %{"id" => id}] -> ["OK", id, false, "auth-required: not authenticated"]
        ["REQ", sub_id | _filters] -> ["CLOSED", sub_id, "auth-required: not authenticated"]
      end

    {:push, text(reply), state}
  end

  defp handle_frame(["EVENT", %{"id" => id} = event_map], state) do
    stored =
      case Event.from_map(event_map) do
        {:ok, event} when state.accept -> [event | state.events]
        _other -> state.events
      end

    {:push, text(["OK", id, state.accept, state.reason]), %{state | events: stored}}
  end

  defp handle_frame(["REQ", sub_id | filters], state) do
    matches = Enum.filter(state.events, fn event -> Enum.any?(filters, &matches?(event, &1)) end)
    frames = Enum.map(matches, &text(["EVENT", sub_id, Event.to_map(&1)]))
    {:push, frames ++ [text(["EOSE", sub_id])], state}
  end

  defp handle_frame(["CLOSE", _sub_id], state), do: {:ok, state}
  defp handle_frame(_other, state), do: {:ok, state}

  defp text(frame), do: {:text, Jason.encode!(frame)}

  # authors / kinds / ids / #d only — enough for the tests
  defp matches?(event, filter) do
    Enum.all?(filter, fn
      {"authors", list} -> event.pubkey in list
      {"kinds", list} -> event.kind in list
      {"ids", list} -> event.id in list
      {"#" <> tag, list} -> Event.tag_value(event, tag) in list
      _other -> true
    end)
  end

  defmodule Plug do
    @moduledoc false
    @behaviour Elixir.Plug

    @impl Elixir.Plug
    def init(name), do: name

    @impl Elixir.Plug
    def call(conn, name) do
      conn
      |> WebSockAdapter.upgrade(MediaCentaur.Nostr.FakeRelay, name, timeout: 60_000)
      |> Elixir.Plug.Conn.halt()
    end
  end
end
