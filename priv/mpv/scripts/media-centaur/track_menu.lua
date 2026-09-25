-- track_menu.lua — Three-column audio / subtitle / sound-processing selector overlay
-- Dark panel with a highlight bar, forced key bindings while open.
--
-- Default keys (a user's input.conf overrides them):
--   TAB  script-binding media_centaur/track-menu   open / close the menu
--   n    script-binding media_centaur/night-mode   toggle the dynaudnorm filter
-- Other scripts: script-message track-menu-toggle-sound <dynaudnorm|dialog>
--
-- Debug: mpv --msg-level=media_centaur=trace <file>

local msg = require("log")("track-menu")
local assdraw = require("mp.assdraw")
local utils = require("mp.utils")
local theme = require("theme")

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
    -- Colors from the shared theme; the alphas are this panel's own
    bg_color      = theme.bg,      bg_alpha      = "0A",  -- ~96% opaque
    hl_color      = theme.hl,      hl_alpha      = "99",  -- ~40% opaque
    text_color    = theme.text,                           -- normal text
    bright_color  = theme.bright,                         -- highlighted text
    header_color  = theme.header,                         -- column headers
    border_color  = theme.border,  border_alpha  = "80",  -- ~50% opaque
    dim_color     = theme.dim,                            -- dim placeholder text
    active_color  = theme.active,                         -- active marker color
}

-- ── Sound processing ────────────────────────────────────────────────
-- track-menu owns the managed audio filters (see the manager block after
-- render) so the limiter is always kept last and choices persist, whether
-- toggled from the menu or the `n` keybind.
--
-- dialoguenhance needs stereo in; mpv auto-inserts the downmix, so it is
-- safe on 5.1/7.1 sources too (verified) — no explicit aresample needed.

-- Fixed-order filter specs (reconcile rebuilds the chain so @limiter is last).
local SPECS = {
    dialog     = "@dialog:dialoguenhance",
    dynaudnorm = "@dynaudnorm:dynaudnorm=f=500:g=31:p=0.9:m=4:s=0",
}
-- Transparent true-peak limiter, auto-applied whenever any sound filter is on.
local LIMITER = "@limiter:alimiter=limit=0.95:level=false"

-- Menu display order (Sound column); on/off lives in `sound_on`.
local sound_items = {
    { name = "Night mode",     label = "dynaudnorm" },
    { name = "Dialogue boost", label = "dialog" },
}
local sound_on = { dynaudnorm = false, dialog = false }

-- ── State ───────────────────────────────────────────────────────────
local state = {
    visible     = false,
    overlay     = nil,
    column      = "sub",       -- "audio", "sub" or "sound"
    audio_idx   = 1,
    sub_idx     = 1,
    sound_idx   = 1,
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
    if col == "sound" then return end  -- sound column never scrolls (few items)
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

local ass_color = theme.color
local ass_alpha = theme.alpha
local ass_border_color = theme.border_color
local ass_border_alpha = theme.border_alpha

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
    local snd_count = #sound_items
    local max_rows = math.max(
        math.min(cfg.max_visible, a_count),
        math.min(cfg.max_visible, s_count),
        math.min(cfg.max_visible, snd_count)
    )
    if max_rows == 0 then max_rows = 1 end

    -- Panel dimensions
    local panel_w = pad_x * 2 + col_width * 3 + col_gap * 2
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
    local col3_x = col2_x + col_width + col_gap
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
    draw_header(col3_x, top_y, "Sound", state.column == "sound")

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

    -- Draw the Sound column (live audio-processing toggles)
    local function draw_sound_column(x, y, is_active)
        for i, item in ipairs(sound_items) do
            local row_y = y + (i - 1) * line_height
            local is_cursor = is_active and (i == state.sound_idx)
            local on = sound_on[item.label]

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

            -- ON state reuses the active-track marker/colour
            local prefix = on and "● " or "   "
            local color = is_cursor and cfg.bright_color or cfg.text_color
            local prefix_color = on and cfg.active_color or color
            local text_offset = math.floor(2 * scale)
            local label_indent = math.floor(28 * scale)

            ass:new_event()
            ass:pos(x, row_y + text_offset)
            ass:append("{\\an7\\bord0\\shad0\\fs" .. font_size ..
                "\\fnsans-serif" ..
                ass_color(prefix_color) .. "}" .. prefix)

            ass:new_event()
            ass:pos(x + label_indent, row_y + text_offset)
            ass:append("{\\an7\\bord0\\shad0\\fs" .. font_size ..
                "\\fnsans-serif" ..
                ass_color(color) .. "}" .. item.name .. ": " .. (on and "ON" or "OFF"))
        end
    end

    draw_column(col1_x, list_y, state.audio_tracks, state.audio_idx,
                state.audio_scroll, state.column == "audio", "(no audio tracks)")
    draw_column(col2_x, list_y, state.sub_tracks, state.sub_idx,
                state.sub_scroll, state.column == "sub", nil)
    draw_sound_column(col3_x, list_y, state.column == "sound")

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

-- ── Sound filters: persistence + reconcile ──────────────────────────
-- track-menu owns the managed audio filters so @limiter is always last and
-- choices persist, whether toggled from the menu or the `n` keybind (which
-- routes here via toggle_sound).

-- Runtime state lives outside the (version-controlled) config dir, in the XDG
-- state dir. NOTE: mpv's "~~state/" prefix only expands when used alone (not
-- with a filename appended) in this build, so use reliable "~/" expansion.
local STATE_PATH = mp.command_native({ "expand-path", "~/.local/state/mpv/sound-toggles.json" })

-- Directory of the current file, or nil for streams/protocols (no persistence).
local function current_dir()
    local path = mp.get_property("path")
    if not path or path:find("://") then return nil end
    local dir = utils.split_path(path)
    if not dir or dir == "" or dir == "." then return nil end
    return dir
end

local function read_store()
    local f = io.open(STATE_PATH, "r")
    if not f then return {} end
    local data = f:read("*a"); f:close()
    local t = utils.parse_json(data or "")
    return type(t) == "table" and t or {}
end

local function write_store(store)
    local function attempt()
        local f = io.open(STATE_PATH, "w")
        if not f then return false end
        f:write(utils.format_json(store)); f:close()
        return true
    end
    if attempt() then return true end
    os.execute('mkdir -p "' .. (utils.split_path(STATE_PATH)) .. '"')  -- ensure dir, retry
    return attempt()
end

local function save_state()
    local dir = current_dir()
    if not dir then return end
    local store = read_store()
    store[dir] = { dynaudnorm = sound_on.dynaudnorm, dialog = sound_on.dialog }
    if write_store(store) then
        msg.debug("save_state: " .. dir)
    else
        msg.warn("save_state: cannot write " .. STATE_PATH)
    end
end

-- Rebuild the managed chain in fixed order so @limiter is always last.
local function reconcile()
    mp.commandv("af", "remove", "@dialog")
    mp.commandv("af", "remove", "@dynaudnorm")
    mp.commandv("af", "remove", "@limiter")
    if sound_on.dialog     then mp.commandv("af", "add", SPECS.dialog) end
    if sound_on.dynaudnorm then mp.commandv("af", "add", SPECS.dynaudnorm) end
    if sound_on.dialog or sound_on.dynaudnorm then
        mp.commandv("af", "add", LIMITER)
    end
end

local function name_for(label)
    for _, it in ipairs(sound_items) do
        if it.label == label then return it.name end
    end
    return label
end

local function set_sound(label, on)
    if sound_on[label] == nil then return end
    sound_on[label] = on and true or false
    reconcile()
    save_state()
    if state.visible then
        render()
    else
        mp.osd_message(name_for(label) .. ": " .. (sound_on[label] and "ON" or "OFF"))
    end
end

local function toggle_sound(label)
    set_sound(label, not sound_on[label])
end

-- Restore this folder's saved choices when a new file loads.
local function load_state()
    local dir = current_dir()
    local entry = dir and read_store()[dir] or nil
    sound_on.dynaudnorm = entry ~= nil and entry.dynaudnorm == true
    sound_on.dialog     = entry ~= nil and entry.dialog == true
    msg.debug("load_state: dir=" .. tostring(dir)
        .. " dynaudnorm=" .. tostring(sound_on.dynaudnorm)
        .. " dialog=" .. tostring(sound_on.dialog))
    reconcile()
    render()
end

-- ── Navigation ──────────────────────────────────────────────────────

local function get_active_list()
    if state.column == "audio" then
        return state.audio_tracks
    elseif state.column == "sub" then
        return state.sub_tracks
    else
        return sound_items
    end
end

local function get_cursor()
    if state.column == "audio" then
        return state.audio_idx
    elseif state.column == "sub" then
        return state.sub_idx
    else
        return state.sound_idx
    end
end

local function set_cursor(val)
    if state.column == "audio" then
        state.audio_idx = val
    elseif state.column == "sub" then
        state.sub_idx = val
    else
        state.sound_idx = val
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

local COLUMNS = { "audio", "sub", "sound" }

local function step_column(delta)
    local idx = 1
    for i, c in ipairs(COLUMNS) do
        if c == state.column then idx = i break end
    end
    idx = clamp(idx + delta, 1, #COLUMNS)
    state.column = COLUMNS[idx]
    msg.trace("step_column: -> " .. state.column)
    render()
end

local function activate()
    -- Sound column: toggle the focused audio filter instead of selecting a track
    if state.column == "sound" then
        local item = sound_items[state.sound_idx]
        if not item then return end
        msg.info("activate: toggle sound item " .. item.name)
        toggle_sound(item.label)
        return
    end

    local list = get_active_list()
    if #list == 0 then return end
    local track = list[get_cursor()]
    if not track then return end
    msg.info("activate: col=" .. state.column .. " id=" .. track.id .. " label=" .. track.label)

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
    bind("left",  "track-menu-left",  function() step_column(-1) end)
    bind("right", "track-menu-right", function() step_column(1) end)
    bind("enter", "track-menu-enter", activate)
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
-- Keep the Sound column live when filters are toggled via the `n` keybind
mp.observe_property("af", "native", function()
    if state.visible then render() end
end)

-- ── Register ────────────────────────────────────────────────────────

-- Default keys; a user's input.conf overrides them.
mp.add_key_binding("tab", "track-menu", toggle_menu)
mp.add_key_binding("n", "night-mode", function() toggle_sound("dynaudnorm") end)

-- Any external caller toggles sound filters through here, so limiter
-- ordering and per-folder persistence stay correct.
mp.register_script_message("track-menu-toggle-sound", toggle_sound)

-- Restore this folder's saved sound choices when a new file loads.
mp.register_event("file-loaded", load_state)

msg.info("bindings registered")
