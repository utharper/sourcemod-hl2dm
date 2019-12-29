XMS (eXtended Match System) is a set of SourceMod plugins for competitive HL2DM servers, originally inspired by the *PMS* pack from HL2DM.net but created from scratch with many more features and game fixes, and support for additional gamemodes. You can easily define your own custom gamemodes, but the default config contains **dm**, **tdm**, **jm** (Jump Maps) and **lgdm** (Low-Grav).

XMS is designed to be modular, such that you could (mostly) run any combination of these plugins if you really wanted to - only `xms.smx` is required - but this is intended to be a complete match server package. `xms_exfov.smx` is standalone and does not require XMS to be running on your server.

You can currently see this system in use on:
- Australian Deathmatch (server.hl2dm.pro:27015)
- West Coast Deathmatch (server-us.hl2dm.pro:27015)

Discussion and help is available in the HL2DM Community Discord Channel: https://discord.gg/gT4cZ7v

How to install
---
If you're running on a Linux VPS, you can use my quick-and-dirty script to automatically deploy a 100 tick HL2DM server, grab the latest XMS pack, and set up auto-update and auto-restart (Debian/Ubuntu, run as root):

- `wget -O - https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/deploy_server.sh | bash`

Otherwise, install the HL2DM server [yourself](https://developer.valvesoftware.com/wiki/SteamCMD) and then extract the files from the latest **[XMS pack](https://github.com/jackharpr/hl2dm-xms/releases)** (make sure to overwrite existing files). You can then proceed to configuration.

If you set up your server manually (instead of using the XMS pack) you will of course need to install Metamod/SourceMod, along with the [**steamtools**](https://builds.limetech.io/?p=steamtools) and [**VPhysics**](https://builds.limetech.io/?project=vphysics) extensions. If you want to automatically zip and upload your match demos to an FTP server, you also need [**System2**](https://forums.alliedmods.net/showthread.php?t=146019). You should also get the [**Updater**](https://forums.alliedmods.net/showthread.php?p=1570806) plugin to keep XMS updated. Additional requirements apply for xms_discord (see below).

Configuration
---
Everything should work out of the box, but you'll first want to edit `cfg/server.cfg` and `cfg/server_match.cfg` to set your desired hostname, sv_region, etc.

After verifying that things are working, you should go through `addons/sourcemod/configs/xms.cfg` to configure XMS to your desired settings. Everything is explained in there. You'll need to reload xms (`sm plugins reload xms`) for changes to the .cfg to take affect; this will also restart the current map.

Here is an incomplete list of the features of each plugin:

Base plugin (xms.smx)
---
*Requires [SteamTools](https://builds.limetech.io/?p=steamtools)*
- Natives/forwards for other plugins
- Reverts to the default gamemode and default mapcycle when the server is empty (handy to attract newbies who use the basic server browser and will usually connect to default map servers)
- Sets the game description (Game tab in server browser) to current mode.

Client commands (xms_commands.smx)
---
**!run** `<gamemode>` `<map>`

Change to the specified map and/or gamemode. eg: `!run tdm`, `!run tdm lockdown`, `!run lockdown`.

Only one argument is required. The arguments can be in either order (*!run dm lockdown* **or** *!run lockdown dm*)
For the map query, first a list of predefined map abbreviations (in xms.cfg) is checked, eg `ldr6` corresponds to`dm_lockdown_r6`. If an exact match is not found there, the server maps folder is searched directly. If multiple maps match the search term, it will output a list to the player and take no action. This may seem over-complicated but is intended to be intuitive to players, instead of having to memorize abbreviations.

![sm_run](https://i.imgur.com/TJzFJ85.png)

**!start**

Begins a countdown to start a competitive match. Teams are locked during a match: players can't switch teams, and spectators can't join. In the default configuration, matches are only available on the `dm` and `tdm` modes.

**!stop**

Brings a match to a premature end. The match demo will be discarded.

**!list**

Displays a list of available maps on the server. By default, it will show maps from the current mapcycle (which is gamemode-specific).
This can be overriden to show maps for another gamemode, eg *!list jm* will show all maps from mapcycle_jm.txt
Players can also use *!list all* to display every map on the server.

**!coinflip**

Randomly returns heads or tails. Useful for determining who gets first map choice, etc.

**!profile** `<player name>`

Opens the player's Steam profile in a MOTD window.

**!forcespec** `<player name>`

*Requires Generic Admin*

Moves the specified player to spectators. Useful if someone is AFK and blocking a match. Spectators will stay in spec between map-changes, until they manually change teams, so you'll only need to use this command once.

### Other Features
- Unregistered backwards compatibility for PMS commands (cm, tp, cf) and the #.# command trigger
- Overrides basetriggers to fix the output of 'say timeleft' (which doesn't reset with mp_restartgame). Also intercepts the 'nextmap' and 'ff' triggers for style consistency.
- Converts **all** commands and arguments to lower-case, removing case sensitivity which causes frustration to players and is a poor design choice IMO. This could theoretically break other plugins if they expect uppercase arguments.

Client menu (xms_menu.smx)
---
*Requires xms_commands*
Provides a simple menu which automatically opens and stays open. This allows players to quickly press ESC and access most functionality without having to type in commands:

![menu](https://i.imgur.com/sJyEiJd.png)

Players need to set `cl_showpluginmessages 1` for the menu to be visible (in common with all Sourcemod menus in HL2DM, after a game update a few years ago). If they have not set this, a warning message will be displayed in their chat advising them to do so.

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
- Removes the (pointless) alternative-third-person spec mode, now there is only one 3rd person view.
- Fixes the 1 health bug when spectating players (now the health value updates as expected)
- Fixes prop gravity (without this fix, props retain the gravity from the previous map)
- Fixes mp_falldamage not having any affect
- Fixes messages not being sent when the game is paused.
- Prevents useless game spam, such as "Please wait x seconds before switching", "You are on Team x"  and convar change messages.
- Styles player connect, disconnect and name change messages.
- Includes [shotgun altfire fix](https://forums.alliedmods.net/showthread.php?p=2362625) by **V952**
- Includes [hands animation fix](https://forums.alliedmods.net/showthread.php?p=2404259) by **toizy**
- Includes [env_sprite fix](https://forums.alliedmods.net/showthread.php?p=2587139) (grenade exploit fix) by **sidezz**

Sounds (xms_sounds.smx)
---
- Plays a short sound on player connect/disconnect (except during a match)
- Plays one of several HL2/HL1 music tracks during mp_chattime, fading out as the map changes.
- Fully sv_pure compatible (original game sounds only)

HUD (xms_hud.smx)
---
- Time remaining clock at the top of the screen.
- HUD showing player's pressed keys, velocity and angle, health and suit values. Adapted from the original hudkeys plugin by **Adrianilloo**. Shown when spectating a player, and to players if "SelfKeys" gamemode variable is enabled.

Pause (xms_pause.smx)
---
- Allows players to pause the game (only during a match)
- Only people in the match can pause the game (not spectators). The game will be paused for up to 60 seconds. Only the person who paused the game can unpause it early.
- After 60 seconds the game will automatically unpause. It can be paused again, but the soft limit is to discourage people taking too long and wasting other players' time.

SourceTV Controller (xms_sourcetv.smx)
---
*Optionally requires [System2](https://forums.alliedmods.net/showthread.php?t=146019) for compress/upload functionality*
- Handles tv_record / tv_stoprecord for matches
- Automatically deletes demos of prematurely ended matches (!stop)
- Optionally compresses and uploads completed demos to a configured location, via FTP
- Broadcasts the URL of the demo file after upload

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

A link to download the demo will be shown if you have enabled demo uploading in the config, and set your URL in there.

![Discord Match Report](https://i.imgur.com/ngaHGzn.png)

Extended FOV (xms_exfov.smx)
---
**This plugin is standalone once compiled, you don't need to be running XMS.**

Removes the field-of-view limit (by default the game limits it to 90), allowing players to set it to any value between 90 and 120. Players can set their FOV by typing `fov <value>` in console, or via the **!fov** command.

The FOV temporarily (and seamlessly) resets to 90 when players use zoom functions (such as toggle_zoom and crossbow secondary attack), to overcome glitchy behaviour as seen in previous FOV plugins.

Future improvements
---
Likely there are some bugs, which I will try to fix as I become aware of them.

Some ideas to extend functionality further:
- Additional gamemodes e.g. arcade, CTF, Last Man Standing, 357 instagib
- Automated events system which will lock the server to particular settings during a specified time period (for example, Low Grav night on Wednesdays)
- Custom stats system and match reporting to a database, with a web interface similar to VirtuousGamers.eu
