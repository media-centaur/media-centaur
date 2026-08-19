---
status: accepted
date: 2026-08-18
---
# Episode auto-advance rides the mpv playlist inside one session

## Context and Problem Statement

Finishing a TV episode dead-ends: mpv sits on the final frame
(`keep-open`) or quits, and continuing the series means going back to
the app and pressing Play again. Netflix-style auto-advance was missing
because it wasn't clear where it should live.

Two placements were considered:

1. **Relaunch per episode** — on EOF the backend notices completion and
   starts a fresh session; `Resume.resolve/2` picks the next episode.
   Minimal new code, but every transition tears down and respawns the
   mpv window, and on the TV path re-locks the HDMI link for HDR —
   several seconds of black between every episode, repeated for the
   whole binge.
2. **Playlist advance within one mpv process** — the backend appends
   the successor episode to mpv's playlist; mpv's native EOF advance
   carries playback into it seamlessly. `hdr-display.lua` already
   guarantees HDR→HDR playlist transitions don't bounce the display.

Option 2 breaks an implicit assumption: one `MpvSession` has, until
now, played exactly one file for its whole life.

## Decision Outcome

Chosen option: **playlist advance within one session**, because the
transition cost of relaunching (window flash + HDR re-lock) lands on
every single episode boundary and is exactly the experience the feature
exists to smooth over.

The session contract changes from *one session, one file* to *one
session, one viewing chain*:

* After resolving the episode to play, the backend also resolves its
  successor and appends it to the mpv playlist with a **per-entry**
  `start` option carrying the successor's own resume position. The
  global `--start` flag (ADR-013) applies only to the first file — it
  must never leak onto later playlist entries. *[Corrected 2026-08-19:
  mpv applies a bare global `--start` to **every** file it loads,
  playlist entries included — the original premise was wrong, and an
  unwatched successor (no per-entry `start` to override the global)
  started at the first episode's resume offset. Fixed by scoping the
  launch resume with per-file option grouping (`--{ --start=… <file> --}`);
  see `MpvSession.launch_target/2`.]*
* `MpvSession` observes the file transition, closes out progress for
  the finished episode, re-attributes tracking to the new playable
  item, and appends the next successor — always one ahead.
* "Quit on EOF" becomes "quit at playlist end". Mid-chain EOF is an
  advance, not an exit.
* Advancing early (the credits-chapter "Next Episode" pill in mpv) is a
  plain `playlist-next` inside mpv — the backend observes it like any
  other transition. No new IPC vocabulary; observation-not-control is
  preserved.
* The chain ends where the successor lookup ends: season/series end, or
  next episode not playable. No append, no pill, `keep-open` behaves as
  today.

### Consequences

* Good, because episode transitions are seamless — no window teardown,
  no HDR bounce, no orchestration race between quit and relaunch.
* Good, because auto-advance at EOF needs no backend trigger at all;
  mpv does it natively, and the backend merely observes.
* Good, because the ending conditions are structural (no next playlist
  entry) rather than policed by timers or state machines.
* Bad, because `MpvSession` must handle mid-life file changes:
  progress attribution, completion marking, and `now_playing`
  broadcasts all key off the currently playing path instead of a fixed
  launch-time file. Session recovery (ADR-023) already re-derives the
  entity from the probed path, which is the same discipline.
* Bad, because a stale playlist entry can outlive its file (deleted or
  directory offline after append). Accepted: mpv fails to a skip/stop
  the classifier already handles, and the window is minutes long.
