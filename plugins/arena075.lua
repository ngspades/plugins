-- arena: round-based elimination (last team standing wins the round).
--
-- 0.75-ONLY MODE. This plugin is a Lua port of the pyspades/piqueserver
-- arena script (piqueserver/game_modes/arena.py) and speaks only the 0.75
-- wire: it builds and destroys gates as ordinary blocks and moves players
-- with teleports, the way the classic servers did. It does NOT use the
-- native 1.0 arena mode (Arena.c, --gamemode arena), its HUD, countdown
-- keys or refill path, so a client on a 1.0 connection to a 1.0 server
-- should use --gamemode arena instead.
--
-- On the 0.75 profile (--profile 075) this is the arena a 0.75 client and
-- a 1.0 client (which falls back to 0.75 there) can play together.
--
-- Licence: GPL-3.0 (ported from piqueserver, itself from PySnip).
--
-- game.supported_profiles("075")

game.supported_profiles("075")

-- A Lua game mode: this one is for the 0.75 server (0.75-only). The 1.0
-- server has the native arena mode (--gamemode arena, Arena.c) instead.

local mode = {name = "arena075", wire = "ctf", mode = true}

-- config (from [plugins.arena] in config.toml; defaults below)
local function cfg(key, default)
    if type(config) == "table" and config[key] ~= nil then
        return config[key]
    end
    return default
end

local SPAWN_ZONE_TIME = 15.0
local TEAM_COLOR_TIME = 4.0
local MAX_ROUND_TIME = 180
local MAP_CHANGE_DELAY = 25.0
local HIDE_COORD = {0, 0, 63}
local MAX_SPAWN_DISTANCE = 15.0
local BUILDING_ENABLED = false
local ROUNDS_TO_WIN = 5

-- state
local arena_enabled = false
local arena_running = false
local arena_counting_down = false
local arena_countdown_timers = {}
local arena_limit_timer = nil
local arena_old_fog = nil
local arena_max_spawn_distance = MAX_SPAWN_DISTANCE

local old_respawn_time = nil
local old_building = nil
local old_killing = nil

local gates = {}
local green_spawns = nil
local blue_spawns = nil

local round_wins = {0, 0}
local current_round = 0
local round_started = false
local round_ended = false
local next_round_at = nil
local alive = {}
local waiting_for_players = false
local countdown_end = 0

local function make_color(r, g, b)
    return r, g, b
end

local function team_of(p)
    return p.team
end

local function count_alive(team)
    local n = 0
    for _, p in ipairs(game.players()) do
        if p.team == team and p.alive then
            n = n + 1
        end
    end
    return n
end

local function both_teams_ready()
    local ready = {false, false}
    for _, p in ipairs(game.players()) do
        if (p.team == 1 or p.team == 2) and p.alive then
            ready[p.team] = true
        end
    end
    return ready[1] and ready[2]
end

-- gate flood fill by uniform color
local function record_gate(seed_x, seed_y, seed_z)
    local sx, sy, sz = game.map_size()
    local r0, g0, b0 = game.color(seed_x, seed_y, seed_z)
    if r0 == nil then return nil end
    local blocks = {}
    local support = {}
    local seen = {}
    local function key(x, y, z) return x .. "," .. y .. "," .. z end
    local function flood(x, y, z)
        if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz then return end
        if seen[key(x, y, z)] then return end
        local r, g, b = game.color(x, y, z)
        if r == nil or r ~= r0 or g ~= g0 or b ~= b0 then return end
        seen[key(x, y, z)] = true
        table.insert(blocks, {x, y, z})
        -- support: a neighbour of different color/air
        local is_support = false
        local nbrs = {{x+1,y,z},{x-1,y,z},{x,y+1,z},{x,y-1,z},{x,y,z+1},{x,y,z-1}}
        for _, n in ipairs(nbrs) do
            local nr, ng, nb = game.color(n[1], n[2], n[3])
            if nr == nil or nr ~= r0 or ng ~= g0 or nb ~= b0 then
                is_support = true
            end
        end
        if is_support then table.insert(support, {x, y, z}) end
        flood(x+1, y, z)
        flood(x-1, y, z)
        flood(x, y+1, z)
        flood(x, y-1, z)
        flood(x, y, z+1)
        flood(x, y, z-1)
    end
    flood(seed_x, seed_y, seed_z)
    return {blocks = blocks, support = support, color = {r0, g0, b0}}
end

local function build_gate(gate)
    local r, g, b = gate.color[1], gate.color[2], gate.color[3]
    for _, blk in ipairs(gate.blocks) do
        game.set_block(blk[1], blk[2], blk[3], r, g, b)
    end
end

local function destroy_gate(gate)
    for _, blk in ipairs(gate.support) do
        game.clear_block(blk[1], blk[2], blk[3])
    end
    for _, blk in ipairs(gate.blocks) do
        game.clear_block(blk[1], blk[2], blk[3])
    end
end

local function read_config()
    SPAWN_ZONE_TIME = cfg("spawn_zone_time", SPAWN_ZONE_TIME)
    MAX_ROUND_TIME = cfg("max_round_time", MAX_ROUND_TIME)
    MAX_SPAWN_DISTANCE = cfg("max_spawn_distance", MAX_SPAWN_DISTANCE)
    BUILDING_ENABLED = cfg("building", BUILDING_ENABLED)
    ROUNDS_TO_WIN = cfg("rounds_to_win", ROUNDS_TO_WIN)
    local gates_cfg = cfg("gates", nil)
    if type(gates_cfg) == "table" then
        gates = {}
        for _, g in ipairs(gates_cfg) do
            local gate = record_gate(g[1], g[2], g[3])
            if gate then table.insert(gates, gate) end
        end
    end
    -- spawns from config or game.spawn
    local gs = cfg("green_spawns", nil)
    local bs = cfg("blue_spawns", nil)
    if type(gs) == "table" then green_spawns = gs end
    if type(bs) == "table" then blue_spawns = bs end
end

local function arena_spawn_all()
    for _, p in ipairs(game.players()) do
        if p.team == 1 or p.team == 2 then
            local sp = (p.team == 1) and green_spawns or blue_spawns
            if sp and #sp > 0 then
                local s = sp[math.random(#sp)]
                p:teleport(s[1], s[2], s[3])
                p:restock()
            end
        end
    end
end

local function refill_all()
    for _, p in ipairs(game.players()) do
        if p.team == 1 or p.team == 2 then
            p:restock()
        end
    end
end

local function build_gates()
    for _, g in ipairs(gates) do build_gate(g) end
end

local function destroy_gates()
    for _, g in ipairs(gates) do destroy_gate(g) end
end

local function team_alive_count(team)
    local n = 0
    for _, p in ipairs(game.players()) do
        if p.team == team and p.alive then n = n + 1 end
    end
    return n
end

local function check_round_end()
    if not arena_running then return end
    local c1 = team_alive_count(1)
    local c2 = team_alive_count(2)
    if c1 == 0 and c2 > 0 then
        -- team 2 wins
        round_wins[2] = round_wins[2] + 1
        game.set_score(2, round_wins[2])
        game.notice("Team 2 wins the round!")
        begin_countdown()
    elseif c2 == 0 and c1 > 0 then
        round_wins[1] = round_wins[1] + 1
        game.set_score(1, round_wins[1])
        game.notice("Team 1 wins the round!")
        begin_countdown()
    elseif c1 == 0 and c2 == 0 then
        game.notice("Round draw!")
        begin_countdown()
    end
    -- check match win
    if round_wins[1] >= ROUNDS_TO_WIN then
        game.notice("Team 1 wins the match!")
        game.win(1)
    elseif round_wins[2] >= ROUNDS_TO_WIN then
        game.notice("Team 2 wins the match!")
        game.win(2)
    end
end

function begin_countdown()
    if arena_limit_timer then
        -- cancel not available; just ignore
    end
    arena_running = false
    arena_counting_down = true
    arena_limit_timer = nil
    -- disable killing/building
    old_killing = game.killing
    old_building = game.building
    game.killing = false
    game.building = false
    build_gates()
    arena_spawn_all()
    game.notice("The round will begin in " .. SPAWN_ZONE_TIME .. " seconds.")
    -- countdown messages
    for i = 1, 5 do
        game.later(SPAWN_ZONE_TIME - i, function()
            game.notice(tostring(i))
        end)
    end
    game.later(SPAWN_ZONE_TIME, function()
        begin_arena()
    end)
end

function begin_arena()
    -- check both teams have players
    if team_alive_count(1) == 0 or team_alive_count(2) == 0 then
        game.notice("Not enough players on both teams.")
        begin_countdown()
        return
    end
    arena_counting_down = false
    arena_running = true
    game.killing = true
    game.building = BUILDING_ENABLED
    refill_all()
    destroy_gates()
    game.notice("Go!")
    if MAX_ROUND_TIME > 0 then
        game.notice("Time limit: " .. MAX_ROUND_TIME .. " seconds.")
        game.later(MAX_ROUND_TIME, function()
            arena_time_limit()
        end)
    end
    -- record alive
    alive = {}
    for _, p in ipairs(game.players()) do
        if (p.team == 1 or p.team == 2) and p.alive then
            table.insert(alive, p)
        end
    end
end

function arena_time_limit()
    if not arena_running then return end
    local c1 = team_alive_count(1)
    local c2 = team_alive_count(2)
    if c1 > c2 then
        round_wins[1] = round_wins[1] + 1
        game.set_score(1, round_wins[1])
        game.notice("Time's up! Team 1 wins.")
    elseif c2 > c1 then
        round_wins[2] = round_wins[2] + 1
        game.set_score(2, round_wins[2])
        game.notice("Time's up! Team 2 wins.")
    else
        game.notice("Time's up! Draw.")
    end
    begin_countdown()
end

function mode.on_init()
    read_config()
    if not arena_enabled then
        -- allow always enabled via config
        arena_enabled = cfg("enabled", true)
    end
    if not arena_enabled then return end
    -- defaults for spawns
    if not green_spawns then
        local x, y = game.spawn(1)
        green_spawns = {{math.floor(x), math.floor(y), game.ground(math.floor(x), math.floor(y))}}
    end
    if not blue_spawns then
        local x, y = game.spawn(2)
        blue_spawns = {{math.floor(x), math.floor(y), game.ground(math.floor(x), math.floor(y))}}
    end
    old_respawn_time = game.respawn_time
    game.respawn_time = 0
    game.set_score(1, 0)
    game.set_score(2, 0)
    round_wins = {0, 0}
    current_round = 0
    game.later(MAP_CHANGE_DELAY, function()
        begin_countdown()
    end)
    game.log("arena (0.75 port): enabled, " .. #gates .. " gates")
    game.notice("Arena (0.75): round-based elimination. Last team standing wins.")
end

function mode.on_map_change()
    -- cleanup
    if old_respawn_time then game.respawn_time = old_respawn_time end
    if old_building ~= nil then game.building = old_building end
    if old_killing ~= nil then game.killing = old_killing end
    arena_enabled = false
    arena_running = false
    arena_counting_down = false
    gates = {}
    read_config()
    arena_enabled = cfg("enabled", true)
    if not arena_enabled then return end
    if not green_spawns then
        local x, y = game.spawn(1)
        green_spawns = {{math.floor(x), math.floor(y), game.ground(math.floor(x), math.floor(y))}}
    end
    if not blue_spawns then
        local x, y = game.spawn(2)
        blue_spawns = {{math.floor(x), math.floor(y), game.ground(math.floor(x), math.floor(y))}}
    end
    old_respawn_time = game.respawn_time
    game.respawn_time = 0
    game.set_score(1, 0)
    game.set_score(2, 0)
    round_wins = {0, 0}
    game.later(MAP_CHANGE_DELAY, function()
        begin_countdown()
    end)
end

function mode.on_tick()
    if not arena_enabled then return end
    -- leash during countdown
    if arena_counting_down then
        for _, p in ipairs(game.players()) do
            if (p.team == 1 or p.team == 2) and p.alive then
                local sp = (p.team == 1) and green_spawns or blue_spawns
                if sp and #sp > 0 then
                    local s = sp[1]
                    local dx = p.x - s[1]
                    local dy = p.y - s[2]
                    local dz = p.z - s[3]
                    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                    if dist > arena_max_spawn_distance then
                        p:teleport(s[1], s[2], s[3])
                        p:restock()
                    end
                end
            end
        end
    end
    -- check round end during round
    if arena_running then
        check_round_end()
    end
end

function mode.on_kill(killer, victim, reason)
    if not arena_running then return end
    -- check after a death
    game.later(0, function() check_round_end() end)
end

function mode.on_spawn(player)
    if not arena_enabled then return end
    if arena_running then
        player:kill()
    end
end

function mode.on_player_tick(player)
    if not arena_enabled then return end
    if arena_counting_down and (player.team == 1 or player.team == 2) and player.alive then
        local sp = (player.team == 1) and green_spawns or blue_spawns
        if sp and #sp > 0 then
            local s = sp[1]
            local dx = player.x - s[1]
            local dy = player.y - s[2]
            local dz = player.z - s[3]
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist > arena_max_spawn_distance then
                player:teleport(s[1], s[2], s[3])
                player:restock()
            end
        end
    end
end

return mode