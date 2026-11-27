-- welcome: greets the players named in the config when they join.
--
-- Ported to Lua for Nexgen Spades from welcome.py (PySnip
-- feature_server/scripts), maintained by mat^2. Original licence: GPL-3.0.
--
-- config.toml:
--   [plugins.welcome]
--   welcomes = { Deuce = "Welcome back, Deuce!" }

local plugin = {}
local welcomes = config.welcomes or {}

function plugin.on_join(p, team)
    local text = welcomes[p.name]
    if text then
        game.notice(text)
        game.log("welcomed " .. p.name)
    end
end

return plugin
