-- votekick: /votekick <player> <reason>, /y, /cancel.
--
-- Ported to Lua for Nextgen Spades from votekick.py (pyspades), by
-- James Hofmann (triplefox), 2012. Original licence: GPL-3.0.
--
-- Staff are immune, a bot cannot be voted, one vote runs at a time, and an
-- instigator waits `cooldown` seconds between votes. The commands need no
-- role, so any player may use them.
--
-- config.toml (all optional):
--   [plugins.votekick]
--   percent = 50          # share of the humans that must say /y (at least 2)
--   seconds = 120         # how long a vote stays open
--   cooldown = 120        # between votes started by the same player
--   reason = true         # require a reason

local plugin = {}
local PERCENT = config.percent or 50
local SECONDS = config.seconds or 120
local COOLDOWN = config.cooldown or 120
local REASON = config.reason ~= false
local vote = nil
local last = {}
local token = 0

local function humans()
    local n = 0
    for _, p in ipairs(game.players()) do
        if not p.bot and p.team > 0 then
            n = n + 1
        end
    end
    return n
end

local function needed()
    return math.max(2, math.ceil(humans() * PERCENT / 100))
end

local function finish(why)
    if vote == nil then
        return
    end
    local v = vote
    vote = nil
    game.notice("Votekick against " .. v.name .. " ended: " .. why)
    game.log("votekick end target=" .. v.name .. " why=" .. why)
end

local function start(p, target, reason)
    if vote ~= nil then
        p:message("A votekick is already in progress.")
        return
    end
    if target == nil then
        p:message("No player with that name.")
        return
    end
    if target.id == p.id then
        p:message("You cannot votekick yourself.")
        return
    end
    if target.bot then
        p:message("Bots cannot be votekicked.")
        return
    end
    if target:has_role("mod") then
        p:message("That player is staff.")
        return
    end
    if REASON and reason == "" then
        p:message("Give a reason: /votekick <player> <reason>")
        return
    end
    local now = game.time()
    if last[p.id] ~= nil and now - last[p.id] < COOLDOWN then
        p:message("You cannot start another votekick yet.")
        return
    end
    last[p.id] = now
    token = token + 1
    vote = {name = target.name, id = target.id, by = p.id, reason = reason, yes = {[p.id] = true}, need = needed(), token = token}
    game.notice(p.name .. " started a votekick against " .. target.name ..
                " (" .. needed() .. " votes). Reason: " .. (reason ~= "" and reason or "none") ..
                ". Say /y to agree.")
    game.log("votekick start target=" .. target.name .. " by=" .. p.name .. " need=" .. needed())
    local mine = vote.token
    game.later(SECONDS, function()
        if vote ~= nil and vote.token == mine then
            finish("timed out")
        end
    end)
end

game.command("y", {help = "Votes yes in a votekick"}, function(p)
    if p == nil then
        return "the console has no vote"
    end
    if vote == nil then
        return "No votekick in progress."
    end
    if p.id ~= vote.id and vote.yes[p.id] == nil then
        vote.yes[p.id] = true
        local n = 0
        for _ in pairs(vote.yes) do
            n = n + 1
        end
        game.notice(p.name .. " voted yes (" .. n .. "/" .. vote.need .. ").")
        if n >= vote.need then
            local target = game.player(vote.id)
            local name = vote.name
            if target ~= nil then
                target:kick("votekicked: " .. (vote.reason ~= "" and vote.reason or "no reason"))
            end
            finish("passed")
            game.log("votekick passed target=" .. name)
        end
    end
end)

game.command("cancel", {help = "Cancels your votekick (staff: any)"}, function(p)
    if vote == nil then
        return "No votekick in progress."
    elseif p == nil or p.id == vote.by or p:has_role("mod") then
        finish("cancelled")
    else
        return "Only the instigator or staff can cancel it."
    end
end)

game.command("votekick", {help = "Starts a vote to kick a player. Usage: votekick <player> <reason>"}, function(p, args, rest)
    if p == nil then
        return "the console can /kick"
    end
    local name, reason = rest:match("^(%S+)%s*(.*)$")
    if name == nil then
        return "Usage: /votekick <player> <reason>"
    end
    start(p, game.find(name), reason)
end)

function plugin.on_leave(p)
    last[p.id] = nil
    if vote ~= nil and (p.id == vote.id or p.id == vote.by) then
        finish(p.name .. " left")
    end
end

return plugin
