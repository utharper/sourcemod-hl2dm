#define PLUGIN_NAME         "XMS Core (eXtended Match System)"
#define PLUGIN_VERSION      "1.13"
#define PLUGIN_DESCRIPTION  "Base plugin for competitive HL2DM servers"
#define PLUGIN_AUTHOR       "harper"
#define PLUGIN_URL          "HL2DM.PRO"
#define UPDATE_URL          "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms.upd"

#pragma semicolon 1
#include <sourcemod>
#include <steamtools>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <updater>

#define REQUIRE_PLUGIN
#pragma newdecls required
#include <hl2dm-xms>

int         Gamestate;

bool        Firstload = true,
            IsTeamplay,
            EndTrigger;
            
float       PreGameTime;

char        Gamemode[MAX_MODE_LENGTH],
            DefaultMode[MAX_MODE_LENGTH],
            Path_Cfg[PLATFORM_MAX_PATH],
            GameID[1024];

Handle      Fw_Gamestate;

KeyValues   Cfg;

/******************************************************************/

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    CreateNative("XMS_GetConfigString", N_GetConfigString);
    CreateNative("XMS_GetConfigKeys", N_GetConfigKeys);
    CreateNative("XMS_GetGamestate", N_GetGamestate);
    CreateNative("XMS_SetGamestate", N_SetGamestate);
    CreateNative("XMS_GetGamemode", N_GetGamemode);
    CreateNative("XMS_SetGamemode", N_SetGamemode);
    CreateNative("XMS_GetTimeRemaining", N_GetTimeRemaining);
    CreateNative("XMS_GetTimeElapsed", N_GetTimeElapsed);
    CreateNative("XMS_IsGameTeamplay", N_IsGameTeamplay);
    CreateNative("XMS_GetGameID", N_GetGameID);

    Fw_Gamestate = CreateGlobalForward("OnGamestateChanged", ET_Event, Param_Cell, Param_Cell);

    RegPluginLibrary("hl2dm-xms");
}

public int N_GetConfigString(Handle plugin, int params)
{
    char    value[1024],
            key[32],
            inKey[32];

    Cfg.Rewind();
    GetNativeString(3, key, sizeof(key));
    for(int param = 4; param <= params; param++)
    {
        GetNativeString(param, inKey, sizeof(inKey));
        if(!Cfg.JumpToKey(inKey))
        {
            return -1;
        }
    }

    if(Cfg.GetString(key, value, sizeof(value))) 
    {
        if(StrEqual(value, NULL_STRING)) return 0;

        SetNativeString(1, value, GetNativeCell(2));
        return 1;
    }

    return -1;
}

public int N_GetConfigKeys(Handle plugin, int params)
{
    char    subkeys[1024],
            inKey[32];

    Cfg.Rewind();
    for(int param = 3; param <= params; param++)
    {
        GetNativeString(param, inKey, sizeof(inKey));
        if(!Cfg.JumpToKey(inKey)) return -1;
    }

    if(Cfg.GotoFirstSubKey())
    {
        int count = 1;

        do {
            Cfg.GetSectionName(subkeys[strlen(subkeys)], sizeof(subkeys));
            subkeys[strlen(subkeys)] = ',';
            count++;
        } while (Cfg.GotoNextKey());
        subkeys[strlen(subkeys) - 1] = 0;

        SetNativeString(1, subkeys, GetNativeCell(2));
        return count;
    }

    return -1;
}

public int N_GetGamestate(Handle plugin, int numParams)
{
    return Gamestate;
}

public int N_SetGamestate(Handle plugin, int numParams)
{
    if(Gamestate != STATE_CHANGE)
    {
        ChangeGamestate(GetNativeCell(1));
        return 1;
    }

    return 0;
}

public int N_GetGamemode(Handle plugin, int numParams)
{
    int bytes;

    SetNativeString(1, Gamemode, GetNativeCell(2), true, bytes);
    return bytes;
}

public int N_SetGamemode(Handle plugin, int numParams)
{
    char newMode[MAX_MODE_LENGTH];

    GetNativeString(1, newMode, sizeof(newMode));
    ChangeGamemode(newMode);

    return 1;
}

public int N_GetTimeRemaining(Handle plugin, int numParams)
{
    float t = GetConVarFloat(FindConVar("mp_timelimit")) * 60 - GetGameTime() + PreGameTime;

    if(GetNativeCell(1)) t += GetConVarFloat(FindConVar("mp_chattime"));

    return view_as<int>(t ? t : 0.0);
}

public int N_GetTimeElapsed(Handle plugin, int numParams)
{
    return view_as<int>(GetGameTime() - PreGameTime);
}

public int N_IsGameTeamplay(Handle plugin, int params)
{
    return view_as<int>(IsTeamplay);
}

public int N_GetGameID(Handle plugin, int numParams)
{
    SetNativeString(1, GameID, GetNativeCell(2));
    return 1;
}

/******************************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{   
    BuildPath(Path_SM, Path_Cfg, PLATFORM_MAX_PATH, "configs/xms.cfg");
    Cfg = new KeyValues(NULL_STRING);
    Cfg.ImportFromFile(Path_Cfg);
    
    XMS_GetConfigString(DefaultMode, sizeof(DefaultMode), "$default", "MapModes");
    SplitString(DefaultMode, ",", DefaultMode, sizeof(DefaultMode));

    HookUserMessage(GetUserMessageId("VGUIMenu"), UserMsg_VGUIMenu);
    HookEvent("round_start", OnRoundStart, EventHookMode_Pre);

    IsTeamplay = GetConVarBool(FindConVar("mp_teamplay"));

    CreateConVar("hl2dm-xms_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    
    if(LibraryExists("updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnMapStart()
{
    EndTrigger = false;

    if(Firstload)
    {
        char currentmap[MAX_MAP_LENGTH];

        ChangeGamemode(DefaultMode);
        Firstload = false;

        // On first load we will restart the map - avoids issues with sourcetv etc
        GetCurrentMap(currentmap, sizeof(currentmap));
        ServerCommand("sm_nextmap %s;changelevel_next", currentmap);
    }
    else LoadGamemode();

    ChangeGamestate(STATE_DEFAULT);
    PreGameTime = GetGameTime() - 1;
}

public Action OnRoundStart(Handle event, const char[] name, bool noBroadcast)
{
    PreGameTime = GetGameTime();
}

public void OnClientPutInServer(int client)
{
    CreateTimer(1.0, T_Announce, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action T_Announce(Handle timer, int client)
{
    static int iter = 0;

    // I politely ask you not to remove this
    PrintCenterText(client, "XMS (eXtended Match System) v%s - www.hl2dm.pro", PLUGIN_VERSION);

    if(iter >= 3)
    {
        iter = 0;
        return Plugin_Stop;
    }

    iter++;
    return Plugin_Continue;
}

public Action UserMsg_VGUIMenu(UserMsg msg_id, Handle msg, const players[], int playersNum, bool reliable, bool init)
{
    char buffer[10];

    BfReadString(msg, buffer, sizeof(buffer));
    if(StrEqual(buffer, "scores"))
    {
        if(!EndTrigger)
        {
            EndTrigger = true;
            RequestFrame(ChangeGamestate, STATE_POST);
        }
    }
    return Plugin_Continue;
}

public void OnClientDisconnect_Post(int client)
{
    if(GetClientCount(true) == 1 || (GetClientCount(true) == 0 && !GetConVarBool(FindConVar("tv_enable"))))
    {
        // everyone left (except sourcetv)
        if(Gamestate != STATE_CHANGE)
        {
            CreateTimer(Gamestate == STATE_MATCH ? 1.0 : 60.0, T_Revert);
        }
    }
}

public Action T_Revert(Handle timer)
{
    if(GetClientCount(true) == 1)
    {
        // Revert to default state
        ChangeGamemode(DefaultMode);
        ServerCommand("changelevel_next");
    }
}

public void OnMapEnd()
{
    ChangeGamestate(STATE_CHANGE);
    IsTeamplay = GetConVarBool(FindConVar("mp_teamplay"));

    if(GetClientCount(false) <= 1)
    {
        // Stick to default maps when server is empty
        ServerCommand("mapcyclefile \"mapcycle_default.txt\"");
    }

}

void ChangeGamemode(const char[] mode)
{
    strcopy(Gamemode, sizeof(Gamemode), mode);
    LoadGamemode();
}

void ChangeGamestate(int state)
{
    int prestate = Gamestate;
    Gamestate = state;

    if(state != prestate)
    {
        Call_StartForward(Fw_Gamestate);
        Call_PushCell(state);
        Call_PushCell(prestate);
        Call_Finish();

        if(state == STATE_DEFAULT && (prestate == STATE_MATCH || prestate == STATE_MATCHEX))
        {
            ServerCommand("exec server");
            LoadGamemode();
        }

        if((state == STATE_MATCH || state == STATE_DEFAULT) &&
            (prestate != STATE_MATCHWAIT && prestate != STATE_PAUSE)
        ){
            char timedate[32],
                 map[MAX_MAP_LENGTH],
                 mode[MAX_MODE_LENGTH];

            GetCurrentMap(map, sizeof(map));
            XMS_GetGamemode(mode, sizeof(mode));
            FormatTime(timedate, sizeof(timedate), "%y%m%d-%Hh%Mm");        
            Format(GameID, sizeof(GameID), "%s-%s-%s", timedate, map, mode);
        }

        else if(state == STATE_MATCHWAIT)
        {
            LoadMatchSettings();
        }
    }
}

void LoadMatchSettings()
{
    char servercmd[PLATFORM_MAX_PATH];

    if(XMS_GetConfigString(servercmd, sizeof(servercmd), "ServerCommand", "Match")) ServerCommand(servercmd);
}

void LoadGamemode()
{
    char servercmd[PLATFORM_MAX_PATH],
         mapcycle[PLATFORM_MAX_PATH],
         description[1024];

    if(XMS_GetConfigString(servercmd, sizeof(servercmd), "ServerCommand", "GameModes", Gamemode))
    {
        ServerCommand(servercmd);
    }

    if(XMS_GetConfigString(description, sizeof(description), "Name", "GameModes", Gamemode))
    {
        if(StrContains(description, Gamemode, false) == -1) Format(description, sizeof(description), "%s (%s)", description, Gamemode);
        Steam_SetGameDescription(description);
    }
    else Steam_SetGameDescription("Custom Mode");
    
    if(XMS_GetConfigString(mapcycle, sizeof(mapcycle), "Mapcycle", "GameModes", Gamemode))
    {
        ServerCommand("mapcyclefile \"%s\"", mapcycle);
    }
    else ServerCommand("mapcyclefile \"mapcycle_default.txt\"");
}