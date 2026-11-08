-- koth: king of the hill. A game mode: --gamemode koth.
--
-- Written for Shoot and Destroy after koth.py / koth_script.py (aloha.pk's
-- redistribution of Ace of Spades community scripts), which only switched
-- pyspades to territorial control; the hill and its points are ours.
-- Licence: GPL-3.0.
--
-- A hill halfway between the two spawns (the nearest dry
-- ground to it). Every second the team with more players alive on it holds
-- it; each HOLD_POINT seconds held is a point, and the first team to the
-- map's score limit (capture_limit in its toml) wins. Bots go to the hill
-- (game.objective) and fight for it.

-- A Lua game mode: the 0.75 server plays only ctf and babel, so this
-- plugin is for the 1.0 server alone (first, before anything runs).
game.supported_profiles("10")

local mode = {name = "koth10", wire = "ctf", mode = true}

local RADIUS = 8        -- blocks round the middle
local HEIGHT = 6        -- and this far above or below its ground
local HOLD_POINT = 5    -- seconds held for a point

local hill = {x = 0, y = 0, z = 0, next = 0, holder = 0, held = {0, 0}}

-- the dry column nearest to x, y: rings outward (the middle of 2Fort is water)
local function dry_near(x, y)
    local sx, sy, sz = game.map_size()
    for r = 0, 40 do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local cx, cy = x + dx, y + dy
                    if cx >= 0 and cy >= 0 and cx < sx and cy < sy and game.ground(cx, cy) < sz - 2 then
                        return cx, cy
                    end
                end
            end
        end
    end
    return x, y
end

function mode.on_init()
    game.set_score(1, 0)
    game.set_score(2, 0)
    local ax, ay = game.spawn(1)
    local bx, by = game.spawn(2)
    hill.x, hill.y = dry_near(math.floor((ax + bx) / 2), math.floor((ay + by) / 2))
    hill.z = game.ground(hill.x, hill.y)
    hill.next, hill.holder, hill.held = game.time() + 1, 0, {0, 0}
    game.objective(hill.x + 0.5, hill.y + 0.5, RADIUS)
    game.log("king of the hill at " .. hill.x .. "," .. hill.y .. "," .. hill.z .. ", first to " .. game.score_limit())
    game.later(5, function()
        game.notice("King of the hill: hold the middle, " .. HOLD_POINT .. " s held is a point, first to " ..
                    game.score_limit())
    end)
end

function mode.on_tick()
    local now = game.time()
    if now < hill.next then
        return
    end
    hill.next = now + 1
    local on = {0, 0}
    for _, p in ipairs(game.players()) do
        if p.alive and p.team > 0 then
            local dx, dy = p.x - (hill.x + 0.5), p.y - (hill.y + 0.5)
            if dx * dx + dy * dy <= RADIUS * RADIUS and math.abs(p.z - hill.z) <= HEIGHT then
                on[p.team] = on[p.team] + 1
            end
        end
    end
    local holder = 0
    if on[1] > on[2] then holder = 1 elseif on[2] > on[1] then holder = 2 end
    if holder ~= hill.holder then
        hill.holder = holder
        if holder > 0 then
            game.notice("Team " .. holder .. " holds the hill")
            game.log("holder team=" .. holder .. " on=" .. on[1] .. "-" .. on[2])
        end
    end
    if holder == 0 then
        return
    end
    hill.held[holder] = hill.held[holder] + 1
    local score = hill.held[holder] // HOLD_POINT
    if score ~= game.score(holder) then
        game.set_score(holder, score)
        if score >= game.score_limit() then
            game.notice("Team " .. holder .. " is king of the hill")
            game.win(holder)
        end
    end
end

return mode
