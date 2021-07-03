#define PLUGIN_VERSION  "1.8"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xms.upd"
public Plugin myinfo = {
    name              = "XMS (eXtended Match System)",
    version           = PLUGIN_VERSION,
    description       = "Multi-gamemode match plugin for competitive HL2DM servers",
    author            = "harper",
    url               = PLUGIN_URL
};
/*************************************************************************************************/

#pragma dynamic 2097152
#pragma semicolon 1
#pragma newdecls optional
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
#define REQUIRE_PLUGIN

#pragma newdecls required
#include <jhl2dm>
#include <xms>

/*************************************************************************************************/

#define BITS_SPRINT             0x00000001
#define OFFS_COLLISIONGROUP     500

#define OVERTIME_TIME           1
#define DELAY_ACTION            4

#define SOUND_CONNECT           "friends/friend_online.wav"
#define SOUND_DISCONNECT        "friends/friend_join.wav"
#define SOUND_ACTIONPENDING     "buttons/blip1.wav"
#define SOUND_ACTIONCOMPLETE    "hl1/fvox/beep.wav"
#define SOUND_VOTECALLED        "xms/votecall.wav"
#define SOUND_VOTEFAILED        "xms/votefail.wav"
#define SOUND_VOTESUCCESS       "xms/voteaccept.wav"
#define SOUND_GG                "xms/gg.mp3"

enum(+=1){
    VOTE_RUN, VOTE_RUNNEXT, VOTE_MATCH, VOTE_CUSTOM
}

/*************************************************************************************************/

char gsModelPath[19][70] = {
    "models/combine_soldier.mdl",
    "models/combine_soldier_prisonguard.mdl",
    "models/combine_super_soldier.mdl",
    "models/police.mdl",
    "models/humans/group03/female_01.mdl",
    "models/humans/group03/female_02.mdl",
    "models/humans/group03/female_03.mdl",
    "models/humans/group03/female_04.mdl",
    "models/humans/group03/female_06.mdl",
    "models/humans/group03/female_07.mdl",
    "models/humans/group03/male_01.mdl",
    "models/humans/group03/male_02.mdl",
    "models/humans/group03/male_03.mdl",
    "models/humans/group03/male_04.mdl",
    "models/humans/group03/male_05.mdl",
    "models/humans/group03/male_06.mdl",
    "models/humans/group03/male_07.mdl",
    "models/humans/group03/male_08.mdl",
    "models/humans/group03/male_09.mdl"
};

char gsMusicPath[6][PLATFORM_MAX_PATH] = {
    "music/hl2_song14.mp3",
    "music/hl2_song20_submix0.mp3",
    "music/hl2_song15.mp3",
    "music/hl1_song25_remix3.mp3",
    "music/hl1_song10.mp3",
    "music/hl2_song12_long.mp3"
};

char gsConfigPath[PLATFORM_MAX_PATH];
KeyValues ghConfig;

bool gbPluginReady;
bool gbModTags;
float gfPretime;
float gfEndtime;

Handle ghForwardGamestateChanged;
Handle ghForwardMatchStart;
Handle ghForwardMatchEnd;

Handle ghCookieMusic;
Handle ghCookieSounds;
Handle ghCookieColorR;
Handle ghCookieColorG;
Handle ghCookieColorB;

Handle ghTimeHud;
Handle ghVoteHud;
Handle ghKeysHud;
Handle ghOvertimer = INVALID_HANDLE;

ConVar ghConVarTags;
ConVar ghConVarTimelimit;
ConVar ghConVarTeamplay;
ConVar ghConVarChattime;
ConVar ghConVarFriendlyfire;
ConVar ghConVarPausable;
ConVar ghConVarTv;
ConVar ghConVarNextmap;
ConVar ghConVarRestart;

int giGamestate;
int giOvertime;
char gsGameId[128];
char gsMap[MAX_MAP_LENGTH];
char gsNextMap[MAX_MAP_LENGTH];
char gsMode[MAX_MODE_LENGTH];
char gsModeName[32];
char gsNextMode[MAX_MODE_LENGTH];
char gsValidModes[512];
char gsRetainModes[512];
char gsDefaultMode[MAX_MODE_LENGTH];

int giAllowClient;
int giPauseClient;
bool gbClientInit[MAXPLAYERS + 1];
bool gbClientNoRagdoll[MAXPLAYERS + 1];
Menu ghMenuClient[MAXPLAYERS + 1];
int giClientMenuType[MAXPLAYERS + 1];

char gsVoteMotion[128];
int giVoteMinPlayers;
int giVoteMaxTime;
int giVoteCooldown;
int giVoteType;
int giVoteStatus;
int giClientVote[MAXPLAYERS + 1];
int giClientVoteCallTick[MAXPLAYERS + 1];

int giSpawnHealth;
int giSpawnSuit;
char gsSpawnWeapon[16][32];
int giSpawnAmmo[16][2];

bool gbTeamplay;
bool gbDisableProps;
bool gbDisableCollisions;
bool gbUnlimitedAux;
bool gbRecording;
bool gbShowKeys;

char gsServerName[32];
char gsServerAdmin[32];
char gsServerURL[32];
char gsDemoPath[PLATFORM_MAX_PATH];
char gsDemoURL[PLATFORM_MAX_PATH];
char gsDemoExtension[8];

char gsRemovePrefixes[512];
int giAdFrequency;

StringMap gsmTeams;

/**************************************************************************************************/

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    CreateNative("GetConfigKeys", Native_GetConfigKeys);
    CreateNative("GetConfigString", Native_GetConfigString);
    CreateNative("GetConfigInt", Native_GetConfigInt);
    CreateNative("GetGamestate", Native_GetGamestate);
    CreateNative("GetGamemode", Native_GetGamemode);
    CreateNative("GetTimeRemaining", Native_GetTimeRemaining);
    CreateNative("GetTimeElapsed", Native_GetTimeElapsed);
    CreateNative("GetGameID", Native_GetGameID);
    CreateNative("IsGamestate", Native_IsGamestate);
    
    ghForwardMatchStart = CreateGlobalForward("OnMatchStart", ET_Event);
    ghForwardMatchEnd =     CreateGlobalForward("OnMatchEnd", ET_Event, Param_Cell);
    ghForwardGamestateChanged = CreateGlobalForward("OnGamestateChanged", ET_Event, Param_Cell, Param_Cell);

    RegPluginLibrary("xms");
}

public int Native_GetConfigString(Handle plugin, int params)
{
    char value[1024], key[32], inKey[32];

    ghConfig.Rewind();
    GetNativeString(3, key, sizeof(key));
    for(int p = 4; p <= params; p++) {
        GetNativeString(p, inKey, sizeof(inKey));
        if(!strlen(inKey)) {
            continue;
        }
        
        if(!ghConfig.JumpToKey(inKey)) {
            return -1;
        }
    }

    if(ghConfig.GetString(key, value, sizeof(value))) {
        if(StrEqual(value, NULL_STRING)) {
            return 0;
        }
        
        SetNativeString(1, value, GetNativeCell(2));
        return 1;
    }
    return -1;
}

public int Native_GetConfigInt(Handle plugin, int params)
{
    char value[32], key[32], inKey[4][32];
    
    GetNativeString(1, key, sizeof(key));
    for(int p = 2; p <= params; p++) {
        GetNativeString(p, inKey[p-2], sizeof(inKey[]));
    }

    if(GetConfigString(value, sizeof(value), key, inKey[0], inKey[1], inKey[2], inKey[3])) {
        return StringToInt(value);
    }
    return -1;
}

public int Native_GetConfigKeys(Handle plugin, int params)
{
    int count;
    char subkeys[1024], inKey[32];
    
    ghConfig.Rewind();
    for(int p = 3; p <= params; p++) {
        GetNativeString(p, inKey, sizeof(inKey));
        if(!ghConfig.JumpToKey(inKey)) {
            return -1;
        }
    }
    
    if(ghConfig.GotoFirstSubKey(false)) {
        do {
            ghConfig.GetSectionName(subkeys[strlen(subkeys)], sizeof(subkeys));
            subkeys[strlen(subkeys)] = ',';
            count++;
        } while(ghConfig.GotoNextKey(false));
        
        subkeys[strlen(subkeys) - 1] = 0;
        SetNativeString(1, subkeys, GetNativeCell(2));
        return count;
    }

    return -1;
}

public int Native_GetGamestate(Handle plugin, int numParams)
{
    return giGamestate;
}

public int Native_GetGamemode(Handle plugin, int numParams)
{
    int bytes;
    SetNativeString(1, gsMode, GetNativeCell(2), true, bytes);
    return bytes;
}

public int Native_GetTimeRemaining(Handle plugin, int numParams)
{
    float t = ghConVarTimelimit.FloatValue * 60 - GetGameTime() + gfPretime;
        
    if(GetNativeCell(1)) {
        if(IsGamestate(GAME_OVER)) {
            return view_as<int>(ghConVarChattime.FloatValue - (GetGameTime() - gfEndtime));
        }
        return view_as<int>(t + ghConVarChattime.FloatValue);
    }
    
    return view_as<int>(t);
}

public int Native_GetTimeElapsed(Handle plugin, int numParams)
{
    return view_as<int>(GetGameTime() - gfPretime);
}

public int Native_IsGamestate(Handle plugin, int params)
{
    for(int p = 1; p <= params; p++) {
        if(GetNativeCellRef(p) == giGamestate) {
            return 1;
        }
    }
    return 0;
}

public int Native_GetGameID(Handle plugin, int numParams)
{
    int bytes;
    SetNativeString(1, gsGameId, GetNativeCell(2), true, bytes);
    return bytes;
}

void Forward_OnGamestateChanged(int state)
{
    Call_StartForward(ghForwardGamestateChanged);
    Call_PushCell(state);
    Call_PushCell(giGamestate);
    Call_Finish();
}

void Forward_OnMatchStart()
{
    Call_StartForward(ghForwardMatchStart);
    Call_Finish();
}

void Forward_OnMatchEnd(bool matchCompleted)
{
    Call_StartForward(ghForwardMatchEnd);
    Call_PushCell(view_as<int>(matchCompleted));
    Call_Finish();
}

/*************************************************************************************************/

public void OnPluginStart()
{
    BuildPath(Path_SM, gsConfigPath, PLATFORM_MAX_PATH, "configs/xms.cfg");
    LoadTranslations("common.phrases.txt");
    LoadTranslations("xms.phrases.txt");
    
    // commands
    RegConsoleCmd("run",         Cmd_Run, "[vote to] change the current map");
    RegConsoleCmd("runnow",      Cmd_Run, "[vote to] change the current map");
    RegConsoleCmd("runnext",     Cmd_Run, "[vote to] set the next map");
    RegConsoleCmd("start",       Cmd_Start, "[vote to] start a match");
    RegConsoleCmd("cancel",      Cmd_Cancel, "[vote to] cancel the match");
    RegConsoleCmd("list",        Cmd_MapList, "view a list of available maps");
    RegConsoleCmd("maplist",     Cmd_MapList, "view a list of available maps");
    RegConsoleCmd("profile",     Cmd_Profile, "view a player's steam profile");
    RegConsoleCmd("showprofile", Cmd_Profile, "view a player's steam profile");
    RegConsoleCmd("info",        Cmd_Profile, "view a player's steam profile");
    RegConsoleCmd("menu",        Cmd_Menu, "display the XMS menu");
    RegConsoleCmd("model",       Cmd_Model, "change player model");
    RegConsoleCmd("vote",        Cmd_CallVote, "call a custom vote");
    RegConsoleCmd("yes",         Cmd_CastVote, "vote yes");
    RegConsoleCmd("no",          Cmd_CastVote, "vote no");
    RegConsoleCmd("hudcolor",    Cmd_HudColor, "set hud color");
    RegAdminCmd("forcespec", AdminCmd_Forcespec, ADMFLAG_GENERIC, "force a player to spectate");
    RegAdminCmd("allow",     AdminCmd_AllowJoin, ADMFLAG_GENERIC, "allow a player to join the match");
    
    AddCommandListener(ListenCmd_Fov,   "sm_fov");
    AddCommandListener(ListenCmd_Team,  "jointeam");
    AddCommandListener(ListenCmd_Team,  "spectate");
    AddCommandListener(ListenCmd_Pause, "pause");
    AddCommandListener(ListenCmd_Pause, "unpause");
    AddCommandListener(ListenCmd_Pause, "setpause");
    AddCommandListener(OnMapChanging,   "changelevel");
    AddCommandListener(OnMapChanging,   "changelevel_next");
    AddCommandListener(Listen_Basecommands, "timeleft");
    AddCommandListener(Listen_Basecommands, "nextmap");
    AddCommandListener(Listen_Basecommands, "currentmap");
    AddCommandListener(Listen_Basecommands, "ff");

    // cookies
    ghCookieMusic =  RegClientCookie("xms_endmusic", "Enable game end music", CookieAccess_Public);
    ghCookieSounds = RegClientCookie("xms_miscsounds", "Enable plugin alert sounds", CookieAccess_Public);
    ghCookieColorR = RegClientCookie("hudcolor_r", "HUD color red value", CookieAccess_Public);
    ghCookieColorG = RegClientCookie("hudcolor_g", "HUD color green value", CookieAccess_Public);
    ghCookieColorB = RegClientCookie("hudcolor_b", "HUD color blue value", CookieAccess_Public);

    // prepare vars
    gsmTeams = CreateTrie();
    ghKeysHud = CreateHudSynchronizer();
    ghTimeHud = CreateHudSynchronizer();
    ghVoteHud = CreateHudSynchronizer();
    
    // text colors
    MC_AddColor("N", COLOR_NORMAL);
    MC_AddColor("I", COLOR_INFORMATION);
    MC_AddColor("H", COLOR_HIGHLIGHT);
    MC_AddColor("E", COLOR_ERROR);
    
    // events
    HookEvent("player_changename",     Event_GameMessage, EventHookMode_Pre);
    HookEvent("player_connect_client", Event_GameMessage, EventHookMode_Pre);    
    HookEvent("player_team",       Event_GameMessage, EventHookMode_Pre);
    HookEvent("player_connect",    Event_GameMessage, EventHookMode_Pre);
    HookEvent("player_disconnect", Event_GameMessage,EventHookMode_Pre);
    HookEvent("round_start",   Event_RoundStart, EventHookMode_Post);
    HookEvent("player_death",  Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_spawn",  Event_PlayerSpawn, EventHookMode_Post);
    HookUserMessage(GetUserMessageId("TextMsg"), UserMsg_TextMsg, true);
    HookUserMessage(GetUserMessageId("VGUIMenu"), UserMsg_VGUIMenu, false);
    
    // convars
    CreateConVar("xms_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    
    ghConVarTv =       FindConVar("tv_enable");
    ghConVarPausable = FindConVar("sv_pausable");
    ghConVarTeamplay = FindConVar("mp_teamplay");
    ghConVarChattime = FindConVar("mp_chattime");
    ghConVarRestart =  FindConVar("mp_restartgame");
    ghConVarFriendlyfire = FindConVar("mp_friendlyfire");
    ghConVarNextmap =   FindConVar("sm_nextmap");
    ghConVarTags =      FindConVar("sv_tags");
    ghConVarTimelimit = FindConVar("mp_timelimit");
    ghConVarRestart  . AddChangeHook(OnGameRestarting);
    ghConVarNextmap  . AddChangeHook(OnNextmapChanged);
    ghConVarTags     . AddChangeHook(OnTagsChanged);
    ghConVarTimelimit. AddChangeHook(OnTimelimitChanged);

    // ready to go
    AddPluginTag();
    LoadConfigValues();
    
    CreateTimer(0.1, T_KeysHud, _, TIMER_REPEAT);
    CreateTimer(0.1, T_TimeHud, _, TIMER_REPEAT);
    CreateTimer(1.0, T_Voting, _, TIMER_REPEAT);
    if(giAdFrequency) {
        CreateTimer(float(giAdFrequency), T_Adverts, _, TIMER_REPEAT);
    }
    
    if(LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnAllPluginsLoaded()
{
    if(!gbPluginReady) {
        // on first load we will restart the map - avoids issues with sourcetv etc
        CreateTimer(1.0, T_RestartMap, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

void AddPluginTag()
{
    char tags[128];
    ghConVarTags.GetString(tags, sizeof(tags));
  
    if(StrContains(tags, "xms") == -1)
    {
        StrCat(tags, sizeof(tags), tags[0] != 0 ? ",xms" : "xms");
        gbModTags = true;
        ghConVarTags.SetString(tags);
        gbModTags = false;
    }
}

void LoadConfigValues()
{
    ghConfig = new KeyValues("");
    ghConfig.ImportFromFile(gsConfigPath);
  
    if(!GetConfigKeys(gsValidModes, sizeof(gsValidModes), "gamemodes") || !GetConfigString(gsDefaultMode, sizeof(gsDefaultMode), "defaultMode")) {
        LogError("xms.cfg missing or corrupted!");
    }
    GetConfigString(gsDemoPath, sizeof(gsDemoPath), "demoFolder");
    GetConfigString(gsDemoURL, sizeof(gsDemoURL), "demoURL");
    GetConfigString(gsDemoExtension, sizeof(gsDemoExtension), "demoExtension");
    GetConfigString(gsServerName, sizeof(gsServerName), "serverName");
    GetConfigString(gsServerAdmin, sizeof(gsServerAdmin), "serverAdmin");
    GetConfigString(gsServerURL, sizeof(gsServerURL), "serverURL");
    GetConfigString(gsRetainModes, sizeof(gsRetainModes), "retainModes");
    GetConfigString(gsRemovePrefixes, sizeof(gsRemovePrefixes), "stripPrefix", "maps");
  
    if(!GetConfigString(gsModeName, sizeof(gsModeName), "name", "gamemodes", gsMode)) {
        gsModeName = "";
    }
  
    giSpawnHealth = GetConfigInt("spawnHealth", "gamemodes", gsMode);
    giSpawnSuit = GetConfigInt("spawnSuit", "gamemodes", gsMode);    
    gbDisableCollisions = (GetConfigInt("noCollisions", "gamemodes", gsMode) == 1);
    gbUnlimitedAux = (GetConfigInt("unlimitedAux", "gamemodes", gsMode) == 1);
    gbDisableProps = (GetConfigInt("disableProps", "gamemodes", gsMode) == 1);
    giOvertime = (GetConfigInt("overtime", "gamemodes", gsMode) == 1);
    gbShowKeys = (GetConfigInt("selfkeys", "gamemodes", gsMode) == 1);
    giAdFrequency = GetConfigInt("frequency", "serverAds");
    giVoteMinPlayers = GetConfigInt("voteMinPlayers");
    giVoteMaxTime = GetConfigInt("voteMaxTime");
    giVoteCooldown = GetConfigInt("voteCooldown");
    
    char weapons[512], weapon[16][32];
    if(GetConfigString(weapons, sizeof(weapons), "spawnWeapons", "gamemodes", gsMode))
    {
        for(int i = 0; i < ExplodeString(weapons, ",", weapon, 16, 32); i++)
        {
            char sAmmo[2][6];
            int pos = SplitString(weapon[i], "(", gsSpawnWeapon[i], sizeof(gsSpawnWeapon[]));
            if(pos != -1)
            {
                int pos2 = SplitString(weapon[i][pos], "-", sAmmo[0], sizeof(sAmmo[]));
                if(pos2 == -1) {
                    strcopy(sAmmo[0], sizeof(sAmmo[]), weapon[i][pos]);
                    sAmmo[0][strlen(sAmmo[0])-1] = 0;
                }
                else {
                    strcopy(sAmmo[1], sizeof(sAmmo[]), weapon[i][pos+pos2]);
                    sAmmo[1][strlen(sAmmo[1])-1] = 0;
                }
            }
            else {
                strcopy(gsSpawnWeapon[i], sizeof(gsSpawnWeapon[]), weapon[i]);
            }
        
            for(int z = 0; z < 2; z++) {
                if(!StringToIntEx(sAmmo[z], giSpawnAmmo[i][z])) {
                    giSpawnAmmo[i][z] = -1;
                }
            }
        }
    }
    else {
        gsSpawnWeapon[0] = "default";
    }
}


/**************************************************************************************************
 *** Commands
**************************************************************************************************/
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if(client == 0) {
        // spam be gone
        return Plugin_Handled;
    }
    
    if(StrContains(sArgs, "!") == 0 || StrContains(sArgs, "/") == 0 || StrContains(sArgs, "#.#") == 0)
    {
        char args[MAX_SAY_LENGTH];
        bool corrected;
        
        strcopy(args, sizeof(args), sArgs);
        
        // backwards compatibility for old PMS commands
        if(StrContains(args, "cm") == 1) {
            FakeClientCommandEx(client, "say !run%s", args[3]);
        }
        else if(StrContains(args, "run") == 1 && (StrEqual(args[5], "1v1") || StrEqual(args[5], "2v2") || StrEqual(args[5], "3v3") || StrEqual(args[5], "4v4") || StrEqual(args[5], "duel"))) {
            FakeClientCommandEx(client, "say !start");
        }
        else if(StrContains(args, "tp ") == 1 || StrContains(args, "teamplay ") == 1)
        {
            if(StrContains(args, " on") != -1 || StrContains(args, " 1") != -1) {
                FakeClientCommandEx(client, "say !run tdm");
            }
            else if(StrContains(args, " off") != -1 || StrContains(args, " 0") != -1) {
                FakeClientCommandEx(client, "say !run dm");
            }
        }
        else if(StrEqual(args[1], "cf") || StrEqual(args[1], "coinflip") || StrEqual(args[1], "flip")) {
            MC_PrintToChatAllFrom(client, false, "%t", "xmsc_coinflip", GetRandomInt(0, 1) ? "heads" : "tails");
        }
        else if(StrEqual(args[1], "stop")) {
            FakeClientCommandEx(client, "say !cancel");
        }
        // more minor commands
        else if(StrEqual(args[1], "pause") || StrEqual(args[1], "unpause")) {
            FakeClientCommandEx(client, "pause");
        }
        else if(StrContains(args, "jointeam ") == 1) {
            FakeClientCommandEx(client, "jointeam %s", args[10]);
        }
        else if(StrEqual(args[1], "join")) {
            FakeClientCommand(client, "jointeam %i", GetOptimalTeam());
        }        
        else if(StrEqual(args[1], "spec") || StrEqual(args[1], "spectate")) {
            FakeClientCommandEx(client, "spectate");
        }
        else if(corrected) {
            // now cycle back in corrected form
            FakeClientCommandEx(client, "say %s", args);
        }
        else {
            return Plugin_Continue;
        }
    }
    else if(giVoteStatus && (StrEqual(sArgs, "yes") || StrEqual(sArgs, "no"))) {
        giClientVote[client] = StrEqual(sArgs, "yes") ? 1 : -1;
    }
    else if(IsGamestate(GAME_PAUSED)) {
        // fix chat when paused
        MC_PrintToChatAllFrom(client, StrEqual(command, "say_team", false), sArgs);
    }    
    else if(StrEqual(sArgs, "gg", false) && IsGamestate(GAME_OVER, GAME_CHANGING)) {
        IfCookiePlaySound(ghCookieSounds, SOUND_GG);
        return Plugin_Continue;
    }
    else if(StrEqual(sArgs, "timeleft") || StrEqual(sArgs, "nextmap") || StrEqual(sArgs, "currentmap") || StrEqual(sArgs, "ff")) {
        Basecommands_Override(client, sArgs, true);
    }
    else {
        return Plugin_Continue;
    }
    
    return Plugin_Stop;
}




// command: start
// start a competitive match on supported gamemodes
public Action Cmd_Start(int client, int args)
{
    if(client == 0) {
        Start();
    }
    else if(GetRealClientCount(true, false, false) == 1) {
        MC_ReplyToCommand(client, "%t", "xmsc_start_deny");
    }
    else if(giVoteStatus) {
        MC_ReplyToCommand(client, "%t", "xmsc_vote_deny");
    }
    else if(VoteTimeout(client)  && !IsClientAdmin(client)) {
        MC_ReplyToCommand(client, "%t", "xmsc_vote_timeout", VoteTimeout(client));
    }
    else if(IsClientObserver(client) && !IsClientAdmin(client)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_spectator");
    }
    else if(!IsModeMatchable(gsMode)) {
        MC_ReplyToCommand(client, "%t", "xmsc_start_denygamemode", gsMode);
    }
    else if(IsGamestate(GAME_MATCH, GAME_MATCHEX, GAME_PAUSED)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_match");
    }
    else if(IsGamestate(GAME_CHANGING, GAME_MATCHWAIT)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_changing");
    }
    else if(IsGamestate(GAME_OVER) || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_over");
    }
    else {
        RequestStart(client);
    }
}

void RequestStart(int client)
{
    if(GetRealClientCount(true, false, false) < giVoteMinPlayers || giVoteMinPlayers <= 0 || client == 0) {
        MC_PrintToChatAllFrom(client, false, "%t", "xms_started");
        Start();
    }
    else {
        CallVote(VOTE_MATCH, client, "start match");
    }
}

void Start()
{
    SetGamestate(GAME_MATCHWAIT);
    Game_Restart();
    CreateTimer(1.0, T_Start, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action T_Start(Handle timer)
{
    static int iter;

    if(iter == DELAY_ACTION - 1) {
        SetGamestate(GAME_MATCH);
        Game_Restart();
    }
  
    if(iter != DELAY_ACTION)
    {
        PrintCenterTextAll("%t", "xms_starting", DELAY_ACTION - iter);
        IfCookiePlaySound(ghCookieSounds, SOUND_ACTIONPENDING);
        iter++;
        return Plugin_Continue;
    }
  
    PrintCenterTextAll("");
    IfCookiePlaySound(ghCookieSounds, SOUND_ACTIONCOMPLETE);
    iter = 0;
    return Plugin_Stop;
}


// command: cancel
// cancel an ongoing competitive match
public Action Cmd_Cancel(int client, int args)
{
    if(client == 0) {
        Cancel();
    }
    else if(giVoteStatus) {
        MC_ReplyToCommand(client, "%t", "xmsc_vote_deny");
    }
    else if(VoteTimeout(client)  && !IsClientAdmin(client)) {
        MC_ReplyToCommand(client, "%t", "xmsc_vote_timeout", VoteTimeout(client));
    }
    else if(IsClientObserver(client) && !IsClientAdmin(client)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_spectator");
    }
    else if(IsGamestate(GAME_PAUSED)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_paused");
    }
    else if(IsGamestate(GAME_DEFAULT, GAME_OVERTIME)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_nomatch");
    }
    else if(IsGamestate(GAME_MATCHEX)) {
        MC_ReplyToCommand(client, "%t", "xmsc_cancel_matchex");
    }
    else if(IsGamestate(GAME_CHANGING, GAME_MATCHWAIT)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_changing");
    }
    else if(IsGamestate(GAME_OVER) || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_over");
    }
    else {
        RequestCancel(client);
    }
}

void RequestCancel(int client)
{
    if(GetRealClientCount() < giVoteMinPlayers || giVoteMinPlayers <= 0) {
        MC_PrintToChatAllFrom(client, false, "%t", "xms_cancelled");
        Cancel();
    }
    else {
        CallVote(VOTE_MATCH, client, "cancel match");
    }
}

void Cancel()
{
    SetGamestate(GAME_DEFAULT);
    Game_Restart();
}


// command: run <mode>:<map>
// change the map and/or gamemode
public Action Cmd_Run(int client, int args)
{
    static int fail_iter[MAXPLAYERS+1], multi_iter[MAXPLAYERS+1];
    char sQuery[MAX_MAP_LENGTH], sAbbrev[MAX_MAP_LENGTH], newMap[MAX_MAP_LENGTH], newMode[MAX_MODE_LENGTH]; 
    
    if(!args || args > 3) {
        MC_ReplyToCommand(client, "%t", "xmsc_run_usage");
        return Plugin_Handled;
    }
    if(giVoteStatus) {
        MC_ReplyToCommand(client, "%t", "xmsc_vote_deny");
        return Plugin_Handled;
    }
    if(VoteTimeout(client) && !IsClientAdmin(client)) {
        MC_ReplyToCommand(client, "%t", "xmsc_vote_timeout", VoteTimeout(client));
        return Plugin_Handled;
    }
    if(IsGamestate(GAME_PAUSED)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_paused");
        return Plugin_Handled;
    }
    if(IsGamestate(GAME_MATCH)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_match");
        return Plugin_Handled;
    }
    if(IsGamestate(GAME_CHANGING)) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_changing");
        return Plugin_Handled;
    }
    
    GetCmdArg(0, sQuery, sizeof(sQuery));
    bool delayed = StrContains(sQuery, "runnext", false) == 0;
    
    GetCmdArg(1, sQuery, sizeof(sQuery));
    String_ToLower(sQuery, sQuery, sizeof(sQuery));
    
    if(IsValidGamemode(sQuery))
    {
        strcopy(newMode, sizeof(newMode), sQuery);
        if(args == 1)
        {
            // only mode was specified, fetch map..
            if(!StrEqual(gsMode, newMode))
            {
                if(!(GetConfigString(newMap, sizeof(newMap), "defaultmap", "gamemodes", newMode) && IsMapValid(newMap) && !(IsItemDistinctInList(gsMode, gsRetainModes) && IsItemDistinctInList(newMode, gsRetainModes)))) {
                    strcopy(newMap, sizeof(newMap), gsMap);        
                }
                RequestRun(client, newMode, newMap, delayed);
            }
            else {
                MC_ReplyToCommand(client, "%t", "xmsc_run_denymode", newMode);
            }
                    
            return Plugin_Handled;
        }
        else
        {
            // client also specified the map
            GetCmdArg(2, sQuery, sizeof(sQuery));
            if(StrEqual(sQuery, ":")) {
                GetCmdArg(3, sQuery, sizeof(sQuery));
            }
            String_ToLower(sQuery, sQuery, sizeof(sQuery));
        }
    }
    else if(args > 1)
    {
        // first arg was not a valid mode, try second
        GetCmdArg(2, newMode, sizeof(newMode));
        String_ToLower(newMode, newMode, sizeof(newMode));
                
        if(!IsValidGamemode(newMode)) {
            MC_ReplyToCommand(client, "%t", "xmsc_run_invalidmode", gsValidModes);
            return Plugin_Handled;
        }
    }

    // de-abbreviate map if applicable
    bool abbrev = GetMapByAbbrev(sAbbrev, sizeof(sAbbrev), sQuery);
    
    // we have all the info, time to do the work
    Handle dir = OpenDirectory("maps");
    FileType filetype;
    bool matched, exact;
    int hits, xhits;
    char sFile[256], sOutput[140], sFullOutput[600];
    
    while(ReadDirEntry(dir, sFile, sizeof(sFile), filetype) && !exact)
    {
        if(filetype == FileType_File && strlen(sFile) <= MAX_MAP_LENGTH && StrContains(sFile, ".ztmp") == -1 && ReplaceString(sFile, sizeof(sFile), ".bsp", ""))
        {
            if(StrContains(sFile, sQuery, false) >= 0 || (abbrev && StrContains(sFile, sAbbrev, false) >= 0))
            {
                exact = abbrev ? StrEqual(sFile, sAbbrev, false) : StrEqual(sFile, sQuery, false);
                hits++;
                    
                if(hits == 1 || exact) {
                    strcopy(newMap, sizeof(newMap), sFile);
                    hits = 1;
                    xhits = 0;
                }
                            
                if(!exact)
                {
                    // pass more results to console
                    if(strlen(sFullOutput) + strlen(sFile) < sizeof(sFullOutput)-1) {
                        Format(sFullOutput, sizeof(sFullOutput), "%s　%s", sFullOutput, sFile);
                    }
                    
                    if(GetCmdReplySource() != SM_REPLY_TO_CONSOLE)
                    {                    
                        // colorise results for chat
                        char sQuery2[256];
                        Format(sQuery2, sizeof(sQuery2), "{H}%s{I}", sQuery);
                        ReplaceString(sFile, sizeof(sFile), sQuery, sQuery2, false);
                        if(strlen(sOutput) + strlen(sFile) + (hits == 1 ? 0 : 3) < 140) {
                            Format(sOutput, sizeof(sOutput), "%s%s%s", sOutput, hits == 1 ? "" : ", ", sFile);
                            xhits++;
                        }
                    }
                }
            }
        }
    }
    CloseHandle(dir);    
    
    switch(hits)
    {
        case 0: {
            fail_iter[client]++;
            MC_ReplyToCommand(client, "%t", "xmsc_run_notfound", sQuery);
        }
        case 1:
        {
            matched = true;
            if(args == 1) {
                GetModeForMap(newMode, sizeof(newMode), newMap);
            }
        }
        default:
        {
            if(GetCmdReplySource() != SM_REPLY_TO_CONSOLE) {
                MC_ReplyToCommand(client, "%t", "xmsc_run_found", sOutput, hits - xhits);
            }
            PrintToConsole(client, "%t", "xmsc_run_results", sQuery, sFullOutput, hits);
            multi_iter[client]++; 
        }
    }
        
    if(!matched)
    {
        if(multi_iter[client] >= 3 && !exact && hits > xhits && GetCmdReplySource() != SM_REPLY_TO_CONSOLE) {
            MC_ReplyToCommand(client, "%t", "xmsc_run_tip1");
            multi_iter[client] = 0;                
        }
        else if(fail_iter[client] >= 3) {
            MC_ReplyToCommand(client, "%t", "xmsc_run_tip2");
            fail_iter[client] = 0;
        }
    }
    else {
        RequestRun(client, newMode, newMap, delayed);
    }
    
    return Plugin_Handled;
}

void RequestRun(int client, const char[] mode, const char[] map, bool delayed)
{
    if(GetRealClientCount() < giVoteMinPlayers || giVoteMinPlayers <= 0 || client == 0)
    {
        strcopy(gsNextMode, sizeof(gsNextMode), mode);
        ghConVarNextmap.SetString(map);
        
        if(!delayed) {
            MC_PrintToChatAllFrom(client, false, "%t", "xmsc_run_now", mode, DeprefixMap(map));
            Run();
        }
        else {
            MC_PrintToChatAllFrom(client, false, "%t", "xmsc_run_next", mode, DeprefixMap(map));
        }
    }
    else {
        CallVote(delayed ? VOTE_RUNNEXT : VOTE_RUN, client, "%s:%s", mode, map);
    }
}

void Run()
{
    DataPack dpack;
    SetGamestate(GAME_CHANGING);
    CreateTimer(1.0, T_Run, dpack, TIMER_REPEAT);
}

public Action T_Run(Handle timer, DataPack dpack)
{
    static int iter;
    static char cmap[MAX_MAP_LENGTH];

    if(!iter) {
        strcopy(cmap, sizeof(cmap), DeprefixMap(gsNextMap));
    }
    
    if(iter == DELAY_ACTION)
    {
        PrintCenterTextAll("");
        
        strcopy(gsMode, sizeof(gsMode), gsNextMode);
        SetMapcycle();
        ServerCommand("changelevel_next");
        
        iter = 0;
        return Plugin_Stop;
    }
    else
    {
        PrintCenterTextAll("%t", "xms_loading", gsNextMode, cmap, DELAY_ACTION - iter);
        IfCookiePlaySound(ghCookieSounds, DELAY_ACTION-iter > 1 ? SOUND_ACTIONPENDING : SOUND_ACTIONCOMPLETE);
    }
    
    iter++;
    return Plugin_Continue;
}


// command: maplist <mode/all>
// display list of available maps
public Action Cmd_MapList(int client, int args)
{
    int count;
    char sArg[MAX_MODE_LENGTH], path_mapcycle[PLATFORM_MAX_PATH];
    
    if(!args) {
        strcopy(sArg, sizeof(sArg), gsMode);
    }
    else {
        GetCmdArg(1, sArg, sizeof(sArg));
    }
    
    if(StrEqual(sArg, "all"))
    {
        char sFile[PLATFORM_MAX_PATH];
        Handle dir;
        any filetype;
        
        MC_ReplyToCommand(client, "%t", "xmsc_list_pre_all");
        
        dir = OpenDirectory("maps");
        while (ReadDirEntry(dir, sFile, sizeof(sFile), filetype))
        {
            if(filetype == FileType_File && strlen(sFile) <= MAX_MAP_LENGTH && StrContains(sFile, ".ztmp") == -1 && ReplaceString(sFile, sizeof(sFile), ".bsp", NULL_STRING))
            {
                count++;
                MC_ReplyToCommand(client, "> {I}%s", DeprefixMap(sFile));
            }
        }
        CloseHandle(dir);
        
        MC_ReplyToCommand(client, "%t", "xmsc_list_post", count);
    }
    else if(IsValidGamemode(sArg))
    {
        char map[MAX_MAP_LENGTH];
        File file;
        
        GetConfigString(path_mapcycle, sizeof(path_mapcycle), "mapcycle", "gamemodes", sArg);
        Format(path_mapcycle, sizeof(path_mapcycle), "cfg/%s", path_mapcycle);
        
        MC_ReplyToCommand(client, "%t", "xmsc_list_pre", sArg);
        
        file = OpenFile(path_mapcycle, "r");
        while (!file.EndOfFile() && file.ReadLine(map, sizeof(map)))
        {
            int len = strlen(map);
            
            if(map[0] == ';' || !IsCharAlpha(map[0])) {
                continue;
            }
            
            for(int i = 0; i < len; i++)
            {
                if(IsCharSpace(map[i])) {
                    map[i] = '\0';
                    break;
                }
            }
            
            if(!IsMapValid(map)) {
                LogError("map `%s` in mapcyclefile `%s` is invalid!", map, path_mapcycle);
                continue;
            }
            
            count++;
            MC_ReplyToCommand(client, "> {I}%s", DeprefixMap(map));
        }
        CloseHandle(file);
        
        MC_ReplyToCommand(client, "%t", "xmsc_list_post", count);
    }
    else {
        MC_ReplyToCommand(client, "%t", "xmsc_list_invalid", sArg);
    }
    
    MC_ReplyToCommand(client, "%t", "xmsc_list_modes", gsValidModes);
}


// admin command: forcespec <player>
// force a player to spectate
public Action AdminCmd_Forcespec(int client, int args)
{
    if(!args) {
        MC_ReplyToCommand(client, "%t", "xmsc_forcespec_usage");
        return Plugin_Handled;
    }
  
    int target = ClientArgToTarget(client, 1);
    if(target > 0)
    {
        char name[MAX_NAME_LENGTH];
        GetClientName(target, name, sizeof(name));
    
        if(GetClientTeam(target) != TEAM_SPECTATORS)
        {
            ChangeClientTeam(target, TEAM_SPECTATORS);
            MC_PrintToChat(target, "%t", "xmsc_forcespec_warning");
            MC_ReplyToCommand(client, "%t", "xmsc_forcespec_success", name);
        }
        else {
            MC_ReplyToCommand(client, "%t", "xmsc_forcespec_fail", name);
        }
    }
    else {
        MC_ReplyToCommand(client, "%t", "xmsc_forcespec_notfound");
    }
    
    return Plugin_Handled;
}


// admin command: allow <player>
// allow a player into an ongoing match
public Action AdminCmd_AllowJoin(int client, int args)
{
    if(!IsGameMatch()) {
        MC_ReplyToCommand(client, "%t", "xmsc_deny_nomatch");
    }
    else if(args)
    {
        int target = ClientArgToTarget(client, 1);
        if(target > 0)
        {
            char name[MAX_NAME_LENGTH];
            GetClientName(target, name, sizeof(name));
            
            if(GetClientTeam(target) == TEAM_SPECTATORS)
            {
                giAllowClient = target;
                FakeClientCommand(target, "join");
                MC_PrintToChatAllFrom(client, false, "%t", "xmsc_allow_success", name);
            }
            else {
                MC_ReplyToCommand(client, "%t", "xmsc_allow_fail", name);
            }
        }
    }
    else {
        MC_ReplyToCommand(client, "%t", "xmsc_allow_usage");
    }
}


// command: pause
// pause or unpause the match
public Action ListenCmd_Pause(int client, const char[] command, int argc)
{
    if(!ghConVarPausable.BoolValue) {
        return Plugin_Handled;
    }
    
    if(client == 0)
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i)) {
                giPauseClient = i;
                break;
            }
        }
        
        if(!giPauseClient) {
            ReplyToCommand(0, "Cannot pause when no players are in the server!");
        }
        else {
            FakeClientCommand(giPauseClient, "pause");
        }
        
        return Plugin_Handled;
    }
    
    if(client == giPauseClient) {
        SetGamestate(IsGamestate(GAME_PAUSED) ? GAME_MATCH : GAME_PAUSED);
        return Plugin_Continue;
    }
    
    if(!IsClientAdmin(client))
    {
        if(IsClientObserver(client) && client != giPauseClient) {
            MC_ReplyToCommand(client, "%t", "xmsc_deny_spectator");
            return Plugin_Handled;
        }
    }
    
    switch(giGamestate)
    {
        case GAME_PAUSED:
        {
            IfCookiePlaySound(ghCookieSounds, SOUND_ACTIONCOMPLETE);
            MC_PrintToChatAllFrom(client, false, "%t", "xms_match_resumed");
            SetGamestate(GAME_MATCH);
            return Plugin_Continue;
        }
        case GAME_MATCH:
        {
            IfCookiePlaySound(ghCookieSounds, SOUND_ACTIONCOMPLETE);
            MC_PrintToChatAllFrom(client, false, "%t", "xms_match_paused");
            SetGamestate(GAME_PAUSED);
            return Plugin_Continue;
        }
        case GAME_MATCHWAIT: {
            MC_ReplyToCommand(client, "%t", "xmsc_deny_nomatch");
        }
        case GAME_MATCHEX: {
            MC_ReplyToCommand(client, "%t", "xmsc_cancel_matchex");
        }
        case GAME_OVER: {
            MC_ReplyToCommand(client, "%t", "xmsc_deny_over");
        }
        default: {
            MC_ReplyToCommand(client, "%t", "xmsc_deny_nomatch");
        }
    }
    
    return Plugin_Handled;
}


// command: model <name>
// change player model
public Action Cmd_Model(int client, int args)
{
    if(!args) {
        if(giClientMenuType[client] == 2) {
            ghMenuClient[client] = Menu_Model(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
        }
        return Plugin_Handled;
    }
    
    char name[70];
    GetCmdArg(1, name, sizeof(name));
    
    if(StrContains(name, "/") == -1) {
        Format(name, sizeof(name), "%s/%s", StrContains(name, "male") > -1 ? "models/humans/group03" : "models", name);
    }
    ClientCommand(client, "cl_playermodel %s%s", name, StrContains(name, ".mdl") == -1 ? ".mdl" : "");
    return Plugin_Handled;
}


// command: jointeam / spectate
public Action ListenCmd_Team(int client, const char[] command, int args)
{
    int team = (StrEqual(command, "jointeam", false) ? GetCmdArgInt(1) : TEAM_SPECTATORS);
    
    if(giAllowClient == client) {
        giAllowClient = 0;
    }
    else if(GetClientTeam(client) == team) {
        char name[MAX_TEAM_NAME_LENGTH];
        GetTeamName(team, name, sizeof(name));
        MC_PrintToChat(client, "%t", "xmsc_teamchange_same", name);
    }
    else if(IsGameMatch()) {
        MC_PrintToChat(client, "%t", "xmsc_teamchange_deny");
        return Plugin_Handled;
    }
    else if(gbTeamplay && team == TEAM_COMBINE) {
        ClientCommand(client, "cl_playermodel models/police.mdl");
    }
    
    return Plugin_Continue;
}


// basecommands overrides
public Action Listen_Basecommands(int client, const char[] command, int args)
{
    if(IsClientConnected(client) && IsClientInGame(client)) {
        Basecommands_Override(client, command, false);
    }
    return Plugin_Stop; // doesn't work for timeleft, blocked in TextMsg
}

void Basecommands_Override(int client, const char[] command, bool broadcast)
{
    if(broadcast) {
        MC_PrintToChatAllFrom(client, false, command);
    }
    
    if(StrEqual(command, "timeleft"))
    {
        float t = GetTimeRemaining(IsGamestate(GAME_OVER));
        int h = RoundToNearest(t) / 3600;
        int s = RoundToNearest(t) % 60;
        int m = RoundToNearest(t) / 60 - (h ? (h * 60) : 0);

        if(!IsGamestate(GAME_CHANGING))
        {
            if(IsGamestate(GAME_OVER))
            {
                if(broadcast) {
                    MC_PrintToChatAll("%t", "xmsc_timeleft_over", s);
                }
                else {
                    MC_PrintToChat(client, "%t", "xmsc_timeleft_over", s);
                }
            }
            else if(ghConVarTimelimit.IntValue)
            {
                if(broadcast) {
                    MC_PrintToChatAll("%t", "xmsc_timeleft", h, m, s);
                }
                else {
                    MC_PrintToChat(client, "%t", "xmsc_timeleft", h, m, s);    
                }
            }
            else
            {
                if(broadcast) {
                    MC_PrintToChatAll("%t", "xmsc_timeleft_none");
                }
                else {
                    MC_PrintToChat(client, "%t", "xmsc_timeleft_none");
                }
            }
        }
    }
    else if(StrEqual(command, "nextmap"))
    {
        if(broadcast) {
            MC_PrintToChatAll("%t", "xmsc_nextmap", gsNextMode, DeprefixMap(gsNextMap));
        }
        else {
            MC_PrintToChat(client, "%t", "xmsc_nextmap", gsNextMode, DeprefixMap(gsNextMap));
        }
    }
    else if(StrEqual(command, "currentmap"))
    {
        if(broadcast) {
            MC_PrintToChatAll("%t", "xmsc_currentmap", gsMode, DeprefixMap(gsMap));
        }
        else {
            MC_PrintToChat(client, "%t", "xmsc_currentmap", gsMode, DeprefixMap(gsMap));
        }
    }
    else if(StrEqual(command, "ff"))
    {
        if(gbTeamplay)
        {
            if(broadcast) {
                MC_PrintToChatAll("%t", "xmsc_ff", ghConVarFriendlyfire.BoolValue ? "enabled" : "disabled");
            }
            else {
                MC_PrintToChat(client, "%t", "xmsc_ff", ghConVarFriendlyfire.BoolValue ? "enabled" : "disabled");
            }
        }
    }
}


// command: fov <value>
// change player field-of-view (requires extended fov plugin)
public Action ListenCmd_Fov(int client, const char[] command, int args)
{
    if(CommandExists("sm_fov") && args < 1) {
        if(giClientMenuType[client] == 2) {
            ghMenuClient[client] = Menu_Fov(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
        }
    }
}


// command: menu
// display the plugin menu
public Action Cmd_Menu(int client, int args)
{
    giClientMenuType[client] = 0;
    QueryClientConVar(client, "cl_showpluginmessages", ShowMenuIfVisible, client);
}


// command: profile <player>
// display a player's steam profile
public Action Cmd_Profile(int client, int args)
{
    if(args)
    {
        char url[128];
        int target = ClientArgToTarget(client, 1);
        if(target)
        {
            Format(url, sizeof(url), "https://steamcommunity.com/profiles/%s", GetClientSteamID(target, AuthId_SteamID64));
            
            // have to load a blank page first for it to work:
            ShowMOTDPanel(client, "Loading", "about:blank", MOTDPANEL_TYPE_URL);
            ShowMOTDPanel(client, "Steam Profile", url, MOTDPANEL_TYPE_URL);
        }
    }
    else {
        MC_ReplyToCommand(client, "%t", "xmsc_profile_usage");
    }
}


// command: hudcolor <rrr> <ggg> <bbb>
// set color for hud text elements (timeleft, spectator hud, etc)
public Action Cmd_HudColor(int client, int argc)
{
    if(argc == 3) {
        char args[13], rgb[3][4];
        GetCmdArgString(args, sizeof(args));
        ExplodeString(args, " ", rgb, 3, 4);            
        SetClientCookie(client, ghCookieColorR, rgb[0]);
        SetClientCookie(client, ghCookieColorG, rgb[1]);
        SetClientCookie(client, ghCookieColorB, rgb[2]);
    }
    else {
        MC_ReplyToCommand(client, "%t", "xmsc_hudcolor_usage");
        if(giClientMenuType[client] == 2) {
            ghMenuClient[client] = Menu_HudColor(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
        }        
    }
    
    return Plugin_Handled;
}


// command: vote <motion>
// call a yes/no vote
public Action Cmd_CallVote(int client, int args)
{
    if(!args) {
        MC_ReplyToCommand(client, "%t", "xmsc_callvote_usage");
    }
    else if(giVoteStatus) {
        MC_ReplyToCommand(client, "%t", "xmsc_callvote_deny");
    }
    else if(VoteTimeout(client)  && !IsClientAdmin(client)) {
        MC_ReplyToCommand(client, "%t", "xmsc_callvote_denywait", VoteTimeout(client));
    }
    else {
        char motion[64];
        GetCmdArgString(motion, sizeof(motion));
        
        if(StrContains(motion, "run", false) == 0) {
            bool next = StrContains(motion, "runnext", false) == 0;
            FakeClientCommandEx(client, "%s %s", next ? "runnext" : "run", motion[next ? 8 : 4]);
        }
        else if(StrContains(motion, "cancel") == 0) {
            FakeClientCommandEx(client, "cancel");
        }
        else {
            CallVote(VOTE_CUSTOM, client, motion);
        }
    }
}

void CallVote(int type, int caller, const char[] motion, any ...)
{
    VFormat(gsVoteMotion, sizeof(gsVoteMotion), motion, 4);
    giClientVoteCallTick[caller] = GetGameTickCount();
    giVoteStatus = 1;
    giVoteType = type;
    giClientVote[caller] = 1;
    
    MC_PrintToChatAllFrom(caller, false, "%t", "xmsc_callvote");
    IfCookiePlaySound(ghCookieSounds, SOUND_VOTECALLED);
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }
        
        if(i != caller && (!IsClientObserver(i) || type != VOTE_MATCH)) {
            giClientVote[i] = 0;
            ghMenuClient[i] = Menu_Decision(i);
            ghMenuClient[i].Display(i, MENU_TIME_FOREVER);
        }
    }
}


// command: [yes/no]
// vote for current motion
public Action Cmd_CastVote(int client, int args)
{
    char vote[4];
    GetCmdArg(0, vote, sizeof(vote));
    
    if(IsClientObserver(client) && giVoteType == VOTE_MATCH) {
        MC_ReplyToCommand(client, "%t", "xmsc_castvote_denyspec");
    }
    else {
        giClientVote[client] = StrEqual(vote, "yes", false) ? 1 : -1;
        
        char name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));
        PrintToConsoleAll("%t", "xmsc_castvote", name, vote);
    }
}


/**************************************************************************************************
 *** Main Functions
**************************************************************************************************/
public Action OnLevelInit(const char[] mapName, char mapEntities[2097152])
{  
    char keys[4096], ent[2][2048][512];
  
    if(!GetConfigKeys(keys, sizeof(keys), "gamemodes", gsNextMode, "replaceEntities")) {
        return Plugin_Continue;
    }
  
    for(int i = 0; i < ExplodeString(keys, ",", ent[0], 2048, 512); i++) {
        if(GetConfigString(ent[1][i], 512, ent[0][i], "gamemodes", gsNextMode, "replaceEntities") != -1) {
            ReplaceString(mapEntities, sizeof(mapEntities), ent[0][i], ent[1][i], false);
        }
    }
    
    return Plugin_Changed;
}

public void OnMapStart()
{
    PrepareSound(SOUND_GG);
    PrepareSound(SOUND_VOTECALLED);
    PrepareSound(SOUND_VOTEFAILED);
    PrepareSound(SOUND_VOTESUCCESS);
  
    GetCurrentMap(gsMap, sizeof(gsMap));
    LoadConfigValues();
  
    if(gbPluginReady)
    {
        char description[32];
        strcopy(gsNextMode, sizeof(gsNextMode), gsMode);
        strcopy(description, sizeof(description), gsMode);
        if(strlen(gsModeName)) {
            Format(description, sizeof(description), "%s (%s)", description, gsModeName);
        }
        Steam_SetGameDescription(description);
    }
  
    if(giOvertime == 1) {
        CreateOverTimer();
    }
  
    if(gbTeamplay) {
        Team_SetName(TEAM_SPECTATORS, strlen(gsModeName) ? gsModeName : gsMode);
    }
  
    if(gbDisableProps) {
        RequestFrame(ClearProps);
    }
  
    GenerateGameID();
  
    SetGamestate(GAME_DEFAULT);
    SetGamemode(gsMode);
    gfPretime = GetGameTime() - 1;
    giVoteStatus = 0;

    CreateTimer(0.1, T_CheckPlayerStates, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientConnected(int client)
{
    if(!IsClientSourceTV(client)) {
        TryForceModel(client);
    }
}

public void OnClientPutInServer(int client)
{   
    if(IsGamestate(GAME_PAUSED)) {
        giPauseClient = client;
        CreateTimer(0.1, T_RePause, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
  
    if(!IsGamestate(GAME_MATCH, GAME_MATCHEX, GAME_MATCHWAIT)) {
        char name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));
        MC_PrintToChatAll("%t", "xms_join", name);
    }
  
    if(!IsFakeClient(client))
    {
        CreateTimer(1.0, T_AnnouncePlugin, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    
        // play connect sound
        if(!IsGamestate(GAME_MATCH, GAME_MATCHEX, GAME_MATCHWAIT)) {
            IfCookiePlaySound(ghCookieSounds, SOUND_CONNECT);
        }
    
        // cancel sound fade in case of early map change
        ClientCommand(client, "soundfade 0 0 0 0");
    }
  
    if(!IsClientSourceTV(client))
    {
        // instantly join spec before we determine the correct team
        giAllowClient = client;
        gbClientNoRagdoll[client] = true;
        FakeClientCommandEx(client, "jointeam %i", TEAM_SPECTATORS);
    }
}

public void OnClientCookiesCached(int client)
{
    // set default cookie values
    if(GetClientCookieInt(client, ghCookieMusic) == 0) {
        SetClientCookie(client, ghCookieMusic, "1");
        SetClientCookie(client, ghCookieSounds, "1");
        SetClientCookie(client, ghCookieColorR, "255");
        SetClientCookie(client, ghCookieColorG, "177");
        SetClientCookie(client, ghCookieColorB, "0");
    }
}

void PrepareSound(const char[] file)
{
    char path[PLATFORM_MAX_PATH];
    Format(path, sizeof(path), "sound/%s", file);
    PrecacheSound(file);
    AddFileToDownloadsTable(path);
}

void IfCookiePlaySound(Handle cookie, const char[] sound, bool unset=true)
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }
        
        if(AreClientCookiesCached(i)) {
            if(!GetClientCookieInt(i, cookie)) {
                continue;
            }
        }
        else if(!unset) {
            continue;
        }
        
        ClientCommand(i, "playgamesound %s", sound);
    }
}

public void OnClientPostAdminCheck(int client)
{
    if (!IsFakeClient(client)) {
        giClientMenuType[client] = 0;
        CreateTimer(1.1, T_AttemptInitMenu, client, TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(0.1, T_Welcome, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

void OnMatchPre()
{
    char status[MAX_BUFFER_LENGTH], servercmd[MAX_BUFFER_LENGTH];
      
    ServerCommandEx(status, sizeof(status), "status");
    PrintToConsoleAll("\n\n\n%s\n\n\n", status);
      
    if(GetConfigString(servercmd, sizeof(servercmd), "serverCommand_prematch")) {
        ServerCommand(servercmd);
    }
}

void OnMatchStart()
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }
        
        if(giClientMenuType[i] == 2) {
            ghMenuClient[i] = Menu_Base(i);
            ghMenuClient[i].Display(i, MENU_TIME_FOREVER);
        }
    }

    Forward_OnMatchStart();
}

void OnMatchCancelled()
{
    ServerCommand("exec server");
    SetGamemode(gsMode);
    Forward_OnMatchEnd(false);
}

void OnRoundEnd(bool match)
{
    gfEndtime = GetGameTime();
    
    if(match)
    {
        char servercmd[MAX_BUFFER_LENGTH];
    
        if(GetConfigString(servercmd, sizeof(servercmd), "serverCommand_postmatch")) {
            ServerCommand(servercmd);
        }
    
        Forward_OnMatchEnd(true);
    }
  
    if(giOvertime == 2) {
        MC_PrintToChatAll("%t", "xms_overtime_draw");
        giOvertime = 1;
    }
  
    CreateTimer(ghConVarChattime.IntValue < 20 ? 5.0 : 15.0, T_AnnounceNextmap, _, TIMER_FLAG_NO_MAPCHANGE);
    PlayRoundEndMusic();
}

public void OnGameRestarting(Handle convar, const char[] oldVal, const char[] newVal)
{
    if(StrEqual(newVal, "15")) {
        // trigger for some CTF maps
        Game_End();
    }
}

public Action OnMapChanging(int client, const char[] command, int args)
{
    if(gbPluginReady && client == 0 && (args || StrEqual(command, "changelevel_next")) ) {
        SetGamestate(GAME_CHANGING);
        SetGamemode(gsNextMode);
    }
}

public void OnMapEnd() {   
    gbTeamplay = ghConVarTeamplay.BoolValue;
    giOvertime = 0;
    ghOvertimer = INVALID_HANDLE;
}

public void OnClientDisconnect(int client)
{
    if(!IsFakeClient(client))
    {
        if(GetRealClientCount(IsGameMatch()) == 1 && !IsGamestate(GAME_CHANGING)) {
            // Last player has disconnected, revert to defaults
            LoadDefaults();
        }
        else if(gbClientInit[client] && !IsGameMatch()) {
            IfCookiePlaySound(ghCookieSounds, SOUND_DISCONNECT);
        }
    }
  
    gbClientInit[client] = false;
    giClientMenuType[client] = 0;
    giClientVoteCallTick[client] = 0;
}

public void OnClientDisconnect_Post(int client)
{
    if(client == giPauseClient || GetRealClientCount(false) == 0) {
        giPauseClient = 0;
    }
}

public Action T_CheckPlayerStates(Handle timer)
{
    static int wasTeam[MAXPLAYERS + 1] = -1;

    if(!IsGamestate(GAME_CHANGING))
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(!IsClientInGame(i))
            {
                if(wasTeam[i] != -1) // Client has just DC'd
                {
                    if(IsGameMatch() && wasTeam[i] != TEAM_SPECTATORS) {
                        // Client was participant in match
                        if(!IsGamestate(GAME_PAUSED)) {
                            ServerCommand("pause");
                            MC_PrintToChatAll("%t", "xms_auto_pause");
                        }
                    }
                }
                
                wasTeam[i] = -1;
                continue;
            }
            
            if(IsClientSourceTV(i)) {
                continue;
            }
            
            int team = GetClientTeam(i);

            if(wasTeam[i] == -1) {
                CreateTimer(1.0, T_TeamChange, i, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            }
            
            else if(team != wasTeam[i])
            {
                if(giAllowClient != i && (IsGameMatch() || IsGamestate(GAME_OVER) || (team == TEAM_SPECTATORS && !IsClientObserver(i)) || (IsClientObserver(i) && team != TEAM_SPECTATORS)))
                {
                    // Client has changed teams during match, or is a bugged spectator
                    // Usually caused by changing playermodel
                    ForceTeamSwitch(i, wasTeam[i]);
                }
            }
            
            wasTeam[i] = team;
            
            if(gbClientInit[i] && !IsGameOver())
            {
                // Save player states
                gsmTeams.SetValue(GetClientSteamID(i), (gbTeamplay ? GetClientTeam(i) : IsClientObserver(i) ? TEAM_SPECTATORS : TEAM_REBELS));
            }
        }
    }
    
    return Plugin_Continue;
}

public Action T_TeamChange(Handle timer, int client)
{
    if(IsClientInGame(client))
    {
        if(IsGamestate(GAME_PAUSED) || IsGameOver()) {
            return Plugin_Continue;
        }
        
        int team;
        gsmTeams.GetValue(GetClientSteamID(client), team);
        
        if(team > TEAM_SPECTATORS) {
            ForceTeamSwitch(client, team);
        }
        else if(!IsGameMatch())
        {
            if(team == TEAM_SPECTATORS) {
                MC_PrintToChat(client, "%t", "xms_auto_spectate");
            }
            else {
                CreateTimer(1.0 + client, T_JoinOptimalTeam, client, TIMER_FLAG_NO_MAPCHANGE);
                //ForceTeamSwitch(client, GetOptimalTeam());
            }
        }
        else {
            MC_PrintToChat(client, "%t", "xmsc_teamchange_deny");
        }
        
        gbClientInit[client] = true;
    }
    
    return Plugin_Stop;
}

void GenerateGameID()
{
    FormatTime(gsGameId, sizeof(gsGameId), "%y%m%d%H%M");
    Format(gsGameId, sizeof(gsGameId), "%s-%s", gsGameId, gsMap);
}

void SetGamestate(int newstate)
{
    if(newstate == giGamestate) {
        return;
    }
    else if(newstate == GAME_MATCHWAIT) {
        OnMatchPre();
        if(giOvertime == 2) {
            giOvertime = 1;
        }
    }
    else if(newstate == GAME_MATCH && giGamestate != GAME_PAUSED) {
        OnMatchStart();
    }
    else if(newstate == GAME_OVER) {
        OnRoundEnd(IsGameMatch());
        ServerCommand("sv_allow_point_servercommand disallow");
    }
    else if(newstate == GAME_DEFAULT) {
        ServerCommand("sv_allow_point_servercommand always");
        if(IsGameMatch()) {
            OnMatchCancelled();
        }
    }
    else if(newstate == GAME_CHANGING) {
        if(IsGamestate(GAME_OVER)) {
            CreateTimer(0.1, T_SoundFadeTrigger, _, TIMER_FLAG_NO_MAPCHANGE);
        }
        if(gbTeamplay) {
            InvertTeams();
        }
    }
 
    if(giOvertime == 1) {
        if(newstate == GAME_DEFAULT || newstate == GAME_MATCH && giGamestate != GAME_PAUSED) {
            CreateOverTimer(newstate == GAME_DEFAULT ? 0.0 : 2.9);
        }
    }
      
    if(gbRecording)
    {
        if(newstate == GAME_OVER) {
            CreateTimer(10.0, T_StopRecord, false, TIMER_FLAG_NO_MAPCHANGE);
        }
        else if(IsGamestate(GAME_OVER) && newstate == GAME_CHANGING) {
            StopRecord(false);
        }
        else if(newstate == GAME_DEFAULT || newstate == GAME_CHANGING) {
            StopRecord(true);
        }
    }
    else if(newstate == GAME_MATCHWAIT) {
        GenerateGameID();
        CreateTimer(1.1, T_StartRecord, _, TIMER_FLAG_NO_MAPCHANGE);
    }
  
    giGamestate = newstate;
    Forward_OnGamestateChanged(newstate);
}

void SetGamemode(const char[] mode)
{
    char servercmd[MAX_BUFFER_LENGTH];
    strcopy(gsNextMode, sizeof(gsNextMode), mode);
    strcopy(gsMode, sizeof(gsMode), mode);
  
    if(GetConfigString(servercmd, sizeof(servercmd), "command", "gamemodes", gsMode)) {
        ServerCommand(servercmd);
    }
}

void SetMapcycle()
{
    char mapcycle[PLATFORM_MAX_PATH];
    
    if((GetRealClientCount(false, false) <= 1 && StrEqual(gsDefaultMode, gsMode)) || !GetConfigString(mapcycle, sizeof(mapcycle), "mapcycle", "gamemodes", gsMode)) {
        // use default mapcycle when server is unpopulated on default mode (or if mapcycle for gamemode is undefined)
        Format(mapcycle, sizeof(mapcycle), "mapcycle_default.txt");
    }
    ServerCommand("mapcyclefile %s", mapcycle);
}

void ClearProps()
{
    for(int i = MaxClients; i < GetMaxEntities(); i++)
    {
        if(IsValidEntity(i))
        {
            char class[64];
            GetEntityClassname(i, class, sizeof(class));
      
            if(StrContains(class, "prop_physics") == 0) {
                AcceptEntityInput(i, "kill");
            }
        }
    }
}

void SetNoCollide(int client)
{
    SetEntData(client, OFFS_COLLISIONGROUP, 2, 4, true);
}

void TryForceModel(int client)
{
    if(gbTeamplay) {
        ClientCommand(client, "cl_playermodel models/police.mdl");
    }
    else {
        ClientCommand(client, "cl_playermodel models/humans/group03/%s_%02i.mdl", (GetRandomInt(0, 1) ? "male" : "female"), GetRandomInt(1, 7));
    }
}

void ForceTeamSwitch(int client, int team)
{
    giAllowClient = client;
    gbClientNoRagdoll[client] = IsPlayerAlive(client);
    FakeClientCommandEx(client, "jointeam %i", team);
}

public Action T_JoinOptimalTeam(Handle timer, int client)
{
    if(IsClientConnected(client) && IsClientInGame(client)) {
        ForceTeamSwitch(client, GetOptimalTeam());
    }
}

void InvertTeams()
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientConnected(i) && IsClientInGame(i) && !IsClientObserver(i) && !IsFakeClient(i))
        {
            int wasTeam;
            char id[32];
            GetClientAuthId(i, AuthId_Engine, id, sizeof(id));
            
            gsmTeams.GetValue(id, wasTeam);
            gsmTeams.SetValue(id, (wasTeam == TEAM_REBELS ? TEAM_COMBINE : TEAM_REBELS));
        }
    }
}

int GetOptimalTeam()
{
    int team = TEAM_REBELS;
    
    if(gbTeamplay) {
        int r = GetTeamClientCount(TEAM_REBELS), c = GetTeamClientCount(TEAM_COMBINE);
        team = r > c ? TEAM_COMBINE : c > r ? TEAM_REBELS : GetRandomInt(0, 1) ? TEAM_REBELS : TEAM_COMBINE;
    }
    
    return team;
}

public void OnTagsChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    if(!gbModTags) {
        AddPluginTag();
    }
}

public void OnTimelimitChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    if(giOvertime == 1) {
        CreateOverTimer();
    }
}

public void OnNextmapChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    strcopy(gsNextMap, sizeof(gsNextMap), newValue);
}

public Action T_RestartMap(Handle timer)
{
    SetGamemode(gsDefaultMode);
    ghConVarNextmap.SetString(gsMap);
    ServerCommand("changelevel_next");
    gbPluginReady = true;
}

void Game_Restart(int time = 1)
{
    ghConVarRestart.SetInt(time);
    PrintCenterTextAll("");
}

void LoadDefaults()
{
    SetGamemode(gsDefaultMode);
    SetMapcycle();
    ghConVarNextmap.SetString("");
    ServerCommand("changelevel_next");
}

bool GetMapByAbbrev(char[] buffer, int maxlen, const char[] abbrev)
{
    return view_as<bool>(GetConfigString(buffer, maxlen, abbrev, "maps", "abbreviations") > 0);
}

char DeprefixMap(const char[] map)
{
    char prefix[16], result[MAX_MAP_LENGTH];
    int pos = SplitString(map, "_", prefix, sizeof(prefix));
  
    StrCat(prefix, sizeof(prefix), "_");
  
    if(pos && IsItemDistinctInList(prefix, gsRemovePrefixes)) {
        strcopy(result, sizeof(result), map[pos]);
    }
    else {
        strcopy(result, sizeof(result), map);
    }
  
    return result;
}

int GetModeForMap(char[] buffer, int maxlen, const char[] map)
{
    if(!GetConfigString(buffer, maxlen, map, "maps", "defaultModes"))
    {
        char prefix[16];
        SplitString(map, "_", prefix, sizeof(prefix));
        StrCat(prefix, sizeof(prefix), "_*");
        
        if(!GetConfigString(buffer, maxlen, prefix, "maps", "defaultModes"))
        {
            if(!strlen(gsRetainModes)) {
                return -1;
            }
        
            strcopy(buffer, maxlen, gsRetainModes);
            if(!strlen(gsMode) || !IsItemDistinctInList(gsMode, buffer))
            {
                if(StrContains(buffer, ",")) {
                    SplitString(buffer, ",", buffer, maxlen);
                    return 0;
                }
            }
        
            strcopy(buffer, maxlen, gsMode);
            return 0;
        }
    }
    return 1;
}

int VoteTimeout(int client)
{
    if(GetRealClientCount(true, false, true) > giVoteMinPlayers)
    {  
        int t = (giVoteCooldown * Tickrate() + giClientVoteCallTick[client] - GetGameTickCount()) / Tickrate();
        if(t > 0) {
            return t;
        }
    }
    return 0;
}

public Action T_RemoveWeapons(Handle timer, int client)
{
    Client_RemoveAllWeapons(client);
}

public Action T_SetWeapons(Handle timer, int client)
{
    Client_RemoveAllWeapons(client);

    for(int i = 0; i < 16; i++)
    {
        if(!strlen(gsSpawnWeapon[i])) {
            break;
        }
    
        if(giSpawnAmmo[i][0] == -1 && giSpawnAmmo[i][1] == -1) {
            Client_GiveWeapon(client, gsSpawnWeapon[i], false);
        }
        else if(StrEqual(gsSpawnWeapon[i], "weapon_rpg") || StrEqual(gsSpawnWeapon[i], "weapon_frag")) {
            Client_GiveWeaponAndAmmo(client, gsSpawnWeapon[i], false, giSpawnAmmo[i][0], giSpawnAmmo[i][1], -1, -1);
        }
        else if(StrEqual(gsSpawnWeapon[i], "weapon_slam")) {
            Client_GiveWeaponAndAmmo(client, gsSpawnWeapon[i], false, -1, giSpawnAmmo[i][0], -1, -1);
        }
        else {
            Client_GiveWeaponAndAmmo(client, gsSpawnWeapon[i], false, giSpawnAmmo[i][0], giSpawnAmmo[i][1], 0, 0);  
        }
    }
}

public Action T_RePause(Handle timer)
{
    static int iter;
  
    if(giPauseClient > 0 && IsClientConnected(giPauseClient)) {
        FakeClientCommand(giPauseClient, "pause");
    }
  
    iter++;
    if(iter == 2) {
        giPauseClient = 0;
        iter = 0;
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}

public Action T_Welcome(Handle timer, int client)
{
    static int iter = 0;
    iter++;
    if(!IsClientInGame(client)) {
        if(iter >= 100) {
            return Plugin_Stop;
        }
    }
    else {
        char sWelcome[MAX_SAY_LENGTH];
        Format(sWelcome, sizeof(sWelcome), "%T", "xms_welcome", client, gsServerName);
        MC_PrintToChat(client, "%s {I}[XMS v%s]", sWelcome, PLUGIN_VERSION);
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public Action T_Adverts(Handle timer)
{
    static int iter = 1;
    char buffer[MAX_SAY_LENGTH];
  
    if(!GetRealClientCount() || IsGameMatch()) {
        return Plugin_Continue;
    }
  
    IntToString(iter, buffer, sizeof(buffer));
    if(!GetConfigString(buffer, sizeof(buffer), buffer, "serverAds"))
    {
        if(iter != -1 && !GetConfigString(buffer, sizeof(buffer), "1", "serverAds")) {
            return Plugin_Stop;
        }
        iter = 1;
    }
  
    MC_PrintToChatAll("%t", "xms_serverad", buffer);
    iter++;
  
    return Plugin_Continue;
}

public Action T_AnnouncePlugin(Handle timer, int client)
{
    static int iter;
    
    if(IsClientInGame(client) && iter < 5)
    {
        PrintCenterText(client, "eXtended Match System - %s", PLUGIN_URL);
        iter++;
        return Plugin_Continue;
    }
    
    iter = 0;
    return Plugin_Stop;
}

public Action T_AnnounceNextmap(Handle timer)
{
    if(strlen(gsNextMap) && !IsGamestate(GAME_CHANGING)) {
        MC_PrintToChatAll("%t", "xms_nextmap_announce", gsNextMode, DeprefixMap(gsNextMap), RoundFloat(GetTimeRemaining(true)));
    }
}

void PlayRoundEndMusic()
{
    static int last_rand = -1;
    int rand;
    float fadetime;
  
    do(rand = GetRandomInt(0, 5)); while(last_rand == rand);
    last_rand = rand;
    fadetime = ghConVarChattime.IntValue - 4.5;
  
    IfCookiePlaySound(ghCookieMusic, gsMusicPath[rand]);
    CreateTimer(fadetime < 5 ? 0.1 : fadetime, T_SoundFadeTrigger, _, TIMER_FLAG_NO_MAPCHANGE);
}
  
public Action T_SoundFadeTrigger(Handle timer)
{
    ClientCommandAll("soundfade 100 1 0 5");
    SetGamestate(GAME_CHANGING);
}


/**************************************************************************************************
 *** SourceTV
**************************************************************************************************/
public Action T_StartRecord(Handle timer)
{
    StartRecord();
}

void StartRecord()
{
    if(!ghConVarTv.BoolValue) {
        LogError("SourceTV is not active!");
    }
    
    if(!gbRecording) {
        ServerCommand("tv_name \"%s - %s\";tv_record %s/incomplete/%s", gsServerName, gsGameId, gsDemoPath, gsGameId);
        gbRecording = true;
    }
}

public Action T_StopRecord(Handle timer, bool isEarly)
{
    StopRecord(isEarly);
}

void StopRecord(bool discard)
{
    if(gbRecording)
    {
        char oldPath[PLATFORM_MAX_PATH], newPath[PLATFORM_MAX_PATH];
        Format(oldPath, PLATFORM_MAX_PATH, "%s/incomplete/%s.dem", gsDemoPath, gsGameId);

        ServerCommand("tv_stoprecord");
        gbRecording = false;
        
        if(!discard)
        {
            Format(newPath, PLATFORM_MAX_PATH, "%s/%s.dem", gsDemoPath, gsGameId);
            GenerateDemoTxt(newPath);
            RenameFile(newPath, oldPath, true);

            if(strlen(gsDemoURL)) {
                MC_PrintToChatAll("%t", "xms_announcedemo", gsDemoURL, gsGameId, gsDemoExtension);
            }
            
        }
        else {
            DeleteFile(oldPath, true);
        }
    }
}

void GenerateDemoTxt(const char[] demopath)
{
    static char ip[16];
    static int port = -1;
    
    if(!strlen(ip)) {
        FindConVar("ip").GetString(ip, sizeof(ip));       
        port = FindConVar("hostport").IntValue;        
    }
    
    char path[PLATFORM_MAX_PATH], time[32], title[256], players[2][2048];
    bool duel = GetRealClientCount(true, false, false) == 2;
    File meta;
    
    Format(path, PLATFORM_MAX_PATH, "%s.txt", demopath);
    FormatTime(time, sizeof(time), "%d %b %Y");

    if(gbTeamplay) {
        Format(players[0], sizeof(players[]), "THE COMBINE [Score: %i]:\n", GetTeamScore(TEAM_COMBINE));
        Format(players[1], sizeof(players[]), "REBEL FORCES [Score: %i]:\n", GetTeamScore(TEAM_REBELS));
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i) || IsClientObserver(i)) {
            continue;
        }
        
        int z = gbTeamplay ? GetClientTeam(i) - 2 : 0;
        Format(players[z], sizeof(players[]), "%s\"%N\" %s [%i kills, %i deaths]\n", players[z], i, GetClientSteamID(i), GetClientFrags(i), GetClientDeaths(i));
                
        if(duel) {
            Format(title, sizeof(title), "%s%N%s", title, i, !strlen(title) ? " vs " : "");
        }
    }

    if(gbTeamplay) {
        Format(title, sizeof(title), "%s %iv%i - %s - %s", gsMode, GetTeamClientCount(TEAM_REBELS), GetTeamClientCount(TEAM_COMBINE), gsMap, time);
    }
    else if(duel) {
        Format(title, sizeof(title), "%s 1v1 (%s) - %s - %s", gsMode, title, gsMap, time);
    }
    else {
        Format(title, sizeof(title), "%s ffa - %s - %s", gsMode, gsMap, time);
    }
    
    meta = OpenFile(path, "w", true);
    meta.WriteLine(title);
    meta.WriteLine("");
    meta.WriteLine(players[0]);
    if(gbTeamplay) {
        meta.WriteLine(players[1]);
    }
    meta.WriteLine("Server: \"%s\" [%s:%i]", gsServerName, ip, port);
    meta.WriteLine("Version: %i [XMS v%s]", GameVersion(), PLUGIN_VERSION);
                
    CloseHandle(meta);
}


/**************************************************************************************************
 *** Events
**************************************************************************************************/
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(gbUnlimitedAux) {
        int bits = GetEntProp(client, Prop_Send, "m_bitsActiveDevices");
        if(bits & BITS_SPRINT) {
            SetEntPropFloat(client, Prop_Data, "m_flSuitPowerLoad", 0.0);
            SetEntProp(client, Prop_Send, "m_bitsActiveDevices", bits & ~BITS_SPRINT);
        }
    }
    
    return Plugin_Changed;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if(IsFakeClient(client)) {
        return Plugin_Continue;
    }
        
    if(IsGamestate(GAME_MATCHWAIT)) {
        SetEntityMoveType(client, MOVETYPE_NONE);
        CreateTimer(0.1, T_RemoveWeapons, client);
        return Plugin_Continue;
    }

    if(giSpawnHealth != -1) {
        SetEntProp(client, Prop_Data, "m_iHealth", giSpawnHealth > 0 ? giSpawnHealth : 1);
    }
    if(giSpawnSuit != -1) {
        SetEntProp(client, Prop_Data, "m_ArmorValue", giSpawnSuit > 0 ? giSpawnSuit : 0);
    }
    if(gbDisableCollisions) {
        RequestFrame(SetNoCollide, client);
    }
    if(!StrEqual(gsSpawnWeapon[0], "default")) {
        CreateTimer(0.1, T_SetWeapons, client);
    }

    return Plugin_Continue;
}
    
public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
        
    if(gbClientNoRagdoll[client])
    {
        int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
        if(ragdoll >= 0 && IsValidEntity(ragdoll)) {
            RemoveEdict(ragdoll);
        }
        
        gbClientNoRagdoll[client] = false;
    }
        
    return Plugin_Continue;
}
    
public Action Event_GameMessage(Event event, const char[] eventname, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if(client && IsClientInGame(client))
    {
        if(!IsGameMatch() || GetClientTeam(client) != TEAM_SPECTATORS)
        {
            char name[MAX_NAME_LENGTH];
            GetClientName(client, name, sizeof(name));
            
            if(StrEqual(eventname, "player_disconnect"))
            {
                char reason[32];
                GetEventString(event, "reason", reason, sizeof(reason));
                MC_PrintToChatAll("%t", IsGameMatch() ? "xms_disconnect_match" : "xms_disconnect", name, reason);
            }
            else if(StrEqual(eventname, "player_changename"))
            {
                char newname[MAX_NAME_LENGTH];
                GetEventString(event, "newname", newname, sizeof(newname));
                MC_PrintToChatAll("%t", "xms_changename", name, newname);
            }
        }
    }
        
    // block other messages
    event.BroadcastDisabled = true;
        
    return Plugin_Continue;
}
    
public Action Event_RoundStart(Handle event, const char[] name, bool noBroadcast)
{
    gfPretime = GetGameTime();
        
    if(IsGamestate(GAME_MATCHWAIT))
    {
        for(int i = MaxClients; i < GetMaxEntities(); i++)
        {
            if(IsValidEntity(i) && Phys_IsPhysicsObject(i)) {
                Phys_EnableMotion(i, false); // Lock props on matchwait
            }
        }
    }
}

public Action UserMsg_TextMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
    char message[70];
    BfReadString(msg, message, sizeof(message), true);
    
    // block game chat spam

    if(StrContains(message, "[SM] Time remaining for map") != -1 || StrContains(message, "[SM] No timelimit for map") != -1 || StrContains(message, "[SM] This is the last round!!") != -1)
    {
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public Action UserMsg_VGUIMenu(UserMsg msg_id, Handle msg, const players[], int playersNum, bool reliable, bool init)
{
    char buffer[10];
    
    BfReadString(msg, buffer, sizeof(buffer));
    if(StrEqual(buffer, "scores")) {
        RequestFrame(SetGamestate, GAME_OVER);
    }
    return Plugin_Continue;
}


/**************************************************************************************************
 *** HUD stuff
**************************************************************************************************/
public Action T_KeysHud(Handle timer)
{
    if(!IsGamestate(GAME_OVER, GAME_CHANGING, GAME_PAUSED))
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
                continue;
            }
            
            if(GetClientButtons(i) & IN_SCORE || (!IsClientObserver(i) && !gbShowKeys)) {
                continue;
            }

            char hudtext[1024];
            int target = IsClientObserver(i) ? GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") : i;
                
            if(GetEntProp(i, Prop_Send, "m_iObserverMode") != 7 && target > 0 && IsClientConnected(target) && IsClientInGame(target))
            {
                int buttons = GetClientButtons(target);
                float angles[3];
                GetClientAbsAngles(i, angles);
                    
                Format(hudtext, sizeof(hudtext), "health: %i   suit: %i\nvel: %03i  %s   %0.1fº\n%s         %s          %s\n%s     %s     %s",
                  GetClientHealth(target),
                  GetClientArmor(target),
                  GetClientVelocity(target),
                  (buttons & IN_FORWARD)   ? "↑"       : "  ", 
                  angles[1],
                  (buttons & IN_MOVELEFT)  ? "←"       : "  ", 
                  (buttons & IN_SPEED)     ? "+SPRINT" : "        ", 
                  (buttons & IN_MOVERIGHT) ? "→"       : "  ",
                  (buttons & IN_DUCK)      ? "+DUCK"   : "    ",
                  (buttons & IN_BACK)      ? "↓"       : "  ",
                  (buttons & IN_JUMP)      ? "+JUMP"   : "    "
                );
                SetHudTextParams(-1.0, 0.7, 0.3, GetClientCookieInt(i, ghCookieColorR, 0, 255), GetClientCookieInt(i, ghCookieColorG, 0, 255), GetClientCookieInt(i, ghCookieColorB, 0, 255), 255, 0, 0.0, 0.0, 0.0);            
            }
            else {
                SetHudTextParams(-1.0, -0.02, 0.3, GetClientCookieInt(i, ghCookieColorR, 0, 255), GetClientCookieInt(i, ghCookieColorG, 0, 255), GetClientCookieInt(i, ghCookieColorB, 0, 255), 255, 0, 0.0, 0.0, 0.0);
                Format(hudtext, sizeof(hudtext), "%T\n%T", "xms_hud_spec1", i, "xms_hud_spec2", i);
            }
        
            ShowSyncHudText(i, ghKeysHud, hudtext);
        }
    }
}

public Action T_TimeHud(Handle timer)
{
    static int iter;
    bool red = (giOvertime == 2);
    char hudtext[24];

    if(IsGamestate(GAME_MATCHWAIT, GAME_CHANGING, GAME_PAUSED))
    {
        Format(hudtext, sizeof(hudtext), ". . %s%s%s", iter >= 20 ? ". " : "", iter >= 15 ? ". " : "", iter >= 10 ? "." : "");
        iter++;
        if(iter >= 25) {
            iter = 0;
        }
    }
    
    else if(!IsGamestate(GAME_OVER) && ghConVarTimelimit.BoolValue)
    {
        float t = GetTimeRemaining(false);
        int h = RoundToNearest(t) / 3600,
          s = RoundToNearest(t) % 60,
         m = RoundToNearest(t) / 60 - (h ? (h * 60) : 0);
        red = (t < 60);
            
        if(!h)
        {
            if(t >= 10)
            {
                if(t >= 60) {
                    Format(hudtext, sizeof(hudtext), "%s%i:%02i", hudtext, m, s);
                }
                else {
                    Format(hudtext, sizeof(hudtext), "%s%i", hudtext, RoundToNearest(t));
                }
            }
            else {
                Format(hudtext, sizeof(hudtext), "%s%.1f", hudtext, t);
            }
        }
        else {
            Format(hudtext, sizeof(hudtext), "%s%ih %i:%02i", hudtext, h, m, s);
        }
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i) || !IsClientInGame(i) || (IsFakeClient(i) && !IsClientSourceTV(i)) ) {
            continue;
        }
        
        char itext[24];
        bool margin = IsClientObserver(i) && !IsClientSourceTV(i);

        if(IsGamestate(GAME_OVER)) {
            Format(itext, sizeof(itext), "%T", "xms_hud_gameover", i);
        }
        else if(IsGamestate(GAME_MATCHEX, GAME_OVERTIME)) {
            Format(itext, sizeof(itext), "%T\n%s", "xms_hud_overtime", i, hudtext);    
        }
        else {
            strcopy(itext, sizeof(itext), hudtext);
        }
        
        if(strlen(itext))
        {
            if(red) {
                SetHudTextParams(-1.0, margin ? 0.03 : 0.01, 0.3, 220, 10, 10, 255, 0, 0.0, 0.0, 0.0);
            }
            else {
                SetHudTextParams(-1.0, margin ? 0.03 : 0.01, 0.3, GetClientCookieInt(i, ghCookieColorR, 0, 255), GetClientCookieInt(i, ghCookieColorG, 0, 255), GetClientCookieInt(i, ghCookieColorB, 0, 255), 255, 0, 0.0, 0.0, 0.0);
            }
            ShowSyncHudText(i, ghTimeHud, itext);            
        }
    }
}

public Action T_Voting(Handle timer)
{
    static int iter;
    static char motion[128];
    int votes, yays, nays, lead, lose;
    int yaypercent, naypercent;
    char text[1024];
    
    if(!giVoteStatus) {
        iter = 0;
        return Plugin_Continue;
    }

    if(!iter)
    {
        strcopy(motion, sizeof(motion), gsVoteMotion);
        if(giVoteType == VOTE_RUN) {
            int pos = SplitString(gsVoteMotion, ":", motion, sizeof(motion));
            Format(motion, sizeof(motion), "%s:%s", motion, DeprefixMap(gsVoteMotion[pos]));
        }
    }

    // tally votes
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }
        
        if((giVoteType != VOTE_MATCH || !IsClientObserver(i)) && giClientVote[i] != 0) {
            giClientVote[i] == 1 ? yays++ : nays++;
            votes++;
        }
    }

    lead = yays >= nays ? yays : nays;

    if(votes && yays == nays) {
        yaypercent = 50;
        naypercent = 50;
    }
    else {
        yaypercent = RoundToNearest(yays ? yays / votes * 100.0 : 0.0);
        naypercent = RoundToNearest(nays ? nays / votes * 100.0 : 0.0);
    }

    lose = votes - lead;
    
    // format hud
    Format(text, sizeof(text), "ᴠᴏᴛᴇ - %s%s\n▪ %s: %i (%i%%%%)\n▪ %s:  %i (%i%%%%)\n▪ abstain: %i",
      giVoteType == VOTE_RUN ? "run " : giVoteType == VOTE_RUNNEXT ? "runNext " : "", motion,
      lead == yays ? "YES" : "yes", yays, yaypercent,
      lead == nays ? "NO" : "no", nays, naypercent,
      GetRealClientCount(true, false, giVoteType != VOTE_MATCH) - votes
    );
    
    // calc result
    if(GetRealClientCount(true, false, giVoteType != VOTE_MATCH) - votes + lose <= lead || iter >= giVoteMaxTime) {
        giVoteStatus = yays > nays ? 2 : -1;
    }
    else
    {
        // hud dance
        Format(text, sizeof(text), "%s\n%is remaining..", text, giVoteMaxTime - iter);
        for(int i = 5; i <= giVoteMaxTime; i += 5) {
            if(giVoteMaxTime - i >= iter) {
                StrCat(text, sizeof(text), ".");
            }
        }
    }
        
    switch(giVoteStatus)
    {
        case -1: {
            // vote failed
            SetHudTextParams(0.01, 0.11, 1.01, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);                
        }
        case 2:
        {
            // vote succeeded
            SetHudTextParams(0.01, 0.11, 1.01, 0, 255, 0, 255, 0, 0.0, 0.0, 0.0);

            if(giVoteType != VOTE_CUSTOM)
            {
                if(giVoteType == VOTE_MATCH)
                {
                    if(!IsGameMatch()) {
                        Start();
                    }
                    else {
                        Cancel();
                    }                        
                }
                else
                {
                    char mode[MAX_MODE_LENGTH], map[MAX_MAP_LENGTH];
                    
                    strcopy(map, sizeof(map), gsVoteMotion[SplitString(gsVoteMotion, ":", mode, sizeof(mode))]);
                    strcopy(gsNextMode, sizeof(gsNextMode), mode);
                    ghConVarNextmap.SetString(map);
                        
                    if(giVoteType != VOTE_RUN) {
                        MC_PrintToChatAll("%t", "xmsc_run_next", mode, DeprefixMap(map));
                    }
                    else {
                        Run();
                    }
                }
            }
        }
        default: {
            // vote ongoing
        }
    }
        
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }
        

        if(giVoteStatus != 1)
        {
            if(!AreClientCookiesCached(i) || GetClientCookieInt(i, ghCookieSounds) == 1) {
                ClientCommand(i, "playgamesound %s", giVoteStatus == -1 ? SOUND_VOTEFAILED : SOUND_VOTESUCCESS);
            }
            else {
                MC_PrintToChat(i, "%sVote %s.", giVoteStatus == -1 ? "{E}" : "{H}", giVoteStatus == -1 ? "failed" : "succeeded");
            }
        }
        else {
            int r = GetClientCookieInt(i, ghCookieColorR, 0, 255),
              g = GetClientCookieInt(i, ghCookieColorG, 0, 255),
             b = GetClientCookieInt(i, ghCookieColorB, 0, 255);
            SetHudTextParams(0.01, 0.11, 1.01, r, g, b, 255, view_as<int>(giVoteMaxTime - iter <= 5), 0.0, 0.0, 0.0);                   
        }
        
        ShowSyncHudText(i, ghVoteHud, text);
    }
    
    if(giVoteStatus != 1) {
        giVoteStatus = 0;
    }

    iter++;
    return Plugin_Continue;
}


/**************************************************************************************************
 *** Overtime
**************************************************************************************************/
void CreateOverTimer(float delay=0.0)
{
    if(ghOvertimer != INVALID_HANDLE) {
        KillTimer(ghOvertimer);
        ghOvertimer = INVALID_HANDLE;
    }
        
    ghOvertimer = CreateTimer(GetTimeRemaining(false) - 0.1 + delay, T_PreOvertime, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action T_PreOvertime(Handle timer)
{
    if(GetRealClientCount(true, true, false) > 1)
    {
        if(gbTeamplay) {
            if(GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE) == 0 && GetTeamClientCount(TEAM_REBELS) && GetTeamClientCount(TEAM_COMBINE)) {
                StartOvertime();
            }
        }
        else if(!GetTopPlayer(false)) {
            StartOvertime();
        }
    }

    ghOvertimer = INVALID_HANDLE;
}

void StartOvertime()
{
    giOvertime = 2;
    ghConVarTimelimit.IntValue += OVERTIME_TIME;
    
    if(gbTeamplay || GetRealClientCount(true, false, false) == 2) {
        MC_PrintToChatAll("%t", "xms_overtime_start1", gbTeamplay ? "team" : "player");
    }
    else {
        MC_PrintToChatAll("%t", "xms_overtime_start2");
    }
    CreateTimer(0.1, T_Overtime, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    SetGamestate(IsGamestate(GAME_MATCH) ? GAME_MATCHEX : GAME_OVERTIME);
}
    
public Action T_Overtime(Handle timer)
{
    int result;
        
    if(giOvertime != 2) {
        return Plugin_Stop;
    }
        
    if(gbTeamplay)
    {
        result = GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE);
        
        if(result == 0) {
            return Plugin_Continue;
        }
        
        MC_PrintToChatAll("%t", "xms_overtime_teamwin", result < 0 ? "Combine" : "Rebels");
    }
    else
    {
        result = GetTopPlayer(false);
        
        if(!result) {
            return Plugin_Continue;
        }
        
        char name[MAX_NAME_LENGTH];
        GetClientName(result, name, sizeof(name));
        
        MC_PrintToChatAll("%t", "xms_overtime_win", name);
    }
    
    Game_End();
    giOvertime = 1;
    
    return Plugin_Stop;
}


/**************************************************************************************************
 *** Menus
**************************************************************************************************/
public Action T_AttemptInitMenu(Handle timer, int client)
{
    if(!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client) || giClientMenuType[client] == 2) {
        return Plugin_Stop;
    }
    
    QueryClientConVar(client, "cl_showpluginmessages", ShowMenuIfVisible, client);
    return Plugin_Continue;
}

public void ShowMenuIfVisible(QueryCookie cookie, int client, ConVarQueryResult result, char[] cvarName, char[] cvarValue)
{
    if(!StringToInt(cvarValue))
    {
        if(giClientMenuType[client] == 0) {
            MC_PrintToChat(client, "%t", "xms_menu_fail");

            // keep trying in the background
            CreateTimer(2.0, T_AttemptInitMenu, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            giClientMenuType[client] = 1;
        }
    }
    else
    {
        MC_PrintToChat(client, "%t", "xms_menu_announce");
        giClientMenuType[client] = 2;
        ghMenuClient[client] = Menu_Base(client);
        ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
    }
}

Menu Menu_Base(int client)
{
    static int lan = -1;
    if(lan == -1) {
        lan = FindConVar("sv_lan").BoolValue;
    }
    
    Menu menu = new Menu(MenuLogic_Base);
    char title[512];
    char item[32];
    
    Format(title, sizeof(title), "%T", IsGameMatch() ? "xms_menu_base_matchpre" : "xms_menu_base_pre", client);
    Format(title, sizeof(title), "%s\n%T", title, "xms_menu_base", client, DeprefixMap(gsMap), gsMode, strlen(gsModeName)?"(":"", gsModeName, strlen(gsModeName)?")":"", gsServerName, Tickrate(), lan ? "lan" : "dedicated", strlen(gsServerAdmin) ? "admin:   " : "", gsServerAdmin, strlen(gsServerAdmin) ? "\n" : "", strlen(gsServerURL) ? "website: " : "", gsServerURL, strlen(gsServerURL)     ? "\n" : "", GameVersion(), PLUGIN_VERSION);
    
    menu.SetTitle(title);

    if(!IsGameMatch()) {
        Format(item, sizeof(item), "%T", "xms_menu_base_team", client);
        menu.AddItem("team", item);
    }
    else {
        Format(item, sizeof(item), "%T", "xms_menu_base_pause", client);
        menu.AddItem("pause", item);
    }
    Format(item, sizeof(item), "%T", "xms_menu_base_voting", client);
    menu.AddItem("voting", item);
    Format(item, sizeof(item), "%T", "xms_menu_base_players", client);
    menu.AddItem("players", item);
    Format(item, sizeof(item), "%T", "xms_menu_base_settings", client);
    menu.AddItem("settings", item);
    Format(item, sizeof(item), "%T", "xms_menu_base_servers", client);
    menu.AddItem("servers", item);
    
    SetMenuOptionFlags(menu, MENU_NO_PAGINATION);
    return menu;
}

public int MenuLogic_Base(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select)
        {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
                
            if(StrEqual(info, "team")) {
                ghMenuClient[client] = Menu_Team(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
            else if(StrEqual(info, "players")) {
                ghMenuClient[client] = Menu_Players(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
            else if(StrEqual(info, "settings")) {
                ghMenuClient[client] = Menu_Settings(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
            else if(StrEqual(info, "voting")) {
                ghMenuClient[client] = Menu_Voting(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
            else if(StrEqual(info, "pause")) {
                FakeClientCommand(client, "pause");
                ghMenuClient[client] = Menu_Base(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
            else if(StrEqual(info, "servers")) {
                ghMenuClient[client] = Menu_Servers(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }                
        }
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            if(param == MenuCancel_Exit || param == MenuCancel_ExitBack) {
                ghMenuClient[client] = Menu_Base(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
        }
    }
}


Menu Menu_Servers(int client)
{
    Menu menu = new Menu(MenuLogic_Servers);
    char serverlist[512], servers[32][32];
    int count = GetConfigKeys(serverlist, sizeof(serverlist), "otherServers");
    
    char title[512];
    Format(title, sizeof(title), "%T", "xms_menu_servers", client);
    menu.SetTitle(title);
    
    ExplodeString(serverlist, ",", servers, count, 32);
    for(int i = 0; i < count; i++) {
        char address[64];
        GetConfigString(address, sizeof(address), servers[i], "otherServers");
        menu.AddItem(address, servers[i]);
    }
    
    return menu;
}

public int MenuLogic_Servers(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select) {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
            DisplayAskConnectBox(client, 30.0, info);
            
            ghMenuClient[client] = Menu_Base(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
        } 
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = Menu_Base(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
        }
    }
}


Menu Menu_Team(int client)
{
    Menu menu = new Menu(MenuLogic_Team);
    char title[512];
    Format(title, sizeof(title), "%T", "xms_menu_team", client);
    menu.SetTitle(title);
    
    menu.AddItem("Rebels", "Rebels");
    if(gbTeamplay) {
        menu.AddItem("Combine", "Combine");
    }
    menu.AddItem("Spectators", "Spectators");

    return menu;
}

public int MenuLogic_Team(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select) {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
            FakeClientCommand(client, "jointeam %i", StrEqual(info, "Rebels") ? TEAM_REBELS : StrEqual(info, "Combine") ? TEAM_COMBINE : TEAM_SPECTATORS);
            ghMenuClient[client] = Menu_Base(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = Menu_Base(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
    }
}


Menu Menu_Start(int client)
{
    Menu menu = new Menu(MenuLogic_Start);
    char desc[512];

    if(GetRealClientCount(true, false, false) == 1) {
        Format(desc, sizeof(desc), "%T", "xms_menu_start_denycount", client);
        menu.SetTitle(desc);
    }
    else if(IsModeMatchable(gsMode)) {
        Format(desc, sizeof(desc), "%T", "xms_menu_start", client);
        menu.SetTitle(desc);
        
        Format(desc, sizeof(desc), "%T", "xms_menu_start_confirm", client);
        menu.AddItem("yes", desc);
    }
    else {
        Format(desc, sizeof(desc), "%T", "xms_menu_start_denymode", client);
        menu.SetTitle(desc);
    }
    
    Format(desc, sizeof(desc), "%T", "xms_menu_start_cancel", client);
    menu.AddItem("no", desc);
    
    return menu;
}

public int MenuLogic_Start(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select)
        {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
                
            if(StrEqual(info, "yes")) {
                FakeClientCommand(client, "start");
                ghMenuClient[client] = Menu_Base(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
            }
            else {
                ghMenuClient[client] = Menu_Voting(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
            }
        }
            
        if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = Menu_Voting(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);    
        }
    }
}


Menu Menu_Decision(int client)
{
    Menu menu = new Menu(MenuLogic_Decision);
    
    char desc[512];
    Format(desc, sizeof(desc), "%T", "xms_menu_decision", client, gsVoteMotion);
    menu.SetTitle(desc);
    
    Format(desc, sizeof(desc), "%T", "xms_menu_decision_yes", client);
    menu.AddItem("yes", desc);
    
    Format(desc, sizeof(desc), "%T", "xms_menu_decision_no", client);
    menu.AddItem("no", desc);
    
    Format(desc, sizeof(desc), "%T", "xms_menu_decision_abstain", client);
    menu.AddItem("abstain", desc);

    return menu;
}

public int MenuLogic_Decision(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select)
        {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
            
            if(StrEqual(info, "yes") || StrEqual(info, "no")) {
                FakeClientCommand(client, info);
            }
        }
        
        ghMenuClient[client] = Menu_Base(client);
        ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
    }
}


Menu Menu_Mode(int client)
{
    Menu menu = new Menu(MenuLogic_Mode);
    char list[512], modes[512][MAX_MODE_LENGTH];
    int count = GetConfigKeys(list, sizeof(list), "gamemodes");

    char title[512];
    Format(title, sizeof(title), "%T", "xms_menu_mode", client, gsMode);
    menu.SetTitle(title);

    ExplodeString(list, ",", modes, count, MAX_MODE_LENGTH);
    for(int i = 0; i < count; i++)
    {
        if(!StrEqual(modes[i], gsMode))
        {
            char desc[24];
            
            if(GetConfigString(desc, sizeof(desc), "name", "gamemodes", modes[i]) && !StrEqual(desc, modes[i], false)) {
                Format(desc, sizeof(desc), "%s (%s)", modes[i], desc);
            }
            else {
                strcopy(desc, sizeof(desc), modes[i]);
            }
            
            menu.AddItem(modes[i], desc);
        }
    }

    return menu;
}

public int MenuLogic_Mode(Menu menu, MenuAction action, int client, int param)
{   
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select) {
            char info[MAX_MAP_LENGTH];
            menu.GetItem(param, info, sizeof(info));
            ghMenuClient[client] = Menu_Map(client, info);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);                 
        }
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = Menu_Voting(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
    }
}


Menu Menu_Model(int client)
{
    Menu menu = new Menu(MenuLogic_Model);
    char filename[70];
    
    char title[512];
    Format(title, sizeof(title), "%T", "xms_menu_model", client);
    menu.SetTitle(title);
    
    for(int i = 0; i < sizeof(gsModelPath); i++) {
        File_GetFileName(gsModelPath[i], filename, sizeof(filename));
        menu.AddItem(gsModelPath[i], filename);
    }
    
    return menu;
}

public int MenuLogic_Model(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select) {
            char info[70];
            menu.GetItem(param, info, sizeof(info));
            ClientCommand(client, "cl_playermodel %s", info);
        }
        
        ghMenuClient[client] = Menu_Settings(client);        
        ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
    }
}


Menu Menu_Map(int client, const char[] gamemode, bool byLetter=false, const char[] filter=NULL_STRING)
{   
    char mapcycle[PLATFORM_MAX_PATH], mapname[MAX_MAP_LENGTH], runcommand[64], commandtitle[64], ref[32], title[256];
    File file;
    int count;
    Menu menu = new Menu(MenuLogic_Map);
    
    if(byLetter)
    {
        if(StrEqual(filter, NULL_STRING))
        {
            
            Format(title, sizeof(title), "%T", "xms_menu_map_filter", client);
            menu.SetTitle(title);
    
            char letters[28], letter[2];
            Format(letters, sizeof(letters), "abcdefghijklmnopqrstuvwxyz0");
            for(int i = 0; i < sizeof(letters); i++) {
                strcopy(letter, sizeof(letter), letters[i]);
                Format(ref, sizeof(ref), "byletter-%s%s%s", gamemode, strlen(gamemode) ? "-" : NULL_STRING, letter);
                menu.AddItem(ref, StrEqual(letter, "0") ? "0-9" : letter);
            }
            
            return menu;
        }
    }
    else if(!StrEqual(gamemode, gsMode))
    {
        Format(title, sizeof(title), "%T", "xms_menu_map_mode", client, gamemode);
        Format(runcommand, sizeof(runcommand), "%s %s", gamemode, mapname);
                
        if(IsItemDistinctInList(gsMode, gsRetainModes) && IsItemDistinctInList(gamemode, gsRetainModes)) {
            Format(commandtitle, sizeof(commandtitle), "%T", "xms_menu_map_keepcurrent", client);
            menu.AddItem(runcommand, commandtitle);
        }
    }
    
    if(!byLetter) {
        Format(ref, sizeof(ref), "byletter-%s", gamemode);
        Format(commandtitle, sizeof(commandtitle), "%T", "xms_menu_map_sort", client);
        menu.AddItem(ref, commandtitle);
    }

    Format(mapcycle, sizeof(mapcycle), "cfg/%s", GetConfigString(mapcycle, sizeof(mapcycle), "mapcycle", "gamemodes", gamemode) ? mapcycle : "mapcycle_default.txt");
    
    file = OpenFile(mapcycle, "rt", true);
    if(file != null)
    {
        while (!file.EndOfFile() && file.ReadLine(mapname, sizeof(mapname)))
        {
            int len = strlen(mapname);
                
            if(mapname[0] == ';' || !IsCharAlpha(mapname[0])) {
                continue;
            }

            for(int i = 0; i < len; i++) {
                if(IsCharSpace(mapname[i])) {
                    mapname[i] = '\0';
                    break;
                }
            }
            
            if(!IsMapValid(mapname)) {
                continue;
            }
                
            Format(runcommand, sizeof(runcommand), "%s %s", gamemode, mapname);
            Format(mapname, sizeof(mapname), DeprefixMap(mapname));
            
            if(!byLetter || StrContains(mapname, filter, false) == 0 || ( StrEqual(filter, "0") && IsCharNumeric(mapname[0]) )) {
                count++;
                menu.AddItem(runcommand, mapname);
            }
        }
        
        file.Close();
    }
    else {
        LogError("Couldn't read mapcyclefile: %s", mapcycle);
    }
    
    if(!count) {
        Format(commandtitle, sizeof(commandtitle), "%T", "xms_menu_map_sortnone", client);
        menu.AddItem("", commandtitle);
    }
    
    if(!byLetter) {
        Format(title, sizeof(title), "%T", "xms_menu_map_list", client, count);
    }
    else {
        Format(title, sizeof(title), "%T", "xms_menu_map_sortlist", client, count, StrEqual(filter, "0") ? "0-9" : filter);
    }
    menu.SetTitle(title);
    
    return menu;
}
    
public int MenuLogic_Map(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select)
        {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
                
            if(StrContains(info, "byletter") == 0)
            {
                char gamemode[MAX_MODE_LENGTH], letter[2];
                int pos = SplitString(info[9], "-", gamemode, sizeof(gamemode));
                    
                if(pos == -1) {
                    strcopy(gamemode, sizeof(gamemode), info[9]);
                }
                else {
                    strcopy(letter, sizeof(letter), info[9+pos]);
                }
                
                ghMenuClient[client] = Menu_Map(client, gamemode, true, letter);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
            else {
                ghMenuClient[client] = Menu_Run(client, info);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
        }
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = Menu_Voting(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
    }
}


Menu Menu_Run(int client, const char[] command)
{
    char ref[64], desc[256];
    Menu menu = new Menu(MenuLogic_Run);

    Format(desc, sizeof(desc), "%T", "xms_menu_run", client, command);
    menu.SetTitle(desc);
    
    Format(ref, sizeof(ref), "run %s", command);
    Format(desc, sizeof(desc), "%T", "xms_menu_run_now", client);
    menu.AddItem(ref, desc);
    
    Format(ref, sizeof(ref), "runnext %s", command);
    Format(desc, sizeof(desc), "%T", "xms_menu_run_next", client);
    menu.AddItem(ref, desc);

    
    return menu;
}

public int MenuLogic_Run(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select) {
            char info[64];
            menu.GetItem(param, info, sizeof(info));
            FakeClientCommand(client, "%s", info);
            ghMenuClient[client] = Menu_Base(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        } 
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = Menu_Voting(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
    }
}


Menu Menu_Fov(int client)
{
    Menu menu = new Menu(MenuLogic_Fov);
    
    char title[256];
    Format(title, sizeof(title), "%T", "xms_menu_fov", client);
    menu.SetTitle(title);
    
    int d = FindConVar("xfov_defaultfov").IntValue;
    for(int i = FindConVar("xfov_minfov").IntValue; i <= FindConVar("xfov_maxfov").IntValue; i += 5)
    {
        char si[4];
        IntToString(i, si, sizeof(si));
        
        if(i == d) {
            char desc[15];
            Format(desc, sizeof(desc), "%s (default)", si);
            menu.AddItem(si, desc);
        }
        else {
            menu.AddItem(si, si);
        }
    }

    return menu;
}
    
public int MenuLogic_Fov(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select) {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
            FakeClientCommand(client, "fov %s", info);
        }
        
        ghMenuClient[client] = Menu_Settings(client);
        ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
    }
}


Menu Menu_Players(int client, int target=0)
{
    char name[MAX_NAME_LENGTH], id[12];
    Menu menu = new Menu(MenuLogic_Players);

    char desc[256];

    if(!target)
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
                continue;
            
           }
           
            Format(id, sizeof(id), "%s%i", !IsClientAdmin(client) ? "profile-" : "", i);
            Format(name, sizeof(name), "%N", i);
            menu.AddItem(id, name);
        }
        
        Format(desc, sizeof(desc), "%T", IsClientAdmin(client) ? "xms_menu_players_admin" : "xms_menu_players", client);
        menu.SetTitle(desc);
    }
    else // admin menu
    {
        char ref[32];
        
        Format(ref, sizeof(ref), "profile-%i", target);
        Format(desc, sizeof(desc), "%T", "xms_menu_players_profile", client);
        menu.AddItem(ref, desc);
        
        if(IsClientObserver(target))
        {
            if(IsGameMatch()) {    
                Format(ref, sizeof(ref), "allow-%i", target);
                Format(desc, sizeof(desc), "%T", "xms_menu_players_allow", client);
                menu.AddItem(ref, desc);
            }
        }
        else {
            Format(ref, sizeof(ref), "forcespec-%i", target);
            Format(desc, sizeof(desc), "%T", "xms_menu_players_forcespec", client);
            menu.AddItem(ref, desc);
        }
        
        if(IsClientAdmin(client, ADMFLAG_CHAT)) {
            Format(ref, sizeof(ref), "mute-%i", target);
            Format(desc, sizeof(desc), "%T", BaseComm_IsClientMuted(target) ? "xms_menu_players_unmute" : "xms_menu_players_mute", client);
            menu.AddItem(ref, desc);
        }
        
        if(IsClientAdmin(client, ADMFLAG_KICK)) {
            Format(ref, sizeof(ref), "kick-%i", target);
            Format(desc, sizeof(desc), "%T", "xms_menu_players_kick", client);
            menu.AddItem(ref, desc);
        }
         
        if(IsClientAdmin(client, ADMFLAG_BAN)) {         
            Format(ref, sizeof(ref), "ban-%i", target);
            Format(desc, sizeof(desc), "%T", "xms_menu_players_tempban", client);
            menu.AddItem(ref, desc);
        }

        char targetName[MAX_NAME_LENGTH];
        GetClientName(target, targetName, sizeof(targetName));
        Format(desc, sizeof(desc), "%T", "xms_menu_players_player", client, targetName, GetClientUserId(target), GetClientSteamID(target));
        menu.SetTitle(desc);
        menu.ExitBackButton = true;
    }

    return menu;
}

public int MenuLogic_Players(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select)
        {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
                    
            int target = StringToInt(info[StrContains(info, "-") + 1]);
                    
            if(target && IsClientInGame(target))
            {
                int target_id = GetClientUserId(target);    
                if(StrContains(info, "profile") == 0) {
                    FakeClientCommand(client, "profile %i", target_id);
                }
                else if(StrContains(info, "allow") == 0) {
                    FakeClientCommand(client, "allow %i", target_id);
                }
                else if(StrContains(info, "forcespec") == 0) {
                    FakeClientCommand(client, "forcespec %i", target_id);
                }
                else if(StrContains(info, "kick") == 0) {
                    FakeClientCommand(client, "sm_kick #%i", target_id);
                    target = 0;
                }
                else if(StrContains(info, "ban") == 0) {
                    FakeClientCommand(client, "sm_ban #%i 1440 Banned for 24 hours", target_id);
                    target = 0;
                }
                else if(StrContains(info, "mute") == 0) {
                    FakeClientCommand(client, "sm_%s #%i", BaseComm_IsClientMuted(target) ? "unmute" : "mute", target_id);
                }
                if(!IsClientAdmin(client)) {
                    target = 0;
                }
            }
            else {
                target = 0;
            }
            ghMenuClient[client] = Menu_Players(client, target);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = (param == MenuCancel_Exit ? Menu_Base(client) : Menu_Players(client, 0));
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
        }
    }
}


Menu Menu_Voting(int client)
{
    Menu menu = new Menu(MenuLogic_Voting);
    
    char desc[256];
    Format(desc, sizeof(desc), "%T", "xms_menu_voting", client);
    menu.SetTitle(desc);
    
    if(!IsGameMatch()) {
        Format(desc, sizeof(desc), "%T", "xms_menu_voting_map", client);
        menu.AddItem("map", desc);
        Format(desc, sizeof(desc), "%T", "xms_menu_voting_mode", client);
        menu.AddItem("mode", desc);
        Format(desc, sizeof(desc), "%T", "xms_menu_voting_start", client);
        menu.AddItem("start", desc);
    }
    else {
        Format(desc, sizeof(desc), "%T", "xms_menu_voting_cancel", client);
        menu.AddItem("cancel", desc);        
    }

    return menu;
}

public int MenuLogic_Voting(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select)
        {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
                
            if(StrEqual(info, "map")) {
                ghMenuClient[client] = Menu_Map(client, gsMode);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
            else if(StrEqual(info, "mode")) {
                ghMenuClient[client] = Menu_Mode(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
            else if(StrEqual(info, "start")) {
                ghMenuClient[client] = Menu_Start(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);
            }
            else if(StrEqual(info, "cancel")) {
                FakeClientCommand(client, "cancel");
            }
        }
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = Menu_Base(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
    }
}


Menu Menu_Settings(int client)
{
    Menu menu = new Menu(MenuLogic_Settings);
    char desc[256];
    
    Format(desc, sizeof(desc), "%T", "xms_menu_settings", client);
    menu.SetTitle(desc);
    
    Format(desc, sizeof(desc), "%T", "xms_menu_settings_model", client);
    menu.AddItem("model", desc);
    if(CommandExists("sm_fov")) {
        Format(desc, sizeof(desc), "%T", "xms_menu_settings_fov", client);
        menu.AddItem("fov", desc);
    }
    Format(desc, sizeof(desc), "%T", "xms_menu_settings_hudcolor", client);
    menu.AddItem("hudcolor", desc);
    
    Format(desc, sizeof(desc), "%T", GetClientCookieInt(client, ghCookieMusic) == 1 ? "xms_menu_settings_endmusic1" : "xms_menu_settings_endmusic0", client);
    menu.AddItem("endmusic", desc);
    
    Format(desc, sizeof(desc), "%T", GetClientCookieInt(client, ghCookieSounds) == 1 ? "xms_menu_settings_sounds1" : "xms_menu_settings_sounds0", client);
    menu.AddItem("miscsounds", desc);
    
    return menu;
}

public int MenuLogic_Settings(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select)
        {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
                
            if(StrEqual(info, "fov")) {
                ghMenuClient[client] = Menu_Fov(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
            }
            else if(StrEqual(info, "model")) {
                ghMenuClient[client] = Menu_Model(client);
                ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
            }
            else
            {
                if(StrEqual(info, "hudcolor")) {
                    ghMenuClient[client] = Menu_HudColor(client);
                    ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
                }
                else
                {
                    if(StrEqual(info, "endmusic")) {
                        SetClientCookie(client, ghCookieMusic,   GetClientCookieInt(client, ghCookieMusic) == 1 ? "-1" : "1");
                    }
                    else if(StrEqual(info, "miscsounds")) {
                        SetClientCookie(client, ghCookieSounds, GetClientCookieInt(client, ghCookieSounds) == 1 ? "-1" : "1");
                    }
                        
                    ghMenuClient[client] = Menu_Settings(client);
                    ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
                }
            }            
        }
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = Menu_Base(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
    }
}


Menu Menu_HudColor(int client)
{
    Menu menu = new Menu(MenuLogic_HudColor);
    
    char desc[256];
    Format(desc, sizeof(desc), "%T", "xms_menu_hudcolor", client);
    menu.SetTitle(desc);

    Format(desc, sizeof(desc), "%T", "xms_menu_hudcolor_orange", client);
    menu.AddItem("255 177 0",   desc);
    Format(desc, sizeof(desc), "%T", "xms_menu_hudcolor_cyan", client);
    menu.AddItem("0 255 255",   desc);
    Format(desc, sizeof(desc), "%T", "xms_menu_hudcolor_green", client);
    menu.AddItem("75 255 75",   desc);
    Format(desc, sizeof(desc), "%T", "xms_menu_hudcolor_red", client);
    menu.AddItem("220 10 10",   desc);
    Format(desc, sizeof(desc), "%T", "xms_menu_hudcolor_white", client);
    menu.AddItem("255 255 255", desc);
    Format(desc, sizeof(desc), "%T", "xms_menu_hudcolor_grey", client);
    menu.AddItem("175 175 175", desc);
    Format(desc, sizeof(desc), "%T", "xms_menu_hudcolor_violet", client);
    menu.AddItem("238 130 238", desc);
    Format(desc, sizeof(desc), "%T", "xms_menu_hudcolor_pink", client);
    menu.AddItem("255 105 180", desc);
    
    return menu;
}

public int MenuLogic_HudColor(Menu menu, MenuAction action, int client, int param)
{
    if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        if(action == MenuAction_Select) {
            char info[32];
            menu.GetItem(param, info, sizeof(info));
            FakeClientCommand(client, "hudcolor %s", info);
            ghMenuClient[client] = Menu_HudColor(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
        else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack)) {
            ghMenuClient[client] = Menu_Settings(client);
            ghMenuClient[client].Display(client, MENU_TIME_FOREVER);  
        }
    }
}

// END