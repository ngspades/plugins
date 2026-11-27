-- aliases: remembers the names each address joined with, across maps and
-- restarts, so staff can see who a new name was before.
--
-- Inspired by lsd's alias tracking (totallynotaburner, https://66.135.15.57/lsd);
-- written from scratch for Nexgen Spades.
--
--   /aliases <player>   names joined from that player's address
--   /aliases <address>  names joined from that address
--   /aliases <name>     a name not online: the addresses it used, and
--                       the other names joined from them
--
-- A ban (/ban, game.ban) is by address already, so it covers every alias
-- that address had.
--
-- config.toml:
--   [plugins.aliases]
--   role = "mod"          # who may use /aliases
--   max_addresses = 5000  # the oldest are forgotten past this
--   max_names = 16        # names kept per address

local plugin = {}
local ROLE = config.role or "mod"
local MAX_ADDRESSES = config.max_addresses or 5000
local MAX_NAMES = config.max_names or 16

-- game.store.addresses[ip] = {seen = unix time, names = {[name] = unix time}}
game.store.addresses = game.store.addresses or {}
local addresses = game.store.addresses
local changed = false

local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local function oldest(t, field)
    local key, at
    for k, v in pairs(t) do
        local when = field and v[field] or v
        if at == nil or when < at then
            key, at = k, when
        end
    end
    return key
end

local address_count = count(addresses)

local function remember(p)
    if p.ip == nil then
        return -- a bot
    end
    local now = game.unix_time()
    local entry = addresses[p.ip]
    if entry == nil then
        if address_count >= MAX_ADDRESSES then
            addresses[oldest(addresses, "seen")] = nil
            address_count = address_count - 1
        end
        entry = {names = {}}
        addresses[p.ip] = entry
        address_count = address_count + 1
    end
    entry.seen = now
    if entry.names[p.name] == nil and count(entry.names) >= MAX_NAMES then
        entry.names[oldest(entry.names)] = nil
    end
    entry.names[p.name] = now
    changed = true
end

-- names of one address, the most recent first
local function names_of(ip, skip)
    local entry = addresses[ip]
    if entry == nil then
        return {}
    end
    local list = {}
    for name, at in pairs(entry.names) do
        if name ~= skip then
            list[#list + 1] = {name = name, at = at}
        end
    end
    table.sort(list, function(a, b)
        return a.at > b.at
    end)
    local out = {}
    for i, v in ipairs(list) do
        out[i] = v.name
    end
    return out
end

local function line(title, names)
    if #names == 0 then
        return title .. ": no other name"
    end
    local text = title .. ": " .. table.concat(names, ", ")
    if #text > 200 then
        text = text:sub(1, 197) .. "..."
    end
    return text
end

game.command("aliases", {role = ROLE, help = "Names joined from a player's address. Usage: aliases <player|address|name>"},
    function(p, args, rest)
        if rest == "" then
            return "Usage: /aliases <player|address|name>"
        end
        local online = game.find(rest)
        if online ~= nil and online.ip ~= nil then
            return line(online.name .. " (" .. online.ip .. ")", names_of(online.ip, online.name))
        end
        if addresses[rest] ~= nil then
            return line(rest, names_of(rest))
        end
        -- a name: every address it joined from
        local lower = rest:lower()
        local found = {}
        for ip, entry in pairs(addresses) do
            for name in pairs(entry.names) do
                if name:lower() == lower then
                    for _, other in ipairs(names_of(ip, name)) do
                        found[#found + 1] = other
                    end
                    found[#found + 1] = "(" .. ip .. ")"
                end
            end
        end
        if #found == 0 then
            return "Nobody called " .. rest .. " is remembered"
        end
        return line(rest, found)
    end)

function plugin.on_join(p, team)
    remember(p)
end

-- written once a minute when something changed (the map's end and the
-- shutdown write it anyway)
local function save_later()
    game.later(60, function()
        if changed then
            changed = false
            game.store_save()
        end
        save_later()
    end)
end

function plugin.on_init()
    save_later()
end

return plugin
