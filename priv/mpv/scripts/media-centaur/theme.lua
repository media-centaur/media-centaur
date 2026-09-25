-- theme.lua — the palette every bundled overlay shares, plus ASS tag helpers.
-- Colors are ASS BGR ("FF9F4B" here is #4B9FFF on the web). Alphas are not
-- part of the theme: each surface picks its own opacity.

local theme = {
    bg     = "40302A",  -- dark panel / pill background
    hl     = "FF9F4B",  -- cursor highlight bar
    text   = "ECE8E8",  -- normal text
    bright = "FFFFFF",  -- highlighted / label text
    header = "FF9F4B",  -- headers and accents (arrows)
    border = "ECE8E8",  -- panel / pill border
    dim    = "808080",  -- placeholder and key-hint text
    active = "FF9F4B",  -- active markers
}

function theme.color(bgr)
    return "\\1c&H" .. bgr .. "&"
end

function theme.alpha(a)
    return "\\1a&H" .. a .. "&"
end

function theme.border_color(bgr)
    return "\\3c&H" .. bgr .. "&"
end

function theme.border_alpha(a)
    return "\\3a&H" .. a .. "&"
end

return theme
