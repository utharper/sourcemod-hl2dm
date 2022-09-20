#pragma dynamic 2097152
#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION     "1.92"
#define PLUGIN_URL         "www.hl2dm.community"
#define PLUGIN_UPDATE      "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xms.upd"

public Plugin myinfo = {
    name                 = "XMS (eXtended Match System)",
    version              = PLUGIN_VERSION,
    description          = "Multi-gamemode match plugin for competitive HL2DM servers",
    author               = "harper",
    url                  = PLUGIN_URL
};

/**************************************************************
 * INCLUDES
 *************************************************************/
#include <sourcemod>
#include <clientprefs>
#include <steamtools>
#include <smlib>
#include <sdkhooks>
#include <vphysics>
#include <morecolors>
#include <basecomm>

#undef REQUIRE_PLUGIN
#include <updater>
#tryinclude <gameme_hud>

#define REQUIRE_PLUGIN
#include <jhl2dm>
#include <xms>

/**************************************************************
 * GLOBAL VARS
 *************************************************************/
enum struct _gConVar
{
    ConVar      sv_tags;
    ConVar      mp_timelimit;
    ConVar      mp_teamplay;
    ConVar      mp_chattime;
    ConVar      mp_friendlyfire;
    ConVar      sv_pausable;
    ConVar      tv_enable;
    ConVar      sm_nextmap;
    ConVar      mp_restartgame;
}
_gConVar        gConVar;
 
enum struct _gPath
{
    char        sConfig         [PLATFORM_MAX_PATH];// Path to XMS.cfg
    char        sFeedback       [PLATFORM_MAX_PATH];// Path to feedback.log
    char        sDemo           [PLATFORM_MAX_PATH];// Path to demos folder
    
    char        sDemoWeb        [PLATFORM_MAX_PATH];// URL of demos folder on webserver
    char        sDemoWebExt     [8];                // File extension for demos on webserver
}
_gPath          gPath;

enum struct _gCore
{
    KeyValues   kConfig;                            // Raw values of xms.cfg
    
    char        sServerName     [32];               // Name of the server.
    char        sServerMessage  [192];              // Custom message shown in menu
    
    char        sGamemodes      [512];              // Comma-seperated list of available modes
    char        sRetainModes    [512];              // Never revert to default map when changing between these modes
    char        sDefaultMode    [MAX_MODE_LENGTH];  // Default mode
    
    int         iRevertTime;                        // How long after last player disconnects to reset server (seconds)
    char        sEmptyMapcycle  [PLATFORM_MAX_PATH];// Mapcycle override when server is empty
    
    bool        bReady;                             // Plugin is properly initialised ?
    bool        bChangingTags;                      // Plugin is setting sv_tags value ?
    bool        bRanked;                            // gameME stats integration active ?
    
    int         iAdFrequency;                       // How often to display chat advertisements (seconds)
    int         iMapChanges;                        // Total number of map changes since plugin loaded.
    
    char        sRemoveMapPrefix[512];              // Hide these map prefixes (eg dm_) for simplicity and to save text space.
}
_gCore          gCore;

enum struct _gForward
{
    Handle      hGamestateChanged;                  // OnGamestateChanged
    Handle      hMatchStarted;                      // OnMatchStart
    Handle      hMatchEnded;                        // OnMatchEnd
    Handle      hFeedback;                          // OnClientFeedback
}
_gForward       gForward;

enum struct _gSounds
{
    Cookie      cMusic;                             // End of round music cookie (enabled/disabled)
    Cookie      cMisc;                              // General sounds cookie (enabled/disabled)
}
_gSounds        gSounds;

enum struct _gVoting
{
    int         iMinPlayers;                        // Minimum clients to enable manual voting
    int         iMaxTime;                           // Maximum voting period (seconds)
    int         iElapsed;                           // Current vote time elapsed (seconds)
    int         iCooldown;                          // Seconds until a client can call a new vote
    int         iType;                              // Current vote type
    int         iStatus;                            // Current vote status
    int         iOptions;
    bool        bAutomatic;                         // Automatically call a vote after round ?
}
_gVoting gVoting;

enum struct _gHud
{
    bool        bSelfKeys;                          // Show keys HUD to non-spectators ?
    
    Handle      hTime;                              // Timeleft HUD element
    Handle      hKeys;                              // Pressed Keys HUD element
    Handle      hVote;                              // Voting HUD element
    
    Handle      cColors         [3];                // HUD color cookies {r,g,b}
}
_gHud           gHud;

enum struct _gRound
{
    char        sUID            [128];              // Unique game ID from timestamp and map.
    char        sMap            [MAX_MAP_LENGTH];   // Map name
    char        sMode           [MAX_MODE_LENGTH];  // Mode name
    char        sModeDescription[32];               // Full mode name
    
    float       fStartTime;                         // GameTime at start of round
    float       fEndTime;                           // GameTime at end of round (set at chattime)
    
    bool        bTeamplay;                          // Safe teamplay check
    
    int         iState;                             // Current gamestate (see xms.inc)
    bool        bRecording;                         // Is SourceTV recording ?
    
    int         iSpawnHealth;                       // Custom spawn health value (-1 if not defined)
    int         iSpawnArmor;                        // Custom spawn suit value (-1 if not defined)
    
    bool        bDisableProps;                      // Remove props from map ?
    bool        bDisableCollisions;                 // Disable player collisions ?
    bool        bUnlimitedAux;                      // Unlimited player aux (sprint) power ?
    bool        bOvertime;                          // Overtime enabled ?
    
    Handle      hOvertime;                          // Handle for Overtime timer
    
    StringMap   mTeams;                             // Map client SteamIDs to their team
    
    char        sNextMap        [MAX_MAP_LENGTH];   // Next map if chosen
    char        sNextMode       [MAX_MODE_LENGTH];  // Next mode
}
_gRound         gRound;

enum struct _gClient
{
    bool        bReady;                             // Client initalised (post team assignment) ?
    bool        bForceKilled;                       // Player killed by plugin ?
    
    int         iMenuStatus;                        // Client menu status (0 = none, 1 = attempting, 2 = loaded)
    int         iMenuRefresh;                       // Time in seconds until next menu refresh attempt
    StringMap   mMenu;                              // Current values for XMenuDisplay
    
    int         iVote;                              // Choice for the current vote
    int         iVoteTick;                          // Tick when client last called a vote (to comply with gVoting.iCooldown)
}
_gClient        gClient         [MAXPLAYERS + 1];

enum struct _gSpecialClient
{
    int         iAllowed;                           // Client allowed to switch teams during match.
    int         iPauser;                            // Client with ownership of pause state.
}
_gSpecialClient gSpecialClient;

/**************************************************************
 * COMPONENTS
 *************************************************************/
#include "xms/natives_forwards.sp"  // General natives and forwards for extending functionality (custom gamemodes etc)
#include "xms/gamemod.sp"           // Functions to modify game/engine behaviour
#include "xms/sounds.sp"            // Game and custom sound functions
#include "xms/mapmode.sp"           // Map and gamemode functions
#include "xms/round.sp"             // Game round & match functions
#include "xms/clients.sp"           // General client functions
#include "xms/teams.sp"             // Team management functions
#include "xms/voting.sp"            // Voting functions
#include "xms/xconfig.sp"           // Natives and functions to read and parse XMS config.
#include "xms/xmenu.sp"             // Natives and functions to manage custom XMS menu.
#include "xms/legacy_menu.sp"       // Used for voting and !model menu popups (no way found to force-update XMenu)
#include "xms/hud.sp"               // HUD text elements (timeleft, pressed keys, etc)
#include "xms/sourcetv.sp"          // SourceTV management
#include "xms/announcements.sp"     // Plugin announcements and advertisements.
#include "xms/commands.sp"          // Plugin commands and command overrides.

/**************************************************************
 * CORE
 *************************************************************/
public APLRes AskPluginLoad2(Handle hPlugin, bool bLate, char[] sError, int iLen)
{
    CreateNative("GetConfigKeys"   , Native_GetConfigKeys);
    CreateNative("GetConfigString" , Native_GetConfigString);
    CreateNative("GetConfigInt"    , Native_GetConfigInt);
    CreateNative("GetGamestate"    , Native_GetGamestate);
    CreateNative("GetGamemode"     , Native_GetGamemode);
    CreateNative("GetTimeRemaining", Native_GetTimeRemaining);
    CreateNative("GetTimeElapsed"  , Native_GetTimeElapsed);
    CreateNative("GetGameID"       , Native_GetGameID);
    CreateNative("XMenu"           , Native_XMenu);
    CreateNative("XMenuQuick"      , Native_XMenuQuick);
    CreateNative("XMenuBox"        , Native_XMenuBox);

    gForward.hMatchStarted     = CreateGlobalForward("OnMatchStart"      , ET_Event);
    gForward.hMatchEnded       = CreateGlobalForward("OnMatchEnd"        , ET_Event, Param_Cell);
    gForward.hGamestateChanged = CreateGlobalForward("OnGamestateChanged", ET_Event, Param_Cell  , Param_Cell);
    gForward.hFeedback         = CreateGlobalForward("OnClientFeedback"  , ET_Event, Param_String, Param_String, Param_String, Param_String);

    RegPluginLibrary("xms");
    return APLRes_Success;
}

public void OnPluginStart()
{
    CreateConVar("xms_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    
    BuildPath(Path_SM, gPath.sConfig  , PLATFORM_MAX_PATH, "configs/xms.cfg");
    BuildPath(Path_SM, gPath.sFeedback, PLATFORM_MAX_PATH, "logs/feedback.log");
    LoadTranslations("common.phrases.txt");
    LoadTranslations("xms.phrases.txt");
    LoadTranslations("xms_menu.phrases.txt");

    gRound .hOvertime       = INVALID_HANDLE;
    gRound .mTeams          = CreateTrie();
    gHud   .hKeys           = CreateHudSynchronizer();
    gHud   .hTime           = CreateHudSynchronizer();
    gHud   .hVote           = CreateHudSynchronizer();
    CreateTimer             (0.1, T_KeysHud, _, TIMER_REPEAT);
    CreateTimer             (0.1, T_TimeHud, _, TIMER_REPEAT);
    CreateTimer             (1.0, T_Voting , _, TIMER_REPEAT);
    gHud   .cColors[0]      = RegClientCookie("hudcolor_r"    , "HUD color red value"           , CookieAccess_Public);
    gHud   .cColors[1]      = RegClientCookie("hudcolor_g"    , "HUD color green value"         , CookieAccess_Public);
    gHud   .cColors[2]      = RegClientCookie("hudcolor_b"    , "HUD color blue value"          , CookieAccess_Public);
    gSounds.cMusic          = RegClientCookie("xms_endmusic"  , "Enable end of game music"      , CookieAccess_Public);
    gSounds.cMisc           = RegClientCookie("xms_miscsounds", "Enable beeps & misc XMS sounds", CookieAccess_Public);
    gConVar.tv_enable       = FindConVar("tv_enable");
    gConVar.sv_pausable     = FindConVar("sv_pausable");
    gConVar.mp_teamplay     = FindConVar("mp_teamplay");
    gConVar.mp_chattime     = FindConVar("mp_chattime");
    gConVar.mp_friendlyfire = FindConVar("mp_friendlyfire");
    gConVar.mp_restartgame  = FindConVar("mp_restartgame");
    gConVar.mp_restartgame  . AddChangeHook(OnGameRestarting);
    gConVar.sm_nextmap      = FindConVar("sm_nextmap");
    gConVar.sm_nextmap      . AddChangeHook(OnNextmapChanged);
    gConVar.sv_tags         = FindConVar("sv_tags");
    gConVar.sv_tags         . AddChangeHook(OnTagsChanged);
    gConVar.mp_timelimit    = FindConVar("mp_timelimit");
    gConVar.mp_timelimit    . AddChangeHook(OnTimelimitChanged);
    
    RegisterColors();
    HookEvents();
    
    RegisterCommands();

    CreateTimer(1.0, T_MenuRefresh, _, TIMER_REPEAT);

    AddPluginTag();
    LoadConfigValues();

    if (gCore.iAdFrequency) {
        CreateTimer(float(gCore.iAdFrequency), T_Adverts, _, TIMER_REPEAT);
    }

    if (LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }

    #if defined _gameme_hud_included
        if (LibraryExists("gameme_hud")) {
            gCore.bRanked = true;
        }
    #endif
}

public void OnTagsChanged(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    if (!gCore.bChangingTags) {
        AddPluginTag();
    }
}

void AddPluginTag()
{
    char sTags[128];

    gConVar.sv_tags.GetString(sTags, sizeof(sTags));

    if (StrContains(sTags, "xms") == -1)
    {
        StrCat(sTags, sizeof(sTags), sTags[0] != 0 ? ",xms" : "xms");
        gCore.bChangingTags = true;
        gConVar.sv_tags.SetString(sTags);
        gCore.bChangingTags = false;
    }
}

public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }

    #if defined _gameme_hud_included
        if (StrEqual(sName, "gameme_hud")) {
            gCore.bRanked = true;
        }
    #endif
}

public void OnLibraryRemoved(const char[] sName)
{
    #if defined _gameme_hud_included
        if (StrEqual(sName, "gameme_hud")) {
            gCore.bRanked = false;
        }
    #endif
}

public void OnAllPluginsLoaded()
{
    if (!gCore.bReady) {
        // Restart on first load - avoids issues with SourceTV (etc)
        CreateTimer(1.0, T_RestartMap, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (!LibraryExists("hl2dmfix")) {
        LogError("hl2dmfix is not loaded !");
    }
}