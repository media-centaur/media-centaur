# mpv Integration

End-user content has moved to the wiki:

- **[Playback](https://github.com/media-centarr/media-centarr/wiki/Playback)** — how playback works end-to-end.
- **[Keyboard & Gamepad](https://github.com/media-centarr/media-centarr/wiki/Keyboard-and-Gamepad)** — full mpv key bindings (playback, seek, tracks, volume, subtitles).
- **[FAQ → Why mpv](https://github.com/media-centarr/media-centarr/wiki/FAQ#why-mpv)** — the rationale for delegating to mpv.

---

## Contributor internals

The remainder of this file documents mpv configuration, the couch-mode Lua scripts shipped in `contrib/mpv/`, and their implementation details. End users who just want to know which keys do what should use the wiki links above.

## Installation

Copy the contrib files into your mpv config directory:

```bash
cp contrib/mpv/mpv.conf ~/.config/mpv/mpv.conf
cp contrib/mpv/input.conf ~/.config/mpv/input.conf
cp -r contrib/mpv/scripts/ ~/.config/mpv/scripts/
```

## File Overview

| File | Purpose |
|------|---------|
| `contrib/mpv/mpv.conf` | Player settings — rendering, subtitles, audio, OSD |
| `contrib/mpv/input.conf` | Key bindings |
| `contrib/mpv/scripts/track-menu.lua` | Two-column audio/subtitle track selector overlay |
| `contrib/mpv/scripts/skip-intro.lua` | Chapter-based intro skip button |

## mpv.conf

### Rendering (NVIDIA + Vulkan)

- `gpu-api=vulkan` with `vo=gpu-next` and `hwdec=nvdec` for hardware-accelerated decoding
- `profile=gpu-hq` enables high-quality defaults
- High-quality scaling: `ewa_lanczossharp` for up/chroma, `mitchell` for downscale

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

See the wiki's [Keyboard & Gamepad](https://github.com/media-centarr/media-centarr/wiki/Keyboard-and-Gamepad) page for the user-facing reference. The canonical source is `contrib/mpv/input.conf`.

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

`scripts/skip-intro.lua` detects intro/opening chapters and shows a "Skip Intro" pill button in the bottom-right corner. Press **Enter** to skip to the next chapter.

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
- Files without chapters or with untitled chapters are unaffected
- If the intro is the last chapter (no next chapter), the button is suppressed

### Visual Style

Same glassmorphism aesthetic as track-menu: dark semi-transparent pill with subtle border, dim "ENTER" key hint, bold white "Skip Intro" label, and orange accent arrow.

### Debugging

```bash
mpv --msg-level=skip_intro=trace /path/to/video.mkv
```

This outputs chapter change events, pattern matching results, overlay rendering, and skip actions.
