#define PLUGIN_NAME			"XMS - Overtime"
#define PLUGIN_VERSION		"1.12"
#define PLUGIN_DESCRIPTION	"Sudden-death overtime for eXtended Match System"
#define PLUGIN_AUTHOR		"harper"
#define PLUGIN_URL			"hl2dm.pro"

#define OVERTIME_TIME		1 // minutes

#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <morecolors>

#pragma newdecls required
#include <hl2dm_xms>

bool	Plugin_Enabled,
		IsOvertime;

Handle	PreOvertimer = INVALID_HANDLE;

ConVar	Timelimit;

/****************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{
	Timelimit = FindConVar("mp_timelimit");
	HookConVarChange(Timelimit, OnTimelimitChanged);
}

public void OnMapStart()
{
	char	gamemode[MAX_MODE_LENGTH],
			overtime[2];
			
	XMS_GetGamemode(gamemode, sizeof(gamemode));
	XMS_GetConfigString(overtime, sizeof(overtime), "Overtime", "GameModes", gamemode);
	
	Plugin_Enabled = StrEqual(overtime, "1");
	if(Plugin_Enabled) CreateOverTimer();
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
			if(IsOvertime) CPrintToChatAll("%sOvertime: %sNobody took the lead, so the game is a draw.", CLR_FAIL, CLR_MAIN);
			
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
	if(XMS_IsGameTeamplay() && (GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE) == 0))
	{
		StartOvertime();
	}
	else if(!GetTopPlayer()) StartOvertime();
	
	PreOvertimer = INVALID_HANDLE;
}

void StartOvertime()
{
	int state = XMS_GetGamestate();
	
	IsOvertime = true;
	
	SetConVarInt(Timelimit, GetConVarInt(Timelimit) + OVERTIME_TIME);
	CPrintToChatAll("%sOvertime: %sThe next %s to score wins!", CLR_FAIL, CLR_MAIN, XMS_IsGameTeamplay() ? "team" : "player");
	CreateTimer(0.1, T_Overtime, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);	
	
	if(state == STATE_MATCH)	XMS_SetGamestate(STATE_MATCHEX);
	else						XMS_SetGamestate(STATE_DEFAULTEX);
}

public Action T_Overtime(Handle timer)
{
	int result;
	
	if(XMS_IsGameTeamplay())
	{
		result = GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE);
		if(result == 0) return Plugin_Continue;
		
		CPrintToChatAll("%sOvertime: %sTeam %s took the lead and win the game.", CLR_FAIL, CLR_MAIN, result < 0 ? "Combine" : "Rebels");
	}
	else
	{
		result = GetTopPlayer();
		if(!result) return Plugin_Continue;
		
		CPrintToChatAll("%sOvertime: %s%N %stook the lead and wins the game.", CLR_FAIL, CLR_HIGH, result, CLR_MAIN);
	}
	
	IsOvertime = false;
	SetConVarInt(Timelimit, GetConVarInt(Timelimit) - OVERTIME_TIME);
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
	int		best_score = -99,
			best_scorer;
			
	bool	tie;
		
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
