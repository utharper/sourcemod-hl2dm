This page hosts my public Sourcemod plugins for [Half-Life 2 Deathmatch](https://store.steampowered.com/app/320/HalfLife_2_Deathmatch/) servers.

These were originally created for Australian Deathmatch (IP: [au.hl2dm.community:27015](https://hl2dm.community/connect/?au.hl2dm.community:27015)), and can be seen in action on there.

For discussion and feedback, join us in the [HL2DM Community](https://hl2dm.community) (#development channel)

* [xFov](#xFov) - Extended field-of-view for players
* [xFix](#xFix) - Fixes various game bugs/exploits/annoyances (previously called hl2dmfix)
* [XMS](#XMS) - eXtended Match System for competitive servers
  * [xms_bots](#xms_bots) - RCBot2 controller for XMS servers
  * [xms_discord](#xms_discord) - Publish match results to discord server(s).
* [gameme_hud](#gameme_hud) - Displays a stats HUD in the scoreboard, using gameME data.
* [Misc](#Misc) - Other potentially useful stuff (work in progress).


# xFov
![FOV demonstration](https://i.imgur.com/8XydE9f.png)

HL2DM restricts player field-of-view to a value of 90, which is not ideal for widescreen monitors and can make the game feel very 'zoomed in' compared to other shooters.
This plugin allows players to set thier FOV to any range of values you permit. In the default configuration it will allow a minimum of 90, and a maximum of 110. 

Players can set their FOV by typing `fov <value>` in console, or via the **!fov** command. Their setting will be remembered between map changes and server reconnects, so they only need to do this once.

The FOV temporarily resets to 90 when players use zoom functions (such as toggle_zoom and crossbow secondary attack), to overcome glitchy behaviour seen in previous implementations.

### Convars
You can configure these in `cfg/sourcemod/plugins.xfov.cfg` after first load.

* `xfov_defaultfov` - Default FOV for new players. 90 by default.
* `xfov_minfov` - Minimum FOV allowed on server. 90 by default.
* `xfov_maxfov` - Maximum FOV allowed on server. 110 by default.

### Download
* [Download zip](https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/xfov.zip)
* [Source](addons/sourcemod/scripting/xfov.sp)


# xFix
**Requires [VPhysics](https://builds.limetech.io/?project=vphysics) extension**

This plugin workarounds some of the issues with the game, such as scoring bugs, and aims to improve the overall player experience without compromising gameplay in any way.
This has not really been developed far but already fixes a few things:

- Remove case sensitivity for commands, and adds compatibility for the old `#.#` command prefix
- Disable team chat if mp_teamplay is 0
- Block annoying game chat spam such as 'Please wait x more seconds before trying to switch' and server cvar messages
- Disable showing the MOTD on connect if motd.txt doesn't exist or is empty
- Disable the spectator bottom menu, as the options are mislabeled and it tends to get stuck in place
- Disable an extra third-person spectator mode which serves no function
- Fix various small spectator bugs
- Fix all of the game's scoring bugs
- Improved save scores (if someone disconnects and rejoins the same round, their score is retained)
- Block an exploit which allows crouched players to have the visibility of a standing player
- (via Vphysics) Fix prop gravity not changing correctly with sv_gravity
- Fix mp_falldamage value not having any effect
- Block the annoying explosion ringing sound
- Includes shotgun altfire lag compensation fix, by **V952**
- Includes Hands animation fix, by **toizy**
- Includes env_sprite exploit fix, by **sidezz**

No configuration is required.

### Download
* [Download](https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/xfix.smx)
* [Source](addons/sourcemod/scripting/xfix.sp)


# XMS
**Requires [SteamTools](https://builds.limetech.io/?p=steamtools) and [VPhysics](https://builds.limetech.io/?project=vphysics) extensions, and xFix**

**XMS** (eXtended Match System) is the most advanced system for competitive HL2DM servers. Commands are backwards compatible with VG servers and the old servermanagement plugin by gavvvr. It also features an easy player menu and is intended to be as simple for players to use as possible.

You can easily define your own custom gamemodes, but the default config contains **dm**, **tdm**, **kb** (killbox low-grav), **jm** (jump maps), **surf** (surf maps), **ctf** (Capture The Flag) and **arcade** (spawn with all weapons).

Everything is configured and explained in `addons\sourcemod\configs\xms.cfg`.

### Menu
XMS provides a simple menu which automatically opens and stays open. This allows players to quickly press ESC and access most functionality without having to type in commands:

![menu](https://i.imgur.com/Qt1PFL0.png)

From this menu players can choose their team, call a vote to change the map/gamemode, start/stop/pause a match, view other player's steam profiles, set their FOV (if xFov is in use), change their player model, etc etc.

Players need to set `cl_showpluginmessages 1` for the menu to be visible (in common with all Sourcemod menus in HL2DM, after a game update a few years ago). If they have not set this, a warning message will be displayed in their chat advising them how to do so.

### Commands
**!run** `<gamemode>`:`<map>`

(Vote to) change to the specified map and/or gamemode. eg: `!run tdm`, `!run tdm:lockdown`, `!run lockdown`.

For the map query, first a list of predefined map abbreviations (in xms.cfg) is checked, eg `ld` corresponds to`dm_lockdown`. If an exact match is not found there, then the server maps folder is searched directly. If multiple maps match the search term, then it will output a list to the player and take no action. This may seem over-complicated but is intended to be intuitive to players, instead of having to memorise a thousand map abbreviations.

You can input multiple modes/maps to create a multiple choice vote. eg: `!run lockdown, halls3, dm:runoff, tdm:runoff, arcade:powerhouse` (one command)

**!runnext** `<gamemode>`:`<map>`  _(or **!next**)_

Exactly the same as !run, but it sets the next map rather than changing immediately.

**!runrandom** _(or **!random**)_

Calls a vote to change to one of a selection of random maps and gamemodes.

**!start**

(Vote to) begin a countdown to start a competitive match. During a match several important game settings are enforced, and a match demo is recorded. Teams are also locked during a match: players can't switch teams, and spectators can't join.

**!cancel**

(Vote to) bring a match to a premature end. The match demo will be discarded.

**!list**

Display a list of available maps in the current gamemode. This can be overriden to show maps for another gamemode:
- `!list jm` will show all maps from the jm mode's mapcycle (mapcycle_jm.txt)
- `!list all` will show every map on the server.

**!coinflip** _(or **!flip**)_

Inherited from the old PMS plugin, this randomly returns heads or tails. Useful for determining who gets first map choice, etc.

**!profile** `<player name>`

Open the given player's Steam profile in a MOTD window.

**!forcespec** `<player name>`

*Requires Generic Admin*. Move the specified player to spectators. Useful if someone is AFK and blocking a match. Spectators will stay in spec between map-changes, until they manually change teams, so you'll only need to use this command on them once.

**!allow** `<player name>`

*Requires Generic Admin*. Allow the specified player to join an ongoing match. Useful to substitute players mid-game, or if one of the players has ragequit.

**!shuffle**

(Vote to) shuffle the teams. Team counts will be balanced, and all players assigned to a random team.

**!invert**

(Vote to) invert the teams. All players will swap from their current team, to the opposite team.

**!vote** `<motion>`

Call a custom yes/no vote. No action is taken on the outcome.

**!votekick** `<player name or id>`

Calls a vote to kick this player.

**!votemute** `<player name or id>`

Calls a vote to mute this player. They will not be able to talk on the mic.

**!pause**

Pause/unpause the game

**!menu**

(Re)open the menu if it was accidentally closed.

**!model**

Shortcut to open the player model submenu

**!hudcolor**

Shortcut to open the hud color submenu

### Some other features (extremely out of date)

- Scripting natives if a gamemode requires custom code
- Configurable voting system for core commands, with vote announce sounds taken from [Xonotic](https://xonotic.org/). 
- Remaining time HUD
- Spectator HUD, showing health/suit, pressed keys, angle and velocity. Original idea and implementation by **Adrian**
- End of game music (various tracks from HL2 and HL1), fading out as the map changes
- Working pause system, with auto-pause if someone disconnects during a match
- Working sudden-death overtime system
- Match information and results get saved to a .txt file alongside the .dem (match demo)
- Locked teams during a match, so the server does not need to be password protected
- Overrides the output of basecommands `timeleft`, `nextmap`, `currentmap` to corrected values
- Force player models to rebels or standard combine (no more gleaming white combine models unless a player chooses it)
- Optionally reverts to default mapcycle when server is empty (attracts random players using the simplified server browser)

### Configuration

After extracting the contents of xms.zip, you will want to edit `cfg/server.cfg` to set your desired hostname, sv_region, etc. Make sure to uncomment the correct rates config (first 2 lines). You should also set your hostname in `cfg/server_match.cfg` and `cfg/server_match_post.cfg`.

Make sure the server works, and then you can proceed to edit `xms.cfg` to your desired values. Everything is explained in there.

Finally, you will need to configure your mapcycles (these are also in the `cfg` folder). Be sure to only include maps that are actually in your maps folder. If maps in the mapcycle do not actually exist on the server, this may cause errors (and will be logged).

You can refer to any `error_` log files in `addons/sourcemod/logs` to help identify problems. If you need help, post in the #development channel on Discord.

### Download
* [Download zip](https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/xms.zip)
* [Source](addons/sourcemod/scripting/xms.sp)


## xms_bots
**Requires XMS and [RCBot2](https://github.com/APGRoboCop/rcbot2)**

RCBot2 controller. Quickly created because I had issues with getting bot quotas to work. In its current state, the plugin will spawn a bot when someone joins an empty server. The bot will play until a second human connects, then it will promptly leave. The idea is to boost activity by keeping someone in the server long enough for others to join.

The bot also has a few little taunts and other messages which you can modify in the translation file. Configured in the `"Bots"` section of `xms.cfg`.

### Download
* Included with XMS download
* [Source](addons/sourcemod/scripting/xms_bots.sp)


## xms_discord
**Requires XMS and the [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556) extension**

![xms_discord output example](https://i.imgur.com/o41mcaN.png)

This plugin was created for the [HL2DM Community Discord server](https://hl2dm.community). It posts the results of all matches, along with links to download the match demo and view the participant's profiles. This is done via webhook(s), you can set up multiple webhooks if you wish.
It will also optionally post player feedback (submitted via the XMS menu) to a seperate webhook/channel.

Everything is configured in the `"Discord"` section of `xms.cfg`.

### Download
* Included with XMS download
* [Source](addons/sourcemod/scripting/xms_discord.sp)


# gameme_hud
**Requires the [gameME plugin](https://github.com/gamemedev/plugin-sourcemod) (gameME is a paid service)**

Displays a HUD (left of the scoreboard) showing your overall rank, kills, deaths, headshots, accuracy, etc.
It only shows when the scoreboard is open (by holding TAB). If you are spectating another player, it will show their stats instead.

![gameme_hud_example](https://i.imgur.com/zww76IL.png)

No configuration is required. If the server is also running XMS, it will use the player's desired `!hudcolor`.

It is not strictly just a HUD, as it also provides hacky natives for other plugins to access the data. This allows for stats to also appear in the XMS menu.

Unfortunately, this plugin causes a LOT of rcon message spam in the server console. See [Cleaning up console spam](#Misc).

### Download
* [Download zip](https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/gameme_hud.zip)
* [Source](addons/sourcemod/scripting/gameme_hud.sp)


# Misc

### Cleaning up console spam.

Certain plugins/maps/actions can trigger a lot of annoying spam in the server console, making it difficult to see what is going on. 

This annoyance can be remedied with the [Cleaner](https://forums.alliedmods.net/showthread.php?p=1789738) extension. See an example cleaner.cfg below:

```
playerinfo
gameme_raw_message
[RCBot]
[RCBOT2]
rcon
Ignoring unreasonable position
"Server" requested "top10"
DataTable
Interpenetrating entities
logaddress_
gameME
changed cvar
ConVarRef room_type
Writing ctf/banned_
```
