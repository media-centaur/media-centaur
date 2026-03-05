# Phoenix Channels API Specification

This document specifies the WebSocket API between the backend (backend) and the frontend. The API uses the [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html) protocol over a single WebSocket connection.

---

## Connection

### Endpoint

```
ws://localhost:4000/socket/websocket
```

The UI connects on startup. The Phoenix Channels protocol handles multiplexing, heartbeat, and reconnection over this single connection.

### Lifecycle

1. **Connect:** UI opens a WebSocket to the endpoint
2. **Join channels:** UI joins one or more topic channels (see below)
3. **Heartbeat:** Phoenix sends heartbeat pings every 30 seconds; the UI must respond or the connection is closed
4. **Reconnect:** On disconnect, the UI retries with exponential backoff (1s, 2s, 4s, 8s, max 30s)
5. **Rejoin:** After reconnection, the UI re-joins all channels and receives fresh state

### Authentication

None for v1 — the backend runs locally and serves a single household. Authentication may be added if remote access is ever needed.

---

## Channel Topics

| Topic | Purpose |
|-------|---------|
| `library` | Media library data: full sync on join, incremental updates |
| `playback` | Playback commands and state: play, progress |

---

## `library` Channel

### Join

**Topic:** `library`

On join, the backend returns an empty reply and begins streaming the library as a series of `library:entities` batches, followed by a `library:sync_complete` signal. No parameters required.

**Reply:**

```json
{
  "status": "ok",
  "response": {}
}
```

After the reply, the backend pushes the full library in batches (see `library:entities` below), then pushes `library:sync_complete` to signal the initial sync is done. The UI should accumulate entities from each batch and consider the library fully loaded once `library:sync_complete` arrives.

### Server Push: `library:entities`

A batch of entity payloads with upsert semantics. Used for both initial sync batches and incremental updates from the pipeline.

```json
{
  "entities": [
    {
      "@id": "550e8400-...",
      "entity": { "@type": "Movie", "name": "Sample Movie", ... },
      "progress": null,
      "resumeTarget": { "action": "begin", "name": "Sample Movie" },
      "childTargets": null,
      "lastActivityAt": "2026-01-15T10:00:00Z"
    },
    {
      "@id": "660f9500-...",
      "entity": { "@type": "TVSeries", "name": "Severance", ... },
      "progress": {
        "current_episode": { "season": 2, "episode": 3 },
        "episode_position_seconds": 1200.5,
        "episode_duration_seconds": 3200.0,
        "episodes_completed": 12,
        "episodes_total": 20
      },
      "resumeTarget": {
        "action": "resume",
        "targetId": "ep-uuid",
        "name": "Who Is Alive?",
        "seasonNumber": 2,
        "episodeNumber": 3,
        "positionSeconds": 1200.5,
        "durationSeconds": 3200.0
      },
      "childTargets": {
        "ep-uuid-1": null,
        "ep-uuid-2": { "action": "resume", "positionSeconds": 1200.5, "durationSeconds": 3200.0 },
        "ep-uuid-3": { "action": "begin" }
      },
      "lastActivityAt": "2026-03-01T20:00:00Z"
    }
  ]
}
```

Each entity in the `entities` array follows the wrapper format defined in `DATA-FORMAT.md` (`{@id, entity}`), with additional fields:
- `progress`: aggregated watch progress summary (or `null` if no progress exists)
- `resumeTarget`: display hint for what will play next (see DATA-FORMAT.md Resume Target section; `null` when fully completed)
- `childTargets`: per-child hints keyed by UUID (see DATA-FORMAT.md Child Targets section; `null` for single items)
- `lastActivityAt`: ISO 8601 timestamp of the most recent activity (date added or last watched) across the entity and its children; `null` if no timestamps exist

The UI replaces its local copy of each entity entirely (upsert).

### Server Push: `library:sync_complete`

Signals the initial library sync is done. Sent exactly once after join, after all initial `library:entities` batches. Never sent during incremental updates.

```json
{}
```

### Server Push: `library:entities_removed`

Sent when entities are removed from the library. Contains a batch of removed entity IDs.

```json
{
  "ids": ["550e8400-..."]
}

---

## `playback` Channel

### Join

**Topic:** `playback`

On join, the backend sends the current playback state (if anything is playing).

**Reply:**

```json
{
  "status": "ok",
  "response": {
    "state": "idle",
    "now_playing": null
  }
}
```

Or if something is playing:

```json
{
  "status": "ok",
  "response": {
    "state": "playing",
    "now_playing": {
      "entity_id": "660f9500-...",
      "entity_name": "Severance",
      "season_number": 2,
      "episode_number": 3,
      "episode_name": "Who Is Alive?",
      "content_url": "/media/tv/Severance/S02/S02E03.mkv",
      "position_seconds": 1200.5,
      "duration_seconds": 3200.0
    }
  }
}
```

### Client Message: `play`

Request playback of any playable item by its UUID. The `entity_id` field can identify a top-level Entity, an Episode, a child Movie, or an Extra. The backend resolves the UUID, determines the correct file and resume position, and starts playback.

```json
{
  "entity_id": "660f9500-..."
}
```

**UUID resolution order:**

1. **Entity** — if a series (TV or Movie), the resume algorithm determines which child to play and where to start (see `PLAYBACK.md`). If a single item (Movie, VideoObject), checks progress for resume.
2. **Episode** — loads the parent entity, checks WatchProgress for this specific episode, resumes if partially watched, otherwise plays from the beginning.
3. **Movie (child)** — loads the parent MovieSeries entity, checks WatchProgress for this specific child movie, resumes if partially watched, otherwise plays from the beginning.
4. **Extra** — plays from the beginning (no progress tracking for extras).

The backend tries each lookup in order and uses the first match.

**Reply:**

```json
{
  "status": "ok",
  "response": {
    "action": "resume",
    "entity_id": "660f9500-...",
    "season_number": 2,
    "episode_number": 3,
    "position_seconds": 1200.5
  }
}
```

Possible `action` values: `"resume"`, `"play_next"`, `"restart"`, `"play_episode"`, `"play_movie"`, `"play_extra"`.

If playback cannot start:

```json
{
  "status": "error",
  "response": {
    "reason": "no_playable_content"
  }
}
```

### Server Push: `playback:state_changed`

Sent when the playback state changes (play, pause, stop, new episode).

```json
{
  "state": "playing",
  "now_playing": {
    "entity_id": "660f9500-...",
    "entity_name": "Severance",
    "season_number": 2,
    "episode_number": 3,
    "episode_name": "Who Is Alive?",
    "content_url": "/media/tv/Severance/S02/S02E03.mkv",
    "position_seconds": 1200.5,
    "duration_seconds": 3200.0
  }
}
```

Possible `state` values: `"playing"`, `"paused"`, `"stopped"`, `"idle"`.

When `state` is `"idle"` or `"stopped"`, `now_playing` is `null`.

### Server Push: `playback:entity_progress_updated`

Sent on every `WatchProgress` database write — every ~60 seconds during active watching, and immediately on pause, stop, EOF, or completion. The UI uses this to update progress indicators on grid cards and per-child detail views.

```json
{
  "entity_id": "660f9500-...",
  "progress": {
    "current_episode": { "season": 2, "episode": 3 },
    "episode_position_seconds": 1205.3,
    "episode_duration_seconds": 3200.0,
    "episodes_completed": 12,
    "episodes_total": 20
  },
  "resumeTarget": {
    "action": "resume",
    "targetId": "ep-uuid",
    "name": "Who Is Alive?",
    "seasonNumber": 2,
    "episodeNumber": 3,
    "positionSeconds": 1205.3,
    "durationSeconds": 3200.0
  },
  "childTargets": {
    "ep-uuid": { "action": "resume", "positionSeconds": 1205.3, "durationSeconds": 3200.0 }
  },
  "lastActivityAt": "2026-03-04T20:15:00Z"
}
```

The `childTargets` field is a **delta** — it contains only the affected child (single key), not the full map. The frontend merges this into its local child targets state. For standalone movies, `childTargets` is `null`.
```

---

## Resume Target

The `resumeTarget` field is a display hint that tells the frontend what will play when the user hits "play" on an entity. It is computed server-side using the same resume algorithm that powers the `play` command, so the UI can show accurate hints (e.g. "Resume S2E3" or "Begin The Shadowy Sentinel") without issuing a play command.

`resumeTarget` is included in:
- `library:entities` — on each entity in the batch, alongside `progress`
- `playback:entity_progress_updated` — alongside the updated `progress` summary

`lastActivityAt` is included in:
- `library:entities` — on each entity in the batch (computed by `LastActivity`)
- `playback:entity_progress_updated` — set to the current time when progress is saved

When an entity is fully completed or has no playable content, `resumeTarget` is `null`. When all items would restart, it is also `null` (the UI should not suggest a re-watch as the default action).

`childTargets` is included in:
- `library:entities` — full map of all children's hints (on initial sync and entity updates)
- `playback:entity_progress_updated` — delta with only the affected child's hint (on progress saves)

The frontend maintains the full child targets map locally and merges deltas from progress updates into it.

See `DATA-FORMAT.md` for the full field schemas, value types, and examples.

---

## Entity Progress Summary

The `progress` object attached to entities (in library sync and progress updates) is a backend-computed summary. It is **not** the raw `WatchProgress` records — the backend aggregates them into a display-ready format.

| Field | Type | Description |
|-------|------|-------------|
| `current_episode` | `{season, episode}` or `null` | Next episode to play (TV only); null for movies |
| `episode_position_seconds` | float | Position in the current/last-watched item |
| `episode_duration_seconds` | float | Duration of the current/last-watched item |
| `episodes_completed` | integer | Number of completed episodes (TV only; 0 or 1 for movies) |
| `episodes_total` | integer | Total number of episodes with files (TV only; 1 for movies) |

For movies, `current_episode` is `null`, `episodes_total` is `1`, and `episodes_completed` is `0` or `1`.

---

## Error Handling

All client messages receive a reply with `status: "ok"` or `status: "error"`. Error replies include a `reason` string:

| Reason | Meaning |
|--------|---------|
| `"not_found"` | UUID does not match any entity, episode, movie, or extra |
| `"no_playable_content"` | The resolved item has no content_url (no files) |

> **Note:** Sending `play` while something is already playing silently stops the previous session and starts the new one. No error is returned.

---

## Message Flow Examples

### User opens app and browses library

```
UI → Backend:  join "library"
Backend → UI:  reply {}
Backend → UI:  push "library:entities" {entities: [...batch 1...]}
Backend → UI:  push "library:entities" {entities: [...batch 2...]}
Backend → UI:  push "library:sync_complete" {}

UI → Backend:  join "playback"
Backend → UI:  reply with state: "idle"
```

### User plays a TV series (resume via entity UUID)

```
UI → Backend:       push "play" {entity_id: "660f9500-..."}     (entity UUID)
Backend:            resolves UUID as Entity, runs resume algorithm
Backend → UI:       reply {action: "resume", season: 2, episode: 3, position: 1200.5}
Backend:            launches MPV, seeks to position
Backend → UI:       push "playback:state_changed" {state: "playing", now_playing: {...}}
Backend → UI:       push "playback:entity_progress_updated" {...}      (every ~60s during active watching)
...
Backend → UI:       push "playback:entity_progress_updated" {...}      (final progress saved)
Backend → UI:       push "playback:state_changed" {state: "idle"}     (MPV closed)
```

### User plays a specific episode (via episode UUID)

```
UI → Backend:       push "play" {entity_id: "ep-uuid-123"}     (episode UUID)
Backend:            resolves UUID as Episode, checks progress for resume
Backend → UI:       reply {action: "play_episode", season: 1, episode: 5, position: 0.0}
Backend:            launches MPV
Backend → UI:       push "playback:state_changed" {state: "playing", now_playing: {...}}
```

### Library updates while UI is connected

```
Backend pipeline completes processing a new movie:
Backend → UI:       push "library:entities" {entities: [{entity + progress}]}

Entity deleted:
Backend → UI:       push "library:entities_removed" {ids: ["uuid-1"]}
```
