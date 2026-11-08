# Shoot and Destroy plugins

Lua plugins for Shoot and Destroy servers. A plugin changes how the whole
server plays: a game mode, a mechanic (airstrikes, rampages, spawn
protection), an admin or a building tool. Several plugins run together,
each able to refuse or change what happens, the way pyspades / PySnip
scripts did. Most plugins here are those scripts ported to Lua, and each
names its original author (see [CREDITS.md](CREDITS.md)).

## Installing a plugin

1. Copy `plugins/<name>.lua` into your server's `Resources/plugins/`.
2. List it in `Resources/config.toml`:

   ```toml
   [plugins]
   load = ["spawn_protect", "rampage"]

   [plugins.rampage]      # the plugin's own settings (see the top of its file)
   kills = 3
   ```

3. Restart the server, or change the map: plugins load again with every map.

A plugin that is a game mode (`tdm10`, `koth10`, `push10`, `arena075`) is
played with `--gamemode <name>` instead of being listed. `tdm10`, `koth10`
and `push10` are for the 1.0 server only (`game.supported_profiles("10")`):
the 0.75 server (`--profile 075`) refuses them. `arena075` is the other way
round: it is a 0.75-only mode (`game.supported_profiles("075")`), a port of
the pyspades/piqueserver arena script that builds and destroys the gates as
ordinary blocks and moves players with teleports, the way the classic
servers did. It is NOT the native 1.0 arena mode (`--gamemode arena` in a
1.0 server, `Arena.c`): no arena HUD, no countdown keys, no refill path.
On 0.75, `arena075` is the arena a 0.75 client and a 1.0 client (which falls
back to 0.75 there) can play together. Every other plugin here runs on both
servers.

## Plugins

| Plugin | What it does | Kind |
| --- | --- | --- |
| [tdm10](plugins/tdm10.lua) | team deathmatch: every kill scores | mode (1.0 only) |
| [koth10](plugins/koth10.lua) | king of the hill | mode (1.0 only) |
| [push10](plugins/push10.lua) | capture the flag across the whole map | mode (1.0 only) |
| [arena075](plugins/arena075.lua) | round-based elimination, last team standing wins the round | mode (0.75 only) |
| [welcome](plugins/welcome.lua) | greets named players | extension |
| [spawn_protect](plugins/spawn_protect.lua) | no damage for a few seconds after spawning | extension |
| [rampage](plugins/rampage.lua) | 3 quick kills: restock, red sky, announced | extension |
| [medkit](plugins/medkit.lua) | one heal per spawn, `/medkit` | extension |
| [votekick](plugins/votekick.lua) | `/votekick`, `/y`, `/cancel` with staff immunity | extension |
| [disco](plugins/disco.lua) | staff `/disco`: the sky cycles through colours | extension |
| [totp](plugins/totp.lua) | a second factor for `/login`: an authenticator app's code (`/otp`) | admin |
| [aliases](plugins/aliases.lua) | `/aliases`: the names each address joined with, kept across restarts | admin |
| [sel](plugins/sel.lua) | building tools: `/pos1`, `/pos2`, `/fill`, `/clear`, `/copy`, `/paste`, `/undo` | building |
| [daycycle](plugins/daycycle.lua) | a slow day/sunset/night sky | extension |

More arrive in batches. The scripts that will not be ported, and why, are in
[docs/not-ported.md](docs/not-ported.md).

## Writing a plugin

Start from [examples/hello.lua](examples/hello.lua). It is short and
commented. [examples/broken_example.lua](examples/broken_example.lua) shows
what happens when a plugin fails: the server logs the error and turns off
only that plugin. [examples/bot_escort.lua](examples/bot_escort.lua) is a game
mode that drives the bots (a VIP escort). Every event and function is listed in
[docs/api.md](docs/api.md).

To see what a plugin did, run the server with `SP_EVENTLOG=1`. Each
`game.log` call is written as an `EVT ... plugin action=log` line. To try
plugins without editing the config, set `SP_PLUGINS=a,b`.

## Licence

GPL-3.0, like the scripts these come from. Each ported plugin keeps its
original author and licence in its header.
