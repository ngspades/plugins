-- tdm: team deathmatch. Every enemy killed scores a point for the killer's
-- team; the first team to the map's score limit (capture_limit in its toml)
-- wins. A game mode: --gamemode tdm.
--
-- Ported to Lua for Shoot and Destroy from tdm.py (PySnip
-- feature_server/scripts), maintained by Triplefox. Original licence: GPL-3.0.

-- A Lua game mode: the 0.75 server plays only ctf and babel, so this
-- plugin is for the 1.0 server alone (first, before anything runs).
game.supported_profiles("10")

local mode = {name = "tdm10", wire = "ctf", mode = true}

function mode.on_init()
    game.set_score(1, 0)
    game.set_score(2, 0)
    game.log("team deathmatch, first to " .. game.score_limit())
    game.later(5, function() game.notice("Team deathmatch: every kill scores, first to " .. game.score_limit()) end)
end

function mode.on_kill(killer, victim)
    if killer == nil or killer.id == victim.id or killer.team == victim.team or killer.team == 0 then
        return
    end
    local score = game.score(killer.team) + 1
    game.set_score(killer.team, score)
    if score >= game.score_limit() then
        game.notice(killer.name .. " wins it for team " .. killer.team)
        game.win(killer.team)
    end
end

return mode
