---
status: accepted
date: 2026-03-01
---
# Use MPV --start flag for resume instead of IPC seek

## Context and Problem Statement

When resuming playback, the MpvSession sent a `seek` command over the MPV JSON IPC socket immediately after connecting. This was unreliable — MPV had not yet loaded and demuxed the file, so the seek command was silently dropped. The result was that resume appeared to work in the logs ("resuming at 2657.0s") but MPV actually played from the beginning.

The MPV IPC socket becomes available before the file is ready for seeking. There is no reliable "file loaded" event to wait for before seeking — the `duration` property-change arrives at an unpredictable time relative to playback start.

## Decision Outcome

Chosen option: "Pass `--start=<seconds>` as a CLI argument when launching MPV", because MPV processes CLI arguments before beginning playback, guaranteeing the seek position is applied before the first frame renders.

The IPC seek command was removed from `connect_socket`. The `--start` flag is conditionally added to the MPV launch flags when `start_position > 0`.

### Consequences

* Good, because resume is deterministic — MPV handles the seek internally before playback begins
* Good, because no timing-dependent IPC coordination is needed
* Good, because the user sees the correct frame immediately, with no flash of the beginning
* Neutral, because the IPC `seek` command remains available for user-initiated seeking during playback (unchanged)
