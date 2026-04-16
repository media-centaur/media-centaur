# Watch History — Design Spec

**Date:** 2026-04-11  
**Status:** Approved

## Problem

The existing `WatchProgress` schema is a mutable record upserted per entity — it tracks
live playback state, not history. There is no record of *when* something was watched,
*how many times* it has been completed, or any historical timeline. The dashboard has no
history widget, and there is no dedicated history page.

## Solution

A new bounded context (`WatchHistory`) that listens for playback completion events and
records each completion as a permanent, append-only `WatchEvent`. This powers a history
page with stats, a GitHub-style heatmap, and a paginated event list, plus a dashboard
widget showing recent completions.

## Data Model

New table: `watch_history_events`

| Column           | Type         | Notes |
|------------------|--------------|-------|
| id               | UUID PK      | autogenerate |
| entity_type      | enum string  | :movie \| :episode \| :video_object |
| movie_id         | UUID FK      | nullable, on_delete: :nilify_all |
| episode_id       | UUID FK      | nullable, on_delete: :nilify_all |
| video_object_id  | UUID FK      | nullable, on_delete: :nilify_all |
| title            | string       | denormalized — e.g. "Sample Movie Thirteen" or "Sample Show Eight S05E14" |
| duration_seconds | float        | for stats calculation |
| completed_at     | utc_datetime | when the 90% threshold was crossed |
| inserted_at      | utc_datetime | |
| updated_at       | utc_datetime | |

**FK strategy:** `:nilify_all` (not `:delete_all`) — history entries survive entity deletion
and still display using the denormalized title. The FK is retained when present so
"mark as unwatched" can look up and reset `WatchProgress`.

**Stats are derived** at query time — total count, sum of `duration_seconds`,
group-by-day for the heatmap, consecutive-day streak. Nothing is materialized.

**Re-watches:** Every completion is a separate row. Watch the same movie three times,
get three `WatchEvent` rows. Re-watch count is `count(*)` grouped by entity FK.

## Bounded Context Structure

```
lib/media_centarr/watch_history/
  event.ex          # Ecto schema + changesets
  recorder.ex       # GenServer — subscribes to playback:events, writes WatchEvents
  stats.ex          # Pure functions — totals, streak, heatmap data
watch_history.ex    # Public facade
```

### WatchHistory.Recorder (GenServer)

Subscribes to `"playback:events"` on init. Handles
`{:entity_progress_updated, %{changed_record: record}}` when `record.completed == true`.

No dedup needed: `MpvSession.maybe_mark_completed/3` already guards with
`not record.completed`, so the broadcast fires exactly once per physical completion event.

After writing the `WatchEvent` row, broadcasts `{:watch_event_created, event}` on
`"watch_history:events"` so the history LiveView updates in real-time.

### WatchHistory Public Facade

```elixir
WatchHistory.subscribe()           # PubSub subscribe to "watch_history:events"
WatchHistory.list_events(opts)     # paginated, filterable by type/date/search
WatchHistory.stats(opts)           # %{total_count, total_seconds, streak, heatmap}
WatchHistory.delete_event!(event)  # mark-as-unwatched: delete event + reset WatchProgress
```

### Topics.ex

```elixir
def watch_history_events, do: "watch_history:events"
```

### Supervision Tree

`WatchHistory.Recorder` is added to `MediaCentarr.Application` alongside the other
bounded context workers.

## Mark as Unwatched

`WatchHistory.delete_event!(event)`:
1. Delete the `WatchEvent` row
2. Find `WatchProgress` via the event's FK (`movie_id` / `episode_id` / `video_object_id`)
3. Call `Library.mark_watch_incomplete(record)` — changeset already exists in
   `lib/media_centarr/library/watch_progress.ex`
4. Broadcast `{:entities_changed, [entity_id]}` to `"library:updates"` so LibraryLive
   refreshes the entity's completion state

If the FK has been nilified (entity deleted), skip steps 2–4.

## Completion Trigger

`MpvSession.maybe_mark_completed/3` at
`lib/media_centarr/playback/mpv_session.ex` marks completion at ≥90% playback.
This calls `Library.mark_watch_completed/1`, then `ProgressBroadcaster.broadcast/2`
fires `{:entity_progress_updated, %{changed_record: updated_record}}` on
`"playback:events"`. The Recorder handles this message.

## UI

### Dashboard Widget (LibraryLive)

Added to `lib/media_centarr_web/live/library_live.ex`:
- Stat block: "42 titles completed · 187 hrs watched"
- Last 5 completions: poster thumbnail + title + relative date ("2 days ago")
- "View all history →" navigates to `/history`
- LiveView subscribes to `"watch_history:events"` for real-time widget updates

### History Page (WatchHistoryLive at /history)

Three vertical zones:

**1. Stats bar**
- Total titles completed
- Total hours watched
- Current streak ("7-day streak" / "No current streak")

**2. Heatmap**
- GitHub-style SVG contribution grid, last 52 weeks
- Each cell = one day; color intensity = number of completions (0/1/2–3/4+)
- Clicking a cell filters the event list to that date

**3. Event list**
- Paginated rows: poster thumbnail, denormalized title, type badge, completion
  timestamp, duration, hover-reveal "Mark as unwatched" ghost button
- Controls: type filter chips (All / Movies / Episodes / Video), text search,
  date range filter
- Selecting a heatmap day sets the date range filter

### Route

```elixir
live "/history", WatchHistoryLive, :index
```

Added inside the existing `live_session :default` block in `router.ex`.

## Testing

| Test module | Base case | What it covers |
|-------------|-----------|----------------|
| `WatchHistory.EventTest` | `DataCase` | Schema, nilify on entity delete, changeset validation |
| `WatchHistory.StatsTest` | `async: true` | Totals, streak edge cases (gap breaks streak, same-day multiple completions count once), heatmap data shape |
| `WatchHistory.RecorderTest` | `DataCase` | Send `:entity_progress_updated` with `completed: true`, assert WatchEvent created + broadcast fires |
| `WatchHistoryLiveTest` | `ConnCase` | Mount page, stat block + event list render; real-time update on PubSub push |
| `delete_event!/1` | `DataCase` | WatchEvent deleted, WatchProgress reset, `library:updates` broadcast fires |

Factory additions to `test/support/factory.ex`:
- `build_watch_event(overrides)` — plain struct, no DB
- `create_watch_event(attrs)` — persisted record

## Implementation Order

1. Migration — `watch_history_events` table + indexes
2. `WatchHistory.Event` schema + changesets
3. `WatchHistory.Stats` pure functions
4. `WatchHistory` facade
5. `WatchHistory.Recorder` GenServer
6. Add Recorder to supervision tree + topic to `Topics.ex`
7. `WatchHistoryLive` page
8. Route + dashboard widget in `LibraryLive`
9. Tests (test-first: write tests before each step's implementation)
10. `mix precommit` — zero warnings, all tests pass
