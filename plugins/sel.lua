-- sel: building tools for builders and admins: select a box, fill it,
-- clear it, copy and paste it, undo the last change.
--
-- Inspired by lsd's sel.lua (totallynotaburner, https://66.135.15.57/lsd)
-- and WorldEdit; written from scratch for Nexgen Spades. Best in the
-- creative mode, but it works in any mode on the cells the mode and the
-- map let change.
--
--   /pos1, /pos2       the corners: the block you look at (or your feet)
--   /sel               the selection's size
--   /fill [r g b]      fill it (default: the colour of the block at pos1)
--   /clear             empty it (what then hangs on nothing falls)
--   /copy              keep the selection's blocks
--   /paste             put them with their corner on the block you look at
--   /undo              put back what your last change changed
--
-- These are typed commands, so they are for builders and admins: a match
-- never needs them (the game is played with a gamepad).
--
-- config.toml:
--   [plugins.sel]
--   role = "trusted"     # who may use them
--   max_cells = 32768    # the largest selection

local plugin = {}
local ROLE = config.role or "trusted"
local MAX_CELLS = config.max_cells or 32768
local REACH = 64

local state = {} -- by player id: pos1, pos2, clipboard, undo
local jobs = {} -- the changes being made, a few thousand cells a tick

local function of(p)
    state[p.id] = state[p.id] or {}
    return state[p.id]
end

-- the first solid cell along the look, from the eye; else the cell at the
-- feet
local function target(p)
    local sx, sy, sz = game.map_size()
    for i = 1, REACH * 10 do
        local t = i / 10
        local x = math.floor(p.x + p.ox * t)
        local y = math.floor(p.y + p.oy * t)
        local z = math.floor(p.z + p.oz * t)
        if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz then
            break
        end
        if game.cell(x, y, z) then
            return x, y, z
        end
    end
    return math.floor(p.x), math.floor(p.y), math.floor(p.z + 2)
end

local function box(s)
    if s.pos1 == nil or s.pos2 == nil then
        return nil, "set both corners first: /pos1 and /pos2"
    end
    local a, b = s.pos1, s.pos2
    local b0 = {math.min(a[1], b[1]), math.min(a[2], b[2]), math.min(a[3], b[3])}
    local b1 = {math.max(a[1], b[1]), math.max(a[2], b[2]), math.max(a[3], b[3])}
    local n = (b1[1] - b0[1] + 1) * (b1[2] - b0[2] + 1) * (b1[3] - b0[3] + 1)
    if n > MAX_CELLS then
        return nil, string.format("the selection has %d cells, more than %d", n, MAX_CELLS)
    end
    return b0, b1, n
end

local function tell(id, text)
    local p = game.player(id)
    if p ~= nil then
        p:message(text)
    end
end

-- a change is a list of {x, y, z, r, g, b} (r false: air), made over as
-- many ticks as the server's rate allows; what each cell was is kept
-- for /undo
local function start(p, cells, what)
    local s = of(p)
    if s.busy then
        return "wait: your last change is still being made"
    end
    s.busy = true
    jobs[#jobs + 1] = {id = p.id, cells = cells, i = 1, before = {}, done = 0, skipped = 0, what = what}
    return what .. ": " .. #cells .. " cells"
end

local function same(x, y, z, r, g, b)
    local cr, cg, cb = game.color(x, y, z)
    if r == false then
        return cr == nil
    end
    return cr == r and cg == g and cb == b
end

local function step(job)
    while job.i <= #job.cells do
        local c = job.cells[job.i]
        local x, y, z, r, g, b = c[1], c[2], c[3], c[4], c[5], c[6]
        if not same(x, y, z, r, g, b) then
            local pr, pg, pb = game.color(x, y, z)
            local ok, why
            if r == false then
                ok, why = game.clear_block(x, y, z)
            else
                ok, why = game.set_block(x, y, z, r, g, b)
            end
            if why == "rate" then
                return false -- the server's limit for this tick: go on next tick
            end
            if ok then
                job.before[#job.before + 1] = {x, y, z, pr or false, pg, pb}
                job.done = job.done + 1
            else
                job.skipped = job.skipped + 1
            end
        end
        job.i = job.i + 1
    end
    return true
end

function plugin.on_tick()
    local job = jobs[1]
    if job == nil then
        return
    end
    if step(job) then
        table.remove(jobs, 1)
        local s = state[job.id]
        if s ~= nil then
            s.busy = false
            if job.what ~= "undo" then
                s.undo = job.before
            end
        end
        local text = string.format("%s done: %d changed", job.what, job.done)
        if job.skipped > 0 then
            text = text .. string.format(", %d the map or the mode keeps", job.skipped)
        end
        tell(job.id, text)
        game.log(string.format("%s by player %d: %d changed, %d kept", job.what, job.id, job.done, job.skipped))
    end
end

local opts = function(help)
    return {role = ROLE, help = help}
end

local function corner(n)
    return function(p)
        if p == nil then
            return "only a player can choose a corner"
        end
        local x, y, z = target(p)
        of(p)["pos" .. n] = {x, y, z}
        return string.format("pos%d: %d, %d, %d", n, x, y, z)
    end
end

game.command("pos1", opts("A corner of the selection: the block you look at"), corner(1))
game.command("pos2", opts("The other corner of the selection"), corner(2))

game.command("sel", opts("The selection's size"), function(p)
    if p == nil then
        return "only a player has a selection"
    end
    local b0, b1, n = box(of(p))
    if b0 == nil then
        return b1
    end
    return string.format("%d x %d x %d, %d cells", b1[1] - b0[1] + 1, b1[2] - b0[2] + 1, b1[3] - b0[3] + 1, n)
end)

local function color_arg(args, s)
    if #args >= 3 then
        local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
        if r and g and b then
            return math.floor(r) & 255, math.floor(g) & 255, math.floor(b) & 255
        end
        return nil
    end
    local r, g, b = game.color(s.pos1[1], s.pos1[2], s.pos1[3])
    if r == nil then
        return 128, 128, 128
    end
    return r, g, b
end

game.command("fill", opts("Fills the selection. Usage: fill [r g b]"), function(p, args)
    if p == nil then
        return "only a player has a selection"
    end
    local s = of(p)
    local b0, b1 = box(s)
    if b0 == nil then
        return b1
    end
    local r, g, b = color_arg(args, s)
    if r == nil then
        return "Usage: /fill [r g b], each 0..255"
    end
    local cells = {}
    -- the bottom first (z grows downwards): each block lands on the last
    for z = b1[3], b0[3], -1 do
        for x = b0[1], b1[1] do
            for y = b0[2], b1[2] do
                cells[#cells + 1] = {x, y, z, r, g, b}
            end
        end
    end
    return start(p, cells, "fill")
end)

game.command("clear", opts("Empties the selection"), function(p)
    if p == nil then
        return "only a player has a selection"
    end
    local b0, b1 = box(of(p))
    if b0 == nil then
        return b1
    end
    local cells = {}
    -- the top first: a block taken from under the rest would make it fall
    for z = b0[3], b1[3] do
        for x = b0[1], b1[1] do
            for y = b0[2], b1[2] do
                cells[#cells + 1] = {x, y, z, false}
            end
        end
    end
    return start(p, cells, "clear")
end)

game.command("copy", opts("Keeps the selection's blocks for /paste"), function(p)
    if p == nil then
        return "only a player has a selection"
    end
    local s = of(p)
    local b0, b1 = box(s)
    if b0 == nil then
        return b1
    end
    local clip = {}
    for z = b0[3], b1[3] do
        for x = b0[1], b1[1] do
            for y = b0[2], b1[2] do
                local r, g, b = game.color(x, y, z)
                if r ~= nil then
                    clip[#clip + 1] = {x - b0[1], y - b0[2], z - b1[3], r, g, b}
                end
            end
        end
    end
    s.clipboard = clip
    return string.format("copied %d blocks", #clip)
end)

game.command("paste", opts("Puts the copied blocks on the block you look at"), function(p)
    if p == nil then
        return "only a player can paste"
    end
    local s = of(p)
    if s.clipboard == nil or #s.clipboard == 0 then
        return "nothing copied: /copy first"
    end
    local x0, y0, z0 = target(p)
    z0 = z0 - 1 -- on top of the block looked at, not in it
    local cells = {}
    for i = #s.clipboard, 1, -1 do -- copied top first: pasted bottom first
        local c = s.clipboard[i]
        cells[#cells + 1] = {x0 + c[1], y0 + c[2], z0 + c[3], c[4], c[5], c[6]}
    end
    return start(p, cells, "paste")
end)

game.command("undo", opts("Puts back what your last change changed"), function(p)
    if p == nil then
        return "only a player has changes"
    end
    local s = of(p)
    if s.undo == nil or #s.undo == 0 then
        return "nothing to undo"
    end
    local cells = {}
    for i = #s.undo, 1, -1 do
        cells[#cells + 1] = s.undo[i]
    end
    s.undo = nil
    return start(p, cells, "undo")
end)

function plugin.on_leave(p)
    state[p.id] = nil
end

return plugin
