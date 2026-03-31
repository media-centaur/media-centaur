# mpv Lua API Reference

API surface relevant to media-center overlay scripts. All functions are in the global `mp` namespace, available without `require`.

## Property Reading

| Function | Returns | Purpose |
|----------|---------|---------|
| `mp.get_property(name)` | `string` | Read property as string |
| `mp.get_property_number(name, default)` | `number` | Read numeric property |
| `mp.get_property_bool(name, default)` | `boolean` | Read boolean property |
| `mp.get_property_native(name, default)` | Lua value | Read structured property (tables, arrays) |
| `mp.get_osd_size()` | `width, height` | Current OSD pixel dimensions |

## Property Writing

| Function | Purpose |
|----------|---------|
| `mp.set_property(name, value)` | Set string property |
| `mp.set_property_number(name, value)` | Set numeric property |
| `mp.set_property_bool(name, value)` | Set boolean property |

## Property Observation

```lua
mp.observe_property("chapter", "number", function(name, value)
    -- called when property changes
end)
```

Types: `"number"`, `"string"`, `"bool"`, `"native"`, `"none"` (fires on any change).

## Commands

```lua
mp.commandv("seek", "120", "absolute")          -- seek to 120s
mp.commandv("add", "chapter", "1")              -- next chapter
mp.commandv("loadfile", "/path/to/file.mkv")    -- load file
mp.commandv("quit")                             -- quit
```

## Events

```lua
mp.register_event("end-file", function(event)
    -- event.reason: "eof", "stop", "quit", "error"
end)

mp.register_event("file-loaded", function() end)
mp.register_event("shutdown", function() end)
```

## Key Bindings

```lua
-- Normal binding (coexists with global bindings):
mp.add_key_binding("tab", "my-toggle", function() end)

-- Forced binding (overrides global bindings):
mp.add_forced_key_binding("enter", "my-enter", function() end, { repeatable = true })

-- Remove binding:
mp.remove_key_binding("my-enter")
```

Key names: `enter`, `esc`, `tab`, `up`, `down`, `left`, `right`, `space`, `a`-`z`, `0`-`9`, `WHEEL_UP`, `WHEEL_DOWN`, `MBTN_LEFT`, `MBTN_RIGHT`, `MBTN_BACK`.

Modifiers: `Shift+`, `Ctrl+`, `Alt+`.

## OSD Overlay

```lua
local overlay = mp.create_osd_overlay("ass-events")
overlay.res_x = width    -- MUST set to actual OSD width
overlay.res_y = height   -- MUST set to actual OSD height
overlay.data = ass_text  -- ASS subtitle markup
overlay:update()         -- render
overlay:remove()         -- hide and destroy
```

Only one format is useful: `"ass-events"`. The ASS markup is generated via the `mp.assdraw` module.

## ASSDraw Module

```lua
local assdraw = require("mp.assdraw")
local ass = assdraw.ass_new()

ass:new_event()                              -- start a new rendering layer
ass:pos(x, y)                                -- set position for text/drawing
ass:append("{\\an7\\fs36}text")              -- add styled text
ass:draw_start()                             -- begin vector drawing mode
ass:round_rect_cw(x1, y1, x2, y2, radius)   -- rounded rectangle
ass:rect_cw(x1, y1, x2, y2)                 -- sharp rectangle
ass:draw_stop()                              -- end vector drawing mode
ass.text                                     -- complete ASS document string
```

Each `new_event()` creates an independent layer. Later events render on top of earlier ones.

## ASS Inline Tags

### Color and Transparency

ASS colors use **BGR** byte order (not RGB). Alpha: `00` = fully opaque, `FF` = fully transparent.

| Tag | Purpose | Example |
|-----|---------|---------|
| `\1c&HBBGGRR&` | Text fill color | `\1c&HFFFFFF&` (white) |
| `\1a&HAA&` | Text fill alpha | `\1a&H80&` (50% transparent) |
| `\3c&HBBGGRR&` | Border/outline color | `\3c&HECE8E8&` |
| `\3a&HAA&` | Border/outline alpha | `\3a&H80&` |

### Typography

| Tag | Purpose | Example |
|-----|---------|---------|
| `\fs<n>` | Font size in pixels | `\fs36` |
| `\fn<name>` | Font family | `\fnsans-serif` |
| `\b1` / `\b0` | Bold on/off | |
| `\bord<n>` | Border width | `\bord2` |
| `\shad<n>` | Shadow depth (0=none) | `\shad0` |
| `\an<n>` | Alignment anchor (numpad layout) | `\an7` = top-left |

### Alignment Anchors (`\an`)

```
7 — top-left       8 — top-center       9 — top-right
4 — mid-left       5 — mid-center       6 — mid-right
1 — bottom-left    2 — bottom-center    3 — bottom-right
```

### Drawing Mode

| Tag | Purpose |
|-----|---------|
| `\p1` | Enable drawing mode (interpret text as vector commands) |
| `\p0` | Disable drawing mode (back to text) |

## Properties Useful for Media-Center Scripts

### Playback State

| Property | Type | Description |
|----------|------|-------------|
| `time-pos` | number | Current position in seconds |
| `duration` | number | Total duration in seconds |
| `percent-pos` | number | Position as percentage (0-100) |
| `pause` | bool | Whether paused |
| `eof-reached` | bool | End of file reached |
| `speed` | number | Playback speed multiplier |
| `idle-active` | bool | No file loaded |

### Chapter Information

| Property | Type | Description |
|----------|------|-------------|
| `chapter` | number | Current chapter index (0-based) |
| `chapters` | number | Total chapter count |
| `chapter-list` | native (array) | All chapters: `[{title, time}, ...]` |
| `chapter-metadata` | native (table) | Current chapter metadata |

`chapter-list` returns a Lua table (1-indexed) of objects with `title` (string, may be empty) and `time` (number, seconds). The `chapter` property is 0-indexed, so `chapters[chapter + 1]` gets the current chapter.

### Track Information

| Property | Type | Description |
|----------|------|-------------|
| `track-list` | native (array) | All tracks with type, id, lang, codec, title, flags |
| `aid` | number | Active audio track ID (0 = none) |
| `sid` | number | Active subtitle track ID (0 = none) |
| `vid` | number | Active video track ID |

Each track object: `{type, id, lang, codec, title, default, forced, external, ...}`

### Media Metadata

| Property | Type | Description |
|----------|------|-------------|
| `media-title` | string | Title (from metadata or filename) |
| `filename` | string | Current filename |
| `path` | string | Full file path |
| `file-format` | string | Container format |
| `video-codec` | string | Video codec name |
| `audio-codec-name` | string | Audio codec name |
| `width` / `height` | number | Video dimensions |

### OSD / Display

| Property | Type | Description |
|----------|------|-------------|
| `osd-width` | number | OSD width in pixels |
| `osd-height` | number | OSD height in pixels |
| `fullscreen` | bool | Fullscreen state |
| `display-fps` | number | Display refresh rate |

### Playlist

| Property | Type | Description |
|----------|------|-------------|
| `playlist-count` | number | Number of items |
| `playlist-pos` | number | Current item (0-based) |
| `playlist` | native (array) | All items with filename, title |

## Timers

```lua
local timer = mp.add_timeout(seconds, function() end)   -- one-shot
local timer = mp.add_periodic_timer(seconds, function() end)  -- repeating
timer:kill()   -- cancel
timer:resume() -- restart
```

## Script Messages (Inter-Script Communication)

```lua
-- Listen:
mp.register_script_message("my-message", function(arg1, arg2) end)

-- Send (from another script or input.conf):
mp.commandv("script-message", "my-message", "arg1", "arg2")

-- From input.conf:
-- KEY script-message my-message arg1 arg2
```

## Script Options

Read from `script-opts/{script-name}.conf`:

```lua
local options = require("mp.options")
local opts = { my_option = "default" }
options.read_options(opts, "script-name")
-- opts.my_option now contains the value from the conf file
```

File format: `key=value` per line, no quotes, no sections.

## Useful Utility Patterns

### Debounced Render

```lua
local render_timer = nil
local function schedule_render()
    if render_timer then render_timer:kill() end
    render_timer = mp.add_timeout(0.05, render)
end
```

### Safe Property Read

```lua
local chapter = mp.get_property_number("chapter", -1)
if chapter < 0 then return end  -- no chapters / no file
```

### Forward Declaration (Lua Idiom)

When two functions reference each other (e.g., `open` calls `close` and vice versa):

```lua
local close  -- forward declaration
local function open()
    bind("esc", "my-esc", function() close() end)
end
close = function()
    -- ...
end
```
