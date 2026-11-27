-- rampage: killing 3 enemies in under 8 seconds sends the killer into a
-- rampage for 20 seconds: a full restock, a red sky (blinking in its last 3
-- seconds) and an announcement; whoever ends it is announced too.
--
-- Ported to Lua for Nexgen Spades from rampage.py (PySnip
-- feature_server/scripts), maintained by hompy. Original licence: GPL-3.0.
-- Not ported yet: the faster rate of fire, which needs the server to let a
-- player shoot faster than its gun (it comes with the rapid plugin).
--
-- config.toml (all optional):
--   [plugins.rampage]
--   kills = 3
--   seconds = 8.0          # the kills must fit in this window
--   duration = 20.0
--   grenade_kills = true   # grenade kills count
--   fog = [255, 0, 0]

local plugin = {}
local KILLS = config.kills or 3
local WINDOW = config.seconds or 8.0
local DURATION = config.duration or 20.0
local GRENADE_KILLS = config.grenade_kills ~= false
local FOG = config.fog or {255, 0, 0}
local GRENADE = 3 -- kill reason

local state = {} -- by player id: {kills = {times}, on = bool, token = n}

local function get(id)
    if state[id] == nil then
        state[id] = {kills = {}, on = false, token = 0}
    end
    return state[id]
end

local function stop(id)
    local s = get(id)
    s.on = false
    s.token = s.token + 1
    local p = game.player(id)
    if p ~= nil then
        p:fog(game.get_fog())
    end
end

-- the last seconds: the sky blinks between red and the map's
local function blink(id, token, red, times)
    local s = get(id)
    local p = game.player(id)
    if not s.on or s.token ~= token or p == nil or times == 0 then
        return
    end
    if red then
        p:fog(FOG[1], FOG[2], FOG[3])
    else
        p:fog(game.get_fog())
    end
    game.later(0.5, function() blink(id, token, not red, times - 1) end)
end

local function start(p)
    local s = get(p.id)
    s.kills = {}
    s.on = true
    s.token = s.token + 1
    local token = s.token
    p:restock()
    p:fog(FOG[1], FOG[2], FOG[3])
    game.notice(p.name .. " IS ON A RAMPAGE!!")
    game.log("rampage start " .. p.name)
    if DURATION > 4 then
        game.later(DURATION - 3, function() blink(p.id, token, false, 6) end)
    end
    game.later(DURATION, function()
        if s.on and s.token == token then
            stop(p.id)
            game.log("rampage end " .. p.name .. " why=time")
        end
    end)
end

function plugin.on_kill(killer, victim, reason)
    local was = get(victim.id).on
    if was then
        stop(victim.id)
        game.log("rampage end " .. victim.name .. " why=killed")
    end
    if killer == nil or killer.id == victim.id then
        return
    end
    if was then
        game.notice(victim.name .. "'s rampage was ended by " .. killer.name)
    end
    local s = get(killer.id)
    if s.on or not killer.alive or killer.team == victim.team or (reason == GRENADE and not GRENADE_KILLS) then
        return
    end
    local now = game.time()
    table.insert(s.kills, now)
    if #s.kills > KILLS then
        table.remove(s.kills, 1)
    end
    if #s.kills == KILLS and s.kills[1] >= now - WINDOW then
        start(killer)
    end
end

function plugin.on_leave(p)
    state[p.id] = nil
end

return plugin
