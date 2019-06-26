#define PLUGIN_NAME			"XMS - Commands"
#define PLUGIN_VERSION		"1.12"
#define PLUGIN_DESCRIPTION	"Client commands for eXtended Match System"
#define PLUGIN_AUTHOR		"harper"
#define PLUGIN_URL			"hl2dm.pro"

#define SOUND_T_COUNT		"buttons/blip1.wav"
#define SOUND_T_END			"hl1/fvox/beep.wav"
#define TRIGGER_PRIMARY		"!"
#define TRIGGER_SECONDARY	"/"
#define TRIGGER_PMS			"#.#"
#define DELAY_CHANGE		4
#define DELAY_START			4

#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <morecolors>

#pragma newdecls required
#include <hl2dm_xms>

char	Path_Maps[PLATFORM_MAX_PATH],
		Gamemodes[512];

/******************************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{	
	BuildPath(Path_SM, Path_Maps, PLATFORM_MAX_PATH, "../../maps");
	
	RegConsoleCmd("sm_run", Command_Run, "Change to the specified map and/or mode");
	RegConsoleCmd("sm_start", Command_Start, "Start a competitive match");
	RegConsoleCmd("sm_stop", Command_Stop, "Stop a competitive match");
	RegConsoleCmd("sm_list", Command_List, "List all maps on the server");
	RegConsoleCmd("sm_pause", Command_Pause, "Pause/unpause the game");
	RegConsoleCmd("sm_coinflip", Command_Coinflip, "Flip a coin");
	RegAdminCmd("sm_forcespec", ACommand_Forcespec, ADMFLAG_GENERIC, "Force a player to spectate");
}

public void OnAllPluginsLoaded()
{
	XMS_GetConfigKeys(Gamemodes, sizeof(Gamemodes), "GameModes");
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// add support for old style commands
	if(StrContains(sArgs, TRIGGER_PRIMARY) == 0 || StrContains(sArgs, TRIGGER_SECONDARY) == 0 || StrContains(sArgs, TRIGGER_PMS) == 0)
	{
		char args[MAX_SAY_LENGTH];
		bool corrected;
		
		if(StrContains(sArgs, TRIGGER_PMS) == 0)
		{
			args[0] = '!';
			strcopy(args[1], sizeof(args) - 1, sArgs[IsCharSpace(sArgs[3]) ? 4 : 3]);
			corrected = true;
		}
		else strcopy(args, sizeof(args), sArgs);
		
		for(int i = 1; i <= strlen(sArgs); i++)
		{
			if(IsCharUpper(sArgs[i]))
			{
				// case sensitivity sucks
				String_ToLower(args, args, sizeof(args));
				corrected = true;
			}
		}
		
		if(StrContains(args, "run 1v1") == 1 || StrContains(args, "run 2v2") == 1 || StrContains(args, "run 3v3") == 1
			|| StrContains(args, "run 4v4") == 1 || StrContains(args, "run duel") == 1
		){
			FakeClientCommandEx(client, "say !start");
			return Plugin_Handled;
		}
		
		if(StrContains(args, "cm ") == 1)
		{
			FakeClientCommandEx(client, "say !run %s", args[4]);
			return Plugin_Handled;
		}
		else if(StrContains(args, "tp ") == 1 || StrContains(args, "teamplay ") == 1)
		{
			if(StrContains(args, " on") != -1 || StrContains(args, " 1") != -1)
			{
				FakeClientCommandEx(client, "say !run tdm");
				return Plugin_Handled;
			}
			else if(StrContains(args, " off") != -1 || StrContains(args, " 0") != -1)
			{
				FakeClientCommandEx(client, "say !run dm");
				return Plugin_Handled;
			}
		}
		else if(StrEqual(args[1], "cf"))
		{
			FakeClientCommandEx(client, "say !coinflip");
			return Plugin_Handled;
		}
		else if(corrected)
		{
			FakeClientCommandEx(client, "say %s", args);
			return Plugin_Handled;
		}
			
		return Plugin_Continue;
	}
		
	// Basetriggers overrides
	bool broadcast = GetConVarBool(FindConVar("sm_trigger_show"));
	char output[MAX_SAY_LENGTH];
		
	if(StrEqual(sArgs, "timeleft"))
	{
		bool over = (XMS_GetGamestate() == STATE_POST);
		float time = XMS_GetTimeRemaining(over);
		int h = RoundToNearest(time) / 3600,
			s = RoundToNearest(time) % 60,
			m = RoundToNearest(time) / 60 - (h ? (h * 60) : 0);
			
		if(over)	Format(output, sizeof(output), "%s%sMap will auto-change in %s%i%s seconds", CLR_MAIN, (broadcast ? NULL_STRING : CHAT_PREFIX), CLR_HIGH, s, CLR_MAIN);
		else		Format(output, sizeof(output), "%s%sTime remaining: %s%ih %im %02is", CLR_MAIN, (broadcast ? NULL_STRING : CHAT_PREFIX), CLR_HIGH, h, m, s);
	}
	else if(StrEqual(sArgs, "nextmap"))
	{
		char nextmap[MAX_MAP_LENGTH];
		
		GetNextMap(nextmap, sizeof(nextmap));
		Format(output, sizeof(output), "%s%sNext map: %s%s", CLR_MAIN, (broadcast ? NULL_STRING : CHAT_PREFIX), CLR_HIGH, nextmap);
	}
	else if(StrEqual(sArgs, "ff") && XMS_IsGameTeamplay())
	{		
		Format(output, sizeof(output), "%s%sFriendly fire is %s%s", CLR_MAIN, (broadcast ? NULL_STRING : CHAT_PREFIX), CLR_HIGH, (GetConVarBool(FindConVar("mp_friendlyfire")) ? "enabled" : "disabled"));
	}
	else return Plugin_Continue;
	
	if(broadcast)
	{
		CPrintToChatAllFrom(client, false, sArgs);
		CPrintToChatAll(output);
	}
	else CPrintToChat(client, output);
	
	return Plugin_Stop;
}

public Action Command_Run(int client, int args)
{
	static int	fail_iter[MAXPLAYERS + 1],
				multi_iter[MAXPLAYERS + 1];
				
	int 		hits,
				xhits,
				state = XMS_GetGamestate();
				
	bool 		exact,
				abbrev,
				matched;
	
	char		sQuery[MAX_MAP_LENGTH],
				sAbbrev[MAX_MAP_LENGTH],
				sFile[PLATFORM_MAX_PATH],
				sOutput[MAX_SAY_LENGTH],
				sConOut[MAX_BUFFER_LENGTH],
				mapChangingTo[MAX_MAP_LENGTH],
				modeChangingTo[MAX_MODE_LENGTH];
				
	Handle		dir;
	
	any 		filetype;
	
	switch(state)
	{
		case STATE_PAUSE:
		{
			CReplyToCommand(client, "%s%sError: %sYou can't use this command when the game is paused.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
			return Plugin_Handled;
		}
		case STATE_CHANGE:
		{
			CReplyToCommand(client, "%s%sError: %sPlease wait for the current action to complete.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
			return Plugin_Handled;
		}
		case STATE_MATCH:
		{
			CReplyToCommand(client, "%s%sError: %sYou must %s!stop %sthe current match first.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_INFO, CLR_MAIN);
			return Plugin_Handled;
		}
		default:
		{
			if (!args || args > 2)
			{
				CReplyToCommand(client, "%s%sUsage: !run <map and/or gamemode>, eg '!run tdm', '!run dm lockdown', '!run overwatch'", CLR_INFO, CHAT_PREFIX);
				return Plugin_Handled;
			}
		}
	}
	
	GetCmdArg(1, sQuery, sizeof(sQuery));
	String_ToLower(sQuery, sQuery, sizeof(sQuery));
	
	if(IsValidMode(sQuery))
	{
		strcopy(modeChangingTo, sizeof(modeChangingTo), sQuery);
		
		if(args > 1)
		{
			GetCmdArg(2, sQuery, sizeof(sQuery));
			String_ToLower(sQuery, sQuery, sizeof(sQuery));
		}
		else
		{
			char curmode[MAX_MODE_LENGTH], nextmap[MAX_MAP_LENGTH];
			
			XMS_GetGamemode(curmode, sizeof(curmode));
			if(!StrEqual(curmode, modeChangingTo))
			{
				GetCurrentMap(mapChangingTo, sizeof(mapChangingTo));
				if(XMS_GetConfigString(nextmap, sizeof(nextmap), "DefaultMap", "GameModes", modeChangingTo))
				{
					if(IsMapValid(nextmap))
					{
						strcopy(mapChangingTo, sizeof(mapChangingTo), nextmap);
					}
				}
				RequestChange(client, modeChangingTo, mapChangingTo);
			}
			else CReplyToCommand(client, "%s%sError: %sAlready using mode %s%s", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_INFO, modeChangingTo);
			
			return Plugin_Handled;
		}
	}
	else if(args > 1)
	{
		GetCmdArg(2, modeChangingTo, sizeof(modeChangingTo));
		String_ToLower(modeChangingTo, modeChangingTo, sizeof(modeChangingTo));
		
		if(!IsValidMode(modeChangingTo))
		{		
			CReplyToCommand(client, "%s%sError:%s Invalid gamemode. Valid modes: %s%s", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_INFO, Gamemodes);
			
			return Plugin_Handled;
		}
	}
	
	abbrev = GetMapByAbbrev(sAbbrev, sizeof(sAbbrev), sQuery);
	dir = OpenDirectory(Path_Maps);

	while(ReadDirEntry(dir, sFile, sizeof(sFile), filetype) && !exact)
	{
		if(filetype == FileType_File && strlen(sFile) <= MAX_MAP_LENGTH && ReplaceString(sFile, sizeof(sFile), ".bsp", NULL_STRING))
		{
			if(StrContains(sFile, sQuery, false) >= 0 || (abbrev && StrContains(sFile, sAbbrev, false) >= 0))
			{
				exact = (abbrev ? StrEqual(sFile, sAbbrev, false) : StrEqual(sFile, sQuery, false));
				hits++;
				
				if(hits == 1 || exact)
				{
					strcopy(mapChangingTo, sizeof(mapChangingTo), sFile);
					hits = 1;
					xhits = 0;
				}
				if(!exact)
				{
					Format(sConOut, sizeof(sConOut), "%s　%s", sConOut, sFile);
					FReplaceString(sFile, sizeof(sFile), sQuery, false, "%s%s%s", CLR_HIGH, sQuery, CLR_INFO);
						
					// meh
					if(strlen(sOutput) + strlen(CHAT_PREFIX) + strlen(sFile) + strlen(CLR_HIGH) + strlen(CLR_INFO) + (strlen(CLR_MAIN) * 3) + strlen(", and xxx others.") + strlen(CHAT_PREFIX) + strlen("Found: ") + 2 <= 191)
					{
						Format(sOutput, sizeof(sOutput), "%s%s%s", sOutput, hits == 1 ? NULL_STRING : ", ", sFile);
						xhits++;
					}
				}
			}
		}
	}
	
	if(!hits)
	{
		fail_iter[client]++;
		CReplyToCommand(client, "%sError: %sMap or mode %s%s%s not found.", CLR_FAIL, CLR_MAIN, CLR_INFO, sQuery, CLR_MAIN);
	}
	else if(hits == 1)
	{
		matched = true;
		if(args == 1) GetModeForMap(modeChangingTo, sizeof(modeChangingTo), mapChangingTo);
	}
	else
	{
		multi_iter[client]++;
		PrintToConsole(client, "\n\n\n*** Maps matching query `%s` ...\n%s\n\n\n", sQuery, sConOut);
		CPrintToChat(client, "%s%sFound%s: %s%s, and %s%i%s others.", CLR_MAIN, CHAT_PREFIX, CLR_INFO, sOutput, CLR_MAIN, CLR_HIGH, hits - xhits, CLR_MAIN);
	}
	
	if(matched)
	{
		RequestChange(client, modeChangingTo, mapChangingTo);
	}
	else if(multi_iter[client] >= 3 && !exact && hits > xhits)
	{
		CPrintToChat(client, "%s%sTip: Open your console for a full list of maps matching your search.", CHAT_PREFIX, CLR_INFO);
		multi_iter[client] = 0;
	}
	else if(fail_iter[client] >= 3)
	{
		CPrintToChat(client, "%s%sUsage: !run <map and/or gamemode>, eg '!run tdm', '!run dm lockdown', '!run overwatch'", CLR_INFO, CHAT_PREFIX);
		fail_iter[client] = 0;
	}
	
	CloseHandle(dir);
	return Plugin_Handled;
}

public Action Command_Start(int client, int args)
{
	int		state = XMS_GetGamestate();
	char	mode[MAX_MODE_LENGTH];
	
	XMS_GetGamemode(mode, sizeof(mode));
	
	if(args) CReplyToCommand(client, "%s%sYou don't need to specify the type of match. Just say %s!start", CLR_INFO, CHAT_PREFIX, CLR_HIGH);
	
	if(IsClientObserver(client) && !IsClientAdmin(client))
	{
		CReplyToCommand(client, "%s%sError: %sSpectators can't use this command.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
	}
	else if(!IsModeMatchable(mode))
	{
		CReplyToCommand(client, "%s%sError: %sThe current mode %s%s%s does not support competitive matches.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_INFO, mode, CLR_MAIN);
	}
	else if(state == STATE_MATCH || state == STATE_MATCHEX)
	{
		CReplyToCommand(client, "%s%sError: %sA match is already in progress. %s!end %sit to start again.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_INFO, CLR_MAIN);
	}
	else if(state == STATE_CHANGE || state == STATE_MATCHWAIT)
	{
		CReplyToCommand(client, "%s%sError: %sWait for the current action to complete first.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
	}
	else if(state == STATE_PAUSE)
	{
		CReplyToCommand(client, "%s%sError: %sYou can't use this command when the game is paused.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
	}
	else if(state == STATE_POST || XMS_GetTimeRemaining(false) < 1)
	{
		CReplyToCommand(client, "%s%sError: %sThe game has ended. You must reload the map first.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
	}
	else
	{
		XMS_SetGamestate(STATE_MATCHWAIT);
		
		CPrintToChatAllFrom(client, false, "%sStarted match", CLR_HIGH);
		if(XMS_IsGameTeamplay() && GetTeamClientCount(TEAM_REBELS) != GetTeamClientCount(TEAM_COMBINE))
		{
			CPrintToChatAll("%sWarning: %sTeams are unbalanced!", CLR_FAIL, CLR_MAIN);
		}
		
		RestartGame();
		CreateTimer(1.0, T_Start, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return Plugin_Handled;
}

public Action Command_Stop(int client, int args)
{
	int state = XMS_GetGamestate();
	
	if(IsClientObserver(client) && !IsClientAdmin(client))
	{
		CReplyToCommand(client, "%s%sError: %sSpectators can't use this command.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
		return Plugin_Handled;
	}
	
	if(state == STATE_PAUSE)
	{
		CReplyToCommand(client, "%s%sError: %sYou can't use this command when the game is paused.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
		return Plugin_Handled;
	}
	if(state == STATE_DEFAULT)
	{
		CReplyToCommand(client, "%s%sError: %sThere is no match to stop.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
		return Plugin_Handled;
	}
	if(state == STATE_MATCHEX)
	{
		CReplyToCommand(client, "%s%sError: %sYou can't stop the match during overtime.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
		return Plugin_Handled;
	}
	if(state == STATE_CHANGE || state == STATE_MATCHWAIT)
	{
		CReplyToCommand(client, "%s%sError: %sPlease wait for the current action to complete.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
		return Plugin_Handled;
	}
	if(state == STATE_POST || XMS_GetTimeRemaining(false) < 1)
	{
		CReplyToCommand(client, "%s%sError: %sThe game has ended.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
		return Plugin_Handled;
	}
	
	CPrintToChatAllFrom(client, false, "%sStopped the match", CLR_HIGH);
	XMS_SetGamestate(STATE_DEFAULT);
	RestartGame();
	
	return Plugin_Handled;
}

public Action Command_List(int client, int args)
{
	char	sFile[PLATFORM_MAX_PATH];
	Handle	dir;
	any		filetype;
	
	PrintToChat(client, "***");
	dir = OpenDirectory(Path_Maps);
	while(ReadDirEntry(dir, sFile, sizeof(sFile), filetype))
	{
		if(filetype == FileType_File && strlen(sFile) <= MAX_MAP_LENGTH && ReplaceString(sFile, sizeof(sFile), ".bsp", NULL_STRING))
		{
			PrintToChat(client, sFile);
		}
	}
	CloseHandle(dir);
	PrintToChat(client, "***");
}

public Action Command_Pause(int client, int args)
{
	FakeClientCommand(client, "pause");
}

public Action Command_Coinflip(int client, int args)
{
	int heads = GetRandomInt(0, 1);
	
	CPrintToChatAllFrom(client, false, "%sFlipped a coin - it landed on %s%s%s.", CLR_MAIN, CLR_HIGH, heads ? "heads" : "tails", CLR_MAIN);
}

public Action ACommand_Forcespec(int client, int args)
{
	if(!args)
	{
		CReplyToCommand(client, "%s%sUsage: !forcespec <player name>", CLR_INFO, CHAT_PREFIX);
		return Plugin_Handled;
	}
	
	int target = ClientArgToTarget(client, 1);
	
	if(target > 0 && IsClientInGame(target))
	{
		if(GetClientTeam(target) != TEAM_SPECTATORS)
		{
			ChangeClientTeam(target, TEAM_SPECTATORS);
			CPrintToChat(target, "%s%sAn admin has forced you to spectate. Follow admin instructions!", CLR_FAIL, CHAT_PREFIX);
			CReplyToCommand(client, "%s%sMoved %s%N%s to spectators.", CLR_MAIN, CHAT_PREFIX, CLR_HIGH, target, CLR_MAIN);
		}
		else CReplyToCommand(client, "%s%sError: %s%N%s is already a spectator.", CLR_FAIL, CHAT_PREFIX, CLR_HIGH, target, CLR_MAIN);
	}
	
	return Plugin_Handled;	
}

public Action T_Start(Handle timer)
{
	static int iter;
	
	if(iter == DELAY_START - 1)
	{
		XMS_SetGamestate(STATE_MATCH);
		RestartGame();
	}
	if(iter != DELAY_START)
	{
		PrintCenterTextAll("~ match starting in %i seconds ~", DELAY_START - iter);
		PlayGameSoundAll(SOUND_T_COUNT);
		iter++;
		return Plugin_Continue;
	}
	
	PrintCenterTextAll(NULL_STRING);
	PlayGameSoundAll(SOUND_T_END);
	
	iter = 0;
	return Plugin_Stop;	
}

public Action T_Change(Handle timer, Handle dpack)
{
	static int iter;
	static char	map[MAX_MAP_LENGTH], cmap[MAX_MAP_LENGTH], mode[MAX_MODE_LENGTH];
	
	if(!iter)
	{
		ResetPack(dpack);
		ReadPackString(dpack, map, sizeof(map));
		ReadPackString(dpack, cmap, sizeof(cmap));
		ReadPackString(dpack, mode, sizeof(mode));
	}
	
	if(iter == DELAY_CHANGE)
	{
		PrintCenterTextAll(NULL_STRING);
		XMS_SetGamemode(mode);
		ServerCommand("sm_nextmap %s;changelevel_next", map);
		
		iter = 0;
		return Plugin_Stop;
	}
	else
	{
		PrintCenterTextAll("~ loading %s:%s in %i seconds ~", mode, cmap, DELAY_CHANGE - iter);
		
		if(DELAY_CHANGE - iter > 1) PlayGameSoundAll(SOUND_T_COUNT);
		else 						PlayGameSoundAll(SOUND_T_END);
	}
	
	iter++;
	return Plugin_Continue;
}

void RequestChange(int client, const char[] mode, const char[] map)
{
	DataPack	dpack;
	char cmap[MAX_MAP_LENGTH];
	
	XMS_SetGamestate(STATE_CHANGE);
	
	if(StrContains(map, "dm_") == 0 || StrContains(map, "jm_") == 0 || StrContains(map, "tdm_") == 0 || StrContains(map, "pg_") == 0 || StrContains(map, "jump_") == 0 || StrContains(map, "js_") == 0 || StrContains(map, "surf_") == 0 || StrContains(map, "tr_") == 0 || StrContains(map, "z_") == 0)
	{
		strcopy(cmap, sizeof(cmap), map[StrContains(map, "_") +1]);
	}
	else strcopy(cmap, sizeof(cmap), map);
	
	CPrintToChatAllFrom(client, false, "%sChanging to %s%s:%s", CLR_MAIN, CLR_HIGH, mode, cmap);
	
	CreateDataTimer(1.0, T_Change, dpack, TIMER_REPEAT);
	dpack.WriteString(map);
	dpack.WriteString(cmap);
	dpack.WriteString(mode);
}

void RestartGame()
{
	ServerCommand("mp_restartgame 1");
	PrintCenterTextAll(NULL_STRING);
}

bool GetMapByAbbrev(char[] buffer, int maxlen, const char[] abbrev)
{
	XMS_GetConfigString(buffer, maxlen, abbrev, "MapAbbrevs");
	if(strlen(buffer)) return true;
	return false;
}

bool IsValidMode(const char[] mode)
{
	char gamemodes[512];
	
	XMS_GetConfigKeys(gamemodes, sizeof(gamemodes), "GameModes");
	return (IsModeDistinctInList(mode, gamemodes));
}

bool IsModeDistinctInList(const char[] mode, const char[] list)
{
	char modex[32];
	
	if(StrEqual(list, mode, false)) return true;
	
	Format(modex, sizeof(modex), "%s,", mode);
	if(StrContains(list, modex, false) == 0) return true;
		
	Format(modex, sizeof(modex), ",%s,", mode);
	if(StrContains(list, modex, false) != -1) return true;
		
	Format(modex, sizeof(modex), ",%s", mode);
	if(StrEqual(list[strlen(list) - strlen(modex)], modex, false)) return true;
	
	return false;
}

int GetModeForMap(char[] buffer, int maxlen, const char[] map)
{
	char currentmode[32];
	
	if(!XMS_GetConfigString(buffer, maxlen, map, "MapModes"))
	{
		if(!XMS_GetConfigString(buffer, maxlen, "$default", "MapModes")) return -1;
		
		XMS_GetGamemode(currentmode, sizeof(currentmode));
		if(!strlen(currentmode) || !IsModeDistinctInList(currentmode, buffer))
		{
			if(StrContains(buffer, ","))
			{
				SplitString(buffer, ",", buffer, maxlen);
				return 0;
			}
		}
		
		strcopy(buffer, maxlen, currentmode);
		return 0;
	}
	
	return 1;
}

bool IsModeMatchable(const char[] mode)
{
	char buffer[2];
	
	if(XMS_GetConfigString(buffer, sizeof(buffer), "Matchable", "GameModes", mode))
	{
		return view_as<bool>(StringToInt(buffer));
	}
	return false;
}
