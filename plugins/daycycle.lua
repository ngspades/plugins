-- daycycle: the sky moves slowly from day to sunset to night and back.
--
-- Ported to Lua for Nexgen Spades from daycycle.py (pyspades), maintained
-- by hompy. Original licence: GPL-3.0. The original interpolated a 24-hour
-- colour table; this shorter version keeps the same idea without a 24-hour
-- clock (a handheld match is minutes, not a day).
--
-- config.toml (all optional):
--   [plugins.daycycle]
--   period = 600          # seconds from day to night and back
--   day = [128,232,255]
--   dusk = [255,150,80]
--   night = [8,12,30]

local plugin = {}
local PERIOD = config.period or 600
local DAY = config.day or {128, 232, 255}
local DUSK = config.dusk or {255, 150, 80}
local NIGHT = config.night or {8, 12, 30}
local next_at = 0

local function mix(a, b, t)
    return math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
           math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
           math.floor(a[3] + (b[3] - a[3]) * t + 0.5)
end

function plugin.on_init()
    next_at = 0
end

function plugin.on_tick()
    local now = game.time()
    if now < next_at then
        return
    end
    next_at = now + 0.5
    local phase = (now % PERIOD) / PERIOD
    local r, g, b
    if phase < 0.35 then
        r, g, b = mix(DAY, DUSK, phase / 0.35)
    elseif phase < 0.5 then
        r, g, b = mix(DUSK, NIGHT, (phase - 0.35) / 0.15)
    elseif phase < 0.85 then
        r, g, b = mix(NIGHT, DAY, (phase - 0.5) / 0.35)
    else
        r, g, b = mix(DAY, DUSK, (phase - 0.85) / 0.15)
    end
    game.fog(r, g, b)
end

return plugin
