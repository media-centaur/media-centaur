---
status: accepted
date: 2026-08-18
amended: 2026-08-19
---
# Episode auto-advance rides the mpv playlist inside one session

## Context and Problem Statement

Finishing a TV episode dead-ended on mpv's final frame. Relaunching a fresh
session per episode would tear down and respawn the mpv window on every
boundary and, on the TV path, re-lock the HDMI link for HDR — seconds of
black per episode. Advancing within one mpv process avoids both, at the
cost of the implicit assumption that one `MpvSession` plays exactly one
file.

## Decision Outcome

Playlist advance within one session. The session contract becomes *one
session, one viewing chain*.

1. **Resume is a launch option, not an IPC seek.** The starting position is
   passed to mpv at launch; a seek over the IPC socket immediately after
   connecting was dropped before the file had demuxed. A bare global
   `--start` applies to every file mpv loads, playlist entries included
   (corrected 2026-08-19), so `MpvSession.launch_target/2` scopes the launch
   resume with per-file option grouping (`--{ --start=… <file> --}`).
2. **The backend appends the successor episode** after resolving the one to
   play, with a per-entry `start` carrying the successor's own resume
   position, and keeps the playlist one ahead as transitions happen.
3. **`MpvSession` observes the file transition**, closes out progress for
   the finished episode, re-attributes tracking to the new playable item, and
   appends the next successor.
4. **Quit on EOF becomes quit at playlist end.** A mid-chain EOF is an
   advance. An early advance (the credits-chapter pill in mpv) is a plain
   `playlist-next` the backend observes like any other transition; no new
   IPC vocabulary.
5. **The chain ends where the successor lookup ends** — season or series
   end, or next episode not playable. No append, no pill, `keep-open`
   behaves as before.

### Consequences

* Progress attribution, completion marking and `now_playing` broadcasts key
  off the currently playing path, not a launch-time file. Session recovery
  ([ADR-023](2026-03-06-023-durable-process-design.md)) already re-derives
  the entity from the probed path.
* A stale playlist entry can outlive its file (deleted or offline after the
  append); mpv fails to a skip or stop the classifier already handles.
