-- push: capture the flag across the whole map. A game mode: --gamemode push.
--
-- Ported to Lua for Shoot and Destroy from push.py (pyspades), by danhezee,
-- StackOverflow, izzy, Danke, noway421 and IAmYourFriend. Original licence:
-- GPL-3.0. The original reads the spawns and control points from the map's
-- extensions; this port puts them by each team's spawn.
--
-- Each team picks the enemy's intel up near its own spawn and pushes
-- it to its own tent, which stands out near the enemy's spawn: every capture is a run
-- through the enemy, and a carrier who falls leaves the intel where it lies.
-- The rules are capture the flag's (rules = "ctf"); the script only moves
-- the intels and the tents.

-- A Lua game mode: the 0.75 server plays only ctf and babel, so this
-- plugin is for the 1.0 server alone (first, before anything runs).
game.supported_profiles("10")

local mode = {name = "push10", wire = "ctf", rules = "ctf", mode = true}

local TENT_IN = 0.15 -- the tent this share of the way in from the enemy's spawn

function mode.on_init()
    for team = 1, 2 do
        local enemy = 3 - team
        local ox, oy = game.spawn(team)
        local ex, ey = game.spawn(enemy)
        -- the enemy's intel waits at our spawn: we take it from there
        game.set_intel_spot(enemy, ox, oy)
        -- and our tent stands by theirs: we bring it there
        game.set_tent_spot(team, ex + (ox - ex) * TENT_IN, ey + (oy - ey) * TENT_IN)
    end
    game.log("push: intels at their takers' spawns, tents by the enemy's, first to " .. game.score_limit())
    game.later(5, function()
        game.notice("Push: take the enemy's intel near your spawn and carry it to your tent by theirs")
    end)
end

return mode
