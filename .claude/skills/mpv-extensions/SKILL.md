---
name: mpv-extensions
description: Use this skill when creating or modifying mpv Lua scripts, mpv configuration, key bindings, or any playback overlay UI. Covers the bundled package under priv/mpv, the shared pill module, script options, forced key binding lifecycle, OSD scaling, and project conventions for media-center-style mpv extensions.
---

Media Centaur gives mpv couch behaviour (track menu, Skip Intro, Next
Episode) through one Lua package it ships in the release and loads on every
launch. The package is app code: it lives in this repo, is versioned with
the app, and never touches the user's own mpv configuration.

Read [`docs/mpv.md`](../../../docs/mpv.md) for the two-owner model, the
launch flags and each feature's behaviour, and the
[mpv Lua API reference](references/mpv-lua-api.md) before writing any
script code.

## Layout

| Path | Purpose |
|------|---------|
| `priv/mpv/scripts/media-centaur/main.lua` | Entry point: reads script options, loads each enabled feature, registers default keys |
| `priv/mpv/scripts/media-centaur/pill.lua` | Shared bottom-right pill (frame, fade, hover-gated click, forced ENTER, cleanup) |
| `priv/mpv/scripts/media-centaur/theme.lua` | The palette (ASS BGR) and ASS tag helpers; every overlay requires it |
| `priv/mpv/scripts/media-centaur/log.lua` | `mp.msg` with a per-feature prefix: `local msg = require("log")("my-feature")` |
| `priv/mpv/scripts/media-centaur/skip_intro.lua` | Skip Intro feature |
| `priv/mpv/scripts/media-centaur/next_episode.lua` | Next Episode + countdown feature |
| `priv/mpv/scripts/media-centaur/track_menu.lua` | Track menu + sound toggles |
| `lib/media_centaur/playback/launch_flags.ex` | The launch flags, including `--script=<this dir>` |
| `../contrib/mpv/` | Example config (`mpv.conf`, `input.conf`, `hdr-display.lua`) users may copy; nothing in the app reads it |

The directory is one mpv **directory script**: mpv loads `main.lua`, names
the script `media_centaur` after the directory, and puts the directory on
the Lua package path, so modules `require("pill")` each other.

## No deploy step

In dev, `_build/dev/lib/media_centaur/priv` is a symlink to the repo's
`priv/`. Save the file, start playback from the app, and the new code runs.
Never copy anything into `~/.config/mpv/`: that directory is the user's,
and a copy there would load alongside the bundled module (two pills).

To run the package outside the app:

```bash
mpv --script=priv/mpv/scripts/media-centaur --msg-level=media_centaur=trace /path/to/video.mkv
```

## Script options

`main.lua` reads options with `mp.options`; users set them in
`~/.config/mpv/script-opts/media_centaur.conf` or with
`--script-opts=media_centaur-<key>=<value>`. Current options: `skip_intro`,
`next_episode`, `track_menu`, each `yes`/`no`, default `yes`. A new feature
gets an option of its own name so a user can turn it off. Do not add an
app Setting for the same thing; the script option is the one
representation.

## Default keys

A feature that needs a toggle key registers it itself:

```lua
mp.add_key_binding("tab", "track-menu", toggle_menu)   -- script-binding media_centaur/track-menu
mp.add_key_binding("n", "night-mode", toggle_night)     -- script-binding media_centaur/night-mode
```

A user's `input.conf` overrides these by mpv precedence, so nothing goes
into the example config for them. Features that activate from property
observers (the pills) need no key at all.

## Project visual style

All overlays share a **glassmorphism** aesthetic: dark semi-transparent
panels with subtle borders and blue-orange accents. The palette (ASS BGR
format) lives once, in `theme.lua`; require it rather than copying values:

```lua
local theme = require("theme")
theme.bg      -- "40302A"  dark panel / pill background
theme.hl      -- "FF9F4B"  cursor highlight bar
theme.text    -- "ECE8E8"  normal text
theme.bright  -- "FFFFFF"  highlighted / label text
theme.header  -- "FF9F4B"  headers and accents (arrows)
theme.border  -- "ECE8E8"  panel / pill border
theme.dim     -- "808080"  placeholder and key-hint text
theme.active  -- "FF9F4B"  active markers
-- tag helpers: theme.color(bgr), theme.alpha(hex), theme.border_color(bgr), theme.border_alpha(hex)
```

Alphas are per surface, not part of the theme (a pill is fully opaque, the
track menu ~96%). Do not invent new colors.

## Building a pill

A bottom-right action pill (Skip Intro, Next Episode) is `pill.lua`'s job.
It owns the frame, the fade in/out, the show delay, the hover-gated
`MBTN_LEFT` capture, the forced ENTER binding while visible, repaint on
`osd-width`/`osd-height`, and cleanup on `end-file`. A feature supplies
its label content and its action and calls show/hide. Read the module
header for the current constructor signature before adding a third pill;
extend the module rather than copying its rendering into a feature.

## Resolution scaling

All dimensions are defined at a **1080p baseline** and scaled at render
time:

```lua
local scale = osd_height / 1080
local font_size = math.floor(cfg.font_size * scale)
```

Apply `math.floor` to prevent sub-pixel artifacts. Always set
`overlay.res_x` and `overlay.res_y` to the actual OSD dimensions (mpv
defaults to 720p virtual coordinates otherwise).

## Feature module structure

```
1. Header comment: name, one-line purpose
2. Requires: mp.msg, pill (for pills) or mp.assdraw (for panels)
3. Config table: sizes at 1080p baseline; colours from pill's palette
4. State table: visible flag, overlay handle, cursor/selection state
5. Helpers
6. Data refresh: query mpv properties, normalize into state
7. Render function: build ASS document, update overlay
8. Navigation/interaction
9. Show/hide lifecycle: forced key bindings, overlay creation/removal
10. Property observers
11. Event handlers: end-file cleanup
12. Registration: initial key binding or observer
```

Each module returns nothing; requiring it registers its observers.
`main.lua` requires a module only when its option is on.

## Forced key binding lifecycle

When a feature captures keys (ENTER on a pill, arrows in a menu), use
forced bindings that override `input.conf` only while the UI is active:

```lua
local bindings = {}
local function bind(key, name, fn)
    bindings[#bindings + 1] = name
    mp.add_forced_key_binding(key, name, fn, { repeatable = true })
end
bind("enter", "track-menu-enter", do_action)

-- On hide:
for _, name in ipairs(bindings) do
    mp.remove_key_binding(name)
end
bindings = {}
```

**Namespace binding names** with the feature prefix (`skip-intro-enter`,
`track-menu-up`): all features share one script, so names collide across
modules otherwise. mpv stacks forced bindings; the most recently added
wins, and removing one restores the previous.

## Overlay lifecycle

```lua
if not state.overlay then
    state.overlay = mp.create_osd_overlay("ass-events")
end
state.overlay.res_x = w
state.overlay.res_y = h
state.overlay.data = ass.text
state.overlay:update()

-- On hide:
if state.overlay then
    state.overlay:remove()
    state.overlay = nil
end
```

Always nil-check before `:remove()`. Always re-render on
`osd-width`/`osd-height` changes.

## Logging

One log domain for the package. Prefix every message with the feature name
so the stream stays readable:

```lua
local msg = mp.msg
msg.info("skip-intro: loaded")
msg.debug("track-menu: tracks refreshed: 3")
msg.trace("next-episode: render: osd 1920x1080")
msg.warn("skip-intro: osd size is 0")
```

Debug with `mpv --msg-level=media_centaur=trace …`. Under the app the same
lines land in the per-session `--log-file` (`/tmp/media-centaur-<session>.log`,
deleted when the session stops).

## ASS rendering quick reference

```lua
local assdraw = require("mp.assdraw")
local ass = assdraw.ass_new()

-- Background rectangle:
ass:new_event()
ass:pos(0, 0)
ass:append("{\\an7\\bord0\\shad0\\1c&H40302A&\\1a&H0A&\\p1}")
ass:draw_start()
ass:round_rect_cw(x1, y1, x2, y2, corner_radius)
ass:draw_stop()

-- Border (transparent fill, visible stroke):
ass:new_event()
ass:pos(0, 0)
ass:append("{\\an7\\bord2\\shad0\\1a&HFF&\\3c&HECE8E8&\\3a&H80&\\p1}")
ass:draw_start()
ass:round_rect_cw(x1, y1, x2, y2, corner_radius)
ass:draw_stop()

-- Text:
ass:new_event()
ass:pos(x, y)
ass:append("{\\an7\\bord0\\shad0\\fs36\\fnsans-serif\\1c&HFFFFFF&}Hello")
```

**ASS alignment anchors:** `\an7`=top-left, `\an8`=top-center,
`\an9`=top-right, `\an4`=mid-left, `\an5`=mid-center, `\an6`=mid-right,
`\an1`=bot-left, `\an2`=bot-center, `\an3`=bot-right.

**Colors are BGR, not RGB.** `FF9F4B` in ASS = `#4B9FFF` in web.

## Documentation

When adding or modifying a feature, update `docs/mpv.md` (the module
table, the option table if one was added, the feature's section) and the
wiki's *Keyboard & Gamepad* and *Playback* pages for anything the user
sees. The example config in contrib changes only when the example changes.

## Checklist: new feature module

1. **Create** `priv/mpv/scripts/media-centaur/{name}.lua` following the structure above
2. **Require** `pill` for a pill; require the palette rather than copying it
3. **Add** the `{name}` option to `main.lua` (default `yes`) and load the module behind it
4. **Namespace** forced key binding names with the feature prefix
5. **Register** any default toggle key with `mp.add_key_binding`
6. **Log** with the feature prefix at info (lifecycle), debug (results), trace (detail)
7. **Clean up** on `end-file` (overlays, forced bindings)
8. **Re-render** on `osd-width`/`osd-height`
9. **Update** `docs/mpv.md` and the wiki
10. **Run** `mix test test/media_centaur/playback/bundled_scripts_test.exs` (mpv loads the package idle; a syntax error in any module fails it), then play a file from the app with `--msg-level` tracing in the session log

## Media-center features to consider

- **Track selection overlay** (`track_menu.lua`)
- **Skip intro/outro** (`skip_intro.lua`)
- **Next episode prompt + binge countdown** (`next_episode.lua`)
- **Playback info overlay**: show title, episode, codec info on demand
- **Watch progress indicator**: visual progress on the seek bar

All share the glassmorphism style, the forced binding pattern and the
1080p scaling.
