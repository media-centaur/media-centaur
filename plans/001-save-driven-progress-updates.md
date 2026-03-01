# Save-Driven Progress Updates

## Problem Statement

The backend sends `playback:progress` ticks every 2 seconds during active playback to drive a UI progress bar. But the frontend isn't visible during playback — these messages are wasted. Progress updates should reflect persisted state changes, not real-time position.

## User-Facing Behavior

The frontend receives progress updates when the backend saves to its database:
- Every ~60 seconds during active watching
- Immediately on pause, stop, EOF, or completion

Each update includes full entity context (progress summary, resume target) and a delta of affected child targets, so the frontend can update both the entity card and the specific child (episode/movie) in one message.

`playback:progress` no longer exists.

## Design

### Data Model Changes

None. `WatchProgress` is unchanged. This is purely a channel protocol change.

### Protocol Changes

**Delete `playback:progress`** — remove the 2-second tick message entirely.

**Expand `playback:entity_progress_updated`** — fires on every `WatchProgress` DB write (not just completion milestones). Payload:

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
  }
}
```

- `childTargets` is a **delta** — only the affected child, not the full map. The frontend merges into its local state.
- For standalone movies: `childTargets` is `null`.
- For TV episodes: key is the episode UUID.
- For MovieSeries child movies: key is the child movie UUID.

**`playback:state_changed` is unchanged.** Keeps `position_seconds` and `duration_seconds` in `now_playing` for debuggability.

### Integration Points

- Update `specifications/API.md`: delete `playback:progress` section, update `playback:entity_progress_updated` payload and trigger description
- Update `specifications/PLAYBACK.md`: remove "UI Progress Bar" subsection under Progress Persistence, update write timing to note each write triggers a channel push

### Constraints

- ADR-009: Phoenix Channels is the integration point with the UI (unchanged, this is still channels)
- ADR-011: All mutations broadcast to PubSub (this extends the pattern — progress saves now also push to the playback channel)

### Implementation Steps

I'd like to read source code to write precise implementation steps. The following files are relevant:

- `lib/media_centaur/playback/mpv_session.ex` — where DB writes happen, where 2-second ticks originate
- `lib/media_centaur_web/channels/playback_channel.ex` — where `playback:progress` and `playback:entity_progress_updated` are pushed
- `lib/media_centaur/playback/progress_summary.ex` — computes the `progress` summary
- `lib/media_centaur/playback/watching_tracker.ex` — continuous watching detection
- `test/media_centaur_web/channels/playback_channel_test.exs` — channel contract tests

These should be read at implementation time to identify exact insertion/deletion points.

**High-level steps:**

1. **Update specs first** (`API.md`, `PLAYBACK.md`) — contract changes before code changes.
2. **Remove the 2-second tick** — delete the timer/broadcast that sends `playback:progress` from MpvSession or PlaybackChannel.
3. **Wire progress updates to every DB write** — after each `WatchProgress` upsert or `mark_completed`, compute `progress` summary + `resumeTarget` + `childTargets` delta and push `playback:entity_progress_updated`.
4. **Build the `childTargets` delta** — determine the affected child UUID and its new target hint. This is a single-key map, not the full child enumeration.
5. **Update channel tests** — remove `playback:progress` test cases, add/update `playback:entity_progress_updated` tests verifying the new payload shape fires on save events.
6. **Remove any frontend references** — if the frontend spec or channel code handles `playback:progress`, remove those handlers.

## Acceptance Criteria

- [ ] `playback:progress` message no longer exists in code or specs
- [ ] Every `WatchProgress` DB write triggers a `playback:entity_progress_updated` push
- [ ] Payload includes `entity_id`, `progress`, `resumeTarget`, and `childTargets` (delta)
- [ ] `childTargets` contains only the affected child (single key), not the full map
- [ ] Standalone movies send `childTargets: null`
- [ ] `playback:state_changed` is unchanged
- [ ] `API.md` and `PLAYBACK.md` specs reflect the new contract
- [ ] Channel tests verify the new payload shape

## Decisions

See `adrs/2026-03-01-014-save-driven-progress-updates.md`

## Smoke Tests

- Playback channel contract tests: remove `playback:progress` assertions, add assertions for `playback:entity_progress_updated` firing on DB writes with correct payload shape
- Verify `childTargets` delta contains exactly one key for nested entities, `null` for standalone movies
- Verify the message fires on 60-second periodic saves, pause, stop, and EOF
