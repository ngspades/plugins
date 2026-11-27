-- disco: /disco (staff) cycles the sky through bright colours.
--
-- Ported to Lua for Nexgen Spades from disco.py (pyspades), maintained by
-- mat^2. Original licence: GPL-3.0.
--
-- The server-wide fog is changed every `interval` seconds and restored when
-- the party stops or the map ends. An admin can start it during a match.
--
-- config.toml (all optional):
--   [plugins.disco]
--   interval = 0.35
--   colours = [[235,64,0], [128,232,121], [220,223,12], [43,72,228]]

local plugin = {}
local INTERVAL = config.interval or 0.35
local COLOURS = config.colours or {
    {235, 64, 0}, {128, 232, 121}, {220, 223, 12},
    {43, 72, 228}, {216, 94, 231}, {255, 255, 255},
}
local on = false
local old = nil
local token = 0

local function step(mine)
    if not on or token ~= mine then
        return
    end
    local c = COLOURS[math.random(#COLOURS)]
    game.fog(c[1], c[2], c[3])
    game.later(INTERVAL, function() step(mine) end)
end

function plugin.on_init()
    old = {game.get_fog()}
    on = false
    token = token + 1
end

game.command("disco", {role = "admin", help = "Starts or stops the disco sky"}, function(p)
    on = not on
    token = token + 1
    if on then
        if old == nil then
            old = {game.get_fog()}
        end
        game.notice("DISCO PARTY MODE ENABLED!")
        step(token)
    else
        if old ~= nil then
            game.fog(old[1], old[2], old[3])
        end
        game.notice("The party has been stopped.")
    end
    game.log("disco on=" .. tostring(on))
end)

return plugin
