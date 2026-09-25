# mpv Integration

End-user content lives on the wiki:

- **[Playback](https://github.com/media-centaur/media-centaur/wiki/Playback)** — how playback works end-to-end.
- **[Keyboard & Gamepad](https://github.com/media-centaur/media-centaur/wiki/Keyboard-and-Gamepad)** — full mpv key bindings (playback, seek, tracks, volume, subtitles).
- **[FAQ → Why mpv](https://github.com/media-centaur/media-centaur/wiki/FAQ#why-mpv)** — the rationale for delegating to mpv.

---

## Contributor internals

The remainder of this file documents how the app launches mpv, the bundled
Lua package that gives it couch behaviour, and the example config kept in
the sibling `contrib` repo. Decision record:
[ADR-072](../decisions/architecture/2026-09-25-072-bundled-mpv-scripts.md).
Design and verification transcript:
[`docs/superpowers/specs/2026-09-25-bundled-mpv-scripts-design.md`](superpowers/specs/2026-09-25-bundled-mpv-scripts-design.md).

## Two owners

The player has two owners, and mpv's own precedence rules keep them apart.

| Layer | Owner | Delivered by | Lives in |
|---|---|---|---|
| **Launch flags** | app | command line on every launch (`Playback.LaunchFlags`) | `lib/media_centaur/playback/launch_flags.ex` |
| **Bundled scripts** | app | `--script=<dir>` launch flag | `priv/mpv/scripts/media-centaur/` |
| **User config** | user | mpv reads it as it always does | `~/.config/mpv/` (or `$MPV_HOME`) |
| **User scripts** | user | mpv auto-loads `<user config>/scripts/` | `~/.config/mpv/scripts/` |
| **Example config** | user, by copying | nothing in the app needs it | `../contrib/mpv/` |

Rules that follow:

- **The session never depends on anything in the user config.** Every mpv
  behaviour `MpvSession` relies on is a launch flag, because a launch flag
  survives any `mpv.conf`.
- **The app never writes into the user config.** No `--config-dir`, no
  `--no-config`, no installer copies. `mpv.conf`, `input.conf`, user
  scripts, `script-opts/` and fonts stay live on every app launch.
- **A user tunes or disables a bundled script through mpv's script
  options**, not through the app.

## Launch flags

`Playback.LaunchFlags` builds the list; `MpvSession.spawn_mpv/2` passes it
to `Port.open`. Unit-tested without spawning anything.

| Flag | Why |
|---|---|
| `--fullscreen`, `--force-window=immediate` | The couch window. |
| `--no-terminal`, `--msg-level=all=error` | mpv's stdout is not the diagnostic channel; the log file is. |
| `--input-ipc-server=<socket>` | The observation protocol (see [`playback.md`](playback.md)). |
| `--log-file=<socket_dir>/media-centaur-<session>.log` | Exit classification and script errors. |
| `--keep-open=yes` | `eof-reached` fires only at true playlist end. `always` would fire it at every file and quit mpv mid-chain. |
| `--resume-playback=no` | The app owns position, track choice and sound toggles. mpv's watch-later restore fills in `start`, `aid`, `sid`, `af` and more whenever the command line leaves them unset, which the restart-from-0 path does. |
| `--script=<priv>/mpv/scripts/media-centaur` | The bundled package. |
| `--alang`, `--slang`, `--subs-with-matching-audio`, `--sid=no` | The language policy (`LanguageContext.to_mpv_flags/1`). |
| `--{ --start=N <file> --}` | Resume position, scoped to the launch file so appended successors start at their own offset (ADR-062). |

## Bundled package

`priv/mpv/scripts/media-centaur/` is one mpv **directory script**: mpv loads
`main.lua`, names the script after the directory (`media_centaur`) and adds
the directory to the Lua package path so the modules `require` each other.

| Module | Role |
|---|---|
| `main.lua` | Reads the script options, loads each enabled feature module, registers the default keys. |
| `pill.lua` | The shared bottom-right pill: 1080p scaling, frame, fade in/out, delay timer, hover-gated `MBTN_LEFT` capture, forced ENTER binding while visible, resize repaint, `end-file` cleanup. A feature supplies its label content and its action. |
| `theme.lua` | The palette (ASS BGR) and ASS tag helpers every overlay shares. |
| `log.lua` | `mp.msg` with a per-feature prefix, so one log domain stays readable. |
| `skip_intro.lua` | Skip Intro on an intro chapter. |
| `next_episode.lua` | Next Episode during credits, and the end-of-file countdown. |
| `track_menu.lua` | The TAB overlay: audio, subtitles, sound toggles with per-folder memory and the auto limiter. |

`priv/` ships in every release. In dev `_build/dev/lib/media_centaur/priv`
is a symlink to the repo's `priv/`, so an edit applies on the next launch.
There is no copy step.

### Script options

Read with `mp.options` from `<user config>/script-opts/media_centaur.conf`,
overridden by `--script-opts=media_centaur-<key>=<value>`.

| Option | Default | Effect |
|---|---|---|
| `skip_intro` | `yes` | Load the Skip Intro feature. |
| `next_episode` | `yes` | Load the Next Episode feature. |
| `track_menu` | `yes` | Load the track menu, its default keys and the `track-menu-toggle-sound` script-message. |

### Default keys

Registered by the package with `mp.add_key_binding`, so a stock user config
works. A user's `input.conf` overrides them by mpv precedence.

| Key | Binding | Action |
|---|---|---|
| `TAB` | `script-binding media_centaur/track-menu` | Open or close the track menu. |
| `n` | `script-binding media_centaur/night-mode` | Toggle the `dynaudnorm` sound filter (the same toggle as the menu's Sound column). |
| `ENTER` | forced while a pill shows | Skip Intro, or play the next episode. |

Other scripts toggle a sound filter with
`script-message track-menu-toggle-sound <dynaudnorm|dialog>`.

### Logging

One log domain for the package. Messages carry a feature prefix.

```bash
mpv --msg-level=media_centaur=trace /path/to/video.mkv
# [media_centaur] skip-intro: show: skip target=92.5s
# [media_centaur] next-episode: set_mode: countdown
# [media_centaur] track-menu: open_menu
```

Under the app, the same lines land in the per-session `--log-file` (copy it
while playing; it is deleted when the session stops). A Lua error in any
module is reported there too.

### Stale copies

Before this package, users copied `skip-intro.lua`, `next-episode.lua` and
`track-menu.lua` into `~/.config/mpv/scripts/`. mpv still auto-loads
those, so both the old script and the bundled module run: two pills. At
launch the session checks the user config's `scripts/` for the three
filenames and logs a `:playback` warning naming them (Status → Playback).
It never deletes them.

## Track menu (`track_menu.lua`)

A three-column overlay: Audio, Subtitles, Sound.

### Usage

Press **Tab** to toggle the menu open or closed.

- **Up/Down** move the cursor within the active column
- **Left/Right** switch columns
- **Enter** applies the highlighted track or flips the highlighted sound toggle (the menu stays open)
- **Esc**, **Tab** or **Mouse Back** close the menu

### Behaviour

- The cursor opens on the active subtitle track
- The subtitle column includes a "None" option
- The active track or toggle is marked with `●`
- Enter and Esc have global bindings in a typical `input.conf`; the menu takes them with `mp.add_forced_key_binding` while open and releases them on close
- **Sound column.** *Night mode* (`dynaudnorm`) and *Dialogue boost*
  (`dialoguenhance`) are managed audio filters. Whenever any is on, a
  true-peak limiter (`alimiter`) is appended last and removed when all are
  off. Choices are saved per folder to
  `~/.local/state/mpv/sound-toggles.json` and restored on `file-loaded`.
  Flipping a toggle while paused can reset the other one, because mpv
  cannot rebuild the audio filter chain without a live stream.

### Visual style

Dark semi-transparent panel, orange highlight bar on the cursor row, orange
column headers. All sizes scale from a 1080p baseline.

### Implementation notes

- **OSD overlay resolution.** `mp.create_osd_overlay("ass-events")` defaults
  to a 720p virtual coordinate system; the module sets `overlay.res_x` and
  `overlay.res_y` from `mp.get_osd_size()` so pixel coordinates are correct
  at any resolution.
- **Resolution scaling.** Layout values are defined at 1080p and multiplied
  by `osd_height / 1080` at render time.
- **Forward declaration.** `close_menu` is declared as a local before
  `open_menu`, whose closures reference it.

## Skip Intro (`skip_intro.lua`)

Observes mpv's `chapter` property. When the current chapter's title matches
(case-insensitive) `Intro`, `Intro …`, `Opening`, `Opening …`, `OP`,
`OP …`, `OP<digit>` or `Prologue`, and a next chapter exists, a pill
appears bottom-right after a one-second delay: `ENTER  Skip Intro  ▶▶`.
Enter or a click seeks to the next chapter's start. The pill fades out when
playback leaves the chapter.

- No user key binding is needed; the feature activates from the chapter observer
- ENTER is force-bound while the pill shows and released when it hides
- **The pill is clickable.** A `mouse-pos` observer hit-tests the cursor
  against the pill bounds; `MBTN_LEFT` is force-bound only while the cursor
  is over the pill, so clicks elsewhere still reach the OSC and seek bar.
  Hovering brightens the border to the accent colour
- Files without chapters, or with untitled chapters, are unaffected
- An intro that is the last chapter shows no pill

## Next Episode (`next_episode.lua`)

Shows a "Next Episode" pill when the playlist holds a queued successor (the
backend appends the next episode, ADR-062). Two modes:

- **Skip mode** while rolling credits play: Enter or a click advances
  immediately with `playlist-next`. The pill only shortens the credits; it
  never skips content on its own.
- **Countdown mode** in the final 20 seconds of the file, chapters or not:
  the pill reads "Next episode in Ns" so auto-play never lands unannounced.
  Enter plays now. Quitting the player is how you decline.

### How it works

Observes `chapter`, `playlist-count` and `time-remaining`. Skip mode
appears when both hold:

- the current chapter's title names the credits (`credits` or `outro`,
  case-insensitive whole word, the same words as the backend's
  `ChapterCompletion`) and the chapter starts at or after 80% of the
  runtime, so an "Opening Credits" chapter at t=0 never triggers it; and
- `playlist-count - playlist-pos > 1`, a successor is actually queued.

Countdown mode replaces it, or appears on its own for files without a
credits chapter, once `time-remaining` drops inside the 20-second window
while a successor is queued. The number is the true time to end-of-file,
so pausing pauses the countdown.

- ENTER is force-bound to `playlist-next` while the pill shows; ESC keeps
  its global binding at all times
- Same hover-gated `MBTN_LEFT` capture as Skip Intro
- A chain end or auto-play turned off means no successor and no pill
- Skip mode waits 1 s after the chapter change; countdown mode appears at once

## Example config (`../contrib/mpv/`)

An `mpv.conf`, an `input.conf` and the user script `hdr-display.lua` that a
user may copy into their user config as a starting point. Nothing in the
app reads them. What follows documents them for contributors; the user
guide is `guides/mpv-setup.md` in contrib.

### mpv.conf

**Rendering (NVIDIA + Vulkan)**

- `gpu-api=vulkan` with `vo=gpu-next` and `hwdec=nvdec`
- `profile=gpu-hq`
- `ewa_lanczossharp` for up/chroma scaling, `mitchell` for downscale

**HDR**

- `target-colorspace-hint=yes`: when the compositor runs the display in HDR
  mode, mpv emits PQ BT.2020 untouched and the display does its own tone
  mapping. `hdr-display.lua` flips the display into HDR mode for HDR content.
- **Dolby Vision is not passed through, and there is nothing to switch
  into.** No display mode on this stack carries a DV signal; mpv's
  `--target-colorspace-hint` never sends DV or HDR10+ metadata. libplacebo
  reads the DV RPU itself (`vo=gpu-next`) and applies it, so the TV receives
  HDR10. Profiles 7, 8.1 and 4 carry an HDR10 or HLG base layer, so
  `video-params/gamma` reads `pq`/`hlg` and `hdr-display.lua` engages as for
  HDR10. Profile 5 has no such base layer; mpv maps it to PQ BT.2020 in the
  frame params, which should engage the script the same way, not yet
  confirmed against a real file. A profile 7 enhancement layer is discarded.
- SDR fallback (display in SDR mode): `tone-mapping=bt.2446a` +
  `hdr-contrast-recovery=0.30`, the ITU HDR→SDR broadcast curve, brighter
  than mpv's default spline on dim-graded films.

**Subtitles**: `alang=en,eng`, `slang=en,eng`,
`subs-with-matching-audio=forced`, `subs-fallback=yes`, `sub-auto=fuzzy`.
Under the app the language policy's launch flags override the first three.

**OSD and window**: `osc=yes`, `keep-open=yes` (the app pins this itself),
`autofit-larger=90%x90%`, `cursor-autohide=1000`, `input-ar-delay=1000`
(the FLIRC remote's double-press fix).

**Audio**: `volume=100`, `volume-max=150`, `ad-lavc-ac3drc=1.0` (the
authored AC3 night-mode curve), `audio-channels=stereo`.

**Screenshots**: `~/pictures/`, PNG.

### input.conf

Section-commented, one concern per block. The package binds `TAB` and `n`
itself, so the file carries neither. Every quit key is plain `quit`: the
app saves position over IPC and launches with `--resume-playback=no`, so
`quit-watch-later` would write files the app-launched player never reads.

### hdr-display.lua (user script)

Keeps the desktop in SDR and switches the Hyprland output to 10-bit HDR
while HDR content plays. On a file whose transfer function is PQ or HLG it
runs `hyprctl eval 'hl.monitor({ … cm = "hdr" })'`; on SDR content or quit
it applies the SDR monitor line. With `target-colorspace-hint=yes` the
display receives the untouched HDR10 grade.

- Activates from a `video-params/gamma` observer
- **Every switch holds playback.** The TV shows black for about a second
  while it re-locks the HDMI link. The script pauses before the switch and
  resumes `settle_seconds` later (2.3 s), in both directions but not on
  quit. A player already paused is left alone; resuming by hand during the
  window ends the hold. The app's session sees an ordinary pause.
- **Hyprland must not auto-switch mpv.** The mpv window rule in
  `~/.config/hypr/rules.lua` sets `no_auto_hdr = true`; otherwise Hyprland
  sends the HDR infoframe on mpv's first HDR draw after the hold, a second
  re-lock a few seconds into playback.
- HDR → HDR playlist transitions do not bounce the display
- The monitor lines in the script's config table must mirror `hl.monitor` in
  `~/.config/hypr/hyprland.lua`; `hl.monitor` merges, so the SDR line resets
  every key the HDR line sets
- If mpv is killed hard, the display stays in HDR mode; run the script's SDR
  line through `hyprctl eval`, or reload Hyprland

Debug: `mpv --msg-level=hdr_display=debug /path/to/video.mkv`. For
display-side timing correlate the script's hold/release in the app's
per-session log with mpv's `Preferred surface feedback received` and
libplacebo's `Picked surface configuration … HDR10`.

This script is the canonical example of a user script: one named output,
one TV's settle time, one compositor. It is exactly what the bundled
package must never contain.
