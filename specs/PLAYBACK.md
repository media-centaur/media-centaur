# Playback Specification

This document specifies MPV integration, watch progress tracking, and resume logic for Media Centaur.

---

## MPV Integration

### Architecture

The backend manages MPV playback. Each active playback session is a dedicated GenServer that:

1. Launches an `mpv` process with `--input-ipc-server=/tmp/media-centaur-mpv-{session_id}.sock`
2. Connects to the Unix domain socket for JSON IPC
3. Polls playback position at regular intervals
4. Handles MPV lifecycle events (play, pause, seek, end-of-file, quit)
5. Cleans up the socket file and process on termination

The UI never launches MPV directly. It sends a play command to the backend, which manages the full lifecycle.

### MPV JSON IPC Protocol

MPV exposes a JSON-based IPC interface over a Unix domain socket. Communication is newline-delimited JSON.

**Commands (backend → MPV):**

```json
{"command": ["loadfile", "/path/to/video.mkv"]}
{"command": ["set_property", "pause", true]}
{"command": ["set_property", "pause", false]}
{"command": ["seek", 120, "absolute"]}
{"command": ["quit"]}
```

**Property observation (backend → MPV):**

```json
{"command": ["observe_property", 1, "time-pos"]}
{"command": ["observe_property", 2, "duration"]}
{"command": ["observe_property", 3, "pause"]}
{"command": ["observe_property", 4, "eof-reached"]}
```

**Events (MPV → backend):**

```json
{"event": "property-change", "id": 1, "name": "time-pos", "data": 542.3}
{"event": "property-change", "id": 2, "name": "duration", "data": 2844.0}
{"event": "property-change", "id": 3, "name": "pause", "data": false}
{"event": "property-change", "id": 4, "name": "eof-reached", "data": true}
{"event": "end-file", "reason": "eof"}
{"event": "end-file", "reason": "quit"}
{"event": "shutdown"}
```

### Progress Reporting

The backend observes `time-pos` via MPV's property observation mechanism. MPV sends property-change events whenever the value changes (typically every frame, throttled by the IPC socket). The backend:

1. Records position updates to the database at most **every 60 seconds** during active watching (see [Progress Persistence](#progress-persistence))
2. Pushes a `playback:entity_progress_updated` message to the frontend on every database write (see [Channel Push on Save](#channel-push-on-save))
3. Records a final position on pause, stop, or end-of-file (if actively watching)

### MPV Launch Flags

```
mpv --input-ipc-server=/tmp/media-centaur-mpv-{session_id}.sock
    --fullscreen
    --no-terminal
    --force-window=immediate
    {content_url}
```

Additional flags (e.g. `--sub-file`, `--audio-file`) may be added in the future but are out of scope for the initial implementation.

### Process Lifecycle

```
:idle
    ↓  play command received
:starting        → launch mpv process, connect to IPC socket
    ↓  IPC connected + file loaded
:playing         → observing properties, reporting progress
    ↓  user pauses or MPV pauses
:paused          → progress reporting paused
    ↓  user resumes
:playing
    ↓  end-of-file or quit
:stopped         → final progress recorded, process cleaned up
    ↓
:idle
```

If MPV crashes or the IPC socket disconnects unexpectedly, the GenServer transitions to `:stopped`, records whatever progress was last known, and cleans up.

---

## Watch Progress

### Data Model

Watch progress is tracked per playable item — each movie and each TV episode has at most one progress record.

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `entity_id` | UUID (FK → Entity) | The media entity (movie or TV series) |
| `season_number` | integer or nil | Season number for TV episodes; nil for movies |
| `episode_number` | integer or nil | Episode number for TV episodes; nil for movies |
| `position_seconds` | float | Last known playback position in seconds |
| `duration_seconds` | float | Total duration in seconds (from MPV, more accurate than TMDB metadata) |
| `completed` | boolean | Whether the item is considered "fully watched" |
| `last_watched_at` | utc_datetime | Timestamp of the most recent playback session |
| `inserted_at` | utc_datetime | |
| `updated_at` | utc_datetime | |

**Uniqueness:** `(entity_id, season_number, episode_number)` — one progress record per playable item.

For movies: `season_number` and `episode_number` are both nil.
For TV episodes: both are set. Progress is tracked per-episode, not per-season or per-series.
For MovieSeries child movies: `season_number` is 0, `episode_number` is the 1-based ordinal (position in the series).

### Completion Threshold

An item is marked `completed: true` when:

- `position_seconds / duration_seconds >= 0.90` (90% of total duration)

This accounts for credits, post-credits scenes, and slight duration mismatches. Completion is set by the MpvSession after a successful progress upsert — it is a separate `mark_completed` action, not part of the upsert itself.

**Completion is monotonic:** once `completed` is set to `true`, it never regresses to `false`. Re-watching a completed item from an earlier position preserves the completed flag. The `completed` field is excluded from the upsert's ON CONFLICT UPDATE clause, so only the dedicated `mark_completed` action can set it. It can only be reset by an explicit user action (future feature).

### Progress Persistence

Progress is written to SQLite by the MpvSession GenServer, but only when the user is **actively watching** — not merely seeking through a video.

#### Continuous Watching Detection

The backend tracks whether playback is continuous or the user is seeking:

- **Seek detection:** A position jump of more than **3 seconds** between consecutive `time-pos` updates is treated as a seek. This resets the continuous-watching timer.
- **Continuous threshold:** The user must watch **20 seconds** of uninterrupted playback (no seeks) before the session is considered "actively watching."
- **Saveable position:** Only advances while actively watching. Seeks do not update the saveable position.

This prevents seek-around from corrupting saved progress. If the user opens a video, scrubs to check a scene, and closes it without watching 20 continuous seconds, the previous saved position is preserved.

#### Write Timing

- **During active watching:** Every **60 seconds** (debounced from MPV's frame-level updates)
- **On pause:** Immediately (if actively watching)
- **On stop/end-of-file:** Immediately (if actively watching)
- **On MPV crash:** Last known saveable position (from the most recent 60-second write)
- **Not actively watching:** No DB writes occur

This means at most 60 seconds of progress can be lost if the system crashes during active playback.

#### Channel Push on Save

Every database write triggers a `playback:entity_progress_updated` push to the frontend via PubSub. This includes the entity-level progress summary, resume target, a `childTargets` delta identifying the affected child, and `lastActivityAt` (the current timestamp). The frontend receives progress updates at save cadence — not in real time. See `API.md` for the message format.

---

## Resume Algorithm

The resume algorithm is a **pure function**: given an entity and its progress data, it returns what to play and where to start.

### Input

- Entity (with type, seasons, episodes, or child movies)
- All `WatchProgress` records for that entity

### Output

```
{:resume, content_url, position_seconds}   # resume partially watched item
{:play_next, content_url, 0}               # start next unwatched item from beginning
{:restart, content_url, 0}                 # series complete, restart from first item
{:no_playable_content}                     # no content_url available
```

### Algorithm

#### Movies

1. If progress exists and `completed == false` → `{:resume, content_url, position_seconds}`
2. If progress exists and `completed == true` → `{:play_next, content_url, 0}` (replay from start)
3. If no progress → `{:play_next, content_url, 0}`

#### TV Series

Episodes are ordered by `(season_number, episode_number)`. The algorithm walks the episode list:

1. **Find the last watched episode** — the episode with the most recent `last_watched_at` among all progress records for this series.

2. **If the last watched episode is not completed** → `{:resume, content_url, position_seconds}` (resume where they left off)

3. **If the last watched episode is completed** → advance to the next episode:
   - Next episode in the same season → `{:play_next, content_url, 0}`
   - No more episodes in this season, but next season exists → first episode of the next season: `{:play_next, content_url, 0}`
   - No more seasons (series complete) → `{:restart, first_episode_content_url, 0}` (restart from S01E01)

4. **If no progress exists for any episode** → `{:play_next, first_episode_content_url, 0}` (start from S01E01)

**Edge cases:**

- Episode has no `content_url` (file missing) → skip to the next episode with a `content_url`
- All remaining episodes lack `content_url` → `{:no_playable_content}`
- Only some seasons have files (gaps) → skip missing seasons, advance to the next available episode

#### MovieSeries

Child movies are ordered by `(position, datePublished)`. The algorithm walks the movie list using the same logic as TV Series:

1. **Find the last watched movie** — the movie with the most recent `last_watched_at` among all progress records for this series.

2. **If the last watched movie is not completed** → `{:resume, content_url, position_seconds}` (resume where they left off)

3. **If the last watched movie is completed** → advance to the next movie in order:
   - Next movie exists → `{:play_next, content_url, 0}`
   - No more movies (series complete) → `{:restart, first_movie_content_url, 0}` (restart from first movie)

4. **If no progress exists for any movie** → `{:play_next, first_movie_content_url, 0}` (start from first movie)

**Storage key:** MovieSeries progress uses `season_number: 0, episode_number: ordinal` where ordinal is the 1-based position of the movie in the sorted list.

**Edge cases:**

- Child movie has no `content_url` → skip to the next movie with a `content_url`
- All remaining movies lack `content_url` → `{:no_playable_content}`

### UUID Resolution

The `play` command accepts a single `entity_id` that can identify any playable thing. The backend resolves the UUID by trying lookups in this order:

1. **Entity** — `Ash.get(Entity, uuid)`. If found:
   - Series (TV or Movie): runs the full resume algorithm above
   - Single item (Movie, VideoObject): checks progress for resume/play
2. **Episode** — `Ash.get(Episode, uuid)`. If found: loads the parent entity via Season, checks WatchProgress for `(entity_id, season_number, episode_number)`, resumes if partially watched, otherwise plays from 0.
3. **Movie (child)** — `Ash.get(Movie, uuid)`. If found: loads the parent MovieSeries entity, finds the movie's ordinal, checks WatchProgress for `(entity_id, 0, ordinal)`, resumes if partially watched, otherwise plays from 0.
4. **Extra** — `Ash.get(Extra, uuid)`. If found: plays `content_url` from 0 (no progress tracking for extras).
5. **None found** → `{:error, :not_found}`

Items with `nil` content_url return `{:error, :no_playable_content}`.

### "Play" User Flow

When the user selects "Play" on any entity or child item:

1. UI sends a `play` message with `{"entity_id": "..."}` payload on the `playback` channel. The UUID can identify an entity, episode, child movie, or extra.
2. Backend resolves the UUID (see UUID Resolution above)
3. Backend applies smart resume logic (resume algorithm for entities, per-item progress check for children)
4. Backend launches MPV with the determined file and position
5. Backend pushes playback state to the UI (what's playing, progress)

---

## Progress Display

### Grid Cards

Each entity card in the grid can show a progress indicator:

- **No progress:** No indicator
- **Partially watched (movie):** Thin progress bar at the bottom of the card showing `position / duration`
- **Completed (movie):** Checkmark or "watched" badge
- **TV Series in progress:** Thin progress bar representing overall series progress (episodes completed / total episodes), plus a text label like "S2 E3" indicating the next episode to watch
- **TV Series complete:** Checkmark or "watched" badge

### Detail View

The detail view shows per-episode progress:

- Each episode row shows a progress bar if partially watched
- Completed episodes show a checkmark
- The "next up" episode is visually highlighted

### Data Flow

Progress data for all entities is sent to the UI as part of the library sync (on connect) and as incremental updates during playback. The UI does not query progress separately — it receives it as part of the entity data stream.
