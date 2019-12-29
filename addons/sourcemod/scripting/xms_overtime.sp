#define PLUGIN_VERSION "1.15"
#define UPDATE_URL     "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_overtime.upd"

public Plugin myinfo=
{
    name        = "XMS - Overtime",
    version     = PLUGIN_VERSION,
    description = "Sudden-death overtime for eXtended Match System",
    author      = "harper <www.hl2dm.pro>",
    url         = "www.hl2dm.pro"
};

/******************************************************************/

#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <morecolors>

#undef REQUIRE_PLUGIN
 #include <updater>
#define REQUIRE_PLUGIN

#pragma newdecls required
 #include <hl2dm-xms>
 
/******************************************************************/

#define OVERTIME_TIME       1 // minutes

ConVar Timelimit;

bool   Plugin_Enabled,
       IsOvertime;

Handle PreOvertimer = INVALID_HANDLE;

/******************************************************************/

public void OnPluginStart()
{
    Timelimit = FindConVar("mp_timelimit");
    HookConVarChange(Timelimit, OnTimelimitChanged);
    
    if(LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnMapStart()
{
    char gamemode[MAX_MODE_LENGTH],
         overtime[2];
            
    XMS_GetGamemode(gamemode, sizeof(gamemode));
    XMS_GetConfigString(overtime, sizeof(overtime), "Overtime", "GameModes", gamemode);
    
    Plugin_Enabled = StrEqual(overtime, "1");
    if(Plugin_Enabled)
    {
        CreateOverTimer();
    }
}

public void OnGamestateChanged(int new_state, int old_state)
{
    if(Plugin_Enabled)
    {
        if(new_state == STATE_DEFAULT || new_state == STATE_MATCH && old_state != STATE_PAUSE)
        {
            CreateOverTimer();
        }
        else if(new_state == STATE_MATCHWAIT)
        {
            IsOvertime = false;
        }
        else if(new_state == STATE_POST || new_state == STATE_CHANGE)
        {
            if(IsOvertime) CPrintToChatAll("%sOvertime: %sNobody took the lead, so the game is a draw.", CHAT_FAIL, CHAT_MAIN);
            
            IsOvertime = false;
        }
    }
}

public void OnTimelimitChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    if(Plugin_Enabled && !IsOvertime) CreateOverTimer();
}

public void OnMapEnd()
{
    IsOvertime = false;
    PreOvertimer = INVALID_HANDLE;
}

public Action T_PreOvertime(Handle timer)
{
    if(GetRealClientCount(true, true) > 1)
    {
        if(XMS_IsGameTeamplay())
        {
            if(GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE) == 0)
            {
                if(GetTeamClientCount(TEAM_REBELS) && GetTeamClientCount(TEAM_COMBINE))
                {
                    StartOvertime();
                }
            }
        }
        else if(!GetTopPlayer())
        {
            StartOvertime();
        }
    }
    
    PreOvertimer = INVALID_HANDLE;
}

void StartOvertime()
{
    int state = XMS_GetGamestate();
    
    IsOvertime = true;
    
    SetConVarInt(Timelimit, GetConVarInt(Timelimit) + OVERTIME_TIME);
    CPrintToChatAll("%sOvertime: %sThe next %s to score wins!", CHAT_FAIL, CHAT_MAIN, XMS_IsGameTeamplay() ? "team" : "player");
    CreateTimer(0.1, T_Overtime, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);    
    
    if(state == STATE_MATCH) XMS_SetGamestate(STATE_MATCHEX);
    else                     XMS_SetGamestate(STATE_DEFAULTEX);
}

public Action T_Overtime(Handle timer)
{
    int result;
    
    if(!IsOvertime)
    {
        return Plugin_Stop;
    }
    
    if(XMS_IsGameTeamplay())
    {
        result = GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE);
        if(result == 0) return Plugin_Continue;
        
        CPrintToChatAll("%sOvertime: %sTeam %s took the lead and win the game.", CHAT_FAIL, CHAT_MAIN, result < 0 ? "Combine" : "Rebels");
    }
    else
    {
        result = GetTopPlayer();
        if(!result) return Plugin_Continue;
        
        CPrintToChatAll("%sOvertime: %s%N %stook the lead and wins the game.", CHAT_FAIL, CHAT_HIGH, result, CHAT_MAIN);
    }
    
    SetConVarInt(Timelimit, GetConVarInt(Timelimit) - OVERTIME_TIME);
    IsOvertime = false;
    return Plugin_Stop;
}

void CreateOverTimer()
{
    if(PreOvertimer != INVALID_HANDLE)
    {
        KillTimer(PreOvertimer);
        PreOvertimer = INVALID_HANDLE;
    }
    
    PreOvertimer = CreateTimer(XMS_GetTimeRemaining(false) - 0.1, T_PreOvertime, _, TIMER_FLAG_NO_MAPCHANGE);
}

int GetTopPlayer()
{
    int best_score = -99,
        best_scorer;
            
    bool tie;
        
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) != TEAM_SPECTATORS)
        {
            int score = GetClientFrags(i) - GetClientDeaths(i);
            if(score > best_score)
            {
                best_score = score;
                best_scorer = i;
                tie = false;
            }
            else if(score == best_score) tie = true;
        }
    }
    
    if(tie) return 0;
    return best_scorer;
}