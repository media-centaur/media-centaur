-- skip_intro.lua — Chapter-based intro skip button
-- Shows a "Skip Intro" pill when playback enters an intro/opening chapter.
-- ENTER or a click seeks to the next chapter.
--
-- Debug: mpv --msg-level=media_centaur=trace <file>

local msg = require("log")("skip-intro")
local Pill = require("pill")

-- ── Config ──────────────────────────────────────────────────────────
local cfg = {
    pill_w = 300,   -- 1080p baseline
    delay  = 1.0,   -- seconds after chapter change before showing
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
    skip_time = nil,   -- absolute time to seek to (start of next chapter)
}

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

-- ── Skip Action ─────────────────────────────────────────────────────

local function skip()
    if not state.skip_time then return end
    msg.info("skip: seeking to " .. tostring(state.skip_time) .. "s")
    mp.commandv("seek", tostring(state.skip_time), "absolute")
end

-- ── Pill ────────────────────────────────────────────────────────────

local pill = Pill.new({
    name        = "skip-intro",
    width       = cfg.pill_w,
    on_activate = skip,
    on_hide     = function() state.skip_time = nil end,
    content     = function(ass, geometry)
        Pill.hint_row(ass, geometry, "Skip Intro", true)
    end,
})

-- ── Chapter Change Observer ─────────────────────────────────────────

local function on_chapter_change(_, chapter)
    msg.trace("on_chapter_change: chapter=" .. tostring(chapter))

    if not chapter or chapter < 0 then
        pill:hide()
        return
    end

    local chapters = mp.get_property_native("chapter-list", {})
    local current = chapters[chapter + 1]  -- 0-based → 1-based
    if not current then
        msg.trace("on_chapter_change: no chapter metadata")
        pill:hide()
        return
    end

    local title = current.title
    msg.trace("on_chapter_change: title='" .. tostring(title) .. "'")

    if is_intro(title) then
        local next_time = get_next_chapter_time()
        if next_time then
            state.skip_time = next_time
            msg.info("show: skip target=" .. tostring(next_time) .. "s")
            pill:show({ delay = cfg.delay })
        else
            pill:hide()  -- intro is last chapter, nowhere to skip
        end
    else
        pill:hide()
    end
end

-- ── Register ───────────────────────────────────────────────────────

mp.observe_property("chapter", "number", on_chapter_change)
msg.info("chapter observer registered")
