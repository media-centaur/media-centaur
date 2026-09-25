---
status: active
started: 2026-09-25
last_updated: 2026-09-25
---
# Bundled mpv scripts

## Goal

Ship the couch behaviours in the player (Skip Intro, Next Episode, the
track menu) with the app itself, so a fresh install has them and every
update carries them, without the app ever writing into the user's own mpv
configuration. Design and rationale:
[`docs/superpowers/specs/2026-09-25-bundled-mpv-scripts-design.md`](../docs/superpowers/specs/2026-09-25-bundled-mpv-scripts-design.md).

## Glossary

Defined in the design spec; promoted to `docs/GLOSSARY.md` at completion.
*Player*, *launch flags*, *user config*, *bundled scripts*, *user
scripts*, *script option*, *example config*.

## Status

Approved 2026-09-25 with these assumptions fixed by the implementer:

* One directory script, `priv/mpv/scripts/media-centaur/` (mpv script
  name `media_centaur`), with feature modules `skip_intro.lua`,
  `next_episode.lua`, `track_menu.lua`, a shared `pill.lua`, and `theme.lua` + `log.lua` for the palette and the per-feature log prefix.
* Opt-out script options are in: `skip_intro`, `next_episode`,
  `track_menu` (`yes`/`no`, default `yes`) read from
  `script-opts/media_centaur.conf` or `--script-opts=media_centaur-…`.
* Default keys registered by the package: `TAB` → `media_centaur/track-menu`,
  `n` → `media_centaur/night-mode`. The `track-menu-toggle-sound`
  script-message stays as the seam for other callers.
* Launch flags gain `--keep-open=yes`, `--resume-playback=no`,
  `--script=<bundled dir>`; the list becomes `Playback.LaunchFlags`.
* Stale copies of the old three files in the user config's `scripts/`
  are reported as a `:playback` warning at launch, never deleted.
* The Linux CI runner installs `mpv`; an ExUnit smoke test
  (`bundled_scripts_test.exs`) loads the package in headless mpv, walks a
  committed chaptered fixture through Skip Intro, Next Episode and the
  countdown, and asserts on the log. No `luac` step — a syntax error in
  any module fails that same load.
* Commits stay local (app, contrib, wiki) until the owner says ship.

Implemented 2026-09-25 in one session: Lua package, `Playback.LaunchFlags`
+ `MpvUserConfig`, smoke test, CI, docs on all three surfaces, ADR-072,
glossary. `mix precommit` green. Committed locally in app, contrib and wiki;
nothing pushed. The old single-file copies were removed from the owner's
`~/.config/mpv/scripts/`. Remaining: the owner's real launch on the TV
(rendering cannot be checked headless: `--vo=null` reports an OSD size of
0, so the ASS path never runs in the test), then `/ship`.

## Decisions made

* `2026-09-25` — Two owners: app owns launch flags + bundled scripts,
  user owns `~/.config/mpv/`. Rejected `--config-dir` takeover and
  installer copies into the user config. (design spec; ADR to be written
  with the implementation)
* `2026-09-25` — `--resume-playback=no` is a required launch flag:
  verified that mpv's watch-later restore wins whenever the app launches
  without `--start` (the restart-from-0 path) and restores `aid`/`sid`/`af`
  too. (design spec, verification transcript)
* `2026-09-25` — One package over three files: shared pill module beats
  per-script isolation; script errors are visible in the per-session
  log the app captures.
* `2026-09-25` — Accepted one behaviour change from the pill extraction:
  a pending Skip Intro delay is kept, not restarted, when another intro
  chapter arrives inside the 1 s window (Next Episode's rule became the
  shared one). Observable only for an intro chapter shorter than 1 s.
* `2026-09-25` — `theme.lua` and `log.lua` added beyond the design's
  five modules: the palette was copied three times and the single log
  domain needs a per-feature prefix. ([ADR-072](../decisions/architecture/2026-09-25-072-bundled-mpv-scripts.md))

## Next steps

1. Owner: press Play on a title with an intro chapter and check the pills
   and the TAB menu render as before; check Status → Playback shows no
   stale-copy warning.
2. `/ship`: the CHANGELOG entry carries the migration line (delete
   `skip-intro.lua`, `next-episode.lua`, `track-menu.lua` from
   `~/.config/mpv/scripts/`, or the buttons appear twice; Status →
   Playback names them). Push contrib and the wiki with the release.
3. Delete this file.

## Scheduled convergences (not in this campaign)

* Sound-toggle memory (`~/.local/state/mpv/sound-toggles.json`, per
  folder, script-owned) vs remembered tracks (per title, app-owned).
  Trigger: an app-side surface for sound toggles, or folder keys breaking
  under relink-on-move. Convergence: app owns it, delivers via
  `--script-opts`, script reports changes with `script-message`.
* Credits chapter word list mirrored between `Playback.ChapterCompletion`
  and `next_episode.lua`. Trigger: the next change to either list.

## Completion criteria

* A fresh install with an empty `~/.config/mpv/` shows Skip Intro, Next
  Episode and the TAB track menu on the first play.
* `~/.config/mpv/` on the owner's machine keeps `hdr-display.lua`, uosc
  fonts and `mpv.conf` untouched, and they keep working.
* No file under `contrib/mpv/` is required for any app behaviour.
* The three launch flags are unit-tested; the package smoke test runs in
  CI on Linux.
* Docs on all three surfaces describe the bundled/user split; ADR filed;
  glossary terms promoted.
* Campaign file deleted on completion (git history is the archive).

## Pointers

* Design: `docs/superpowers/specs/2026-09-25-bundled-mpv-scripts-design.md`
* Session: `lib/media_centaur/playback/mpv_session.ex` (`spawn_mpv/2`)
* Auto-advance protocol the scripts implement: ADR-062
* mpv facts verified 2026-09-25 (mpv 0.41): `--script=<dir>` loads
  `main.lua`, sibling `require` works, `script-opts/<name>.conf` is read
  from the user config, CLI `--script-opts` wins over the file.
