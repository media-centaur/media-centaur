-- skip-intro.lua — Chapter-based intro skip button overlay
-- Shows a "Skip Intro" pill when playback enters an intro/opening chapter.
--
-- Logging: run mpv with --msg-level=skip_intro=trace to see all debug output

local msg = mp.msg
local assdraw = require("mp.assdraw")

msg.info("skip-intro.lua loaded")

-- ── Config ──────────────────────────────────────────────────────────
-- Base sizes at 1080p — all scaled by osd_height / 1080 at render time
local cfg = {
    pill_w        = 300,
    pill_h        = 56,
    margin_right  = 48,
    margin_bottom = 120,   -- clears the default OSC bar
    corner_r      = 8,
    border_width  = 2,
    label_size    = 30,
    hint_size     = 22,
    -- Colors (ASS BGR format) — matches track-menu.lua
    bg_color      = "40302A",  bg_alpha      = "0A",  -- ~96% opaque
    text_color    = "ECE8E8",                          -- normal text
    bright_color  = "FFFFFF",                          -- label text
    header_color  = "FF9F4B",                          -- accent (arrow)
    border_color  = "ECE8E8",  border_alpha  = "80",  -- ~50% opaque
    dim_color     = "808080",                          -- key hint text
}

-- Chapter title patterns that trigger the skip button (matched case-insensitive)
local intro_patterns = {
    "^intro$",     "^intro%s",
    "^opening$",   "^opening%s",
    "^op$",        "^op%s",    "^op%d",
    "^prologue$",
}

-- ── State ───────────────────────────────────────────────────────────
local state = {
    visible   = false,
    overlay   = nil,
    skip_time = nil,   -- absolute time to seek to (start of next chapter)
}

local bindings = {}

-- ── Helpers ─────────────────────────────────────────────────────────

local function ass_color(bgr)
    return "\\1c&H" .. bgr .. "&"
end

local function ass_alpha(a)
    return "\\1a&H" .. a .. "&"
end

local function ass_border_color(bgr)
    return "\\3c&H" .. bgr .. "&"
end

local function ass_border_alpha(a)
    return "\\3a&H" .. a .. "&"
end

-- ── Chapter Detection ───────────────────────────────────────────────

local function is_intro(title)
    if not title or title == "" then return false end
    local lower = title:lower()
    for _, pattern in ipairs(intro_patterns) do
        if lower:match(pattern) then
            msg.debug("is_intro: matched '" .. title .. "' with pattern '" .. pattern .. "'")
            return true
        end
    end
    return false
end

local function get_next_chapter_time()
    local chapter = mp.get_property_number("chapter", -1)
    if chapter < 0 then return nil end

    local chapters = mp.get_property_native("chapter-list", {})
    local next_idx = chapter + 2  -- chapter is 0-based, Lua table is 1-based
    if next_idx > #chapters then
        msg.trace("get_next_chapter_time: intro is last chapter, no skip target")
        return nil
    end

    local next_time = chapters[next_idx].time
    msg.trace("get_next_chapter_time: next chapter at " .. tostring(next_time) .. "s")
    return next_time
end

-- ── Render ──────────────────────────────────────────────────────────

local function render()
    msg.trace("render: called, visible=" .. tostring(state.visible))
    if not state.visible then return end

    local w, h = mp.get_osd_size()
    msg.trace("render: osd size " .. tostring(w) .. "x" .. tostring(h))
    if not w or w == 0 then
        msg.warn("render: osd size is 0, aborting")
        return
    end

    local scale = h / 1080
    local pill_w    = math.floor(cfg.pill_w * scale)
    local pill_h    = math.floor(cfg.pill_h * scale)
    local margin_r  = math.floor(cfg.margin_right * scale)
    local margin_b  = math.floor(cfg.margin_bottom * scale)
    local corner_r  = math.floor(cfg.corner_r * scale)
    local border_w  = math.max(1, math.floor(cfg.border_width * scale))
    local label_sz  = math.floor(cfg.label_size * scale)
    local hint_sz   = math.floor(cfg.hint_size * scale)

    -- Pill position (bottom-right)
    local px = w - pill_w - margin_r
    local py = h - pill_h - margin_b
    local center_y = py + pill_h / 2

    local ass = assdraw.ass_new()

    -- Background pill
    ass:new_event()
    ass:pos(0, 0)
    ass:append("{\\an7\\bord0\\shad0" ..
        ass_color(cfg.bg_color) .. ass_alpha(cfg.bg_alpha) ..
        "\\p1}")
    ass:draw_start()
    ass:round_rect_cw(px, py, px + pill_w, py + pill_h, corner_r)
    ass:draw_stop()

    -- Border
    ass:new_event()
    ass:pos(0, 0)
    ass:append("{\\an7\\bord" .. border_w .. "\\shad0" ..
        "\\1a&HFF&" ..
        ass_border_color(cfg.border_color) .. ass_border_alpha(cfg.border_alpha) ..
        "\\p1}")
    ass:draw_start()
    ass:round_rect_cw(px, py, px + pill_w, py + pill_h, corner_r)
    ass:draw_stop()

    -- Layout: [  ENTER   Skip Intro  ▶▶  ]
    local pad = math.floor(16 * scale)
    local gap = math.floor(10 * scale)

    -- "ENTER" hint (dim, small)
    ass:new_event()
    ass:pos(px + pad, center_y)
    ass:append("{\\an4\\bord0\\shad0\\fs" .. hint_sz ..
        "\\fnsans-serif" ..
        ass_color(cfg.dim_color) .. "}ENTER")

    -- "Skip Intro" label (bright, bold)
    local hint_width = math.floor(58 * scale)  -- approximate width of "ENTER" text
    ass:new_event()
    ass:pos(px + pad + hint_width + gap, center_y)
    ass:append("{\\an4\\bord0\\shad0\\fs" .. label_sz ..
        "\\fnsans-serif\\b1" ..
        ass_color(cfg.bright_color) .. "}Skip Intro")

    -- "▶▶" arrow (accent color)
    local arrow_pad = math.floor(14 * scale)
    ass:new_event()
    ass:pos(px + pill_w - pad - arrow_pad, center_y)
    ass:append("{\\an6\\bord0\\shad0\\fs" .. label_sz ..
        "\\fnsans-serif" ..
        ass_color(cfg.header_color) .. "}\226\150\182\226\150\182")

    -- Apply overlay
    if not state.overlay then
        state.overlay = mp.create_osd_overlay("ass-events")
        msg.trace("render: created new overlay object")
    end
    state.overlay.res_x = w
    state.overlay.res_y = h
    state.overlay.data = ass.text
    local ok, err = state.overlay:update()
    msg.debug("render: overlay update result=" .. tostring(ok) .. " err=" .. tostring(err))
end

-- ── Skip Action ─────────────────────────────────────────────────────

local function skip()
    if not state.skip_time then return end
    msg.info("skip: seeking to " .. tostring(state.skip_time) .. "s")
    mp.commandv("seek", tostring(state.skip_time), "absolute")
end

-- ── Show / Hide Lifecycle ───────────────────────────────────────────

local function hide()
    if not state.visible then return end
    msg.info("hide")
    state.visible = false
    state.skip_time = nil

    for _, name in ipairs(bindings) do
        mp.remove_key_binding(name)
    end
    bindings = {}

    if state.overlay then
        state.overlay:remove()
        state.overlay = nil
    end
end

local function bind(key, name, fn)
    bindings[#bindings + 1] = name
    mp.add_forced_key_binding(key, name, fn)
end

local function show(next_time)
    msg.info("show: skip target=" .. tostring(next_time) .. "s")
    state.visible = true
    state.skip_time = next_time

    bind("enter", "skip-intro-enter", skip)

    render()
end

-- ── Chapter Change Observer ─────────────────────────────────────────

local function on_chapter_change(_, chapter)
    msg.trace("on_chapter_change: chapter=" .. tostring(chapter))

    if not chapter or chapter < 0 then
        hide()
        return
    end

    local chapters = mp.get_property_native("chapter-list", {})
    local current = chapters[chapter + 1]  -- 0-based → 1-based
    if not current then
        msg.trace("on_chapter_change: no chapter metadata")
        hide()
        return
    end

    local title = current.title
    msg.trace("on_chapter_change: title='" .. tostring(title) .. "'")

    if is_intro(title) then
        local next_time = get_next_chapter_time()
        if next_time then
            show(next_time)
        else
            hide()  -- intro is last chapter, nowhere to skip
        end
    else
        hide()
    end
end

-- ── Re-render on OSD resize ────────────────────────────────────────

mp.observe_property("osd-width", "number", function()
    if state.visible then render() end
end)
mp.observe_property("osd-height", "number", function()
    if state.visible then render() end
end)

-- ── Cleanup on file end ────────────────────────────────────────────

mp.register_event("end-file", function()
    msg.trace("end-file: cleaning up")
    hide()
end)

-- ── Register ───────────────────────────────────────────────────────

mp.observe_property("chapter", "number", on_chapter_change)
msg.info("skip-intro.lua: chapter observer registered")
