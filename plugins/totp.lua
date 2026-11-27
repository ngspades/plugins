-- totp: a second factor for /login. A role with a secret needs the six
-- digit code of an authenticator app (RFC 6238, the kind Google
-- Authenticator, Aegis or 1Password show) besides its password.
--
-- Inspired by lsd's admin TOTP (totallynotaburner, https://66.135.15.57/lsd);
-- written from scratch for Nexgen Spades.
--
-- How to log in: first `/otp 123456`, then `/login admin <password>`
-- within `window` seconds. A role without a secret logs in as before.
--
-- config.toml:
--   [plugins.totp]
--   window = 60             # seconds a code waits for the /login
--   max_failures = 5        # refused logins before the player is kicked
--   [plugins.totp.secrets]  # base32, as the app's QR code holds it
--   admin = "JBSWY3DPEHPK3PXP"
--   manager = "..."
--
-- Make a secret with any base32 generator (16 or 32 letters A-Z, 2-7) and
-- add it to the app as a time based key. Keep config.toml private: the
-- secret is as good as the password.

local plugin = {}
local WINDOW = config.window or 60
local MAX_FAILURES = config.max_failures or 5
local SECRETS = config.secrets or {}

local pending = {} -- by player id: {code, at}
local failures = {} -- by player id: refused logins

-- SHA-1 and HMAC, on 32 bit words kept in Lua's 64 bit integers

local function rol(x, n)
    return ((x << n) | (x >> (32 - n))) & 0xffffffff
end

local function sha1(msg)
    local h0, h1, h2, h3, h4 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0
    local len = #msg
    msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64) .. string.pack(">I8", len * 8)
    local w = {}
    for chunk = 1, #msg, 64 do
        for i = 0, 15 do
            w[i] = string.unpack(">I4", msg, chunk + i * 4)
        end
        for i = 16, 79 do
            w[i] = rol(w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16], 1)
        end
        local a, b, c, d, e = h0, h1, h2, h3, h4
        for i = 0, 79 do
            local f, k
            if i < 20 then
                f, k = (b & c) | ((~b) & d), 0x5a827999
            elseif i < 40 then
                f, k = b ~ c ~ d, 0x6ed9eba1
            elseif i < 60 then
                f, k = (b & c) | (b & d) | (c & d), 0x8f1bbcdc
            else
                f, k = b ~ c ~ d, 0xca62c1d6
            end
            local t = (rol(a, 5) + (f & 0xffffffff) + e + k + w[i]) & 0xffffffff
            a, b, c, d, e = t, a, rol(b, 30), c, d
        end
        h0 = (h0 + a) & 0xffffffff
        h1 = (h1 + b) & 0xffffffff
        h2 = (h2 + c) & 0xffffffff
        h3 = (h3 + d) & 0xffffffff
        h4 = (h4 + e) & 0xffffffff
    end
    return string.pack(">I4I4I4I4I4", h0, h1, h2, h3, h4)
end

local function xor_with(key, byte)
    return (key:gsub(".", function(c)
        return string.char(c:byte() ~ byte)
    end))
end

local function hmac_sha1(key, msg)
    if #key > 64 then
        key = sha1(key)
    end
    key = key .. string.rep("\0", 64 - #key)
    return sha1(xor_with(key, 0x5c) .. sha1(xor_with(key, 0x36) .. msg))
end

-- base32 (RFC 4648) to bytes; nil when it holds another letter
local function base32(text)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    local bits, value, out = 0, 0, {}
    for c in text:upper():gsub("[%s=]", ""):gmatch(".") do
        local i = alphabet:find(c, 1, true)
        if i == nil then
            return nil
        end
        value = (value << 5) | (i - 1)
        bits = bits + 5
        if bits >= 8 then
            bits = bits - 8
            out[#out + 1] = string.char((value >> bits) & 0xff)
        end
    end
    return table.concat(out)
end

-- the six digits for the 30 second step `step`
local function code_at(key, step)
    local mac = hmac_sha1(key, string.pack(">I8", step))
    local offset = (mac:byte(20) & 0x0f) + 1
    local n = string.unpack(">I4", mac, offset) & 0x7fffffff
    return string.format("%06d", n % 1000000)
end

-- the step the code belongs to, a step either side for a clock off by a
-- little; nil when it is none of them
local function matching_step(key, code)
    local now = game.unix_time() // 30
    for step = now - 1, now + 1 do
        if code_at(key, step) == code then
            return step
        end
    end
    return nil
end

local keys = {}
for role, secret in pairs(SECRETS) do
    keys[role] = base32(secret)
    if keys[role] == nil or #keys[role] < 10 then
        game.log("the secret of " .. role .. " is not base32 of 16 letters or more: that role cannot log in")
        keys[role] = false
    end
end

game.command("otp", {help = "The authenticator's code before /login. Usage: otp <6 digits>"}, function(p, args)
    if p == nil then
        return "the console needs no code"
    end
    local code = args[1] or ""
    if not code:match("^%d%d%d%d%d%d$") then
        return "Usage: /otp <the 6 digits of your authenticator app>"
    end
    pending[p.id] = {code = code, at = game.unix_time()}
    return "Code noted: /login within " .. WINDOW .. " seconds."
end)

local function refuse(p, why)
    failures[p.id] = (failures[p.id] or 0) + 1
    game.log("login of " .. p.name .. " refused: " .. why .. " (" .. failures[p.id] .. ")")
    if failures[p.id] >= MAX_FAILURES then
        p:kick("too many refused logins")
        return false
    end
    p:message(why)
    return false
end

function plugin.on_login(p, role)
    local key = keys[role]
    if key == nil then
        return -- no secret for this role: the password is enough
    end
    if key == false then
        return refuse(p, "This role's code is not set up on the server.")
    end
    local got = pending[p.id]
    pending[p.id] = nil
    if got == nil or game.unix_time() - got.at > WINDOW then
        return refuse(p, "This role needs /otp <code> first, then /login.")
    end
    local step = matching_step(key, got.code)
    -- a code is good once: its step must be later than the last one used
    game.store.last_step = game.store.last_step or {}
    local last = game.store.last_step[role] or 0
    if step == nil or step <= last then
        return refuse(p, "Wrong or used code.")
    end
    game.store.last_step[role] = step
    game.store_save()
    failures[p.id] = nil
    game.log(p.name .. " logged in as " .. role .. " with a code")
end

function plugin.on_leave(p)
    pending[p.id] = nil
    failures[p.id] = nil
end

return plugin
