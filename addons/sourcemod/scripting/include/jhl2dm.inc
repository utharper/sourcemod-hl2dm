#if !defined _smlib_included
    #error "smlib required"
#endif

#if defined _jhl2dm_included
    #endinput
#endif
#define _jhl2dm_included

// dumping ground for minor stuff used across my plugins

#define MAX_MAP_LENGTH  32
#define MAX_SAY_LENGTH  192

#define TEAM_SPECTATORS 1
#define TEAM_COMBINE    2
#define TEAM_REBELS     3

#define SPECMODE_FIRSTPERSON 4
#define SPECMODE_THIRDPERSON 5
#define SPECMODE_ENEMYVIEW   6
#define SPECMODE_FREELOOK    7

// clientprefs
#if defined _clientprefs_included
stock bool IsCookieEnabled(Handle hCookie, int iClient, bool bUnset=true)
{
    if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
        return false;
    }

    if (!AreClientCookiesCached(iClient) && !bUnset) {
        return false;
    }

    return (GetClientCookieInt(iClient, hCookie) == 1);
}

stock int GetClientCookieInt(int iClient, Handle hCookie)
{
    char sCookie[8];

    GetClientCookie(iClient, hCookie, sCookie, sizeof(sCookie));

    return StringToInt(sCookie);
}
#endif

// morecolors
#if defined _more_colors_included

#define COLOR_NORMAL      0xFFFFFF
#define COLOR_INFORMATION 0xCCCCCC
#define COLOR_HIGHLIGHT   0x00FF80
#define COLOR_ERROR       0xFF2200
stock void RegisterColors()
{
    MC_AddColor("N", COLOR_NORMAL);
    MC_AddColor("I", COLOR_INFORMATION);
    MC_AddColor("H", COLOR_HIGHLIGHT);
    MC_AddColor("E", COLOR_ERROR);
}

stock void MC_PrintToChatFrom(int iClient, int iRecipient, bool bTeam, const char[] sFormat, any...)
{
    char sMessage[512];

    VFormat(sMessage, sizeof(sMessage), sFormat, 5);

    MC_PrintToChatEx(iRecipient, iClient, "%s{teamcolor}%N{default} :  %s", IsClientObserver(iClient) ? "*SPEC* " : bTeam ? IsClientObserver(iClient) ? "(Spectator)" : "(TEAM)" : NULL_STRING, iClient, sMessage);
}

stock void MC_PrintToChatAllFrom(int iClient, bool bTeam, const char[] sFormat, any...)
{
    char sMessage[512];

    VFormat(sMessage, sizeof(sMessage), sFormat, 4);

    if (iClient != 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
                continue;
            }

            if (bTeam && GetClientTeam(iClient) != GetClientTeam(i)) {
                continue;
            }

            MC_PrintToChatFrom(iClient, i, bTeam, sMessage);
        }
    }
    else {
        MC_PrintToChatAll(sMessage);
    }
}
#endif

// misc
stock int GameVersion()
{
    static int iVersion;

    if (!iVersion)
    {
        char sVersion[512];

        ServerCommandEx(sVersion, sizeof(sVersion), "version");
        SplitString(sVersion[StrContains(sVersion, "Server version:") + 16], "\n", sVersion, sizeof(sVersion));
        iVersion = StringToInt(sVersion);
    }

    return iVersion;
}

stock int Tickrate()
{
    static int iRate;

    if (!iRate) {
        iRate = RoundToFloor(1.0 / GetTickInterval());
    }

    return iRate;
}

stock bool IsClientAdmin(int iClient, int iFlag=ADMFLAG_GENERIC)
{
    return CheckCommandAccess(iClient, "generic_admin", iFlag, false);
}

stock char[] UnbufferedAuthId(int iClient, AuthIdType iType=AuthId_Engine)
{
    char sId[32];

    GetClientAuthId(iClient, iType, sId, sizeof(sId));

    return sId;
}

stock int GetRealClientCount(bool bInGameOnly=true, bool bIncludeBots=false, bool bIncludeSpectators=true)
{
    int iCount;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i) || (bInGameOnly && !IsClientInGame(i)) || (!bIncludeBots && IsFakeClient(i)) || (!bIncludeSpectators && IsClientObserver(i))) {
            continue;
        }

        iCount++;
    }

    return iCount;
}

stock int GetClientVelocity(int iClient)
{
    float fVel[3];

    fVel[0] = GetEntDataFloat(iClient, FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]"));
    fVel[1] = GetEntDataFloat(iClient, FindSendPropInfo("CBasePlayer", "m_vecVelocity[1]"));
    fVel[2] = GetEntDataFloat(iClient, FindSendPropInfo("CBasePlayer", "m_vecVelocity[2]"));

    return RoundToNearest(SquareRoot(fVel[0] * fVel[0] + fVel[1] * fVel[1] + fVel[2] * fVel[2]));
}

stock bool IsItemDistinctInList(const char[] sItem, const char[] sList, bool bCaseSensitive=false)
{
    int  iLen;
    char sFind[32];

    if (StrEqual(sList, sItem, false)) {
        return true;
    }

    Format(sFind, sizeof(sFind), "%s,", sItem);
    if (StrContains(sList, sFind, false) == 0) {
        return true;
    }

    Format(sFind, sizeof(sFind), ",%s,", sItem);
    if (StrContains(sList, sFind, false) != -1) {
        return true;
    }

    Format(sFind, sizeof(sFind), ",%s", sItem);

    iLen = strlen(sList) - strlen(sFind);
    if (iLen < 0) {
        iLen = 0;
    }

    return StrEqual(sList[iLen], sFind, bCaseSensitive);
}

stock int ClientArgToTarget(int iClient, int iArg, bool bExcludeBots=true)
{
    int  iTarget;
    char sArg[MAX_NAME_LENGTH];

    GetCmdArg(iArg, sArg, sizeof(sArg));

    if (String_IsNumeric(sArg)) {
        iTarget = GetClientOfUserId(StringToInt(sArg));
    }

    if (!iTarget || !IsClientInGame(iTarget) || IsFakeClient(iTarget)) {
        iTarget = FindTarget(iClient, sArg, bExcludeBots, false);
    }

    return iTarget;
}

stock void ClientCommandAll(const char[] sFormat, any...)
{
    char sCommand[PLATFORM_MAX_PATH];

    VFormat(sCommand, PLATFORM_MAX_PATH, sFormat, 2);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }

        ClientCommand(i, sCommand);
    }
}

stock int GetTopPlayer(bool bIgnoreBots=true)
{
    int  iBestScore = -99,
         iWinner;
    bool bTie;

    for (int i = 1; i <= MaxClients; i++)
    {
        int iScore;

        if (!IsClientConnected(i) || !IsClientInGame(i) || GetClientTeam(i) == TEAM_SPECTATORS) {
            continue;
        }

        if (bIgnoreBots && IsFakeClient(i)) {
            continue;
        }

        iScore = GetClientFrags(i);

        if (iScore < iBestScore) {
            continue;
        }

        if (iScore == iBestScore) {
            bTie = true;
        }

        if (iScore > iBestScore || (bTie && GetClientDeaths(i) < GetClientDeaths(iWinner)))
        {
            iBestScore = iScore;
            iWinner = i;
            bTie = false;
        }
    }

    if (bTie) {
        return 0;
    }

    return iWinner;
}

stock int GetTopTeam()
{
    int iRebels  = GetTeamScore(TEAM_REBELS),
        iCombine = GetTeamScore(TEAM_COMBINE);

    return (
        iRebels > iCombine ? TEAM_REBELS
        : iCombine > iRebels ? TEAM_COMBINE
        : 0
    );
}

stock char[] Timestring(float fTime, bool bFloatingSeconds=false, bool bClockStyle=false)
{
    char sTime[32];
    int  iHours   = RoundToNearest(fTime) / 3600,
         iSeconds = RoundToNearest(fTime) % 60,
         iMinutes = RoundToNearest(fTime) / 60 - (iHours ? (iHours * 60) : 0),
         iDays    = RoundToFloor(float(iHours / 24));

    if (!iHours)
    {
        if (fTime >= 60) {
            Format(sTime, sizeof(sTime), "%i%s%02i%s", iMinutes, bClockStyle ? ":" : "m ", iSeconds, bClockStyle ? "" : "s");
        }
        else if (!bFloatingSeconds) {
            Format(sTime, sizeof(sTime), "%i%s", RoundToNearest(fTime), bClockStyle ? "" : "s");
        }
        else {
            Format(sTime, sizeof(sTime), "%s%.1f", sTime, fTime);
        }
    }
    else
    {
        if (iDays) {
            iHours -= iDays * 24;
            Format(sTime, sizeof(sTime), "%id ", iDays);
        }
        Format(sTime, sizeof(sTime), "%s%ih %i%s%02i%s", sTime, iHours, iMinutes, bClockStyle ? ":" : "m ", iSeconds, bClockStyle ? "" : "s");
    }

    return sTime;
}

stock char[] BigNumber(int iValue)
{
    char sBigNums[10][4] = { "０", "１", "２", "３", "４", "５", "６", "７", "８", "９" };

    return sBigNums[iValue];
}

stock char[] IntToChar(int iValue)
{
    char sValue[32];
    IntToString(iValue, sValue, sizeof(sValue));
    return sValue;
}

stock bool AttemptTranslation(char[] sPhrase, int iMaxlen, int iClient, bool bLogError=true)
{
    if (!TranslationPhraseExists(sPhrase))
    {
        if (bLogError) {
            LogError("Translation \"%s\" not found!", sPhrase);
        }

        return false;
    }

    Format(sPhrase, iMaxlen, "%T", sPhrase, iClient);

    return true;
}

stock any clamp(any Value, any Min, any Max)
{
    return Value < Min ? Min : Value > Max ? Max : Value;
}

#if defined _smlib_math_included
stock int Math_GetRandomIntNot(int iMin, int iMax, int iNot)
{
    int  iResult;

    do {
        iResult = Math_GetRandomInt(iMin, iMax);
    }
    while (iResult == iNot);

    return iResult;
}
#endif