-- log.lua — mp.msg with a per-feature prefix. The package is one mpv script
-- (log domain `media_centaur`), so every feature prefixes its lines to keep
-- the log readable: `[media_centaur] skip-intro: show`.
--
--     local msg = require("log")("skip-intro")
--     msg.info("chapter observer registered")

local mp_msg = require("mp.msg")

return function(prefix)
    local msg = {}
    for _, level in ipairs({ "fatal", "error", "warn", "info", "verbose", "debug", "trace" }) do
        msg[level] = function(text)
            mp_msg[level](prefix .. ": " .. text)
        end
    end
    return msg
end
