-- next_episode.lua — Chapter-based "Next Episode" button + auto-play countdown
-- Shows a "Next Episode" pill during a credits/outro chapter when the
-- playlist has a queued successor (Media Centaur appends it — ADR-062).
-- ENTER or a click advances with playlist-next; end-of-file advances on
-- its own, so the pill only ever *shortens* the credits, never skips
-- content automatically.
--
-- In the final seconds of the file the pill switches to countdown mode —
-- "Next episode in Ns" — regardless of chapters, so auto-play never
-- lands unannounced. Declining needs no dedicated affordance: quitting
-- the player (ESC / the remote's back button, as ever) ends the session,
-- queued successor and all.
--
-- Debug: mpv --msg-level=media_centaur=trace <file>

local msg = require("log")("next-episode")
local Pill = require("pill")

-- ── Config ──────────────────────────────────────────────────────────
local cfg = {
    pill_w           = 330,  -- 1080p baseline
    delay            = 1.0,  -- seconds after chapter change before showing (skip mode)
    countdown_window = 20,   -- seconds before EOF the countdown mode begins
    -- A credits chapter must start at or after this fraction of the
    -- runtime — mirrors the backend's ChapterCompletion floor, and keeps
    -- an "Opening Credits" chapter at t=0 from triggering the pill.
    outro_floor      = 0.80,
}

-- Chapter title patterns that mark rolling credits (matched
-- case-insensitive, whole-word via %f frontiers). Mirrors the backend's
-- ChapterCompletion: `credits` covers "End Credits" / "Closing Credits" /
-- "Credits"; `outro` covers "Outro". Bare "Ending" is deliberately
-- excluded (often the story climax).
local credits_patterns = {
    "%f[%a]credits%f[%A]",
    "%f[%a]outro%f[%A]",
}

-- ── State ───────────────────────────────────────────────────────────
local state = {
    mode        = nil,     -- "skip" (credits pill) | "countdown" (final seconds)
    remaining   = nil,     -- last observed time-remaining (seconds)
    last_second = nil,     -- last rendered whole second (repaint throttle)
}

-- ── Detection ───────────────────────────────────────────────────────

local function is_credits(title)
    if not title or title == "" then return false end
    local lower = title:lower()
    for _, pattern in ipairs(credits_patterns) do
        if lower:match(pattern) then
            msg.debug("is_credits: matched '" .. title .. "' with pattern '" .. pattern .. "'")
            return true
        end
    end
    return false
end

local function has_next_playlist_entry()
    local count = mp.get_property_number("playlist-count", 1)
    local pos = mp.get_property_number("playlist-pos", 0)
    local has_next = count - pos > 1
    msg.trace("has_next_playlist_entry: count=" .. count .. " pos=" .. pos)
    return has_next
end

-- The current chapter counts as rolling credits when its title names it
-- so AND it starts in the back stretch of the file.
local function in_credits_chapter()
    local chapter = mp.get_property_number("chapter", -1)
    if chapter < 0 then return false end

    local chapters = mp.get_property_native("chapter-list", {})
    local current = chapters[chapter + 1]  -- 0-based → 1-based
    if not current or not is_credits(current.title) then return false end

    local duration = mp.get_property_number("duration")
    if not duration or duration <= 0 then return false end

    if (current.time or 0) < duration * cfg.outro_floor then
        msg.debug("in_credits_chapter: '" .. tostring(current.title) ..
            "' starts before the outro floor, ignoring")
        return false
    end

    return true
end

-- The countdown window is open: a successor is queued and the file ends
-- within cfg.countdown_window seconds. Pausing pauses the countdown too —
-- honest, since the advance happens at EOF and EOF isn't approaching.
local function in_countdown_window()
    return state.remaining ~= nil
        and state.remaining > 0
        and state.remaining <= cfg.countdown_window
end

-- ── Pill ────────────────────────────────────────────────────────────

local pill  -- forward declaration: advance() reads pill.visible

local function advance()
    if not pill.visible then return end
    msg.info("advance: playlist-next")
    mp.commandv("playlist-next")
end

pill = Pill.new({
    name        = "next-episode",
    width       = cfg.pill_w,
    on_activate = advance,
    on_hide     = function()
        state.mode = nil
        state.last_second = nil
    end,
    content     = function(ass, geometry)
        if state.mode == "countdown" then
            -- Layout: [ ENTER  Next episode in 12s ]
            -- Same single-row density as skip-intro; the ticking seconds are
            -- the countdown. No decline affordance — quitting the player is
            -- the decline, same as it ever was.
            local seconds = math.max(1, math.ceil(state.remaining or 0))
            Pill.hint_row(ass, geometry, "Next episode in " .. seconds .. "s", false)
        else
            -- Layout: [  ENTER   Next Episode  ▶▶  ]
            Pill.hint_row(ass, geometry, "Next Episode", true)
        end
    end,
})

-- ── Mode ────────────────────────────────────────────────────────────

local function set_mode(mode)
    if pill.visible then
        if state.mode ~= mode then
            msg.debug("set_mode: " .. tostring(state.mode) .. " → " .. mode)
            state.mode = mode
            pill:render()
        end
        pill:show()
        return
    end

    state.mode = mode
    if mode == "countdown" then
        -- No courtesy delay when the file is about to end
        pill:show()
    else
        pill:show({ delay = cfg.delay })
    end
end

-- ── Evaluation ──────────────────────────────────────────────────────
-- Re-run on chapter changes, playlist-count changes AND time-remaining
-- ticks: the successor is appended by the backend shortly after file
-- load, and the countdown window opens purely on remaining time —
-- chapters or not, auto-play never lands unannounced.

local function evaluate()
    if not has_next_playlist_entry() then
        pill:hide()
        return
    end

    if in_countdown_window() then
        set_mode("countdown")
    elseif in_credits_chapter() then
        set_mode("skip")
    else
        pill:hide()
    end
end

local function on_time_remaining(_, remaining)
    state.remaining = remaining
    evaluate()

    -- Repaint at whole-second granularity while the countdown shows
    if pill.visible and state.mode == "countdown" then
        local second = remaining and math.ceil(remaining) or nil
        if second ~= state.last_second then
            state.last_second = second
            pill:render()
        end
    end
end

-- ── Register ───────────────────────────────────────────────────────

mp.observe_property("chapter", "number", evaluate)
mp.observe_property("playlist-count", "number", evaluate)
mp.observe_property("time-remaining", "number", on_time_remaining)
msg.info("chapter + playlist + time-remaining observers registered")
