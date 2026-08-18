# Auto-advance to the next episode

## Problem Statement

Finishing a TV episode dead-ends the viewing session. mpv sits on the
final frame and continuing the series means leaving the couch flow:
back to the app, find the series, press Play again. The system already
knows what plays next (`Resume.resolve/2`) and already detects rolling
credits (`Playback.ChapterCompletion`) — it just never acts on either
at the moment they matter.

## User-Facing Behavior

* **At end of episode, the next one simply starts.** No window flash,
  no HDR black-out, no interaction required. Credits play out in full —
  nothing is ever skipped automatically (deliberate divergence from
  Netflix's countdown-skip).
* **During rolling credits, a "Next Episode ▶" pill appears** in mpv
  (bottom-right, sibling of the Skip Intro pill) whenever the file has
  a credits/outro chapter and a next episode is queued. **Enter** or a
  click jumps straight to it. Files without chapter markers get no pill
  — EOF advance still works (accepted asymmetry; no "last 30 seconds"
  heuristic).
* **The chain stops naturally** at the end of the season/series or when
  the next episode isn't playable (not downloaded, directory offline).
  mpv then behaves exactly as today (`keep-open` on the last frame).
* **Setting:** Settings → Preferences → "Auto-play next episode",
  default **on**. Off restores today's behavior exactly — nothing is
  queued, so the pill never appears either.
* Applies to any TV episode playback regardless of entry point (series
  card, hero, episode picked deliberately in the modal). **TV only** —
  movie series deferred.

## Design

See [ADR-062](../../decisions/architecture/2026-08-18-062-playlist-based-episode-advance.md):
advance rides the mpv playlist inside one session; the session contract
becomes *one session, one viewing chain*.

### Mechanics

1. **Queueing.** After resolving the episode to play, the backend
   resolves its successor (same episode-walking rules `Resume` uses,
   same playability rules the play button uses) and appends it to the
   mpv playlist over IPC with a per-entry `start` option carrying that
   episode's own resume position (usually 0). The global `--start` flag
   (ADR-013) must not leak onto appended entries.
2. **Advance at EOF** is mpv-native playlist progression — no backend
   trigger.
3. **Advance early** is `playlist-next` issued inside mpv by the new
   `next-episode.lua` (contrib repo), modeled directly on
   `skip-intro.lua`: chapter observer detects a credits/outro chapter
   title (reuse ChapterCompletion's title patterns), checks
   `playlist-count`/`playlist-pos` for a next entry, shows the pill,
   force-binds Enter and hit-tests clicks while visible. By the time
   the pill can appear, ChapterCompletion has already marked the
   episode complete, so jumping loses nothing.
4. **Observing the transition.** `MpvSession` observes the playing
   path/playlist position. On change: save final progress for the
   finished episode, re-resolve the playable item from the new path
   (the ADR-023 recovery discipline), reset the `WatchingTracker`,
   broadcast `playback_state_changed` with the new `now_playing`, and
   append the *next* successor — staying one ahead.
5. **Exit condition.** "Quit on EOF" becomes "quit at playlist end".
6. **Setting read** at queue time (launch and each subsequent append) —
   flipping it mid-session affects the next queueing decision, no
   session restart needed.

### Data Model Changes

None. One new Settings-database preference entry
(`auto_play_next_episode` or similar, boolean, default on).

### Integration Points

* **contrib repo:** new `mpv/scripts/next-episode.lua`.
* **Wiki (same unit of work):** Playback (auto-advance + chain-end
  behavior), Settings-Reference (new toggle), Keyboard-and-Gamepad
  (Enter during credits), FAQ if the no-chapters asymmetry needs a
  word.
* **This repo docs:** `docs/playback.md` (session contract, IPC
  observations), `docs/mpv.md` (new plugin section).
* **LiveView:** nothing new — existing PubSub progress/state broadcasts
  already update Continue Watching and now-playing as episodes
  complete.

### Constraints

* ADR-013 — `--start` is launch-only; per-entry options for appends.
* ADR-023 — path→entity re-derivation is the existing recovery
  discipline; transitions reuse it.
* Observation-not-control — the early advance happens inside mpv; the
  backend observes it like any user seek. The only new control surface
  is the append, which is launch-adjacent setup, not playback control.
* Completion semantics unchanged (chapter trigger or 90%, monotonic).
* Settings live in the Settings DB, not TOML.

## Acceptance Criteria

- [ ] Finishing a mid-season episode rolls into the next with no
      window teardown (single mpv process for the chain).
- [ ] HDR content: episode transition does not re-lock the display
      (verify on the TV path).
- [ ] Progress and completion are attributed to the correct episode
      across a transition; Continue Watching updates live.
- [ ] "Next Episode ▶" pill appears only during a credits/outro
      chapter with a queued successor; Enter and click both advance;
      bindings restore when it hides.
- [ ] Chain ends cleanly at season/series end and when the successor
      is unplayable — no pill, `keep-open` as today.
- [ ] Setting off = behavior byte-identical to today; default on;
      mid-session flip affects the next append.
- [ ] Resume positions: first file resumes via `--start`; appended
      episodes start at their own resume position, never the first
      file's.
- [ ] Movies and movie series: no queueing, no behavior change.
- [ ] Session recovery of a mid-chain session reattaches to the
      currently playing episode.

## Decisions

* [ADR-062 — Episode auto-advance rides the mpv playlist inside one session](../../decisions/architecture/2026-08-18-062-playlist-based-episode-advance.md)

## Deferred

* Movie-series auto-advance (mechanically free via `MovieList`, but
  rolling between films is a different feeling — separate call).
* Any credits-position heuristic for chapterless files.
* "Are you still watching" binge guard — single-user couch app, not
  wanted.

## Smoke Tests

The seam is `MpvSession`'s transition handling: unit-test the
path-change → progress-close/re-attribute/append decision as pure
logic where possible (WatchingTracker-style), and cover the successor
resolution (playability gating, season boundaries, setting off) at the
context level. The Lua pill follows skip-intro's precedent (manual
verification with `--msg-level=next_episode=trace`); no Elixir-side
test can cover it.
