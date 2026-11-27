# Plugin API

This is the contract between a plugin and the Nextgen Spades server.

## The file

- A plugin is one file, `Resources/plugins/<name>.lua`. The name may use
  only `a-z`, `0-9`, `_` and `-`.
- The file runs once each time a map starts. It must return a table; the
  functions in that table named `on_*` are its events. Its variables start
  over at every map; what must last goes in `game.store`.
- Each plugin has its own Lua state, so plugins never share variables.
- The sandbox gives `base`, `table`, `string` and `math`. There is no `io`,
  `os`, `require` or `load`.
- A call that runs too long (an endless loop) is stopped. That counts as an
  error, and an error turns off that plugin alone (`EVT plugin action=error`).
- `config` is the plugin's `[plugins.<name>]` table from `config.toml`, or
  empty when there is none.

A game mode is a plugin whose table has `mode = true`, played with
`--gamemode <name>`. It may also set these fields:

- `wire = "ctf" | "arena"`: how clients draw the mode;
- `rules = "ctf"`: play over capture the flag's rules (intels, tents, the
  bots' CTF roles).

## Profiles: the 1.0 server and the 0.75 server

One server program runs as one of two profiles: `"10"` (protocol 1.0, the
default) or `"075"` (`--profile 075`: the classic 0.75 game for unmodified
0.75 clients, with no classes, perks, squads or next gen modes). A plugin
says which ones it is written for, **as the first line of its file**:

```lua
game.supported_profiles("10")        -- only the 1.0 server
game.supported_profiles("10", "075") -- both
game.supported_profiles("075")       -- only the 0.75 server
```

- When the running profile is not listed, the call stops the file right
  there (nothing after it runs) and the server does not load the plugin:
  `EVT plugin action=refused name=<name> why=profile from=script`. The map
  and the other plugins are not affected. Code above the call has already
  run, so put it first. Catching it with `pcall` does not help: the plugin
  is refused all the same.
- It is taken only while the file runs (from an event it is an error), and
  an unknown profile name is an error. `"1.0"` and `"0.75"` are accepted too.
- A plugin that says nothing is loaded in every profile. The 1.0 only calls
  it makes on the 0.75 server are refused (below), never silently ignored.

The server's owner may also keep a plugin out of a profile, in that
profile's config file (`config.toml` for 1.0, `config-075.toml` for 0.75):

```toml
[plugins.airstrike]
profiles = ["10"]   # not on the 0.75 server
```

That is checked before the file runs (`from=config` in the EVT line). Both
rules apply: the plugin must pass the config's list and its own.

**1.0 only** (marked so below): the classes (`game.classes`, `game.class`,
`game.set_class`, `p:set_class`, the `class` field, the `on_class` event),
the perks (`p:set_jetpack`), the squads (`p:set_squad`), and `game.set_mode`
to a mode the 0.75 profile does not have (it has only `ctf` and `babel`;
`game.next_map` is refused too should the running mode be another one). On
the 0.75 server a query among them returns `nil` and the reason, an action
`false` and the reason (`"profile: protocol 1.0 only, ..."`), `p.class` is
nil and `on_class` is never called. Each is logged once a map:
`EVT plugin action=refused name=<name> why=profile what=game.set_class`.

## Events

Every plugin is asked, in the order of `load`. A mode is asked last.

- Returning `false` refuses the action. The later plugins are not asked,
  and an `EVT plugin_refused` line is logged.
- Returning a value replaces the original for the later plugins and for
  the server. The arrows below show which events take a value.

The arguments `p`, `attacker`, `victim` and `killer` are player tables
(see Players below).

| Event | When | Return |
| --- | --- | --- |
| `on_init()` | the map has started | |
| `on_tick()` | 10 times a second | |
| `on_player_tick(p)` | once a second for each player in the game | |
| `on_join(p, team)` | p joins a team; team is 1, 2, or 0 for spectators | a team number, or false to keep p a spectator |
| `on_team(p, team)` | p asks to change team | false refuses |
| `on_leave(p)` | p disconnects | |
| `on_spawn(p)` | p spawned | |
| `on_spawn_point(p)` | where should p spawn? | x, y, z, or nothing for the usual spot |
| `allows_respawn(p)` | may dead p respawn now? | false keeps p waiting |
| `on_hit(attacker, victim, kind)` | a bullet or a spade hits a player; kind: 0 torso, 1 head, 2 arms, 3 legs, 4 melee | false: no damage |
| `on_damage(attacker, victim, amount, reason)` | any damage: guns, grenades, falls | a new amount, or false |
| `on_kill(killer, victim, reason)` | a death; killer may be nil; reason: 0 body, 1 head, 2 melee, 3 grenade, 4 fall, 5 team change, 6 weapon change | |
| `on_build(p, x, y, z)` | p places a block (also once per cell of a block line) | false refuses |
| `on_destroy(p, x, y, z, kind)` | a block is broken; kind is "spade", "dig" (three blocks), "gun" or "grenade" | false refuses |
| `on_chat(p, text, team_only)` | a chat line, not a /command (see Commands) | new text, or false to drop it |
| `on_tool(p, tool)` | p changes tool: 0 spade, 1 block, 2 gun, 3 grenade | false refuses |
| `on_weapon(p, weapon)` | p changes weapon: 0 rifle, 1 SMG, 2 shotgun | false refuses |
| `on_class(p, name, by)` | **1.0 only.** next gen CTF: p picks a class ("commando", "rocketeer", "marksman", "miner"); by is "client", "join" or "bot" | false refuses |
| `on_grenade(p)` | p throws a grenade | false refuses |
| `on_explode(p, x, y, z)` | p's grenade explodes | |
| `on_reload(p)` | p reloads | |
| `on_intel(p, action)` | action is "pickup", "capture" or "drop" | |
| `on_login(p, role)` | p gave /login the right password for "trusted", "guard", "mod", "admin" or "manager" (p already has the role while asked) | false refuses the login (a second factor, see totp) |
| `on_message(from, topic, data)` | another plugin called `game.send(topic, data)`; `from` is its name | |
| `on_bot_think(bot)` | every think of every bot, 5 a second (see Bots) | a goal table, or nil for the mode's own |
| `on_bot_arrived(bot, name)` | a bot reached the goal this plugin gave it (once per goal) | |
| `on_bot_stuck(bot, why)` | a bot made no progress toward its goal for a while; why is `"no_progress"` | |
| `on_bot_team_tick(team, bots)` | once a second for each team (1, 2), with its bots as a list | |

## Players

A player table is a snapshot taken when it was handed out. To read a player
again later, call `game.player(id)`.

**Fields:**
- `id`, `name`, `team` (1, 2, 0), `alive`, `hp`, `kills`, `deaths`, `bot`;
- `tool`, `weapon`, `blocks`, `grenades`, `intel` (carries one);
- `ip`: its address as text (people only; bots have none);
- `class`: its class's name in the next gen CTF (nil in other modes and on
  the 0.75 server; **1.0 only**);
- `assists`, `score`, `captures`, `shots`, `hits`, `blocks_placed`;
- `squad`, `reloading`, `crouching`, `sprinting`, `airborne`, `wade`, `jetpack`;
- `goal`, `target`: bots only, the name of the goal it follows and the id of
  the enemy it fights (nil when none);
- `x`, `y`, `z` (see Coordinates below);
- `ox`, `oy`, `oz`: where the player looks, as a unit vector.

**Methods:**

| Method | Does |
| --- | --- |
| `p:message(text)` | a line only p reads |
| `p:set_hp(n)` | set health (0 or less kills) |
| `p:damage(n, by)` | hurt p through the normal path (hit marks, kill credit to `by`) |
| `p:kill()` | kill p |
| `p:teleport(x, y, z)` | move p, its own client included |
| `p:restock()` | full health, blocks, grenades and ammo |
| `p:fog(r, g, b)` | p's sky colour only (0..255) |
| `p:drop_crate(kind)` | a supply crate, `kind` `"ammo"` or `"health"`, falls from the sky onto p (a reward). The first player at it who needs it takes it: ammo is the tent's refill, health goes to 100; a full player leaves it for a mate. It goes after 2 minutes on the ground. true when it falls; false with 16 crates out or no ground there. Protocol 1.0 only (nil and the reason on 0.75) |
| `p:sees(q)` | a clear line from p's eye to q's chest (the bots' own sight test) |
| `p:has_role(role)` | logged in as `role` or higher: "trusted", "guard", "mod", "admin", "manager" |
| `p:kick(reason)` | disconnect p; everyone is told (not bots) |
| `p:set_class(name)` | **1.0 only.** next gen CTF: pick that class for p (a living p respawns with it); false when refused |
| `p:set_team(0|1|2)` | spectator, blue or red; the mode's team rules still apply |
| `p:set_tool(0..3)` | spade, block, gun or grenade; the mode's limits still apply |
| `p:set_weapon(0|1|2)` | rifle, SMG or shotgun; the usual clip is refilled |
| `p:set_ammo(clip, reserve)` | set the current and reserve ammunition |
| `p:set_blocks(n)`, `p:set_grenades(n)` | set the inventory (0..255) |
| `p:set_score(n)`, `p:set_kills(n)`, `p:set_deaths(n)`, `p:set_assists(n)` | personal scoreboard columns |
| `p:set_squad(n)` | **1.0 only.** 0 alone, 1..16; the same rules as the client's squad command |
| `p:set_jetpack(true|false)` | **1.0 only.** grant or remove the jetpack for this life |

## game

| Function | Does |
| --- | --- |
| `game.players()` | every player, a list |
| `game.player(id)` | a player, or nil |
| `game.find(name)` | the player with that name, or the only one whose name starts with it |
| `game.notice(text[, team])` | a line every player (or one team) reads |
| `game.fog(r, g, b)`, `game.get_fog()` | everyone's sky colour |
| `game.drop_crate(x, y, kind)` | a supply crate (`"ammo"` or `"health"`) falls onto the column x, y (map coordinates; the nearest dry ground), as `p:drop_crate` |
| `game.score(team)`, `game.set_score(team, n)`, `game.score_limit()` | the scores |
| `game.set_score_limit(n)`, `game.set_capture_limit(n)` | the score the match ends at (1..255) |
| `game.end_match(team)` | the same as `game.win(team)` |
| `game.team_name(team, name)`, `game.team_color(team, r, g, b)` | the two team labels and colours |
| `game.next_map()`, `game.set_map(name)`, `game.set_mode(name)` | queued map/mode changes (see Dangerous calls); on the 0.75 server a mode other than `ctf` or `babel` is 1.0 only |
| `game.run_command(text)` | one console command from the owner's allow-list (see Dangerous calls) |
| `game.win(team)` | that team wins; the next map starts |
| `game.time()` | the game clock in seconds |
| `game.unix_time()` | the machine's clock: whole seconds since 1970 (a test may run the game clock faster, never this one) |
| `game.later(seconds, fn)` | call fn later; at most 64 pending per plugin |
| `game.log(text)` | an `EVT plugin action=log` line |
| `game.map_size()` | x, y, z |
| `game.cell(x, y, z)` | true when the block is solid |
| `game.color(x, y, z)` | the block's r, g, b, or nothing when it is air |
| `game.set_block(x, y, z, r, g, b)` | put a block (see Changing the map) |
| `game.clear_block(x, y, z)` | take a block away; what then hangs on nothing falls (see Changing the map) |
| `game.ground(x, y)` | the column's top block (its smallest z) |
| `game.spawn(team)` | the middle of a team's spawn area: x, y |
| `game.objective(x, y, radius)` | modes only: bots go there and hold it; with no arguments they hunt again |
| `game.set_intel_spot(team, x, y)`, `game.set_tent_spot(team, x, y)` | modes with `rules = "ctf"`: where a team's intel and tent stand |
| `game.classes()` | **1.0 only.** next gen CTF: every class's figures, a list (Commando, Rocketeer, Marksman, Miner) |
| `game.class(name)` | **1.0 only.** one class's figures (by name or number 0..3), or nil |
| `game.set_class(name, figures)` | **1.0 only.** change a class's figures for this map (see Classes); true, or false and the first key refused |
| `game.ban(p, minutes, reason)` | ban p's address (0 minutes: for good), in the server's ban list |
| `game.server_info()` | `{name, map, mode, players, max_players, port}` |
| `game.json_encode(value)` | a string of JSON; a table with keys 1..n is an array, any other an object |
| `game.json_decode(text)` | the value, or nil and the error |
| `game.url_encode(text)` | for a query string |
| `game.command(name, [options], fn)` | a chat command typed with `/` (see Commands) |
| `game.store`, `game.store_save()` | a table kept across maps and restarts (see Keeping data) |
| `game.send(topic, data)` | every other plugin's `on_message(from, topic, data)` at the next tick; `data` is plain data (it crosses as JSON) |

## Bots

Bots are server-side players. A plugin can tell them what to do: it
decides, and the server does the heavy work (finding the way, seeing,
aiming, fighting, digging and building). A plugin never walks a path or
casts rays in Lua: that would cost ten to thirty times what the server's C
does.

`on_bot_think(bot)` is asked at every think of every bot (five a second),
before the game mode. It returns a goal table, or nil to let the mode decide.
The first plugin that returns a table wins. Every field is optional:

| Field | Meaning |
| --- | --- |
| `name` | the goal's name, for the logs and `on_bot_arrived` (default `"plugin"`) |
| `x`, `y` | where to go (map coordinates; default: where the bot stands) |
| `z` | the floor cell there (its top block, `game.ground(x, y)`); 0 or none: unknown |
| `exact` | true: that very cell, not just near it |
| `hold` | stop this close and watch |
| `watch` | where to look while holding: a point `{x =, y =}` or a player table |
| `role` | `"attack"` (default), `"defend"`, `"infiltrate"`, `"cover"`, `"rush"`: the way it fights, and its gun when the mode has no classes |
| `intent` | what the goal is for, a word or a list of words (below) |
| `rush` | true: run there, ignoring fights |
| `assault` | true: fight in the open, no walls, no ducking |
| `walk_only` | true: on foot, no digging and no sneaking |
| `keep_terrain` | true: not even the spade to get out of a jam |
| `climb` | 1: build a pillar up to floor `z` in the goal's column; 2: dig down to it |
| `work` | `{x =, y =, z =, dig = bool, color = 0xRRGGBB}`: within reach, put a block there (or spade it with `dig`) |
| `camp` | 1: a camper (holds a spot behind a wall), 2: the overwatch (a high spot that sees `home`) |
| `home` | `{x =, y =, z =}`: what the team protects; defenders post by it and go for enemies near it first |
| `guard` | `{x =, y =}`: something else to defend; enemies there come first |

| Intent | The bot |
| --- | --- |
| `"take"` | is going to take the objective: close to it, it stops for no fight |
| `"push"` | is an attacker on its way: an enemy farther than 30 blocks does not stop it |
| `"squad"` | is on its squad's lane: it only takes on enemies within 60 |
| `"with"` | keeps up with someone (a leader, a carrier): it shoots on the move |
| `"post"` | holds a post: it fights from it like a camper and never steps aside |
| `"home"` | works at its own base: its way there digs nothing |
| `"guard"` | is the defender at its post by `home` |
| `"chase"` | is after the enemy carrying its team's objective |
| `"brief"` | listens to the team's plan: it holds still |
| `"plant"` | takes an explosive to where it goes |
| `"cover"` | covers a mate |

An unknown role or intent is the plugin's error: the plugin is turned off,
like any other error.

```lua
-- every bot of team 1 follows the first admin it finds
function plugin.on_bot_think(bot)
    if bot.team ~= 1 then return nil end
    for _, p in ipairs(game.players()) do
        if not p.bot and p.alive and p:has_role("admin") then
            return {name = "follow-admin", x = p.x, y = p.y, hold = 4, intent = "with",
                    watch = {x = p.x + p.ox * 10, y = p.y + p.oy * 10}}
        end
    end
    return nil
end
```

`on_bot_arrived(bot, name)` comes once a bot reaches the goal's `hold`
(1.5 blocks at least). A goal that follows someone counts as new only when
its destination jumps far (twice the reach). `on_bot_team_tick(team, bots)`
comes once a second: the place to hand out jobs ("the two nearest defend")
that each `on_bot_think` then reads.

What it costs, measured with 120 bots: 3 to 7 microseconds a call, under
0.15 ms of a 16.7 ms tick. Keep `on_bot_think` short. Work out what the whole
team needs once a second in `on_bot_team_tick`, not five times a second
for every bot.

[examples/bot_escort.lua](../examples/bot_escort.lua) is a whole game mode
on this API: a VIP escort.

## Commands

`game.command(name, [options], fn)` adds a chat command typed with `/`,
like the server's own (`/kick`, `/help`). Call it when the file runs, at
every map:

```lua
game.command("hello", {help = "Says hello"}, function(p, args, line)
    return "hello " .. (p and p.name or "console")
end)

game.command("wipe", {role = "admin", help = "Clears the scores"}, function(p)
    game.set_score(1, 0)
    game.set_score(2, 0)
end)
```

- `name`: `a-z`, `0-9`, `_` and `-`, 1 to 30 characters, with or without
  the `/`. Players may type it in any case.
- `options.role`: who may use it, that role or a higher one ("trusted",
  "guard", "mod", "admin", "manager"); none means everyone. The server
  checks it: `fn` is never called for anyone else. The console may use any
  command.
- `options.help`: its line in `/help`, shown only to those who may use it.
- `fn(p, args, line)`: `p` is the player, or nil from the console; `args`
  the words after the name (`/hello a b` gives `{"a", "b"}`); `line` the
  rest as typed. A string it returns is sent back to whoever typed it.
- The server's commands come first: a name the server or another plugin
  already has is refused, and `game.command` returns false
  (`EVT plugin action=command_refused why=taken`). It returns true when the
  command is added.
- At most 16 commands a plugin.

Remember that the game is played with a gamepad: a command is for admins
and tests, never something a player needs to play.

## Keeping data: game.store

`game.store` is a table that outlives the map and the server's restarts:
everything else in a plugin starts over at every map.

```lua
game.store.visits = (game.store.visits or 0) + 1

function plugin.on_join(p)
    game.store.seen = game.store.seen or {}
    game.store.seen[p.name] = true
    game.store_save()
end
```

- It is read when the plugin loads, before its file runs.
- It is written when the map ends, when the server stops, and on the next
  tick after `game.store_save()`. Call `game.store_save()` after a change
  that must survive a crash.
- It holds what JSON holds: tables, strings, numbers and booleans. A
  function or a player in it stops the save (`EVT plugin
  action=store_refused why=encode`). Keep player names or ids, not players.
- At most 1 MB; past that the save is refused (`why=size`).
- On disk it is `Resources/plugins/data/<name>.json`, one file a plugin;
  a plugin sees only its own. The server's owner may read or edit it while
  the server is off. A file that is not a JSON object is moved to
  `<name>.json.bad` and the store starts empty.
- `game.store = {}` replaces it all.

## Changing the map

`game.set_block` and `game.clear_block` change the map for everyone, like a
player's build and dig, without spending anyone's blocks. Each returns
true, or false and why:

- `"outside"`: out of the map, or at z 62 or 63 (the water layers);
- `"protected"`: a cell the mode or the map keeps (Arena's walls, a
  protected base);
- `"rate"`: the plugin changed enough this tick. A plugin may set 4096
  blocks or clear 1024 a tenth of a second; past that, try the rest on the
  next `on_tick` (sel does).

Clearing a cell that is air already, or setting one, returns true and
costs nothing extra.

## Dangerous calls

`game.set_mode`, `game.set_map`, `game.next_map` and `game.run_command` are
**opt-in** in the server's config:

```toml
[plugins]
allow_map_change = false
allow_commands = []       # names without the slash, e.g. ["say", "addbot"]
```

They are queued and applied at the end of the plugin tick. This is not a
convenience: a map reset calls `plugins_map_start`, which closes every Lua
state, so doing it inside a Lua call would free the state that is still
running. `game.run_command` never accepts `/shutdown`, `/login` or `/logout`,
rejects newlines and shell chaining, and runs only the listed commands.
`game.set_map` validates the map name and its files, and refuses paths.
`game.set_mode` validates the mode name; the map's `map_fits` still applies
at the next load. On the 0.75 server (see Profiles) only `ctf` and `babel`
exist: any other mode is refused with `false` and the profile's reason.

`game.set_teams`/one-team FFA, per-player speed, world-cell edits, entities,
squad leaders and persistent storage are not exposed yet.

## Classes

**1.0 only** (see Profiles): the 0.75 server has no classes.

The next gen CTF has four classes. Each is a table of figures; the server
owner sets them in config.toml (`[classes.<name>]`) and a plugin may change
them with `game.set_class` for the map it runs on (every map starts from
config.toml again). Every player's game is told at once: the class screen,
the speed and jump it predicts, its health.

| Key | Range | Means |
| --- | --- | --- |
| `health` | 1..1000 | the most it has (130, 85, 70, 125) |
| `speed` | 0.3..3 | ground speed, times the usual |
| `jump` | 0.1..1.5 | the jump's upward speed (0.36 the usual) |
| `weapon` | "rifle", "smg", "shotgun", "rocket", "revolver" | its gun |
| `secondary` | "none" or a weapon | a second gun it swaps with the first ("revolver": the Commando's) |
| `blocks` | 0..255 | blocks carried |
| `gear` | "grenades", "drill" | the grenade slot |
| `gear_count` | 0..255 | grenades or drill charges |
| `jetpack` | true, false | worn from every spawn |
| `dig` | 1, 3 | the spade's dig: the usual three blocks, or 3x3x3 |
| `perk` | "none", "sentry", "landmine", "dynamite", "revive" | the streak perk |
| `swing` | 0.05..2 | seconds between spade swings (left button) |
| `title`, `blurb` | 31 and 95 bytes | its name and line on the class screen |
| `enabled` | true, false | false: nobody may pick it (the last one on stays on) |

```lua
function plugin.on_init()
    -- a slower, tougher Miner and no Rocketeer on this server
    game.set_class("miner", {health = 160, speed = 0.9})
    game.set_class("rocketeer", {enabled = false})
end
```

## The network

A plugin reaches nothing outside unless the server's owner lists, in its
section of `config.toml`, the hosts it may call:

```toml
[plugins.my_plugin]
allow_hosts = ["api.example.com", "*.example.org"]   # "*" = any host
```

```lua
local ok, err = game.http{
    url = "https://api.example.com/scores",
    method = "POST",                      -- GET by default
    headers = {["Authorization"] = "Bearer " .. config.token},
    json = {player = p.name, kills = 3},  -- or body = "a string"
    timeout = 10,                         -- seconds, 1 to 30
    on_done = function(status, body, err) -- status 0 and err when it failed
        game.log("answered " .. status)
    end,
}
-- ok is nil and err says why when the request was refused (a host not
-- listed, not http(s), too many waiting)
```

- The request runs on a thread of the server's own; `on_done` is called
  on a plugin tick (a tenth of a second) after the answer arrives. The
  game never waits for it.
- http and https only, no redirects (one could lead to a host not
  listed), answers up to 1 MB, 16 requests waiting per plugin.
- Keep secrets (tokens, webhook URLs) in the plugin's `config.toml`
  section, never in the plugin's file.
- An answer that arrives after the map changed is dropped: the plugin was
  loaded again.

## Plugins working together

Each plugin is on its own, so they talk through `game.send` and
`on_message`. One plugin can be the only one that talks to an outside
service, and the others send it what to say:

```lua
-- in any plugin
game.send("announce", {text = killer.name .. " is on a rampage"})

-- in the plugin that talks to the outside service
function plugin.on_message(from, topic, data)
    if topic == "announce" then
        -- post data.text wherever this plugin talks to
    end
end
```

## Coordinates

These are map coordinates.

- `z` grows downwards. `z = 0` is the top of the world, and the water is
  the bottom layer (`z = 63` on a 64-high map).
- A player's `x`, `y`, `z` is the hip. The floor under a standing player
  is about `z + 2.4`; the server spawns players at `floor_z - 2.4`.
