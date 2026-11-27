# Scripts that are not ported

These come from the collections credited in [CREDITS.md](../CREDITS.md):
ace-of-spades-scripts, pyspades-userscripts, PySnip and piqueserver-extras.
They are not ported because they do not apply to Nextgen Spades, or
cannot. Everything else is being ported, in batches.

| Scripts | Why |
| --- | --- |
| DiscordReport, discord, discord588, discordhelper, IP, geoip, localizer, googletrans, translate, stats, AutoUpdater, coins | They talk to outside services (Discord, IRC, geoip, translators, stats sites, update servers). Plugins have no network access. |
| detectclient, osexclusive | Detecting the client or the OS: there is one client. |
| aimblock, aimbot2, boundarycheck, hacktools, antispawnkill's cheat checks | Anti-cheat for hacked 0.75 clients. The server checks shots, positions and rates itself. |
| bugfix, bugfixmerge, fbpatch, fbpatch2, overblockfix, bugblock, adjustloading, slowmapload12, mapsize | Fixes for 0.75 / pyspades bugs that the 1.0 protocol does not have. |
| avx, csv, utils, networkdict, buildbox, server, run, map_extensions, Mapextension+ | Libraries, or pyspades' own core. Map extensions are built into the server. |
| memcheck, reloadconfig, passreload, silent, togglealias, defaultcommands, commandhelp, autologin, autologin6, autologin6nm, alternatelogin, whois | Python internals or login systems; the server has its own. |
| basicbot, basicbot1, ABBS_23, NRHMG, bot_totugeki10, aceofshazbot | Fake clients posing as bots. The server has real bots. |
| grownade, thanksgiving_turkey_tents, bighead | They need kv6 models the client does not have. |
