This page hosts my public Sourcemod plugins for [Half-Life 2 Deathmatch](https://store.steampowered.com/app/320/HalfLife_2_Deathmatch/) servers.

These were originally created for Australian Deathmatch server (IP: ausdm.hl2dm.community:27015), and can be seen in action on there.

For discussion and feedback, join us in the [HL2DM Community](https://hl2dm.community) (#development channel)

* [xfov](#xfov) - Extended field-of-view for players
* [hl2dmfix](#hl2dmfix) - Fixes various game bugs/exploits/annoyances
* [xms](#xms) - eXtended Match System for competitive servers
  * [xms_bots](#xms_bots) - RCBot2 controller for XMS servers
  * [xms_discord](#xms_discord) - Publish match results to discord server(s).
* [gameme_hud](#gameme_hud) - Displays a stats HUD in the scoreboard, using gameME data.


# xfov
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


# hl2dmfix
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
- Fix all of the game's many scoring bugs
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
* [Plugin](https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/hl2dmfix.smx)
* [Source](addons/sourcemod/scripting/hl2dmfix.sp)


# XMS
**Requires [SteamTools](https://builds.limetech.io/?p=steamtools) and [VPhysics](https://builds.limetech.io/?project=vphysics) extensions**

**XMS** (eXtended Match System) is the most advanced system for competitive HL2DM servers. Commands are backwards compatible with VG servers and the old servermanagement plugin by gavvvr. It also features an easy player menu and is intended to be as simple for players to use as possible.

You can easily define your own custom gamemodes, but the default config contains **dm**, **tdm**, **jm** (jump/bhop), **lg** (low grav), **ctf** (Capture The Flag), **arcade** (spawn with all weapons), and **np** (no props).

Everything is configured through `addons\sourcemod\configs\xms.cfg`.

### Menu
XMS provides a simple menu which automatically opens and stays open. This allows players to quickly press ESC and access most functionality without having to type in commands:

![menu](https://i.imgur.com/1g4ZcNH.png)

From this menu players can choose their team, call a vote to change the map/gamemode, start/stop/pause a match, view other player's steam profiles, set their FOV (if xfov is in use), change their player model, etc etc.

Players need to set `cl_showpluginmessages 1` for the menu to be visible (in common with all Sourcemod menus in HL2DM, after a game update a few years ago). If they have not set this, a warning message will be displayed in their chat advising them how to do so.

### Commands
**!run** `<gamemode>`:`<map>`

(Vote to) change to the specified map and/or gamemode. eg: `!run tdm`, `!run tdm:lockdown`, `!run lockdown`.

For the map query, first a list of predefined map abbreviations (in xms.cfg) is checked, eg `ldr6` corresponds to`dm_lockdown_r6`. If an exact match is not found there, then the server maps folder is searched directly. If multiple maps match the search term, then it will output a list to the player and take no action. This may seem over-complicated but is intended to be intuitive to players, instead of having to memorise a thousand map abbreviations.

**!runnext** `<gamemode>`:`<map>`

Same as !run, but sets the next map rather than changing immediately.

**!start**

(Vote to) begin a countdown to start a competitive match. Teams are locked during a match: players can't switch teams, and spectators can't join.

**!cancel**

(Vote to) bring a match to a premature end. The match demo will be discarded.

**!list**

Display a list of available maps and modes on the server.
This can be overriden to show maps for another gamemode, eg *!list jm* will show all maps from mapcycle_jm.txt

**!coinflip**

Randomly returns heads or tails. Useful for determining who gets first map choice, etc.

**!profile** `<player name>`

Open the given player's Steam profile in a MOTD window.

**!forcespec** `<player name>`

*Requires Generic Admin*. Move the specified player to spectators. Useful if someone is AFK and blocking a match. Spectators will stay in spec between map-changes, until they manually change teams, so you'll only need to use this command on them once.

**!allow** `<player name>`

*Requires Generic Admin*. Allow the specified player to join an ongoing match. Useful to substitute players mid-game, or if one of the players has ragequit.

**!vote** `<motion>`

Call a custom yes/no vote. No action is taken on the outcome.

**!pause**

Pause/unpause the game

**!menu**

(Re)open the menu if it was accidentally closed.

**!model**

Shortcut to open the player model submenu

**!hudcolor**

Shortcut to open the hud color submenu

### Other features (not an exhaustive list)

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
- Revert to default mapcycle when server is empty (attracts random players using the simplified server browser)

### Configuration

After extracting the contents of xms.zip, you will want to edit `cfg/server.cfg` to set your desired hostname, sv_region, etc. Make sure to uncomment the correct rates config (first 2 lines). You should also set your hostname in `cfg/server_match.cfg` and `cfg/server_match_post.cfg`.

Make sure the server works, and then you can proceed to edit `xms.cfg` to your desired values. Everything is explained in there.

Finally, you will need to configure your mapcycles (these are also in the `cfg` folder). Be sure to only include maps that are actually in your maps folder. You will also need to order your maps alphabetically, otherwise they will show out of order in the menu. You can just google 'alphabetize list' to find a website that does this for you.

### Download
* [Download zip](https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/xms.zip)
* [Source](addons/sourcemod/scripting/xms.sp)


## xms_bots
**Requires XMS and [RCBot2](https://github.com/rcbotCheeseh/rcbot2)**

RCBot2 controller. Quickly created because I had issues with getting bot quotas to work. In its current state, the plugin will spawn a bot when someone joins an empty server. The bot will play until a second human connects, then it will promptly leave. The idea is to boost activity by keeping someone in the server long enough for others to join.

### Download
* Included with XMS download
* [Source](addons/sourcemod/scripting/xms_bots.sp)


## xms_discord
**Requires XMS and the [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556) extension**

![xms_discord output example](https://i.imgur.com/ZrAMYDy.png)

This plugin was created for the [HL2DM Community Discord server](https://hl2dm.community). It posts the results of all matches, along with links to download the match demo and view the participant's profiles. This is done via webhook(s), you can set up multiple webhooks if you wish.

Everything is configured in `xms.cfg`, in the `"xms_discord"` section.

### Download
* Included with XMS download
* [Source](addons/sourcemod/scripting/xms_discord.sp)


# gameme_hud
**Requires the [gameME plugin](https://github.com/gamemedev/plugin-sourcemod) (gameME is a paid service)**

Displays a HUD showing your overall rank, kills, deaths, headshots, accuracy, etc.
Only shows when the scoreboard is open (by holding TAB). If you are spectating another player, it will show their stats instead.

This was quickly hacked together and causes a LOT of rcon message spam in the server console.

No configuration is required. If the server is also running XMS, it will use the player's desired `!hudcolor`.

![gameme_hud_example](https://i.imgur.com/MZfEHwF.png)

### Download
* [Plugin](https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/gameme_hud.smx)
* [Source](addons/sourcemod/scripting/gameme_hud.sp)
