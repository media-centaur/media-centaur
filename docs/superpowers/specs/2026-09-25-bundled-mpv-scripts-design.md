# Bundled mpv scripts — design

**Status:** design, awaiting owner approval (2026-09-25). No code changed.

**Problem.** Media Centaur's couch behaviours in the player (Skip Intro, Next
Episode, the track menu) only exist for a user who clones the contrib repo
and hand-copies three Lua files into `~/.config/mpv/scripts/`. A fresh
install has none of them, an installed copy never updates with the app, and
the same directory holds the owner's machine-specific script
(`hdr-display.lua`). The ask: ship the couch behaviours as a default on every
install without taking the user's own mpv configuration away from them.

## Glossary

Terms are mpv's where mpv has one. Defined before use; refined as the work
proceeds; promoted to `docs/GLOSSARY.md` at completion.

| Term | Meaning |
|---|---|
| **player** | The mpv process one playback session launches (`Playback.MpvSession`). |
| **launch flags** | The mpv command-line options the session passes on every launch. mpv gives command-line options precedence over every config file, so a launch flag is the one place a session requirement cannot be undone by user configuration. |
| **user config** | mpv's per-user configuration directory, `~/.config/mpv/` (or `$MPV_HOME`): `mpv.conf`, `input.conf`, `scripts/`, `script-opts/`, `fonts/`. Owned by the user. The app never writes into it. |
| **bundled scripts** | The Lua scripts Media Centaur ships inside its release under `priv/mpv/scripts/` and loads on every launch with the `--script=` launch flag. Versioned, tested and updated with the app. |
| **user scripts** | Lua scripts in the user config's `scripts/` directory. mpv auto-loads them on every launch (`--load-scripts=yes`, the default). `hdr-display.lua`, uosc and mpv-mpris are user scripts. |
| **script option** | mpv's per-script settings mechanism (`mp.options`): values come from `<user config>/script-opts/<script>.conf` and are overridden by the `--script-opts=` launch flag. The one way a user tunes or disables a bundled script. |
| **example config** | The `mpv/` directory of the contrib repo after this change: an `mpv.conf`, an `input.conf` and `hdr-display.lua` a user may copy into their user config as a starting point. Nothing in the app requires it. |

## Core idea

**The player has two owners, and mpv's own precedence rules keep them
apart.** Media Centaur owns what makes mpv *its* player: the session's
assumptions about mpv (launch flags) and the couch behaviours (bundled
scripts). The user owns how their machine plays: rendering, display, keys,
extra scripts (user config, user scripts). Each owner's layer is delivered
through the mpv mechanism built for it, and neither layer writes into the
other's.

Skip Intro is then an instance of "a bundled script", the HDR switcher is an
instance of "a user script", and `keep-open` is an instance of "a launch
flag". Nothing sits beside the model.

## Greenfield design

### 1. Bundled scripts live in the app and load per launch

`priv/mpv/scripts/media-centaur/` is one mpv **directory script**: a
`main.lua` that loads feature modules (`skip_intro.lua`,
`next_episode.lua`, `track_menu.lua`) and the module they share (`pill.lua`:
palette, 1080p scaling, the pill with its hover-gated click binding). mpv
names a directory script after the directory, so the script is
`media_centaur`: one log domain (`--msg-level=media_centaur=trace`), one
script-options file (`script-opts/media_centaur.conf`), one
`script-binding media_centaur/<name>` namespace.

The session passes
`--script=#{Application.app_dir(:media_centaur, "priv/mpv/scripts/media-centaur")}`.
`priv/` ships in every Mix release. In dev, `_build/dev/lib/media_centaur/priv`
is a symlink to the repo's `priv/`, so an edit applies on the next launch
with no copy step. The "forgot to copy the script" failure mode disappears.

Verified 2026-09-25 with mpv 0.41: `--script=<dir>` loads `main.lua`, the
script name is the directory name, a sibling `require("util")` resolves,
`script-opts/<name>.conf` from the config directory is read, and
`--script-opts=<name>-key=value` on the command line overrides the file.

**Trade-off stated.** One directory script means one Lua state and one event
loop for all three features: a runtime error in one takes the other two
down for that launch. Three single-file scripts would isolate them but
cannot share code (mpv adds the script directory to the Lua package path
only for directory scripts), so the pill rendering stays copied. The
package is mpv's recommended packaging for multi-file scripts; script
errors land in the per-session `--log-file` the app already captures, so a
crash is visible on Status → Playback. Package wins.

### 2. Launch flags carry every assumption the session makes

Rule: **the session must not depend on anything in the user config.** Every
mpv behaviour the session relies on is a launch flag, because a launch flag
survives any `mpv.conf`. Today's six flags stay. Three are added:

| Flag | Why |
|---|---|
| `--script=<bundled scripts>` | §1. |
| `--keep-open=yes` | The session's `eof-reached` handler and its moduledoc claim ("quit-on-EOF only ever fires at true playlist end") hold for `yes` and `no`, not for `always`, which fires `eof-reached` at every file and would quit mpv mid-chain. Today `keep-open=yes` lives in the contrib `mpv.conf`, so the claim depends on a file the user may not have. |
| `--resume-playback=no` | The app owns position (`--start`), track choice (`--alang`/`--slang`, remembered tracks) and sound toggles. mpv's watch-later restore fills in any of `start`, `aid`, `sid`, `af`, `vf`, `volume` … the command line did not set. Verified 2026-09-25: with a watch-later entry present, a launch with a per-file `--start=5` starts at 5, but a launch with **no** `--start` (the app's "restart from 0" and "play from 0" paths) starts at the saved 20 s, and the entry is consumed, so it never reproduces twice. The contrib `input.conf` binds ESC — the remote's back button — to `quit-watch-later`, which writes exactly such entries. |

The flag list becomes a pure function in its own module
(`Playback.LaunchFlags`, seeded from today's `launch_target/2`), unit-tested
without spawning anything. `spawn_mpv/2` calls it.

### 3. User config stays live and untouched

No `--config-dir`, no `--no-config`, no `--load-scripts=no`, no installer
writes into `~/.config/mpv/`. The user's `mpv.conf`, `input.conf`, user
scripts, script options and fonts all apply on every app launch exactly as
they do when mpv is started by hand. This is the property that keeps
`hdr-display.lua`, uosc and mpv-mpris working with no app involvement.

### 4. Bundled scripts bring their own default keys

Each feature registers its default key with `mp.add_key_binding` so a stock
user config works: `TAB` for the track menu (already the case), `n` for
night mode (today only in the contrib `input.conf`). mpv gives `input.conf`
precedence over script defaults, so a user rebinds or removes either by
editing their own file. ENTER on the pills stays a forced binding while a
pill is visible, as today.

### 5. Bundled scripts can be turned off with a script option

`script-opts/media_centaur.conf` accepts `skip_intro=no`, `next_episode=no`,
`track_menu=no`. This is the opt-out for users who run uosc's menus or one
of the chapter-skip scripts the contrib guide recommends. A bundled script
with no off switch would contradict that guide. No app Setting for this: the
script option is mpv-native and is one representation. If a Setting ever
appears it delivers into the same option via `--script-opts`, which wins
over the file by mpv precedence. *Droppable if scope must shrink.*

### 6. Contrib keeps the example config

`contrib/mpv/` becomes the example config: `mpv.conf` (rendering, HDR, audio
dynamic range), a trimmed `input.conf`, and `hdr-display.lua` as the
canonical user script (Hyprland, one named output, one TV's settle time —
nothing an app can ship). The README stops calling it "the app's source of
truth". `input.conf` loses the lines the app now owns or that fight it:
`TAB script-binding track_menu/toggle` and the `n` line (defaults in the
script), `quit-watch-later` on ESC/Q/MBTN_BACK (plain `quit`; the app saves
position over IPC regardless), and `h script-binding memo-history` (a
third-party script the guide never installs).

### 7. Migration for existing installs

A user who copied the old scripts has `skip-intro.lua`, `next-episode.lua`
and `track-menu.lua` in `~/.config/mpv/scripts/`. After the update, mpv
loads those *and* the bundled package: two Skip Intro pills. The app cannot
delete files in the user config (§3), so:

- CHANGELOG entry names the three files to delete.
- On launch, the session checks the user config's `scripts/` for those
  three filenames and logs a `:playback` warning naming them, visible on
  Status → Playback. One `File.exists?` per name; no other behaviour.

The sound-toggle memory file (`~/.local/state/mpv/sound-toggles.json`) is
script-owned state; the module keeps the same path, so nothing is lost.

## Diff against the code

| Greenfield | Today | Gap | Disposition |
|---|---|---|---|
| Bundled scripts ship in the release | Three scripts in the contrib repo, hand-copied per machine; version drifts from the ADR-062 playlist protocol they implement | incoherent placement | **Fix now**: move into `priv/mpv/scripts/media-centaur/`. |
| One package, one pill module | Pill rendering and hover-click capture copied between `skip-intro.lua` and `next-episode.lua`; palette copied into three scripts | duplication | **Fix now**, as part of the move (cheapest moment to touch every line). |
| Launch flags carry every session assumption | `keep-open=yes` in contrib `mpv.conf`; `resume-playback` left at mpv's default, verified to restore position/tracks/filters on the no-`--start` path | latent dependency on user config | **Fix now**: `--keep-open=yes`, `--resume-playback=no`, `LaunchFlags` module + tests. |
| Scripts register default keys | `track-menu` already binds TAB; `n` only in `input.conf` | clean seam exists | Use it: add the `n` default. |
| Bundled scripts have an off switch | None; guide recommends alternatives that would double up | missing | **Fix now** (§5), droppable. |
| App never writes into user config | Already true | — | Keep; state it in the ADR. |
| Contrib is an example config | Presents itself as the app's source of truth; carries lines that fight the app (§6) | incoherent wording + bindings | **Fix now** in contrib. |
| One owner per "remembered per-title playback choice" | App remembers tracks per title as languages; `track-menu` remembers sound toggles per *folder* in its own JSON file | two representations of one idea | **Scheduled convergence**, not in this change. Trigger: sound toggles get an app-side surface, or folder-keyed memory breaks under relink-on-move. Convergence point: the app owns the choice, delivers it per launch via `--script-opts`, and the script reports changes with `script-message` (arrives as a `client-message` IPC event). |
| Credits chapter patterns exist once | `Playback.ChapterCompletion` (Elixir regex) and `next-episode.lua` (Lua frontier patterns) mirror each other by hand | two representations | **Scheduled**: next time either list changes, pass one word list from the app via script option and let each side build its own matcher. |

## Rejected shapes

- **`--config-dir=<app-managed dir>`.** mpv then ignores every other config
  directory, including the user's. Kills user scripts outright.
- **Installer copies scripts into `~/.config/mpv/scripts/`.** Makes the app
  a writer into the user's directory: updates either overwrite user edits
  or go stale, and the scripts run in standalone mpv where no session
  exists.
- **Three `--script=` files, no package.** Keeps the duplicated pill code
  for the sake of per-script isolation. See §1 trade-off.
- **App Settings for overlay on/off.** A second entry point to the same
  option; not needed until a preference actually exists (§5).

## Cost

| Item | Size |
|---|---|
| Lua: restructure three scripts (1,617 lines) into the package, extract `pill.lua`, rename the log domain, add the `n` default and the three options | Largest item. One focused session. Manual verification on the TV as today. |
| Elixir: `Playback.LaunchFlags` + tests; stale-copy warning | Small. |
| Verification tooling: `luac -p priv/mpv/**/*.lua` in `mix precommit`; `apt-get install lua5.4` on the CI runner | Small. An mpv smoke test on CI (`mpv --no-config --script=… --idle=once`, assert the load line) needs `mpv` on both runners — droppable. |
| Docs: `docs/mpv.md`, `mpv-extensions` skill (deployment section deleted), guide chapter *Customizing mpv* rewritten as "what is built in / what you can add / how to turn a built-in off", wiki *Playback* + *Keyboard & Gamepad* (the "ESC saves, q doesn't" claim is wrong under the app), contrib README + `guides/mpv-setup.md`, CHANGELOG migration line | Seven files across three repos. |
| ADR: "Bundled mpv scripts ship in the release; the user config is the user's" | Written at implementation, repository-wide boundary rule. |

Two to three sessions. Whether this is a campaign or a single plan is the
owner's call; the work has a definable end state and no long tail.

## Verification transcript (2026-09-25, mpv 0.41.0)

```
# directory script via --script, sibling require, script-opts from config dir
mpv --config-dir=$T/cfg --script=$T/mc --idle=once
  [mc] name=mc enabled=no util=ok dir=…/mc          # enabled=no came from cfg/script-opts/mc.conf
mpv … --script-opts=mc-enabled=cli
  [mc] name=mc enabled=cli …                          # CLI wins over the file

# watch-later vs --start
quit-watch-later at 20 s, then:
mpv … --{ --start=5 test.mkv --}    → time-pos=5.2   # explicit --start wins
mpv … test.mkv                      → time-pos=20.4  # no --start: watch-later restores; entry then deleted
```

Default `--watch-later-options` includes `start, aid, sid, af, vf, volume,
mute, speed, sub-delay, …`.
