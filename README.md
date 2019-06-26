XMS (eXtended Match System) is a set of SourceMod plugins I made for my competitive HL2DM server, similar to the *PMS* pack from HL2DM.net but created from scratch with many more features and game fixes, and support for additional gamemodes. It is designed to be modular, you can run any combination of these plugins if you wanted to (only `xms.smx` is required). You can easily define your own custom gamemodes, but the default config has **dm**, **tdm**, **jm** (Jump Maps) and **lgdm** (Low-Grav).

You can see these plugins in use on my Sydney Matchserver (server.hl2dm.pro:27015) - discussion and help is available on Discord: https://discord.gg/gT4cZ7v

How to install
--
Download and extract the files to your server. Edit *server.cfg* and *server_match.cfg* (set your desired hostname, sv_region, sv_downloadurl and anything else).

You need to install SourceMod and the [**steamtools**](https://builds.limetech.io/?p=steamtools) and [**VPhysics**](https://builds.limetech.io/?project=vphysics) extensions on your server (additional requirements for xms_discord, see below). Everything is configured via `addons/sourcemod/configs/xms.cfg` - you'll need to reload xms (`sm plugins reload xms`) for changes to the .cfg to take affect. Here are the features of each plugin.

xms.smx
---
*Requires [SteamTools](https://builds.limetech.io/?p=steamtools)*
- Natives/forwards for other plugins
- Reverts to the default gamemode and default mapcycle when the server is empty (handy to attract newbies who use the basic server browser and will usually connect to default map servers)
- Sets the game description (Game tab in server browser) to current mode.

Client commands (xms_commands.smx)
---
**sm_run** `<gamemode>` `<map>`

Change to the specified map and/or gamemode. eg: `sm_run dm`, `sm_run tdm lockdown`, `sm_run lockdown`.

Only one argument is required. The arguments can be in either order (*!run dm lockdown* **or** *!run lockdown dm*)
For the map query, first a list of predefined map abbreviations (in xms.cfg) is checked, eg `ldr6` corresponds to`dm_lockdown_r6`. If an exact match is not found there, the server maps folder is searched directly. If multiple maps match the search term, it will output a list to the player and take no action. This may seem over-complicated but is intended to be intuitive to players, instead of having to memorize abbreviations.

![sm_run](https://i.imgur.com/TJzFJ85.png)

**sm_start**

Begins a countdown to start a competitive match. Teams are locked during a match: players can't switch teams, and spectators can't join. In the default configuration, matches are only available on the `dm` and `tdm` modes.

**sm_stop**

Brings a match to a premature end. The match demo will be discarded.

**sm_list**

Returns a list of all maps on the server (similar to the `listmaps` console command, which shows all maps in the current cycle).

**sm_pause**

Pause/unpause the game.

**sm_coinflip**

Randomly returns heads or tails. Useful for determining who gets first map choice, etc.

**sm_forcespec** `<player name>`

*Requires Generic Admin*

Moves the specified player to spectators. Useful if someone is AFK and blocking a match. Spectators will stay in spec between map-changes, until they manually change teams, so you'll only need to use this command once.

### Other Features
- Unregistered backwards compatibility for PMS commands (cm, tp, cf) and the #.# command trigger
- Overrides basetriggers to fix the output of 'say timeleft' (which doesn't reset with mp_restartgame). Also intercepts the 'nextmap' and 'ff' triggers for style consistency.
- Converts **all** commands and arguments to lower-case, removing case sensitivity which causes frustration to players and is a poor design choice IMO. This could theoretically break other plugins if they expect uppercase arguments.

Game Fixes & Enhancements (xms_fixes.smx)
---
*Requires [VPhysics](https://builds.limetech.io/?project=vphysics)*
- Fixes the game's scoring bugs, and automatically saves/restores player scores if they disconnect and rejoin the game.
- Team locking during a match, including preventing spectators from joining, which removes the need for a password lock on the server. Team values are linked to SteamID's, so players can still rejoin their rightful place in the match after an accidental disconnect.
- Keeps players in their teams between map changes.
- Makes players default to a random rebel model during Deathmatch
- Makes players default to the police model if they are on Team Combine (no more bright white combine models)
- Stops clients from activating the (broken) spectator menu
- Disables spectator sprinting
- Fixes the 1 health bug when spectating players (now the health value updates as expected)
- Fixes prop gravity (without this fix, props retain the gravity from the previous map)
- Fixes mp_falldamage not having any affect
- Includes [shotgun altfire fix](https://forums.alliedmods.net/showthread.php?p=2362625) by **V952**
- Includes [hands animation fix](https://forums.alliedmods.net/showthread.php?p=2404259) by **toizy**
- Includes [env_sprite fix](https://forums.alliedmods.net/showthread.php?p=2587139) (grenade exploit fix) by **sidezz**

Chat Messages (xms_chat.smx)
---
- Sends a welcome message with the server commands and configured ServerURL.
- Fixes messages not being sent when the game is paused.
- Prevents useless game spam, such as "Please wait x seconds before switching", "You are on Team x"  and convar change messages.
- Styles player connect, disconnect and name change messages.

Sounds (xms_sounds.smx)
---
- Plays a short sound on player connect/disconnect (except during a match)
- Plays one of several HL2/HL1 music tracks during mp_chattime, fading out as the map changes.
- Fully sv_pure 2 compatible (game sounds only)

HUD (xms_hud.smx)
---
- Time remaining clock at the top of the screen, similar to *advhl2dmtimeleft.smx*.
- Spectator HUD showing the target's current pressed keys, velocity and angle, health and suit values. Adapted from the original hudkeys plugin by **Adrianilloo**

Pause (xms_pause.smx)
---
- Basically just a rewrite of *advanced_pause.smx*
- Only people in the match can pause the game (not spectators). The game will be paused for up to 60 seconds. Only the person who paused the game can unpause it early.
- After 60 seconds the game will automatically unpause. It can be paused again, but the soft limit is to discourage people taking too long and wasting other players' time.

SourceTV Controller (xms_sourcetv.smx)
---
- Handles tv_record / tv_stoprecord for matches
- Automatically deletes demos of prematurely ended matches (!stop)
- Announces the demo name to players at the end of the match

Gamemode: jm (xms_jm.smx)
---
- Infinite sprint and no player collisions for Jump Maps.

Overtime (xms_overtime.smx)
---
- Sudden death overtime
- Once timelimit is reached, if no player (or team if TDM) has a winning score, the game length is extended by 1 minute. The next player/team to score automatically wins.

Discord Match Reports (xms_discord.smx)
---
*Requires [smjansson](https://forums.alliedmods.net/showthread.php?t=184604), [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556) and [discord_api.smx](https://github.com/Deathknife/sourcemod-discord)*

Simply reports all match results to a Discord server, optionally with a link to download the demo. To set this up you need to be an administrator of the Discord server, go to Server Settings > Webhooks > Create Webhook, choose the channel, copy the link and paste that into "WebhookURL" in the config.

For a link to download the demo to be shown, you need to also set "DemoURL" - and you'll of course need to be syncing demos from the gameserver to a webserver via some method. I recommend using rsync if you have SSH access to both the web and gameserver. If they're running on the same box you could symlink the directories. If you're using a Game Server Provider (ie renting your HL2DM server) you will probably need to contact them to set this up.

![Discord Match Report](https://i.imgur.com/ngaHGzn.png)

Future improvements
---
I'm no longer an active player and not likely to develop this further unless I'm made aware of a bug and/or it finds usage on other people's servers. Some ideas I had:
- Additional gamemodes e.g. arena, CTF, Last Man Standing, 357 instagib
- Custom stats system and match reporting to a database, with a web interface (similar to VirtuousGamers.eu)

Other recommended plugins for your match server
--
- [advhl2movement](https://forums.alliedmods.net/showthread.php?p=1324970)
- [lerptracker](https://forums.alliedmods.net/showthread.php?t=149333) or SMAC to restrict *cl_interp* / other client variables
- HLStatsX / gameME
