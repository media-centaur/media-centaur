-- track-menu.lua — Two-column audio/subtitle track selector overlay
-- Glassmorphism-inspired ASS rendering, forced key bindings while open
--
-- Logging: run mpv with --msg-level=track_menu=trace to see all debug output

local msg = mp.msg
local assdraw = require("mp.assdraw")

msg.info("track-menu.lua loaded")

-- ── Config ──────────────────────────────────────────────────────────
-- Base sizes at 1080p — all scaled by osd_height / 1080 at render time
local cfg = {
    font_size     = 36,
    header_size   = 42,
    line_height   = 54,
    max_visible   = 12,
    pad_x         = 36,
    pad_y         = 24,
    col_gap       = 60,
    col_width     = 520,
    border_width  = 2,
    max_label_len = 40,
    -- Colors (ASS BGR format)
    bg_color      = "40302A",  bg_alpha      = "0A",  -- ~96% opaque
    hl_color      = "FF9F4B",  hl_alpha      = "99",  -- ~40% opaque
    text_color    = "ECE8E8",                          -- normal text
    bright_color  = "FFFFFF",                          -- highlighted text
    header_color  = "FF9F4B",                          -- column headers (blue)
    border_color  = "ECE8E8",  border_alpha  = "80",  -- ~50% opaque
    dim_color     = "808080",                          -- dim placeholder text
    active_color  = "FF9F4B",                          -- active marker color
}

-- ── State ───────────────────────────────────────────────────────────
local state = {
    visible     = false,
    overlay     = nil,
    column      = "sub",       -- "audio" or "sub"
    audio_idx   = 1,
    sub_idx     = 1,
    audio_scroll = 0,
    sub_scroll   = 0,
    audio_tracks = {},
    sub_tracks   = {},
    current_aid  = 0,
    current_sid  = 0,
}

-- ── Helpers ─────────────────────────────────────────────────────────

local function clamp(val, lo, hi)
    if val < lo then return lo end
    if val > hi then return hi end
    return val
end

local function truncate(s, max)
    if #s <= max then return s end
    return s:sub(1, max - 3) .. "..."
end

local function format_track(t)
    local parts = {}
    if t.lang and t.lang ~= "" then
        parts[#parts + 1] = t.lang:upper()
    end
    if t.codec and t.codec ~= "" then
        parts[#parts + 1] = t.codec
    end
    local flags = {}
    if t.default then flags[#flags + 1] = "default" end
    if t.forced then flags[#flags + 1] = "forced" end
    if t.external then flags[#flags + 1] = "ext" end
    if #flags > 0 then
        parts[#parts + 1] = "[" .. table.concat(flags, ", ") .. "]"
    end
    if t.title and t.title ~= "" then
        return truncate(t.title .. "  " .. table.concat(parts, "  "), cfg.max_label_len)
    end
    if #parts == 0 then
        return "Track " .. (t.id or "?")
    end
    return truncate(table.concat(parts, "  "), cfg.max_label_len)
end

-- ── Track Refresh ───────────────────────────────────────────────────

local function refresh_tracks()
    msg.trace("refresh_tracks: start")
    local tracks = mp.get_property_native("track-list", {})
    msg.trace("refresh_tracks: got " .. #tracks .. " raw tracks")

    local aid = mp.get_property_number("aid", 0) or 0
    local sid = mp.get_property_number("sid", 0) or 0
    msg.trace("refresh_tracks: aid=" .. tostring(aid) .. " sid=" .. tostring(sid))
    state.current_aid = aid
    state.current_sid = sid

    state.audio_tracks = {}
    state.sub_tracks = {
        { id = 0, label = "None", active = (sid == 0) }
    }

    for _, t in ipairs(tracks) do
        if t.type == "audio" then
            local label = format_track(t)
            msg.trace("refresh_tracks: audio id=" .. t.id .. " label=" .. label)
            state.audio_tracks[#state.audio_tracks + 1] = {
                id     = t.id,
                label  = label,
                active = (t.id == aid),
            }
        elseif t.type == "sub" then
            local label = format_track(t)
            msg.trace("refresh_tracks: sub id=" .. t.id .. " label=" .. label)
            state.sub_tracks[#state.sub_tracks + 1] = {
                id     = t.id,
                label  = label,
                active = (t.id == sid),
            }
        end
    end

    -- Set cursor to active track
    for i, t in ipairs(state.audio_tracks) do
        if t.active then state.audio_idx = i; break end
    end
    for i, t in ipairs(state.sub_tracks) do
        if t.active then state.sub_idx = i; break end
    end

    -- Clamp
    if #state.audio_tracks > 0 then
        state.audio_idx = clamp(state.audio_idx, 1, #state.audio_tracks)
    end
    state.sub_idx = clamp(state.sub_idx, 1, #state.sub_tracks)

    msg.debug("refresh_tracks: done — " .. #state.audio_tracks .. " audio, " .. #state.sub_tracks .. " sub")
end

-- ── Scroll ──────────────────────────────────────────────────────────

local function adjust_scroll(col)
    local idx, scroll, count
    if col == "audio" then
        idx = state.audio_idx
        scroll = state.audio_scroll
        count = #state.audio_tracks
    else
        idx = state.sub_idx
        scroll = state.sub_scroll
        count = #state.sub_tracks
    end
    local max_vis = math.min(cfg.max_visible, count)
    if idx <= scroll then
        scroll = idx - 1
    elseif idx > scroll + max_vis then
        scroll = idx - max_vis
    end
    scroll = clamp(scroll, 0, math.max(0, count - max_vis))
    if col == "audio" then
        state.audio_scroll = scroll
    else
        state.sub_scroll = scroll
    end
end

-- ── Render ──────────────────────────────────────────────────────────

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

local function render()
    msg.trace("render: called, visible=" .. tostring(state.visible))
    if not state.visible then return end

    local w, h = mp.get_osd_size()
    msg.trace("render: osd size " .. tostring(w) .. "x" .. tostring(h))
    if not w or w == 0 then
        msg.warn("render: osd size is 0, aborting")
        return
    end

    -- Scale all sizes relative to 1080p baseline
    local scale = h / 1080
    local font_size   = math.floor(cfg.font_size * scale)
    local header_size = math.floor(cfg.header_size * scale)
    local line_height = math.floor(cfg.line_height * scale)
    local pad_x       = math.floor(cfg.pad_x * scale)
    local pad_y       = math.floor(cfg.pad_y * scale)
    local col_gap     = math.floor(cfg.col_gap * scale)
    local col_width   = math.floor(cfg.col_width * scale)
    local border_w    = math.max(1, math.floor(cfg.border_width * scale))

    local a_count = #state.audio_tracks
    local s_count = #state.sub_tracks
    local max_rows = math.max(
        math.min(cfg.max_visible, a_count),
        math.min(cfg.max_visible, s_count)
    )
    if max_rows == 0 then max_rows = 1 end

    -- Panel dimensions
    local panel_w = pad_x * 2 + col_width * 2 + col_gap
    local header_h = header_size + math.floor(12 * scale)
    local panel_h = pad_y * 2 + header_h + max_rows * line_height + math.floor(8 * scale)
    local corner_r = math.floor(8 * scale)
    local px = (w - panel_w) / 2
    local py = (h - panel_h) / 2
    msg.trace("render: panel " .. panel_w .. "x" .. panel_h .. " at " .. px .. "," .. py .. " scale=" .. scale)

    local ass = assdraw.ass_new()

    -- Background panel
    ass:new_event()
    ass:pos(0, 0)
    ass:append("{\\an7\\bord0\\shad0" ..
        ass_color(cfg.bg_color) .. ass_alpha(cfg.bg_alpha) ..
        "\\p1}")
    ass:draw_start()
    ass:round_rect_cw(px, py, px + panel_w, py + panel_h, corner_r)
    ass:draw_stop()

    -- Border
    ass:new_event()
    ass:pos(0, 0)
    ass:append("{\\an7\\bord" .. border_w .. "\\shad0" ..
        "\\1a&HFF&" ..
        ass_border_color(cfg.border_color) .. ass_border_alpha(cfg.border_alpha) ..
        "\\p1}")
    ass:draw_start()
    ass:round_rect_cw(px, py, px + panel_w, py + panel_h, corner_r)
    ass:draw_stop()

    -- Column positions
    local col1_x = px + pad_x
    local col2_x = col1_x + col_width + col_gap
    local top_y = py + pad_y

    -- Headers
    local function draw_header(x, y, text, is_active)
        ass:new_event()
        ass:pos(x, y)
        local style = "{\\an7\\bord0\\shad0\\fs" .. header_size ..
            "\\fnsans-serif" ..
            ass_color(cfg.header_color)
        if is_active then
            style = style .. "\\b1"
        end
        style = style .. "}"
        ass:append(style .. text)
    end

    draw_header(col1_x, top_y, "Audio", state.column == "audio")
    draw_header(col2_x, top_y, "Subtitles", state.column == "sub")

    local list_y = top_y + header_h

    -- Draw a column's track list
    local function draw_column(x, y, tracks, cursor, scroll, is_active, is_empty_msg)
        if #tracks == 0 then
            ass:new_event()
            ass:pos(x, y + line_height * 0.3)
            ass:append("{\\an7\\bord0\\shad0\\fs" .. font_size ..
                "\\fnsans-serif" ..
                ass_color(cfg.dim_color) .. "}" ..
                (is_empty_msg or "(none)"))
            return
        end

        local vis = math.min(cfg.max_visible, #tracks)
        local scroll_font = math.floor(16 * scale)

        -- Scroll indicators
        if scroll > 0 then
            ass:new_event()
            ass:pos(x + col_width / 2, y - math.floor(4 * scale))
            ass:append("{\\an8\\bord0\\shad0\\fs" .. scroll_font .. "\\fnsans-serif" ..
                ass_color(cfg.dim_color) .. "}▲ more")
        end
        if scroll + vis < #tracks then
            ass:new_event()
            ass:pos(x + col_width / 2, y + vis * line_height + math.floor(4 * scale))
            ass:append("{\\an8\\bord0\\shad0\\fs" .. scroll_font .. "\\fnsans-serif" ..
                ass_color(cfg.dim_color) .. "}▼ more")
        end

        for i = 1, vis do
            local ti = i + scroll
            local track = tracks[ti]
            if not track then break end

            local row_y = y + (i - 1) * line_height
            local is_cursor = is_active and (ti == cursor)

            -- Highlight bar
            local hl_pad = math.floor(6 * scale)
            local hl_r = math.floor(4 * scale)
            if is_cursor then
                ass:new_event()
                ass:pos(0, 0)
                ass:append("{\\an7\\bord0\\shad0" ..
                    ass_color(cfg.hl_color) .. ass_alpha(cfg.hl_alpha) ..
                    "\\p1}")
                ass:draw_start()
                ass:round_rect_cw(x - hl_pad, row_y, x + col_width + hl_pad, row_y + line_height - 2, hl_r)
                ass:draw_stop()
            end

            -- Track label
            local prefix = track.active and "● " or "   "
            local color = is_cursor and cfg.bright_color or cfg.text_color
            local prefix_color = track.active and cfg.active_color or color
            local text_offset = math.floor(2 * scale)
            local label_indent = math.floor(28 * scale)

            -- Active marker
            ass:new_event()
            ass:pos(x, row_y + text_offset)
            ass:append("{\\an7\\bord0\\shad0\\fs" .. font_size ..
                "\\fnsans-serif" ..
                ass_color(prefix_color) .. "}" .. prefix)

            -- Label text
            ass:new_event()
            ass:pos(x + label_indent, row_y + text_offset)
            ass:append("{\\an7\\bord0\\shad0\\fs" .. font_size ..
                "\\fnsans-serif" ..
                ass_color(color) .. "}" .. track.label)
        end
    end

    draw_column(col1_x, list_y, state.audio_tracks, state.audio_idx,
                state.audio_scroll, state.column == "audio", "(no audio tracks)")
    draw_column(col2_x, list_y, state.sub_tracks, state.sub_idx,
                state.sub_scroll, state.column == "sub", nil)

    -- Apply overlay
    msg.trace("render: creating overlay, ass length=" .. #ass.text)
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

-- ── Navigation ──────────────────────────────────────────────────────

local function get_active_list()
    if state.column == "audio" then
        return state.audio_tracks
    else
        return state.sub_tracks
    end
end

local function get_cursor()
    if state.column == "audio" then
        return state.audio_idx
    else
        return state.sub_idx
    end
end

local function set_cursor(val)
    if state.column == "audio" then
        state.audio_idx = val
    else
        state.sub_idx = val
    end
end

local function move_cursor(delta)
    msg.trace("move_cursor: delta=" .. delta .. " col=" .. state.column)
    local list = get_active_list()
    if #list == 0 then return end
    local cur = get_cursor()
    cur = clamp(cur + delta, 1, #list)
    set_cursor(cur)
    adjust_scroll(state.column)
    render()
end

local function switch_column(col)
    msg.trace("switch_column: " .. col)
    if col == "audio" and #state.audio_tracks == 0 then return end
    state.column = col
    render()
end

local function select_track()
    local list = get_active_list()
    if #list == 0 then return end
    local track = list[get_cursor()]
    if not track then return end
    msg.info("select_track: col=" .. state.column .. " id=" .. track.id .. " label=" .. track.label)

    if state.column == "audio" then
        if track.id == 0 then
            mp.set_property("aid", "no")
        else
            mp.set_property_number("aid", track.id)
        end
    else
        if track.id == 0 then
            mp.set_property("sid", "no")
        else
            mp.set_property_number("sid", track.id)
        end
    end

    refresh_tracks()
    render()
end

-- ── Menu Lifecycle ──────────────────────────────────────────────────

local bindings = {}
local close_menu  -- forward declaration

local function bind(key, name, fn)
    bindings[#bindings + 1] = name
    mp.add_forced_key_binding(key, name, fn, { repeatable = true })
end

local function open_menu()
    msg.info("open_menu")
    state.visible = true
    state.column = "sub"
    refresh_tracks()
    adjust_scroll("audio")
    adjust_scroll("sub")

    bind("up",    "track-menu-up",    function() move_cursor(-1) end)
    bind("down",  "track-menu-down",  function() move_cursor(1) end)
    bind("left",  "track-menu-left",  function() switch_column("audio") end)
    bind("right", "track-menu-right", function() switch_column("sub") end)
    bind("enter", "track-menu-enter", select_track)
    bind("esc",   "track-menu-esc",   function() close_menu() end)
    bind("tab",   "track-menu-tab",   function() close_menu() end)

    render()
end

close_menu = function()
    msg.info("close_menu")
    state.visible = false
    for _, name in ipairs(bindings) do
        mp.remove_key_binding(name)
    end
    bindings = {}
    if state.overlay then
        state.overlay:remove()
        state.overlay = nil
    end
end

local function toggle_menu()
    msg.info("toggle_menu: visible=" .. tostring(state.visible))
    if state.visible then
        close_menu()
    else
        open_menu()
    end
end

-- ── Re-render on OSD resize ─────────────────────────────────────────

mp.observe_property("osd-width", "number", function()
    if state.visible then render() end
end)
mp.observe_property("osd-height", "number", function()
    if state.visible then render() end
end)

-- ── Register ────────────────────────────────────────────────────────

mp.add_key_binding("tab", "toggle", toggle_menu)
msg.info("track-menu.lua: binding registered")
