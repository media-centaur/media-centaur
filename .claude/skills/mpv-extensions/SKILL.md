---
name: mpv-extensions
description: "Use this skill when creating or modifying mpv Lua scripts, mpv configuration, key bindings, or any playback overlay UI. Covers the ASS rendering pattern, forced key binding lifecycle, OSD scaling, and project conventions for media-center-style mpv extensions."
---

Media Centarr extends mpv with custom Lua scripts that add media-center UX (track selection, intro skipping, playback info overlays). All scripts live in `contrib/mpv/scripts/` and share a common visual language and implementation pattern.

Read the [mpv Lua API reference](references/mpv-lua-api.md) before writing any script code.

## File Layout

| File | Purpose |
|------|---------|
| `contrib/mpv/mpv.conf` | Player settings — rendering, subtitles, audio, OSD |
| `contrib/mpv/input.conf` | Key bindings (section-commented, one concern per block) |
| `contrib/mpv/scripts/*.lua` | Auto-loaded Lua scripts |
| `docs/mpv.md` | User-facing documentation for all mpv config and scripts |

Scripts auto-load from `scripts/` — no registration needed. mpv converts hyphens in filenames to underscores internally (`skip-intro.lua` becomes `skip_intro` in `input.conf` bindings and `--msg-level`).

## Deployment

The repo files in `contrib/mpv/` are the source of truth. mpv reads from `~/.config/mpv/` at runtime. After creating or modifying any script, config, or key binding, **copy the changed files to the runtime directory**:

```bash
cp contrib/mpv/scripts/*.lua ~/.config/mpv/scripts/
cp contrib/mpv/mpv.conf ~/.config/mpv/mpv.conf
cp contrib/mpv/input.conf ~/.config/mpv/input.conf
```

There is no automatic sync — forgetting to copy means mpv runs stale or missing scripts. Always deploy after changes.

## Project Visual Style

All overlay scripts share a **glassmorphism** aesthetic — dark semi-transparent panels with subtle borders and blue-orange accents. The canonical color palette (ASS BGR format):

```lua
bg_color      = "40302A",  bg_alpha      = "0A",  -- ~96% opaque dark
hl_color      = "FF9F4B",  hl_alpha      = "99",  -- ~40% opaque highlight bar
text_color    = "ECE8E8",                          -- normal text
bright_color  = "FFFFFF",                          -- highlighted/active text
header_color  = "FF9F4B",                          -- headers and accents
border_color  = "ECE8E8",  border_alpha  = "80",  -- ~50% opaque border
dim_color     = "808080",                          -- placeholder/hint text
active_color  = "FF9F4B",                          -- active markers
```

**Copy these values verbatim into new scripts.** Do not invent new colors.

## Resolution Scaling

All dimensions are defined at a **1080p baseline** and scaled at render time:

```lua
local scale = osd_height / 1080
local font_size = math.floor(cfg.font_size * scale)
```

This ensures consistent appearance at any resolution. Apply `math.floor` to prevent sub-pixel rendering artifacts. Always set `overlay.res_x` and `overlay.res_y` to the actual OSD dimensions (mpv defaults to 720p virtual coords otherwise).

## Script Structure Convention

Every script follows this layout:

```
1. Header comment — name, one-line purpose, logging hint
2. Requires — mp.msg, mp.assdraw (if rendering)
3. Config table — sizes at 1080p baseline, colors (copied from palette above)
4. State table — visible flag, overlay handle, cursor/selection state
5. Helpers — clamp, truncate, ASS formatting wrappers
6. Data refresh — query mpv properties, normalize into state
7. Render function — build ASS document, update overlay
8. Navigation/interaction — cursor movement, selection, actions
9. Show/hide lifecycle — forced key binding management, overlay creation/removal
10. Property observers — chapter changes, OSD resize, etc.
11. Event handlers — end-file cleanup
12. Registration — initial key binding or observer
```

## Forced Key Binding Lifecycle

When a script captures keys (e.g., ENTER for "Skip Intro", arrow keys for a menu), use forced bindings that override global `input.conf` bindings only while the UI is active:

```lua
-- On show:
local bindings = {}
local function bind(key, name, fn)
    bindings[#bindings + 1] = name
    mp.add_forced_key_binding(key, name, fn, { repeatable = true })
end
bind("enter", "my-script-enter", do_action)

-- On hide:
for _, name in ipairs(bindings) do
    mp.remove_key_binding(name)
end
bindings = {}
```

**Namespace binding names** with the script name prefix (`skip-intro-enter`, `track-menu-up`) to avoid collisions. mpv stacks forced bindings — the most recently added wins. When removed, the previous binding on the stack is restored automatically.

## Overlay Lifecycle

```lua
-- Create once, reuse:
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

Always nil-check before `:remove()`. Always re-render on `osd-width`/`osd-height` changes.

## Logging Convention

Use `mp.msg` at appropriate levels. The script name (from filename) is the log domain:

```lua
local msg = mp.msg
msg.info("script loaded")           -- lifecycle events
msg.debug("tracks refreshed: 3")    -- summary results
msg.trace("render: osd 1920x1080")  -- per-frame detail
msg.warn("osd size is 0")           -- problems
```

Debug with: `mpv --msg-level=skip_intro=trace /path/to/video.mkv`

## ASS Rendering Quick Reference

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

**ASS alignment anchors:** `\an7`=top-left, `\an8`=top-center, `\an9`=top-right, `\an4`=mid-left, `\an5`=mid-center, `\an6`=mid-right, `\an1`=bot-left, `\an2`=bot-center, `\an3`=bot-right.

**Colors are BGR, not RGB.** `FF9F4B` in ASS = `#4B9FFF` in web.

## Key Binding in input.conf

When a script needs a toggle key (like TAB for track-menu), add it to `input.conf` using script-binding syntax:

```
TAB script-binding track_menu/toggle
```

Remember: hyphens in filename become underscores. Group related bindings under a section comment.

Scripts that activate automatically (via property observers, not user toggle) don't need `input.conf` entries.

## Documentation

When adding or modifying a script, update `docs/mpv.md`:
1. Add the script to the **File Overview** table
2. Add a section with usage, behavior, visual style, and debugging instructions
3. If the script adds key bindings, update the relevant key binding table

## Checklist: New mpv Script

1. **Create** `contrib/mpv/scripts/{name}.lua` following the structure convention above
2. **Copy** the color palette and scaling pattern from an existing script
3. **Namespace** all forced key binding names with the script name
4. **Add logging** at info (lifecycle), debug (results), trace (detail) levels
5. **Handle cleanup** on `end-file` event (remove overlays, unbind keys)
6. **Re-render** on `osd-width`/`osd-height` property changes
7. **Add** `input.conf` entry if the script has a user-toggled binding
8. **Update** `docs/mpv.md` with documentation
9. **Deploy** to `~/.config/mpv/scripts/` (see Deployment section)
10. **Test** with `--msg-level={script_name}=trace` to verify logging and behavior

## Media-Center Features to Consider

These are the kinds of extensions this project builds — features that make mpv behave like a polished media-center player (Netflix, Plex, Jellyfin):

- **Track selection overlay** (track-menu.lua) — audio/subtitle picker
- **Skip intro/outro** — chapter-based detection with skip button
- **Playback info overlay** — show title, episode, codec info on demand
- **Next episode prompt** — "Next Episode in 10s" near end of file
- **Watch progress indicator** — visual progress on the seek bar
- **Binge mode** — auto-play next episode with countdown

All share the same glassmorphism visual style, forced binding pattern, and 1080p scaling.
