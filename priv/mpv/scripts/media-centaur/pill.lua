-- pill.lua — the bottom-right action pill that Skip Intro and Next Episode
-- share: frame, fade in/out, optional show delay, hover-gated MBTN_LEFT
-- capture, a forced ENTER binding while visible, repaint on OSD resize and
-- cleanup on end-file. A feature supplies its name, width, action and
-- content; the pill owns everything else.
--
--     local pill = Pill.new({
--         name        = "skip-intro",     -- log prefix + forced binding names
--         width       = 300,              -- 1080p baseline; scaled at render
--         on_activate = skip,             -- ENTER or a click on the pill
--         on_hide     = reset,            -- optional: after the pill is gone
--         content     = function(ass, geometry)
--             Pill.hint_row(ass, geometry, "Skip Intro", true)
--         end,
--     })
--     pill:show({ delay = 1.0 })  -- a pending delay is kept; delay 0 shows now
--     pill:hide()                 -- fade out (cancels a pending delay)
--     pill:force_hide()           -- immediate cleanup
--     pill:render()               -- repaint (content changed)
--     pill.visible                -- true from show until fully faded out

local assdraw = require("mp.assdraw")
local theme = require("theme")

-- Base sizes at 1080p — all scaled by osd_height / 1080 at render time
local base = {
    pill_h        = 56,
    margin_right  = 48,
    margin_bottom = 120,   -- clears the default OSC bar
    corner_r      = 8,
    border_width  = 2,
    label_size    = 30,
    hint_size     = 22,
    bg_alpha      = "00",  -- fully opaque
    border_alpha  = "40",  -- ~75% opaque
    fade_in       = 0.3,   -- seconds
    fade_out      = 0.2,   -- seconds
}

local Pill = {}
Pill.__index = Pill

-- ── Construction ────────────────────────────────────────────────────

function Pill.new(opts)
    local self = setmetatable({}, Pill)
    self.name        = opts.name
    self.width       = opts.width
    self.on_activate = opts.on_activate
    self.on_hide     = opts.on_hide
    self.content     = opts.content
    self.msg         = require("log")(opts.name)

    self.visible     = false
    self.overlay     = nil
    self.fade        = 0       -- current fade level (0 = invisible, 1 = fully visible)
    self.fade_target = 0
    self.fade_timer  = nil     -- periodic timer for the fade animation
    self.delay_timer = nil     -- one-shot timer for a delayed show
    self.rect        = nil     -- last-rendered bounds {x1,y1,x2,y2} for hit-testing
    self.hover       = false   -- cursor is over the pill
    self.mouse_bound = false   -- MBTN_LEFT forced binding is active (only while hovering)
    self.bindings    = {}

    mp.observe_property("osd-width", "number", function()
        if self.visible then self:render() end
    end)
    mp.observe_property("osd-height", "number", function()
        if self.visible then self:render() end
    end)
    mp.observe_property("mouse-pos", "native", function(_, pos)
        self:on_mouse_move(pos)
    end)
    mp.register_event("end-file", function()
        self.msg.trace("end-file: cleaning up")
        self:force_hide()
    end)

    return self
end

-- ── Helpers ─────────────────────────────────────────────────────────

-- Interpolate alpha from fully transparent (FF) toward target based on fade
function Pill:faded(target_hex)
    local target = tonumber(target_hex, 16)
    local alpha = math.floor(0xFF - (0xFF - target) * self.fade)
    return string.format("%02X", alpha)
end

-- The standard row: [  ENTER   <label>  ▶▶  ]. The arrow is optional.
function Pill.hint_row(ass, g, label, with_arrow)
    -- "ENTER" hint (dim, small)
    ass:new_event()
    ass:pos(g.x + g.pad, g.center_y)
    ass:append("{\\an4\\bord0\\shad0\\fs" .. g.hint_size ..
        "\\fnsans-serif" ..
        theme.color(theme.dim) .. theme.alpha(g.text_alpha) .. "}ENTER")

    -- Label (bright, bold)
    local hint_width = math.floor(58 * g.scale)
    ass:new_event()
    ass:pos(g.x + g.pad + hint_width + g.gap, g.center_y)
    ass:append("{\\an4\\bord0\\shad0\\fs" .. g.label_size ..
        "\\fnsans-serif\\b1" ..
        theme.color(theme.bright) .. theme.alpha(g.text_alpha) .. "}" .. label)

    if with_arrow then
        -- "▶▶" arrow (accent color)
        local arrow_pad = math.floor(14 * g.scale)
        ass:new_event()
        ass:pos(g.x + g.w - g.pad - arrow_pad, g.center_y)
        ass:append("{\\an6\\bord0\\shad0\\fs" .. g.label_size ..
            "\\fnsans-serif" ..
            theme.color(theme.header) .. theme.alpha(g.text_alpha) .. "}\226\150\182\226\150\182")
    end
end

-- ── Render ──────────────────────────────────────────────────────────

function Pill:render()
    local msg = self.msg
    msg.trace("render: called, visible=" .. tostring(self.visible) .. " fade=" .. string.format("%.2f", self.fade))
    if not self.visible or self.fade <= 0 then return end

    local w, h = mp.get_osd_size()
    msg.trace("render: osd size " .. tostring(w) .. "x" .. tostring(h))
    if not w or w == 0 then
        msg.warn("render: osd size is 0, aborting")
        return
    end

    local scale = h / 1080
    local pill_w    = math.floor(self.width * scale)
    local pill_h    = math.floor(base.pill_h * scale)
    local margin_r  = math.floor(base.margin_right * scale)
    local margin_b  = math.floor(base.margin_bottom * scale)
    local corner_r  = math.floor(base.corner_r * scale)
    local border_w  = math.max(1, math.floor(base.border_width * scale))
    local label_sz  = math.floor(base.label_size * scale)
    local hint_sz   = math.floor(base.hint_size * scale)

    -- Pill position (bottom-right)
    local px = w - pill_w - margin_r
    local py = h - pill_h - margin_b
    local center_y = py + pill_h / 2

    -- Record bounds so the mouse observer can hit-test clicks/hover
    self.rect = { x1 = px, y1 = py, x2 = px + pill_w, y2 = py + pill_h }

    -- Fade-adjusted alphas
    local bg_a = self:faded(base.bg_alpha)
    local text_a = self:faded("00")

    -- Hover brightens the border to the accent color for a clickable affordance
    local border_c = self.hover and theme.header or theme.border
    local border_a = self.hover and self:faded("00") or self:faded(base.border_alpha)

    local ass = assdraw.ass_new()

    -- Background pill
    ass:new_event()
    ass:pos(0, 0)
    ass:append("{\\an7\\bord0\\shad0" ..
        theme.color(theme.bg) .. theme.alpha(bg_a) ..
        "\\p1}")
    ass:draw_start()
    ass:round_rect_cw(px, py, px + pill_w, py + pill_h, corner_r)
    ass:draw_stop()

    -- Border
    ass:new_event()
    ass:pos(0, 0)
    ass:append("{\\an7\\bord" .. border_w .. "\\shad0" ..
        "\\1a&HFF&" ..
        theme.border_color(border_c) .. theme.border_alpha(border_a) ..
        "\\p1}")
    ass:draw_start()
    ass:round_rect_cw(px, py, px + pill_w, py + pill_h, corner_r)
    ass:draw_stop()

    -- Content
    self.content(ass, {
        x          = px,
        y          = py,
        w          = pill_w,
        h          = pill_h,
        center_y   = center_y,
        scale      = scale,
        pad        = math.floor(16 * scale),
        gap        = math.floor(10 * scale),
        hint_size  = hint_sz,
        label_size = label_sz,
        text_alpha = text_a,
    })

    -- Apply overlay
    if not self.overlay then
        self.overlay = mp.create_osd_overlay("ass-events")
        msg.trace("render: created new overlay object")
    end
    self.overlay.res_x = w
    self.overlay.res_y = h
    self.overlay.data = ass.text
    self.overlay:update()
end

-- ── Mouse Interaction ───────────────────────────────────────────────
-- The pill is clickable. To avoid swallowing clicks meant for the OSC /
-- seek bar, MBTN_LEFT is only captured while the cursor is over the pill
-- (gated by the mouse-pos observer) — same pattern mpv's own OSC uses.

local function point_in_rect(x, y, r)
    return r and x and y and x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2
end

function Pill:bind_click()
    if self.mouse_bound then return end
    self.mouse_bound = true
    mp.add_forced_key_binding("MBTN_LEFT", self.name .. "-click", function() self.on_activate() end)
    self.msg.trace("bind_click: MBTN_LEFT captured")
end

function Pill:unbind_click()
    if not self.mouse_bound then return end
    self.mouse_bound = false
    mp.remove_key_binding(self.name .. "-click")
    self.msg.trace("unbind_click: MBTN_LEFT released")
end

function Pill:on_mouse_move(pos)
    local inside = self.visible and point_in_rect(pos and pos.x, pos and pos.y, self.rect)
    if inside == self.hover then return end

    self.hover = inside
    if inside then self:bind_click() else self:unbind_click() end
    self:render()  -- repaint border in hover/non-hover style
end

-- ── Overlay Cleanup ────────────────────────────────────────────────

function Pill:cleanup_overlay()
    self.msg.debug("cleanup_overlay")
    self.visible = false
    self.fade = 0
    self.fade_target = 0
    self.rect = nil
    self.hover = false

    self:unbind_click()
    for _, name in ipairs(self.bindings) do
        mp.remove_key_binding(name)
    end
    self.bindings = {}

    if self.overlay then
        self.overlay:remove()
        self.overlay = nil
    end

    if self.on_hide then self.on_hide() end
end

-- ── Fade Animation ─────────────────────────────────────────────────

function Pill:ensure_fade_timer()
    if self.fade_timer then return end
    if self.fade == self.fade_target then return end

    self.fade_timer = mp.add_periodic_timer(1 / 60, function()
        local dt = 1 / 60
        if self.fade < self.fade_target then
            self.fade = math.min(self.fade + dt / base.fade_in, self.fade_target)
        elseif self.fade > self.fade_target then
            self.fade = math.max(self.fade - dt / base.fade_out, self.fade_target)
        end

        self:render()

        if self.fade == self.fade_target then
            self.fade_timer:kill()
            self.fade_timer = nil
            if self.fade <= 0 then
                self:cleanup_overlay()
            end
        end
    end)
end

function Pill:animate_to(target)
    self.fade_target = target
    self:ensure_fade_timer()
end

-- ── Show / Hide Lifecycle ───────────────────────────────────────────

function Pill:cancel_delay()
    if self.delay_timer then
        self.delay_timer:kill()
        self.delay_timer = nil
    end
end

function Pill:bind(key, name, fn)
    self.bindings[#self.bindings + 1] = name
    mp.add_forced_key_binding(key, name, fn)
end

function Pill:begin_show()
    self.delay_timer = nil
    self.msg.info("pill shown")
    self.visible = true
    self:bind("enter", self.name .. "-enter", function() self.on_activate() end)
    self:animate_to(1)
end

-- Show the pill. `opts.delay` (seconds) defers the appearance; a delay
-- already pending is kept, not restarted. No delay (or 0) shows at once and
-- cancels any pending delay. A visible pill just fades back to full.
function Pill:show(opts)
    local delay = opts and opts.delay or 0

    if self.visible then
        self:cancel_delay()
        self:animate_to(1)
        return
    end

    if delay > 0 then
        if self.delay_timer then return end
        self.delay_timer = mp.add_timeout(delay, function() self:begin_show() end)
        self.msg.debug("show: delay timer started (" .. delay .. "s)")
        return
    end

    self:cancel_delay()
    self:begin_show()
end

function Pill:hide()
    self:cancel_delay()
    if not self.visible then return end
    self.msg.info("hide: fading out")
    self:animate_to(0)
end

function Pill:force_hide()
    self:cancel_delay()
    if self.fade_timer then
        self.fade_timer:kill()
        self.fade_timer = nil
    end
    self:cleanup_overlay()
end

return Pill
