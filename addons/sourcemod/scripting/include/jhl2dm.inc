#if defined _jhl2dm_included
    #endinput
#endif
#define _jhl2dm_included

/**************************************************************************************************/

#define MAX_MAP_LENGTH  32
#define MAX_SAY_LENGTH  192
#define COLOR_NORMAL      0xFFFFFF
#define COLOR_INFORMATION 0xCCCCCC
#define COLOR_HIGHLIGHT   0x00FF80
#define COLOR_ERROR       0xFF2200

enum(+=1) {
    TEAM_SPECTATORS = 1, TEAM_COMBINE, TEAM_REBELS,
    SPECMODE_FIRSTPERSON, SPECMODE_THIRDPERSON, SPECMODE_ENEMYVIEW, SPECMODE_FREELOOK    
}

/**************************************************************************************************/

stock int GameVersion()
{
    static int version;
    if(!version) {
        char buffer[512];
        ServerCommandEx(buffer, sizeof(buffer), "version");
        SplitString(buffer[StrContains(buffer, "Server version:") + 16], "\n", buffer, sizeof(buffer));
        version = StringToInt(buffer);
    }
    return version;
}

stock int Tickrate()
{
    static int tick;
    if(!tick) {
        tick = RoundToFloor(1.0 / GetTickInterval());
    }
    return tick;
}

stock bool IsClientAdmin(int client, int type=ADMFLAG_GENERIC)
{
    return CheckCommandAccess(client, "generic_admin", type, false);
}

stock char GetClientSteamID(int client, AuthIdType type=AuthId_Engine)
{
    char id[32];
    GetClientAuthId(client, type, id, sizeof(id));
    return id;
}

stock int GetRealClientCount(bool inGameOnly=true, bool includeBots=false, bool includeSpectators=true)
{
    int count;
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i) || (inGameOnly && !IsClientInGame(i)) || (!includeBots && IsFakeClient(i)) || (!includeSpectators && IsClientObserver(i))) {
            continue;
        }
        count++;
    }
    return count;
}

stock int GetClientVelocity(int client)
{
    float x, y, z;
    x = GetEntDataFloat(client, FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]"));
    y = GetEntDataFloat(client, FindSendPropInfo("CBasePlayer", "m_vecVelocity[1]"));
    z = GetEntDataFloat(client, FindSendPropInfo("CBasePlayer", "m_vecVelocity[2]"));
    return RoundToNearest(SquareRoot(x * x + y * y + z * z));
}

stock bool IsItemDistinctInList(const char[] item, const char[] list, bool caseSensitive=false)
{
    char itemx[32];
    int len;
    
    if(StrEqual(list, item, false)) {
        return true;
    }
    
    Format(itemx, sizeof(itemx), "%s,", item);
    if(StrContains(list, itemx, false) == 0) {
        return true;
    }
    
    Format(itemx, sizeof(itemx), ",%s,", item);
    if(StrContains(list, itemx, false) != -1) {
        return true;
    }
    
    Format(itemx, sizeof(itemx), ",%s", item);
    
    len = strlen(list) - strlen(itemx);
    if(len < 0) {
        len = 0;
    }
    
    if(StrEqual(list[len], itemx, caseSensitive)) {
        return true;
    }
    return false;
}

stock int ClientArgToTarget(int client, int arg, bool excludeBots=true)
{
    char buffer[MAX_NAME_LENGTH];
    int target;
    
    GetCmdArg(arg, buffer, sizeof(buffer));
    if(String_IsNumeric(buffer)) {
        target = GetClientOfUserId(StringToInt(buffer));
    }
    
    if(!target || !IsClientInGame(target) || IsFakeClient(target)) {
        target = FindTarget(client, buffer, excludeBots, false);
    }
    return target;
}

stock int GetCmdArgInt(int arg)
{
    char buffer[192];
    GetCmdArg(arg, buffer, sizeof(buffer));
    return (StringToInt(buffer));
}

stock void ClientCommandAll(const char[] command, any...)
{
    char formatCmd[PLATFORM_MAX_PATH];
    
    VFormat(formatCmd, PLATFORM_MAX_PATH, command, 2);
    for (int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }
        ClientCommand(i, formatCmd);
    }
}

stock int GetTopPlayer(bool ignoreBots=true)
{
    int best_score = -99, best_scorer;
    bool tie;
        
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i) || !IsClientInGame(i) || GetClientTeam(i) == TEAM_SPECTATORS) {
            continue;
        }
        
        if(ignoreBots && IsFakeClient(i)) {
            continue;
        }
        
        int score = GetClientFrags(i);
            
        if(score < best_score) {
            continue;
        }
            
        if(score == best_score) {
            tie = true;
        }
            
        if(score > best_score || (tie && GetClientDeaths(i) < GetClientDeaths(best_scorer))) {
            best_score = score;
            best_scorer = i;
            tie = false;
        }
    }
        
    if(tie) {
        return 0;
    }
    
    return best_scorer;
}

stock int GetTopTeam()
{
    int r = GetTeamScore(TEAM_REBELS);
    int c = GetTeamScore(TEAM_COMBINE);
    return (r == c ? 0 : r > c ? r : c);
}


// clientprefs
#if defined _clientprefs_included

stock int GetClientCookieInt(int client, Handle cookie, int minBound=-9999, int maxBound=9999)
{
    char buffer[8];
    GetClientCookie(client, cookie, buffer, sizeof(buffer));
    
    int result = StringToInt(buffer);
    return(result < minBound ? minBound : result > maxBound ? maxBound : result);
}

#endif


// morecolors
#if defined _more_colors_included

stock void MC_PrintToChatFrom(int client, int recipient, bool team, const char[] message, any...)
{
    char fmessage[512];
    VFormat(fmessage, sizeof(fmessage), message, 5);
        
    MC_PrintToChatEx(recipient, client, "%s{teamcolor}%N{default} :  %s", IsClientObserver(client) ? "*SPEC* " : team ? IsClientObserver(client) ? "(Spectator)" : "(TEAM)" : NULL_STRING, client, fmessage);
}
    
stock void MC_PrintToChatAllFrom(int client, bool team, const char[] message, any...)
{
    char fmessage[512];
    VFormat(fmessage, sizeof(fmessage), message, 4);
        
    if(client != 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
                continue;
            }
            
            if(team && GetClientTeam(client) != GetClientTeam(i)) {
                continue;
            }
            
            MC_PrintToChatFrom(client, i, team, fmessage);
        }
    }
    else {
        MC_PrintToChatAll(fmessage);
    }
}

#endif