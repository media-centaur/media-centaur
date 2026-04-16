---
status: accepted
date: 2026-03-01
---
# Replace real-time playback ticks with save-driven progress updates

## Context and Problem Statement

The backend sends `playback:progress` messages to the frontend every 2 seconds during active playback, intended to drive a real-time progress bar. However, the frontend is not visible during playback — the user is watching fullscreen video in MPV. These messages are wasted. Meanwhile, `playback:entity_progress_updated` only fires on completion milestones, so the frontend doesn't learn about intermediate progress until playback ends.

## Decision Outcome

Chosen option: "push progress on every DB write, delete 2-second ticks", because the frontend only needs to know about persisted state changes, and every DB write (60-second interval, pause, stop, EOF, completion) is a natural trigger. The `playback:entity_progress_updated` message is expanded to include full entity context and a `childTargets` delta for nested items, so the frontend can update both entity-level and child-level UI in one message.

### Consequences

* Good, because it eliminates unnecessary network traffic during playback
* Good, because the frontend always reflects persisted state (no phantom progress that wasn't saved)
* Good, because the delta-based `childTargets` keeps payloads small for series with many episodes
* Good, because the same payload shape works for standalone movies, TV episodes, and MovieSeries children
* Bad, because the frontend can only show progress at save granularity (~60s) if it ever becomes visible during playback — but this is explicitly not a requirement
