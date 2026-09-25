-- driver.lua — test driver for the bundled mpv package (never shipped).
-- Loaded by bundled_scripts_test.exs next to the package, it walks
-- chaptered.mkv through Skip Intro, Next Episode in skip mode, the
-- end-of-file countdown and the advance into the second playlist entry,
-- then quits. Every wait is wall-clock because the pills' own delays are.
--
-- Timeline (seconds after the first file-loaded):
--   1.0  Skip Intro pill appears (its 1 s delay)
--   1.5  ENTER → skip-intro seeks to the Body chapter at 10 s
--   2.0  seek to 97 s (Credits) → Next Episode schedules skip mode
--   3.0  Next Episode pill appears
--   3.5  seek to 116 s → 4 s remaining → countdown mode
--   4.0  ENTER → playlist-next → second entry loads → quit

local msg = require("mp.msg")

local loads = 0

mp.register_event("file-loaded", function()
    loads = loads + 1
    msg.info("file-loaded #" .. loads .. " playlist-pos=" .. tostring(mp.get_property("playlist-pos")))

    if loads == 2 then
        mp.add_timeout(0.2, function() mp.command("quit") end)
        return
    end

    mp.add_timeout(1.5, function()
        msg.info("step: ENTER on Skip Intro")
        mp.commandv("keypress", "ENTER")
    end)
    mp.add_timeout(2.0, function()
        msg.info("step: seek to credits")
        mp.commandv("seek", "97", "absolute")
    end)
    mp.add_timeout(3.5, function()
        msg.info("step: seek into the countdown window")
        mp.commandv("seek", "116", "absolute")
    end)
    mp.add_timeout(4.0, function()
        msg.info("step: ENTER on Next Episode")
        mp.commandv("keypress", "ENTER")
    end)
end)

-- Deadline: a stuck run exits with status 3 instead of hanging the suite.
mp.add_timeout(8, function()
    msg.warn("deadline reached, quitting")
    mp.commandv("quit", "3")
end)
