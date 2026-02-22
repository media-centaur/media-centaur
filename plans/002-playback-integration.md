# 002 — Playback Integration & Watch Progress (Backend)

## Context

The media-manager evolves from a write-side metadata manager into the authoritative backend for the entire Freedia Center system. This plan covers adding: MPV process management, watch progress tracking, resume logic, and a Phoenix Channels WebSocket API for the user-interface to connect to.

**Specifications:** `../specifications/COMPONENTS.md`, `../specifications/PLAYBACK.md`, `../specifications/API.md`.

---

## 1. Watch Progress — Ash Resource

Create a new `WatchProgress` resource in `lib/media_manager/library/`.

**Resource:** `MediaManager.Library.WatchProgress`

**Attributes:**

| Attribute | Type | Notes |
|-----------|------|-------|
| `id` | `:uuid` | Primary key (default) |
| `entity_id` | `:uuid` | FK → Entity; required |
| `season_number` | `:integer` | nil for movies |
| `episode_number` | `:integer` | nil for movies |
| `position_seconds` | `:float` | Default 0.0 |
| `duration_seconds` | `:float` | Default 0.0 |
| `completed` | `:boolean` | Default false |
| `last_watched_at` | `:utc_datetime` | |
| `timestamps` | | inserted_at, updated_at |

**Identity:** `unique_on: [:entity_id, :season_number, :episode_number]` — one record per playable item.

**Relationship:** `belongs_to :entity, MediaManager.Library.Entity`

**Actions:**

| Action | Type | Description |
|--------|------|-------------|
| `:upsert_progress` | create/upsert | Sets position, duration, last_watched_at; auto-computes `completed` using 90% threshold |
| `:for_entity` | read | Returns all progress records for an entity_id, ordered by season_number then episode_number |
| `:mark_completed` | update | Explicitly marks an item completed |

The `:upsert_progress` action should use an Ash change module that computes `completed = position_seconds / duration_seconds >= 0.90` when both values are positive.

**Migration:** Run `mix ash_sqlite.generate_migrations --name add_watch_progress` after defining the resource.

**Add to domain:** Register `WatchProgress` in `MediaManager.Library` domain and add `has_many :watch_progress` to the Entity resource.

---

## 2. MPV Manager

### 2.1 `MediaManager.Playback.MpvSession` (GenServer)

Each active playback session is a GenServer that manages one MPV process.

**State:**

```elixir
%{
  session_id: String.t(),
  entity_id: String.t(),
  season_number: integer() | nil,
  episode_number: integer() | nil,
  content_url: String.t(),
  mpv_port: port(),
  socket: :gen_tcp.socket(),
  socket_path: String.t(),
  state: :starting | :playing | :paused | :stopped,
  position_seconds: float(),
  duration_seconds: float(),
  last_persisted_at: DateTime.t()
}
```

**Lifecycle:**

1. `start_link/1` — receives entity_id, season/episode numbers, content_url, start_position
2. `init/1` — generates session_id, launches MPV with `--input-ipc-server=/tmp/freedia-mpv-{session_id}.sock`, starts a connection retry loop (MPV takes a moment to create the socket)
3. Once connected, sends `observe_property` commands for `time-pos`, `duration`, `pause`, `eof-reached`
4. If `start_position > 0`, sends a `seek` command
5. Listens for MPV JSON messages in a receive loop (via `:gen_tcp`)
6. On `time-pos` property changes: updates internal state, debounces DB writes to every 5 seconds, broadcasts to PubSub every 2 seconds
7. On `eof-reached` or `end-file`: persists final progress, transitions to `:stopped`, cleans up
8. On unexpected socket close / MPV crash: persists last known position, transitions to `:stopped`

**Public API:**

- `pause/1` — sends `set_property pause true/false` toggle
- `stop/1` — sends `quit` command
- `seek/2` — sends `seek` command

**MPV launch:** Use `Port.open/2` with `{:spawn_executable, mpv_path}` and the flags from PLAYBACK.md. The port monitors the OS process — if it exits, the GenServer receives `{port, {:exit_status, code}}`.

**IPC connection:** Use `:gen_tcp.connect/3` with `{:local, socket_path}` for the Unix domain socket. Set `active: true` for async message receipt. Parse newline-delimited JSON with `Jason.decode/1`.

### 2.2 `MediaManager.Playback.Manager` (GenServer)

A singleton that manages the current playback session. Only one session at a time.

**API:**

- `play/1` — accepts `%{entity_id, season_number, episode_number, content_url, position_seconds}`, starts an `MpvSession`, monitors it
- `pause/0` — delegates to current session
- `stop/0` — delegates to current session
- `seek/1` — delegates to current session
- `current_state/0` — returns current playback state for API responses
- `handle_info({:DOWN, ...})` — session process died, clean up state

### 2.3 `MediaManager.Playback.Resume` (Pure Module)

The resume algorithm. No GenServer — pure functions only.

**Main function:**

```elixir
@spec resolve(Entity.t(), [WatchProgress.t()]) :: resume_result()
@type resume_result ::
  {:resume, String.t(), float()}
  | {:play_next, String.t(), float()}
  | {:restart, String.t(), float()}
  | {:no_playable_content}
```

**Implementation:**

- For movies: check if progress exists; if completed → replay from 0; if partial → resume; if none → play from 0
- For TV series: load episodes ordered by (season_number, episode_number); find last watched (most recent `last_watched_at`); if partial → resume; if completed → advance to next episode with a `content_url`; if all complete → restart from S01E01; if no progress → start from S01E01

The function receives fully loaded entity data (with seasons/episodes) and all progress records. It does not touch the database.

---

## 3. Phoenix Channels API

### 3.1 Socket

**File:** `lib/media_manager_web/channels/user_socket.ex`

```elixir
defmodule MediaManagerWeb.UserSocket do
  use Phoenix.Socket

  channel "library", MediaManagerWeb.LibraryChannel
  channel "playback", MediaManagerWeb.PlaybackChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
```

Add the socket to the endpoint: `socket "/socket", MediaManagerWeb.UserSocket, websocket: true`.

### 3.2 `MediaManagerWeb.LibraryChannel`

**Topic:** `"library"`

**Join:** Load all entities with associations and progress, serialize to the API format (wrapper + entity + progress summary), return as `{:ok, %{entities: [...]}, socket}`.

**PubSub integration:** Subscribe to `"library:updates"` on join. When the pipeline completes processing or an entity is modified, broadcast on this topic. The channel forwards as pushes:

- `library:entity_added` — new entity
- `library:entity_updated` — metadata changed
- `library:entity_removed` — entity removed

**Progress summary computation:** Create a `MediaManager.Playback.ProgressSummary` module with a function that takes an entity + its progress records and returns the display-ready summary object (current_episode, position, duration, episodes_completed, episodes_total).

### 3.3 `MediaManagerWeb.PlaybackChannel`

**Topic:** `"playback"`

**Join:** Return current playback state from `Playback.Manager.current_state/0`.

**Incoming messages:**

| Message | Handler |
|---------|---------|
| `"play"` | Load entity, run `Resume.resolve/2`, call `Manager.play/1` |
| `"play_episode"` | Load specific episode, call `Manager.play/1` with position 0 |
| `"pause"` | Call `Manager.pause/0` |
| `"stop"` | Call `Manager.stop/0` |
| `"seek"` | Call `Manager.seek/1` |

**PubSub integration:** Subscribe to `"playback:events"` on join. The MpvSession broadcasts state changes and progress ticks on this topic. The channel forwards as:

- `playback:state_changed` — state transitions (playing, paused, stopped, idle)
- `playback:progress` — position ticks (every 2 seconds)
- `playback:entity_progress_updated` — when an episode is marked completed or progress changes significantly

### 3.4 Endpoint Configuration

Add to `MediaManagerWeb.Endpoint`:

```elixir
socket "/socket", MediaManagerWeb.UserSocket,
  websocket: [timeout: 45_000],
  longpoll: false
```

### 3.5 PubSub Broadcasting

Use `Phoenix.PubSub.broadcast/3` from within the pipeline, MpvSession, and any entity mutation path. Topics:

- `"library:updates"` — library changes
- `"playback:events"` — playback state and progress

---

## 4. Entity Serialization for API

The existing `MediaManager.Serializer` produces the schema.org JSON-LD format for `media.json`. The API needs the same entity format but with an added `progress` field.

**Approach:** Reuse `Serializer.serialize_entity/1` for the entity body. Wrap it with `@id` and `progress` in the channel handler:

```elixir
%{
  "@id" => entity.id,
  "entity" => Serializer.serialize_entity(entity),
  "progress" => ProgressSummary.compute(entity, progress_records)
}
```

This keeps serialization DRY and ensures the API and `media.json` always agree on entity format.

---

## 5. Supervision Tree

Add to the application supervision tree:

```elixir
children = [
  # ... existing children ...
  MediaManager.Playback.Manager
]
```

`MpvSession` processes are started dynamically by the Manager and linked to it (or monitored). They are not in the static supervision tree.

---

## 6. Migration Path

### Phase 1 (this plan)
- Add WatchProgress resource, MPV manager, Channels API, resume logic
- Keep `media.json` generation via JsonWriter (unchanged)
- Both data paths work simultaneously

### Phase 2 (future)
- UI switches to WebSocket as primary data source
- `media.json` generation runs less frequently (or on-demand only)

### Phase 3 (future)
- Remove `media.json` generation entirely
- Remove JsonWriter GenServer

---

## 7. Smoke Tests

Minimal automated tests to provide confidence without maintenance burden.

### 7.1 Resume Algorithm (`test/media_manager/playback/resume_test.exs`)

Pure function tests — no GenServers, no database.

| Test | Input | Expected |
|------|-------|----------|
| Movie, no progress | Movie entity, [] | `{:play_next, content_url, 0}` |
| Movie, partial | Movie entity, [progress at 50%] | `{:resume, content_url, position}` |
| Movie, completed | Movie entity, [progress at 95%] | `{:play_next, content_url, 0}` |
| TV, no progress | TVSeries entity, [] | `{:play_next, S01E01_url, 0}` |
| TV, partial episode | TVSeries, [S01E03 at 50%] | `{:resume, S01E03_url, position}` |
| TV, completed mid-season | TVSeries, [S01E03 completed] | `{:play_next, S01E04_url, 0}` |
| TV, season boundary | TVSeries, [S01E10 completed, S02 exists] | `{:play_next, S02E01_url, 0}` |
| TV, series complete | TVSeries, [all episodes completed] | `{:restart, S01E01_url, 0}` |
| TV, missing content_url | TVSeries, [S01E03 completed, S01E04 no url] | `{:play_next, S01E05_url, 0}` (skip) |

### 7.2 Watch Progress Persistence (`test/media_manager/integration_test.exs`)

Add to existing integration test file:

- Create an entity, upsert progress, read it back — verify fields
- Upsert progress at 95% position — verify `completed` is auto-set to `true`
- Upsert progress for same entity+episode twice — verify upsert (no duplicate)

### 7.3 Channel Connectivity (future, once UI is connecting)

Deferred — will add a basic channel test when the UI starts connecting. Not worth testing until there's a real client.

---

## Files to Create

| File | Contents |
|------|---------|
| `lib/media_manager/library/watch_progress.ex` | WatchProgress Ash resource |
| `lib/media_manager/library/watch_progress/changes/compute_completed.ex` | Ash change: auto-compute `completed` flag |
| `lib/media_manager/playback/manager.ex` | Singleton playback manager GenServer |
| `lib/media_manager/playback/mpv_session.ex` | Per-session MPV GenServer |
| `lib/media_manager/playback/resume.ex` | Resume algorithm (pure functions) |
| `lib/media_manager/playback/progress_summary.ex` | Entity progress summary computation |
| `lib/media_manager_web/channels/user_socket.ex` | Phoenix socket |
| `lib/media_manager_web/channels/library_channel.ex` | Library channel |
| `lib/media_manager_web/channels/playback_channel.ex` | Playback channel |
| `test/media_manager/playback/resume_test.exs` | Resume algorithm tests |

## Files to Modify

| File | Change |
|------|--------|
| `lib/media_manager/library.ex` | Add WatchProgress to domain resources |
| `lib/media_manager/library/entity.ex` | Add `has_many :watch_progress` relationship |
| `lib/media_manager_web/endpoint.ex` | Add socket mount |
| `lib/media_manager/application.ex` | Add Playback.Manager to supervision tree |
| `test/media_manager/integration_test.exs` | Add watch progress persistence tests |
