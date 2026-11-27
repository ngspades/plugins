-- medkit: a small heal carried from spawn, used with /medkit.
--
-- Ported to Lua for Nexgen Spades from medkit.py (PySnip
-- feature_server/scripts), by Booboorocks998, maintained by mat^2.
-- Original licence: GPL-3.0.
--
-- config.toml (all optional):
--   [plugins.medkit]
--   medkits = 1
--   heal_amount = 40

local plugin = {}
local left = {}
local MAX = config.medkits or 1
local HEAL = config.heal_amount or 40

function plugin.on_spawn(p)
    left[p.id] = MAX
end

function plugin.on_leave(p)
    left[p.id] = nil
end

game.command("medkit", {help = "Heals you with a medkit"}, function(p)
    if p == nil then
        return "only a player carries medkits"
    end
    local n = left[p.id] or 0
    if n <= 0 then
        return "You have no medkits left."
    end
    if p.hp >= 100 then
        return "You are already at full health."
    end
    p:set_hp(math.min(100, p.hp + HEAL))
    left[p.id] = n - 1
    game.log("medkit " .. p.name .. " hp=" .. p.hp .. " left=" .. (n - 1))
    return "Medkit used (" .. (n - 1) .. " left)."
end)

return plugin
