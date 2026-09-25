---
status: accepted
date: 2026-09-25
---
# Bundled mpv scripts ship in the release; the user's mpv config is the user's

## Context and Problem Statement

The couch behaviours in the player (Skip Intro, Next Episode, the track
menu) were three Lua scripts in the sibling `contrib` repo that a user
copied by hand into `~/.config/mpv/scripts/`. A fresh install had none of
them, an installed copy never updated with the app, and it sat beside the
owner's machine-specific script (`hdr-display.lua`: one compositor, one
named output, one TV's settle time). The scripts implement the app's own
playlist protocol (ADR-062), so their version drifted from the code that
depends on them. The ask: ship the behaviours as a default on every
install without taking the user's mpv configuration away from them.

Two facts shaped the decision. The session relied on `keep-open=yes` from
the contrib `mpv.conf`, a file the user might not have. And mpv's
watch-later restore (`--resume-playback`, default on) fills in `start`,
`aid`, `sid`, `af` and more whenever the command line leaves them unset,
which the app's restart-from-0 path does; the contrib `input.conf` bound
ESC to `quit-watch-later`, so a completed film could resume at 92% on its
next play and the entry was consumed, never reproducing twice. Verified
2026-09-25 against mpv 0.41.

## Decision Outcome

Chosen option: "two owners, separated by mpv's own precedence rules",
because each layer then has one delivery mechanism that mpv already
provides and neither layer can write into the other's.

1. **The app owns launch flags and bundled scripts.** Every mpv behaviour
   `Playback.MpvSession` relies on is a command-line option, built by
   `Playback.LaunchFlags`: the existing six, plus `--keep-open=yes`,
   `--resume-playback=no` and `--script=<priv>/mpv/scripts/media-centaur`.
   A launch flag survives any `mpv.conf`, so the session never depends on
   anything in the user config.
2. **The bundled scripts are one mpv directory script in `priv/`.**
   `priv/mpv/scripts/media-centaur/` (`main.lua`, `pill.lua`, `theme.lua`, `log.lua`,
   `skip_intro.lua`, `next_episode.lua`, `track_menu.lua`) ships in every
   release, updates with the app, and is smoke-tested by loading it into
   mpv in CI. In dev the priv symlink makes an edit live on the next launch.
3. **The user owns `~/.config/mpv/`.** The app never writes there: no
   `--config-dir`, no `--no-config`, no `--load-scripts=no`, no installer
   copies. `mpv.conf`, `input.conf`, user scripts, `script-opts/` and fonts
   apply on every app launch as they do when mpv is started by hand.
4. **A user tunes or disables a bundled feature through mpv's script
   options** (`script-opts/media_centaur.conf`: `skip_intro`,
   `next_episode`, `track_menu`), and rebinds its default keys (`TAB`,
   `n`) in their own `input.conf`. No app Setting duplicates either.
5. **Contrib keeps an example config**: `mpv.conf`, `input.conf`,
   `hdr-display.lua`. Nothing in the app requires it.

Rejected: `--config-dir=<app-managed dir>` (mpv then ignores every other
config directory, including the user's); the installer copying scripts
into the user config (the app becomes a writer there, updates overwrite
edits or go stale, and the scripts run in standalone mpv with no session);
three single-file `--script=` entries (isolates a Lua error per feature but
cannot share code, so the pill rendering stays copied).

### Consequences

* Good, because a fresh install has the couch behaviours on first play and
  every release carries the scripts its protocol expects.
* Good, because the user's own scripts, rendering settings and key
  bindings keep working with no app involvement, and the one
  machine-specific script stays exactly where it belongs.
* Good, because two latent dependencies on the user config (`keep-open`,
  watch-later restore) became explicit flags with unit tests.
* Bad, because one directory script is one Lua state: a runtime error in
  one feature takes the other two down for that launch. Script errors land
  in the per-session log the app already captures.
* Bad, because a user who copied the old scripts sees doubled overlays
  until they delete the three files; the session logs a warning naming
  them and never deletes them.
* Scheduled, not done: the sound-toggle memory (per folder, script-owned)
  and remembered tracks (per title, app-owned) are two representations of
  one idea; the credits word list is mirrored between
  `Playback.ChapterCompletion` and `next_episode.lua`. Both are recorded in
  the campaign with their triggers.

Campaign: `campaigns/bundled-mpv-scripts.md`. Design and verification
transcript: `docs/superpowers/specs/2026-09-25-bundled-mpv-scripts-design.md`.
