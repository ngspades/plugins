-- spawn_protect: a player who just spawned cannot be hurt for a few seconds.
--
-- Ported to Lua for Nextgen Spades from spawn_protect.py (PySnip
-- feature_server/scripts). Original licence: GPL-3.0.
--
-- config.toml:
--   [plugins.spawn_protect]
--   spawn_protect_time = 3.0   # seconds

local plugin = {}
local SECONDS = config.spawn_protect_time or 3.0
local spawned = {} -- by player id: when it spawned

function plugin.on_spawn(p)
    spawned[p.id] = game.time()
end

function plugin.on_leave(p)
    spawned[p.id] = nil
end

local function left(victim)
    local t = spawned[victim.id]
    if t == nil then
        return 0
    end
    return SECONDS - (game.time() - t)
end

-- shots and the spade: the shooter is told why it did nothing
function plugin.on_hit(attacker, victim, kind)
    if attacker.id ~= victim.id and left(victim) > 0 then
        attacker:message(string.format("%s is spawn-protected for %.1f s.", victim.name, left(victim)))
        game.log("protected " .. victim.name .. " from " .. attacker.name)
        return false
    end
end

-- grenades and anything else that hurts
function plugin.on_damage(attacker, victim, amount, reason)
    if attacker ~= nil and attacker.id ~= victim.id and left(victim) > 0 then
        game.log("protected " .. victim.name .. " from " .. attacker.name .. " reason=" .. reason)
        return false
    end
end

return plugin
