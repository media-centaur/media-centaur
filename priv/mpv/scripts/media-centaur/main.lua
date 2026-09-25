-- main.lua — Media Centaur's bundled mpv scripts (mpv script name: media_centaur)
--
-- Loaded by the app on every launch with --script=<this directory>; the
-- user's own ~/.config/mpv/ is untouched and still applies. One feature
-- per module, each gated by a script option so a user can turn it off:
--
--   ~/.config/mpv/script-opts/media_centaur.conf      (or --script-opts=media_centaur-<key>=<value>)
--     skip_intro=yes      Skip Intro pill on an intro chapter
--     next_episode=yes    Next Episode pill during credits + end-of-file countdown
--     track_menu=yes      TAB track menu with the Sound column; `n` night mode
--
-- Debug: mpv --msg-level=media_centaur=trace <file>

local msg = require("mp.msg")
local options = require("mp.options")

local o = {
    skip_intro   = true,
    next_episode = true,
    track_menu   = true,
}
options.read_options(o)

if o.skip_intro   then require("skip_intro") end
if o.next_episode then require("next_episode") end
if o.track_menu   then require("track_menu") end

msg.info(string.format("loaded: skip_intro=%s next_episode=%s track_menu=%s",
    tostring(o.skip_intro), tostring(o.next_episode), tostring(o.track_menu)))
