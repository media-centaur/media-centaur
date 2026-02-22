# 003 — MpvSession Shutdown Cascade Fix & Proper Supervision

## Context

`MpvSession` has a shutdown cascade problem. When playback ends naturally, MPV emits multiple sequential events (`eof-reached` → `end-file` → `tcp_closed` → `exit_status`). Each handler independently calls `persist_progress`, `broadcast_entity_progress`, and `broadcast_state_changed(:stopped)` — resulting in up to **4x duplicate DB writes and 4x PubSub broadcasts** for a single "video ended" event. The DB upsert is idempotent so correctness is preserved, but the waste is significant and the event stream is noisy for the UI.

Additionally, MpvSession processes are started via bare `start_link` from Manager — no supervisor. There is no `terminate/2` callback, so application shutdown can orphan MPV processes and lose final watch progress.

This plan fixes both issues: idempotent finalization and proper OTP supervision.

**Specifications:** `../specifications/PLAYBACK.md` (MPV lifecycle, progress persistence intervals, resume algorithm).

---

## 1. Idempotent Finalization in MpvSession

**File:** `lib/media_manager/playback/mpv_session.ex`

### Problem: Four shutdown paths, each doing full cleanup

Current shutdown handlers and what they each do:

| Handler | persist | broadcast entity | broadcast stopped | cleanup | stops GenServer |
|---------|---------|-----------------|-------------------|---------|-----------------|
| `eof-reached` | yes | yes | yes | no | no |
| `end-file` | yes | yes | yes | yes | no |
| `{:tcp_closed, _}` | yes | yes | yes | yes | yes |
| `{port, {:exit_status, _}}` | yes | yes | yes | yes | yes |

Natural end sequence: `eof-reached` → sends `["quit"]` → `end-file` → `tcp_closed` / `exit_status`. That's 4x persist, 4x broadcast, 3x cleanup for one event.

### Solution: Single `finalize/1` function with state guard

Add a private `finalize/1` function. It checks the session state — if already `:stopped`, it's a no-op. If `:playing` or `:paused`, it persists progress, broadcasts, and transitions to `:stopped`. If `:starting` (no progress to persist), it just transitions.

```elixir
defp finalize(%{state: state} = session) when state in [:playing, :paused] do
  persist_progress(session)
  broadcast_entity_progress(session)
  broadcast_state_changed(:stopped, session)
  %{session | state: :stopped}
end

defp finalize(session), do: %{session | state: :stopped}
```

### Revised shutdown handlers

All four handlers now call `finalize/1`. Only `tcp_closed` and `exit_status` return `{:stop, :normal, state}` to terminate the GenServer. The other two just update state.

**`eof-reached`** — finalize, then send quit command:
```elixir
defp handle_mpv_message(
       %{"event" => "property-change", "name" => "eof-reached", "data" => true},
       state
     ) do
  state = finalize(state)
  send_mpv_command(state.socket, ["quit"])
  state
end
```

**`end-file`** — finalize only (GenServer stays alive for port/socket events):
```elixir
defp handle_mpv_message(%{"event" => "end-file"}, state), do: finalize(state)
```

**`tcp_closed`** — finalize and stop (cleanup in `terminate/2`):
```elixir
def handle_info({:tcp_closed, _socket}, state) do
  Logger.info("MpvSession #{state.session_id}: socket closed")
  {:stop, :normal, finalize(state)}
end
```

**`exit_status`** — finalize and stop (cleanup in `terminate/2`):
```elixir
def handle_info({_port, {:exit_status, status}}, state) do
  Logger.info("MpvSession #{state.session_id}: MPV exited with status #{status}")
  {:stop, :normal, finalize(state)}
end
```

Remove all explicit `persist_progress`, `broadcast_entity_progress`, `broadcast_state_changed`, and `cleanup` calls from these four handlers.

### Late IPC messages after finalization

After `finalize/1` sets state to `:stopped`, stale `time-pos` property changes may still arrive on the socket. Add an early-return guard to the TCP data handler:

```elixir
def handle_info({:tcp, _socket, _data}, %{state: :stopped} = state), do: {:noreply, state}
```

Place this clause above the existing `{:tcp, _socket, data}` handler.

---

## 2. Add `terminate/2` and `trap_exit`

**File:** `lib/media_manager/playback/mpv_session.ex`

### `Process.flag(:trap_exit, true)` in `init/1`

Required so that `terminate/2` runs when the supervisor sends a shutdown signal. Add at the top of `init/1`:

```elixir
def init(params) do
  Process.flag(:trap_exit, true)
  # ... existing init code ...
end
```

### `terminate/2` callback

Guarantees final progress persistence and resource cleanup regardless of how the GenServer stops:

```elixir
@impl true
def terminate(_reason, state) do
  finalize(state)
  cleanup(state)
  :ok
end
```

`finalize/1` is idempotent — if already called during a shutdown handler, it's a no-op. `cleanup/1` is already effectively idempotent (`:gen_tcp.close` on a closed socket returns `{:error, :closed}`, `File.rm` on a missing file returns `{:error, :enoent}`).

### Remove explicit `cleanup` calls

Remove `cleanup(state)` from:
- The socket connect timeout path (line ~154) — let `terminate/2` handle it
- The `end-file` handler (line ~249) — already removed above
- The `tcp_closed` handler (line ~182) — already removed above
- The `exit_status` handler (line ~193) — already removed above

### Catch-all `handle_info`

With `trap_exit: true`, the Port link sends `{:EXIT, port, reason}` as a message when MPV exits. Add a catch-all to absorb this and any other unexpected messages:

```elixir
@impl true
def handle_info(_message, state), do: {:noreply, state}
```

### `child_spec/1`

Add so DynamicSupervisor knows the restart strategy:

```elixir
def child_spec(params) do
  %{
    id: __MODULE__,
    start: {__MODULE__, :start_link, [params]},
    restart: :temporary
  }
end
```

`:temporary` — crashed sessions are never restarted. The user must explicitly start a new play command.

---

## 3. Supervision Tree

### New file: `lib/media_manager/playback/session_supervisor.ex`

DynamicSupervisor for MpvSession processes:

```elixir
defmodule MediaManager.Playback.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for MpvSession processes.
  Sessions use :temporary restart — crashed sessions are not restarted.
  """
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_session(params) do
    DynamicSupervisor.start_child(__MODULE__, {MediaManager.Playback.MpvSession, params})
  end
end
```

### New file: `lib/media_manager/playback/supervisor.ex`

Groups Manager and SessionSupervisor. Uses `:one_for_all` — if SessionSupervisor crashes, Manager's session reference is invalid; if Manager crashes, any active session is orphaned. Both must restart together:

```elixir
defmodule MediaManager.Playback.Supervisor do
  @moduledoc """
  Top-level supervisor for the playback subsystem.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      MediaManager.Playback.SessionSupervisor,
      MediaManager.Playback.Manager
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
```

### Manager changes

**File:** `lib/media_manager/playback/manager.ex`

Replace `MpvSession.start_link(params)` with `SessionSupervisor.start_session(params)` in the `handle_call({:play, params}, ...)` clause:

```elixir
alias MediaManager.Playback.SessionSupervisor

def handle_call({:play, params}, _from, state) do
  case SessionSupervisor.start_session(params) do
    {:ok, pid} ->
      ref = Process.monitor(pid)
      # ... rest unchanged ...
  end
end
```

Manager keeps `Process.monitor/1` — it fires regardless of whether the session was started via DynamicSupervisor or bare `start_link`.

### Application.ex change

**File:** `lib/media_manager/application.ex`

Replace `MediaManager.Playback.Manager` with `MediaManager.Playback.Supervisor` in the children list:

```elixir
children = [
  # ...
  MediaManager.Playback.Supervisor,   # was: MediaManager.Playback.Manager
  MediaManagerWeb.Endpoint
]
```

### Resulting supervision tree

```
MediaManager.Supervisor (:one_for_one)
  ├── Telemetry, Repo, PubSub, Config, Watcher, Pipeline ...
  ├── MediaManager.Playback.Supervisor (:one_for_all)
  │   ├── MediaManager.Playback.SessionSupervisor (DynamicSupervisor)
  │   │   └── MpvSession (temporary, at most one at a time)
  │   └── MediaManager.Playback.Manager (singleton)
  └── MediaManagerWeb.Endpoint
```

### Graceful app shutdown flow

1. Application supervisor sends shutdown to `Playback.Supervisor`
2. `Playback.Supervisor` shuts down children → `SessionSupervisor` receives shutdown
3. `SessionSupervisor` shuts down `MpvSession` → `terminate/2` runs
4. `terminate/2` calls `finalize` (persist final progress, broadcast stopped) then `cleanup` (close socket, remove socket file)
5. Port close sends SIGTERM to MPV, which exits cleanly

---

## Implementation Order

1. Create `lib/media_manager/playback/session_supervisor.ex`
2. Create `lib/media_manager/playback/supervisor.ex`
3. Modify `lib/media_manager/playback/mpv_session.ex`:
   - Add `child_spec/1`
   - Add `Process.flag(:trap_exit, true)` in `init/1`
   - Add `finalize/1` private function
   - Add `terminate/2` callback
   - Add early-return guard for `{:tcp, _, _}` when stopped
   - Add catch-all `handle_info`
   - Revise all four shutdown handlers to use `finalize/1`
   - Remove explicit `cleanup` calls from handlers
4. Modify `lib/media_manager/playback/manager.ex`:
   - Add `alias MediaManager.Playback.SessionSupervisor`
   - Replace `MpvSession.start_link(params)` with `SessionSupervisor.start_session(params)`
5. Modify `lib/media_manager/application.ex`:
   - Replace `MediaManager.Playback.Manager` with `MediaManager.Playback.Supervisor`
6. Run `mix precommit`

## Smoke Tests

These changes affect GenServer internals (shutdown ordering, supervision structure). Per the testing strategy, GenServer internals are not unit-tested. No external contracts change (wire format, PubSub message shapes, DB schema). Existing channel and resource tests verify unchanged contracts.

**Manual verification:**
1. Start playback, let video end naturally → logs show exactly one persist + broadcast (not 4x)
2. Start playback, kill the app with Ctrl+C → verify final progress was persisted to DB
3. Start playback, stop via UI → verify clean shutdown, socket file removed
