# mpv Integration

End-user content has moved to the wiki:

- **[Playback](https://github.com/media-centaur/media-centaur/wiki/Playback)** — how playback works end-to-end.
- **[Keyboard & Gamepad](https://github.com/media-centaur/media-centaur/wiki/Keyboard-and-Gamepad)** — full mpv key bindings (playback, seek, tracks, volume, subtitles).
- **[FAQ → Why mpv](https://github.com/media-centaur/media-centaur/wiki/FAQ#why-mpv)** — the rationale for delegating to mpv.

---

## Contributor internals

The remainder of this file documents mpv configuration, the couch-mode Lua scripts shipped in `../contrib/mpv/`, and their implementation details. End users who just want to know which keys do what should use the wiki links above.

> **Repo layout note:** mpv configs live in the sibling `contrib/` repo at `~/src/media-centaur/contrib/`, not inside this main app repo. Paths below are relative to this repo's root. If the contrib repo isn't checked out alongside, clone it: `git clone git@github.com:media-centaur/contrib.git ../contrib`.

## Installation

Copy the contrib files into your mpv config directory:

```bash
cp ../contrib/mpv/mpv.conf ~/.config/mpv/mpv.conf
cp ../contrib/mpv/input.conf ~/.config/mpv/input.conf
cp -r ../contrib/mpv/scripts/ ~/.config/mpv/scripts/
```

## File Overview

| File | Purpose |
|------|---------|
| `../contrib/mpv/mpv.conf` | Player settings — rendering, subtitles, audio, OSD |
| `../contrib/mpv/input.conf` | Key bindings |
| `../contrib/mpv/scripts/track-menu.lua` | Two-column audio/subtitle track selector overlay |
| `../contrib/mpv/scripts/skip-intro.lua` | Chapter-based intro skip button |
| `../contrib/mpv/scripts/next-episode.lua` | "Next Episode" button during credits + auto-play countdown |
| `../contrib/mpv/scripts/hdr-display.lua` | Auto-switch the Hyprland output to HDR mode while HDR content plays |

## mpv.conf

### Rendering (NVIDIA + Vulkan)

- `gpu-api=vulkan` with `vo=gpu-next` and `hwdec=nvdec` for hardware-accelerated decoding
- `profile=gpu-hq` enables high-quality defaults
- High-quality scaling: `ewa_lanczossharp` for up/chroma, `mitchell` for downscale

### HDR

- `target-colorspace-hint=yes` — when the compositor runs the display in HDR
  mode, mpv emits PQ BT.2020 untouched and the display does its own tone
  mapping. The `hdr-display.lua` script (below) flips the display into HDR
  mode automatically for HDR content.
- **Dolby Vision is not passed through, and there is nothing to switch into.**
  No display mode on this stack carries a DV signal — DRM/KMS, Hyprland and
  the NVIDIA driver expose no DV tunnelling, and mpv's `--target-colorspace-hint`
  docs state it never sends DV or HDR10+ metadata. libplacebo instead reads the
  DV RPU itself (`vo=gpu-next`, format's `dolbyvision=yes` by default) and
  applies it, so the TV receives HDR10. Profiles 7, 8.1 and 4 carry an HDR10 or
  HLG base layer, so `video-params/gamma` reads `pq`/`hlg` and `hdr-display.lua`
  engages exactly as it does for HDR10. Profile 5 has no such base layer; mpv
  maps it to PQ BT.2020 in the frame params, which should engage the script the
  same way — not yet confirmed against a real file. A profile 7 enhancement
  layer (FEL) is discarded; no Linux player applies it.
- SDR fallback (display in SDR mode): `tone-mapping=bt.2446a` +
  `hdr-contrast-recovery=0.30` — the ITU HDR→SDR broadcast-conversion curve,
  noticeably brighter than mpv's default spline on dim-graded films.

### Subtitles

- Preferred languages: `alang=en,eng`, `slang=en,eng`
- `subs-with-matching-audio=forced` — only show forced subs when audio matches preferred language
- `subs-fallback=yes` — fall back to any available sub track
- `sub-auto=fuzzy` — load external subtitle files with fuzzy name matching

### OSD & Window

- `osc=yes` — built-in on-screen controller enabled
- `keep-open=yes` — don't close the window when playback ends
- `autofit-larger=90%x90%` — cap initial window size at 90% of screen
- `cursor-autohide=1000` — hide cursor after 1 second

### Audio

- `volume=100`, `volume-max=150` — default volume with headroom for boost

### Screenshots

- Saved to `~/pictures/` as PNG

## Key Bindings (input.conf)

See the wiki's [Keyboard & Gamepad](https://github.com/media-centaur/media-centaur/wiki/Keyboard-and-Gamepad) page for the user-facing reference. The canonical source is `../contrib/mpv/input.conf`.

## track-menu Plugin

`scripts/track-menu.lua` is a custom two-column overlay for selecting audio and subtitle tracks. It replaces the uosc menu with a purpose-built track selector.

### Usage

Press **Tab** to toggle the menu open/closed.

- **Up/Down** — move cursor within the active column
- **Left/Right** — switch between Audio (left) and Subtitles (right) columns
- **Enter** — apply the highlighted track (menu stays open)
- **Esc**, **Tab**, or **Mouse Back** — close the menu

### Behavior

- Cursor defaults to the currently active subtitle track on open
- The subtitle column includes a "None" option to disable subs
- Active (currently playing) track is marked with `●`
- Enter and Esc have global bindings (`cycle fullscreen` and `quit-watch-later`), but the plugin uses `mp.add_forced_key_binding` to override them while the menu is open and restores them on close

### Visual Style

Glassmorphism-inspired dark panel with semi-transparent background, blue highlight bar on the cursor row, and blue column headers. All sizes scale relative to display resolution (1080p baseline) so the menu looks consistent at any resolution.

### Debugging

Run mpv with trace-level logging for the plugin:

```bash
mpv --msg-level=track_menu=trace /path/to/video.mkv
```

This outputs detailed logs for script loading, track discovery, rendering, overlay updates, and navigation events.

### Implementation Notes

- **Script name mapping:** mpv converts hyphens in script filenames to underscores internally. The file is `track-menu.lua` but the binding in `input.conf` must use `track_menu/toggle`.
- **OSD overlay resolution:** `mp.create_osd_overlay("ass-events")` defaults to a 720p virtual coordinate system. The plugin sets `overlay.res_x` and `overlay.res_y` to match `mp.get_osd_size()` so that pixel coordinates work correctly at any resolution.
- **Resolution scaling:** All layout values (font sizes, padding, column widths) are defined at a 1080p baseline and multiplied by `osd_height / 1080` at render time.
- **Forward declaration:** Lua requires `close_menu` to be forward-declared as a local before `open_menu` since `open_menu`'s closures reference it.

## skip-intro Plugin

`scripts/skip-intro.lua` detects intro/opening chapters and shows a "Skip Intro" pill button in the bottom-right corner. Press **Enter** or **click the pill** to skip to the next chapter.

### How It Works

The script observes mpv's `chapter` property. When a chapter change occurs, it checks the chapter title (case-insensitive) against these patterns:

- `Intro`, `Intro Credits`, etc.
- `Opening`, `Opening Theme`, etc.
- `OP`, `OP 1`, `OP2`, etc.
- `Prologue`

If the title matches and there is a next chapter to skip to, a glassmorphism pill appears in the bottom-right corner with `ENTER  Skip Intro  ▶▶`. The button auto-dismisses when playback leaves the intro chapter.

### Behavior

- **No key binding needed** — the script activates automatically via chapter observation
- ENTER is force-bound to "skip to next chapter" while the button is visible, overriding the global fullscreen toggle. The global binding is restored when the button disappears.
- **The pill is clickable.** A `mouse-pos` observer hit-tests the cursor against the pill bounds; `MBTN_LEFT` is force-bound only while the cursor is over the pill, so clicks elsewhere still reach the OSC / seek bar. Hovering brightens the border to the orange accent as a clickable affordance.
- Files without chapters or with untitled chapters are unaffected
- If the intro is the last chapter (no next chapter), the button is suppressed

### Visual Style

Same glassmorphism aesthetic as track-menu: dark semi-transparent pill with subtle border, dim "ENTER" key hint, bold white "Skip Intro" label, and orange accent arrow.

### Debugging

```bash
mpv --msg-level=skip_intro=trace /path/to/video.mkv
```

This outputs chapter change events, pattern matching results, overlay rendering, and skip actions.

## next-episode Plugin

`scripts/next-episode.lua` shows a "Next Episode" pill in the bottom-right
corner when the playlist holds a queued successor (the backend appends the
next episode — ADR-062). It has two modes:

- **Skip mode** — while rolling credits play: press **Enter** or **click
  the pill** to advance immediately with `playlist-next`. The pill only
  shortens the credits, it never skips content automatically.
- **Countdown mode** — in the final 20 seconds of the file, chapters or
  not: the pill switches to "Next episode in Ns" so auto-play never lands
  unannounced. **Enter** plays now. Declining needs no dedicated control —
  quitting the player (ESC / the remote's back button, as ever) ends the
  session, queued successor and all.

### How It Works

The script observes `chapter`, `playlist-count` and `time-remaining`. Skip
mode appears when **both** hold:

- the current chapter's title names the credits (`credits`/`outro`,
  case-insensitive whole-word — same patterns as the backend's
  `ChapterCompletion`) **and** the chapter starts at ≥ 80% of the runtime
  (so an "Opening Credits" chapter at t=0 never triggers it); and
- `playlist-count - playlist-pos > 1` — a successor is actually queued.

Countdown mode replaces it (or appears on its own for files without a
credits chapter) once `time-remaining` drops inside the 20-second window
while a successor is queued. The countdown number is the true time to
end-of-file — when mpv itself advances — so pausing pauses the countdown.

### Behavior

- **No key binding needed** — activates automatically via property observers
- ENTER is force-bound to `playlist-next` while the pill is visible; the
  global binding is restored when it disappears. ESC keeps its global
  quit binding at all times — exiting the player is how you decline
- The pill is clickable with the same hover-gated `MBTN_LEFT` capture as
  skip-intro — clicks elsewhere still reach the OSC / seek bar
- Series without a queued successor (chain end, auto-play turned off) never
  show the pill in either mode
- Skip mode waits 1 s after the chapter change before appearing; countdown
  mode appears immediately

### Visual Style

Same glassmorphism pill as skip-intro: dim key hints, bold white label,
orange accent arrows. The countdown pill reuses the same
footprint — no progress bar (the ticking seconds are the countdown).

### Debugging

```bash
mpv --msg-level=next_episode=trace /path/to/video.mkv
```

This outputs chapter/playlist/time observations, credits detection results,
mode switches, overlay rendering, and advance actions.

## hdr-display Plugin

Keeps the desktop in SDR (where it looks right) while giving HDR films a
real HDR signal. When mpv loads a file whose transfer function is PQ or HLG,
the script switches the Hyprland output to 10-bit HDR mode through the
compositor's Lua config manager (`hyprctl eval 'hl.monitor({ … cm = "hdr" })'`);
when playback moves to SDR content or mpv quits, it applies the SDR monitor
line again. Combined with `target-colorspace-hint=yes`, the display receives
the film's untouched HDR10 grade and applies its own tone mapping.

### Behavior

- **No key binding needed** — activates via a `video-params/gamma` observer
- **Every switch holds playback.** The display shows black for about a
  second while it re-locks the HDMI link on a mode change (same as a game
  console). The script pauses before the switch and resumes `settle_seconds`
  later (2.3 s), so the opening of the film isn't lost under the black. The
  hold applies in both directions — entering HDR, and dropping back to SDR
  when the next playlist entry is SDR — but not on quit. A player that was
  already paused is left alone, and resuming by hand during the window ends
  the hold.
- The app's playback session sees the hold as an ordinary pause: expect a
  paused/resumed pair in the playback log on every HDR launch.
- **Hyprland must not auto-switch mpv.** The mpv window rule in
  `~/.config/hypr/rules.lua` sets `no_auto_hdr = true`. Hyprland's
  `render:cm_auto_hdr` (on by default) sends the HDR infoframe only once the
  fullscreen surface is HDR, and mpv's swapchain turns HDR on its first draw
  after the hold — that put a second HDMI re-lock a few seconds into
  playback. With the rule, the infoframe follows the script's monitor line,
  inside the hold.
- HDR → HDR playlist transitions don't bounce the display (gamma is only
  `nil` between files, and `nil` never triggers a switch)
- The monitor lines in the script's config table must mirror `hl.monitor` in
  `~/.config/hypr/hyprland.lua` so the SDR line lands on the compositor's
  steady state. `hl.monitor` merges, so the SDR line resets every key the
  HDR line sets.
- If mpv is killed hard (no shutdown event), the display stays in HDR mode —
  recover by running the script's SDR line through `hyprctl eval`, or reload
  Hyprland

### Debugging

```bash
mpv --msg-level=hdr_display=debug /path/to/video.mkv
```

This outputs gamma observations, the hold and release of playback around
each switch, and the hyprctl calls.

For display-side timing, the app launches mpv with `--log-file` at
`/tmp/media-centaur-<session>.log` (deleted when the session stops — copy it
while playing). The lines to correlate are the script's hold/release, mpv's
`Preferred surface feedback received` (the compositor's colourspace change)
and libplacebo's `Picked surface configuration … HDR10` (mpv's swapchain
turning HDR). The Hyprland log shows `drm: Modesetting` per re-lock but
carries no timestamps.
