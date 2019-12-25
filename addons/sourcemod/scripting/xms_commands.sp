#define PLUGIN_VERSION "1.14"
#define UPDATE_URL     "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_commands.upd"

public Plugin myinfo=
{
    name        = "XMS - Commands",
    version     = PLUGIN_VERSION,
    description = "Client commands for XMS",
    author      = "harper",
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

#define DELAY_ACTION 4
#define SOUND_TIMER_COUNT "buttons/blip1.wav"
#define SOUND_TIMER_END   "hl1/fvox/beep.wav"

char Path_Maps  [PLATFORM_MAX_PATH],
     Currentmode[MAX_MODE_LENGTH],
     Gamemodes  [512];

/******************************************************************/

public void OnPluginStart()
{   
    LoadTranslations("common.phrases.txt");
    BuildPath(Path_SM, Path_Maps, PLATFORM_MAX_PATH, "../../maps");

    RegConsoleCmd("sm_run"      , Command_Run,      "Change to the specified map and/or mode");
    RegConsoleCmd("sm_start"    , Command_Start,    "Start a competitive match");
    RegConsoleCmd("sm_stop"     , Command_Stop,     "Stop a competitive match");
    RegConsoleCmd("sm_list"     , Command_List,     "List available maps");
    RegConsoleCmd("sm_coinflip" , Command_Coinflip, "Flip a coin");
    RegConsoleCmd("sm_profile"  , Command_Profile,  "View steam profile of player");
    
    RegAdminCmd("sm_forcespec", ACommand_Forcespec, ADMFLAG_GENERIC, "Force a player to spectate");
    
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

public void OnAllPluginsLoaded()
{
    XMS_GetConfigKeys(Gamemodes, sizeof(Gamemodes), "GameModes");
}

public void OnMapStart()
{
    XMS_GetGamemode(Currentmode, sizeof(Currentmode));
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    // add support for PMS commands, and strip uppercase characters from all command arguments:
    if(StrContains(sArgs, "!") == 0 || StrContains(sArgs, "/") == 0 || StrContains(sArgs, "#.#") == 0)
    {
        char args [MAX_SAY_LENGTH];
        bool corrected;
        
        if(StrContains(sArgs, "#.#") == 0)
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
                String_ToLower(args, args, sizeof(args));
                corrected = true;
            }
        }
        
        if(StrContains(args, "cm") == 1)
        {
            FakeClientCommandEx(client, "say !run%s", args[3]);
        }
        else if(StrContains(args, "tp ") == 1 || StrContains(args, "teamplay ") == 1)
        {
            if(StrContains(args, " on") != -1 || StrContains(args, " 1") != -1)
            {
                FakeClientCommandEx(client, "say !run tdm");
            }
            else if(StrContains(args, " off") != -1 || StrContains(args, " 0") != -1)
            {
                FakeClientCommandEx(client, "say !run dm");
            }
        }
        else if(StrEqual(args[1], "cf"))
        {
            FakeClientCommandEx(client, "say !coinflip");
        }
        else if(corrected)
        {
            FakeClientCommandEx(client, "say %s", args);
        }
        else return Plugin_Continue;
        
        return Plugin_Handled;
    }
        
    // Basetriggers output overrides:
    
    bool broadcast = GetConVarBool(FindConVar("sm_trigger_show"));
    char output [MAX_SAY_LENGTH];
        
    if(StrEqual(sArgs, "timeleft"))
    {
        bool  over = (XMS_GetGamestate() == STATE_POST);
        float time = XMS_GetTimeRemaining(over);
        int   h = RoundToNearest(time) / 3600,
              s = RoundToNearest(time) % 60,
              m = RoundToNearest(time) / 60 - (h ? (h * 60) : 0);
            
        if(over) Format(output, sizeof(output), "%s%sMap will auto-change in %s%i%s seconds", CLR_MAIN, (broadcast ? NULL_STRING : CHAT_PREFIX), CLR_HIGH, s, CLR_MAIN);
        else     Format(output, sizeof(output), "%s%sTime remaining: %s%ih %im %02is", CLR_MAIN, (broadcast ? NULL_STRING : CHAT_PREFIX), CLR_HIGH, h, m, s);
    }
    else if(StrEqual(sArgs, "nextmap"))
    {
        char nextmap[MAX_MAP_LENGTH];
        
        GetNextMap(nextmap, sizeof(nextmap));
        Format(output, sizeof(output), "%s%sNext map: %s%s", CLR_MAIN, (broadcast ? NULL_STRING : CHAT_PREFIX), CLR_HIGH, nextmap);
    }
    else if(StrEqual(sArgs, "ff"))
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
    static int  fail_iter [MAXPLAYERS + 1],
                multi_iter[MAXPLAYERS + 1],
                uselessCharCount;
                
    int         hits,
                xhits,
                state = XMS_GetGamestate();
    bool        exact,
                abbrev,
                matched;
    char        sQuery  [MAX_MAP_LENGTH],
                sAbbrev [MAX_MAP_LENGTH],
                sFile   [PLATFORM_MAX_PATH],
                sOutput [MAX_SAY_LENGTH],
                sConOut [MAX_BUFFER_LENGTH],
                mapChangingTo  [MAX_MAP_LENGTH],
                modeChangingTo [MAX_MODE_LENGTH];
    Handle      dir;
    any         filetype;
    
    if(!args || args > 2)  CReplyToCommand(client, "%s%sUsage: !run <map and/or gamemode>, eg '!run tdm', '!run dm lockdown', '!run overwatch'", CLR_INFO, CHAT_PREFIX);
    else switch(state)
    {
        case STATE_PAUSE:  CReplyToCommand(client, "%s%sError: %sYou can't use this command when the game is paused.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
        case STATE_CHANGE: CReplyToCommand(client, "%s%sError: %sPlease wait for the current action to complete.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
        case STATE_MATCH:  CReplyToCommand(client, "%s%sError: %sYou must %s!stop %sthe current match before using this command.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_INFO, CLR_MAIN);
        default:
        {
            GetCmdArg(1, sQuery, sizeof(sQuery));
            String_ToLower(sQuery, sQuery, sizeof(sQuery));
            
            // support VG match start commands
            if(StrEqual(sQuery, "1v1") || StrEqual(sQuery, "2v2") || StrEqual(sQuery, "3v3") || StrEqual(sQuery, "4v4") || StrEqual(sQuery, "duel"))
            {
                FakeClientCommandEx(client, "say !start");
                return Plugin_Handled;
            }
            
            // check for gamemode in first arg
            if(XMS_IsValidGamemode(sQuery))
            {
                strcopy(modeChangingTo, sizeof(modeChangingTo), sQuery);
                
                if(args > 1)
                {
                    // map also
                    GetCmdArg(2, sQuery, sizeof(sQuery));
                    String_ToLower(sQuery, sQuery, sizeof(sQuery));
                }
                else
                {
                    // mode only
                    char nextmap[MAX_MAP_LENGTH];
                    
                    if(!StrEqual(Currentmode, modeChangingTo))
                    {
                        if(XMS_GetConfigString(nextmap, sizeof(nextmap), "DefaultMap", "GameModes", modeChangingTo) && IsMapValid(nextmap))
                        {
                            strcopy(mapChangingTo, sizeof(mapChangingTo), nextmap);
                        }
                        else GetCurrentMap(mapChangingTo, sizeof(mapChangingTo));
                        
                        RequestChange(client, modeChangingTo, mapChangingTo);
                    }
                    else CReplyToCommand(client, "%s%sError: %sAlready using mode %s%s", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_INFO, modeChangingTo);
                    
                    return Plugin_Handled;
                }
            }
            
            else if(args > 1)
            {
                // first arg was not a valid mode, try second
                GetCmdArg(2, modeChangingTo, sizeof(modeChangingTo));
                String_ToLower(modeChangingTo, modeChangingTo, sizeof(modeChangingTo));
                
                if(!XMS_IsValidGamemode(modeChangingTo))
                {       
                    CReplyToCommand(client, "%s%sError:%s Invalid gamemode. Valid modes: %s%s", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_INFO, Gamemodes);
                    return Plugin_Handled;
                }
            }
            
            // de-abbreviate map if applicable
            abbrev = GetMapByAbbrev(sAbbrev, sizeof(sAbbrev), sQuery);
            
            // lazy hack to prevent exceeding character limit in chat output
            if(!uselessCharCount)
            {
                uselessCharCount = strlen(CLR_MAIN) * 3 + strlen(CHAT_PREFIX) + strlen(CLR_HIGH) + strlen(CLR_INFO) + strlen(CHAT_PREFIX);
                uselessCharCount += strlen(", and xxx others.") + strlen("Found: "); // not using actual numbers in case we change things around
                uselessCharCount += 2; // not sure what this is for, but scared to break it now
            }
            
            // we have all the info, time to do the work
            dir = OpenDirectory(Path_Maps);
            while(ReadDirEntry(dir, sFile, sizeof(sFile), filetype) && !exact)
            {
                if(filetype == FileType_File && strlen(sFile) <= MAX_MAP_LENGTH && ReplaceString(sFile, sizeof(sFile), ".bsp", NULL_STRING))
                {
                    if(StrContains(sFile, sQuery, false) >= 0 || (abbrev && StrContains(sFile, sAbbrev, false) >= 0))
                    {
                        exact = (abbrev ? StrEqual(sFile, sAbbrev, false)
                                        : StrEqual(sFile, sQuery, false)
                        );
                        
                        hits++;
                        
                        if(hits == 1 || exact)
                        {
                            strcopy(mapChangingTo, sizeof(mapChangingTo), sFile);
                            hits = 1;
                            xhits = 0;
                        }
                        
                        if(!exact)
                        {
                            // send results to console also
                            Format(sConOut, sizeof(sConOut), "%s　%s", sConOut, sFile);
                            
                            // colorise matches
                            FReplaceString(sFile, sizeof(sFile), sQuery, false, "%s%s%s", CLR_HIGH, sQuery, CLR_INFO);
                                
                            if(strlen(sOutput) + strlen(sFile) + uselessCharCount <= MAX_SAY_LENGTH)
                            {
                                Format(sOutput, sizeof(sOutput), "%s%s%s", sOutput,
                                    hits == 1 ? NULL_STRING
                                    : ", ", sFile
                                );
                                
                                xhits++;
                            }
                        }
                    }
                }
            }
            
            if(hits == 1)
            {
                matched = true;
                if(args == 1) GetModeForMap(modeChangingTo, sizeof(modeChangingTo), mapChangingTo);
            }
            else if(!hits)
            {
                fail_iter[client]++;
                CReplyToCommand(client, "%sError: %sMap or mode %s%s%s not found.", CLR_FAIL, CLR_MAIN, CLR_INFO, sQuery, CLR_MAIN);
            }
            else
            {
                multi_iter[client]++;
                PrintToConsole(client, "\n\n\n*** Maps matching query `%s` ...\n%s\n\n\n", sQuery, sConOut);
                CReplyToCommand(client, "%s%sFound%s: %s%s, and %s%i%s others.", CLR_MAIN, CHAT_PREFIX, CLR_INFO, sOutput, CLR_MAIN, CLR_HIGH, hits - xhits, CLR_MAIN);
            }
            
            if(matched)
            {
                RequestChange(client, modeChangingTo, mapChangingTo);
            }
            else if(multi_iter[client] >= 3 && !exact && hits > xhits)
            {
                // maybe client is looking for a map but the chat output isn't long enough
                CReplyToCommand(client, "%s%sTip: Open your console for a full list of maps matching your search.", CLR_INFO, CHAT_PREFIX);
                multi_iter[client] = 0;
            }
            else if(fail_iter[client] >= 3)
            {
                // maybe client needs reminding what is available on the server
                CReplyToCommand(client, "%s%sTip: View a list of available maps/mode with the %s!list %scommand", CLR_INFO, CHAT_PREFIX, CLR_HIGH, CLR_INFO);
                fail_iter[client] = 0;
            }
            
            CloseHandle(dir);
        }
    }
    return Plugin_Handled;
}
    
public Action Command_Start(int client, int args)
{
    int     state = XMS_GetGamestate();
    
    if(IsClientObserver(client) && !IsClientAdmin(client))
    {
        CReplyToCommand(client, "%s%sError: Spectators can't use this command.", CLR_FAIL, CHAT_PREFIX);
    }
    else if(!IsModeMatchable(Currentmode))
    {
        CReplyToCommand(client, "%s%sError: The current mode %s%s%s does not support competitive matches.", CLR_FAIL, CHAT_PREFIX, CLR_INFO, Currentmode, CLR_FAIL);
    }
    else if(state == STATE_MATCH || state == STATE_MATCHEX)
    {
        CReplyToCommand(client, "%s%sError: %sA match is already in progress. %s!stop %sit to start again.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_INFO, CLR_MAIN);
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
        
        CPrintToChatAllFrom(client, false, "%sStarted a competitive match", CLR_MAIN);
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
    }
    else if(state == STATE_PAUSE)
    {
        CReplyToCommand(client, "%s%sError: %sYou can't use this command when the game is paused.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
    }
    else if(state == STATE_DEFAULT || state == STATE_DEFAULTEX)
    {
        CReplyToCommand(client, "%s%sError: %sThere is no match to stop.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
    }
    else if(state == STATE_MATCHEX)
    {
        CReplyToCommand(client, "%s%sError: %sYou can't stop the match during overtime.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
    }
    else if(state == STATE_CHANGE || state == STATE_MATCHWAIT)
    {
        CReplyToCommand(client, "%s%sError: %sPlease wait for the current action to complete.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
    }
    else if(state == STATE_POST || XMS_GetTimeRemaining(false) < 1)
    {
        CReplyToCommand(client, "%s%sError: %sThe game has ended.", CLR_FAIL, CHAT_PREFIX, CLR_MAIN);
    }
    else
    {
        CPrintToChatAllFrom(client, false, "%sStopped the match", CLR_MAIN);
        
        XMS_SetGamestate(STATE_DEFAULT);
        RestartGame();
    }
    
    return Plugin_Handled;
}

public Action Command_List(int client, int args)
{
    char sArg[MAX_MODE_LENGTH],
         path_mapcycle[PLATFORM_MAX_PATH];
         
    int count;
    
    if(args)
    {
        GetCmdArg(1, sArg, sizeof(sArg));
        
        if(StrEqual(sArg, "all"))
        {
            char    sFile[PLATFORM_MAX_PATH];
            Handle  dir;
            any     filetype;
            
            CReplyToCommand(client, "%s%sListing all maps on server:", CLR_MAIN, CHAT_PREFIX);
            
            dir = OpenDirectory(Path_Maps);
            while(ReadDirEntry(dir, sFile, sizeof(sFile), filetype))
            {
                if(filetype == FileType_File && strlen(sFile) <= MAX_MAP_LENGTH && ReplaceString(sFile, sizeof(sFile), ".bsp", NULL_STRING))
                {
                    count++;
                    StripMapPrefix(sFile, sFile, sizeof(sFile));
                    CReplyToCommand(client, "%s%s%s", CLR_INFO, CHAT_PREFIX, sFile);
                }
            }
            CloseHandle(dir);
            
            CReplyToCommand(client, "%s%s^ Found %s%i %smaps on the server ^", CLR_MAIN, CHAT_PREFIX, CLR_HIGH, count, CLR_MAIN);
            
            return Plugin_Handled;
        }
    }
    else strcopy(sArg, sizeof(sArg), Currentmode);
    
    if(XMS_IsValidGamemode(sArg))
    {
        char map[MAX_MAP_LENGTH];
        File file;
        
        XMS_GetConfigString(path_mapcycle, sizeof(path_mapcycle), "Mapcycle", "GameModes", sArg);
        Format(path_mapcycle, sizeof(path_mapcycle), "cfg/%s", path_mapcycle);
        
        CReplyToCommand(client, "%s%sListing maps for gamemode %s%s%s:", CLR_MAIN, CHAT_PREFIX, CLR_HIGH, sArg, CLR_MAIN);
        
        file = OpenFile(path_mapcycle, "r");
        while(!file.EndOfFile() && file.ReadLine(map, sizeof(map)))
        {
            int len = strlen(map);
        
            if(map[0] == ';' || !IsCharAlpha(map[0])) continue;
            for(int i = 0; i < len; i++)
            {
                if(IsCharSpace(map[i]))
                {
                    map[i] = '\0';
                    break;
                }
            }
        
            if(!IsMapValid(map))
            {
                LogError("map `%s` in mapcyclefile `%s` is invalid!", map, path_mapcycle);
                continue;
            }
            
            count++;
            StripMapPrefix(map, map, sizeof(map));
            CReplyToCommand(client, "%s%s%s", CLR_INFO, CHAT_PREFIX, map);
        }
        CloseHandle(file);
        
        CReplyToCommand(client, "%s%s^ Found %s%i %smaps for gamemode %s%s%s ^", CLR_MAIN, CHAT_PREFIX, CLR_HIGH, count, CLR_MAIN, CLR_HIGH, sArg, CLR_MAIN);
        CReplyToCommand(client, "%s%sAvailable modes: %s%s", CLR_INFO, CHAT_PREFIX, CLR_HIGH, Gamemodes);
    }
    else CReplyToCommand(client, "%s%sError: %sInvalid gamemode %s", CLR_FAIL, CHAT_PREFIX, CLR_MAIN, sArg);
    
    return Plugin_Handled;
}

public Action Command_Coinflip(int client, int args)
{
    int heads = GetRandomInt(0, 1);
    
    CPrintToChatAllFrom(client, false, "%sFlipped a coin - it landed on %s%s%s.", CLR_MAIN, CLR_HIGH, heads ? "heads" : "tails", CLR_MAIN);
}

public Action Command_Profile(int client, int args)
{
    if(args)
    {
        char communityID[18],
             url[128];
        int  target = ClientArgToTarget(client, 1);
        
        if(target)
        {
            GetClientAuthId(client, AuthId_SteamID64, communityID, sizeof(communityID));
            Format(url, sizeof(url), "https://steamcommunity.com/profiles/%s", communityID);
            ShowMOTDPanel(client, "Steam Profile", url, MOTDPANEL_TYPE_URL);
        }
        // else FindTarget will advise if no match
    }
    else CReplyToCommand(client, "%s%sUsage: !profile <player name or userid>", CLR_INFO, CHAT_PREFIX);
}

public Action ACommand_Forcespec(int client, int args)
{
    if(args)
    {
        int target = ClientArgToTarget(client, 1);
        
        if(target)
        {
            if(GetClientTeam(target) != TEAM_SPECTATORS)
            {
                ChangeClientTeam(target, TEAM_SPECTATORS);
                CPrintToChat(target, "%s%sAn admin has forced you to spectate. Follow admin instructions!", CLR_FAIL, CHAT_PREFIX);
                
                CReplyToCommand(client,  "%s%sMoved %s%N%s to spectators.", CLR_MAIN, CHAT_PREFIX, CLR_HIGH, target, CLR_MAIN);
            }
            else CReplyToCommand(client, "%s%sError: %s%N%s is already a spectator.", CLR_FAIL, CHAT_PREFIX, CLR_HIGH, target, CLR_MAIN);
        }
        // else FindTarget will advise if no match
    }
    else CReplyToCommand(client, "%s%sUsage: !forcespec <player name or userid>", CLR_INFO, CHAT_PREFIX);
}

public Action T_Start(Handle timer)
{
    static int iter;
    
    if(iter == DELAY_ACTION - 1)
    {
        XMS_SetGamestate(STATE_MATCH);
        RestartGame();
    }
    if(iter != DELAY_ACTION)
    {
        PrintCenterTextAll("~ match starting in %i seconds ~", DELAY_ACTION - iter);
        PlayGameSoundAll(SOUND_TIMER_COUNT);
        iter++;
        return Plugin_Continue;
    }
    
    PrintCenterTextAll(NULL_STRING);
    PlayGameSoundAll(SOUND_TIMER_END);
    
    iter = 0;
    return Plugin_Stop; 
}

public Action T_Change(Handle timer, Handle dpack)
{
    static int iter;
    static char map[MAX_MAP_LENGTH],
                cmap[MAX_MAP_LENGTH], 
                mode[MAX_MODE_LENGTH];
    
    if(!iter)
    {
        ResetPack(dpack);
        ReadPackString(dpack, map,  sizeof(map));
        ReadPackString(dpack, cmap, sizeof(cmap));
        ReadPackString(dpack, mode, sizeof(mode));
    }
    
    if(iter == DELAY_ACTION)
    {
        PrintCenterTextAll(NULL_STRING);
        XMS_SetGamemode(mode);
        ServerCommand("sm_nextmap %s;changelevel_next", map);
        
        iter = 0;
        return Plugin_Stop;
    }
    else
    {
        PrintCenterTextAll("~ loading %s:%s in %i seconds ~", mode, cmap, DELAY_ACTION - iter);
        
        if(DELAY_ACTION - iter > 1) PlayGameSoundAll(SOUND_TIMER_COUNT);
        else                        PlayGameSoundAll(SOUND_TIMER_END);
    }
    
    iter++;
    return Plugin_Continue;
}

void RequestChange(int client, const char[] mode, const char[] map)
{
    char cmap[MAX_MAP_LENGTH];
    DataPack dpack;
    
    StripMapPrefix(map, cmap, sizeof(cmap));
    XMS_SetGamestate(STATE_CHANGE);
    
    CPrintToChatAllFrom(client, false, "%sChanging to %s%s:%s", CLR_MAIN, CLR_HIGH, mode, cmap);
    
    CreateDataTimer(1.0, T_Change, dpack, TIMER_REPEAT);
    
    dpack.WriteString(map );
    dpack.WriteString(cmap);
    dpack.WriteString(mode);
}

void RestartGame()
{
    ServerCommand("mp_restartgame 1");
    PrintCenterTextAll(NULL_STRING);
}

/******************************************************************/

stock bool GetMapByAbbrev(char[] buffer, int maxlen, const char[] abbrev)
{
    XMS_GetConfigString(buffer, maxlen, abbrev, "MapAbbrevs");
    if(strlen(buffer)) return true;
    return false;
}

stock int GetModeForMap(char[] buffer, int maxlen, const char[] map)
{   
    if(!XMS_GetConfigString(buffer, maxlen, map, "MapModes"))
    {
        if(!XMS_GetConfigString(buffer, maxlen, "$default", "MapModes")) return -1;
        
        if(!strlen(Currentmode) || !IsItemDistinctInList(Currentmode, buffer))
        {
            if(StrContains(buffer, ","))
            {
                SplitString(buffer, ",", buffer, maxlen);
                return 0;
            }
        }
        
        strcopy(buffer, maxlen, Currentmode);
        return 0;
    }
    
    return 1;
}

stock bool IsModeMatchable(const char[] mode)
{
    char buffer[2];
    
    if(XMS_GetConfigString(buffer, sizeof(buffer), "Matchable", "GameModes", mode))
    {
        return view_as<bool>(StringToInt(buffer));
    }
    return false;
}

stock int ClientArgToTarget(int client, int arg)
{
    char buffer[MAX_NAME_LENGTH];
    int target;
    
    GetCmdArg(arg, buffer, sizeof(buffer));
    
    if(String_IsNumeric(buffer))
    {
        target = GetClientOfUserId(StringToInt(buffer));
    }
    if(!target || !IsClientInGame(target) || IsFakeClient(target))
    {
        target = FindTarget(client, buffer, true, false);
    }
    return target;
}