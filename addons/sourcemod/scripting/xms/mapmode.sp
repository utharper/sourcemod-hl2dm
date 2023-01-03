/**************************************************************
 * MAP MANAGEMENT
 *************************************************************/
public void OnMapStart()
{
    char sModeDesc[32];

    if (!gCore.bReady) {
        return;
    }

    gCore.iMapChanges++;
    GetCurrentMap(gRound.sMap, sizeof(gRound.sMap));
    strcopy(gRound.sNextMode, sizeof(gRound.sNextMode), gRound.sMode);
    strcopy(sModeDesc, sizeof(sModeDesc), gRound.sMode);

    if (GetConfigString(gRound.sModeDescription, sizeof(gRound.sModeDescription), "Name", "Gamemodes", gRound.sMode) == 1) {
        Format(sModeDesc, sizeof(sModeDesc), "%s (%s)", sModeDesc, gRound.sModeDescription);
    }
    else {
        gRound.sModeDescription[0] = '\0';
    }

    Steam_SetGameDescription(sModeDesc);

    PrepareSound(SOUND_GG);
    PrepareSound(SOUND_VOTECALLED);
    PrepareSound(SOUND_VOTEFAILED);
    PrepareSound(SOUND_VOTESUCCESS);
    for (int i = 0; i < 6; i++) {
        PrepareSound(gsMusicPath[i]);
    }

    LoadConfigValues();
    GenerateGameID();
    SetGamestate(GAME_DEFAULT);
    SetGamemode(gRound.sMode);

    gRound.fStartTime = GetGameTime() - 1.0;

    gVoting.iStatus             = 0;
    for (int i = 0; i <= MaxClients; i++)
    {
        gClient[i].bForceKilled = false;
        gClient[i].iVote        = 0;
        gClient[i].iVoteTick    = 0;
        gClient[i].iMenuRefresh = 0;
    }
    gSpecialClient.iAllowed     = 0;
    gSpecialClient.iPauser      = 0;

    if (gRound.bOvertime) {
        CreateOverTimer();
    }

    if (gRound.bDisableProps) {
        RequestFrame(ClearProps);
    }

    CreateTimer(0.1, T_CheckPlayerStates, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    if (gVoting.bAutomatic) {
        gConVar.sm_nextmap.SetString(""); // fuck off
    }
}

public void OnNextmapChanged(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    strcopy(gRound.sNextMap, sizeof(gRound.sNextMap), sNewValue);
}

public Action OnMapChanging(int iClient, const char[] sCommand, int iArgs)
{
    if (gCore.bReady && iClient == 0 && (iArgs || StrEqual(sCommand, "changelevel_next")) )
    {
        SetGamestate(GAME_CHANGING);
        SetGamemode(gRound.sNextMode);

        CreateTimer(10.0, T_MapChangeFailsafe, gCore.iMapChanges);
    }

    return Plugin_Continue;
}

public void OnMapEnd()
{
    gRound.bTeamplay = gConVar.mp_teamplay.BoolValue;
    gRound.hOvertime = INVALID_HANDLE;
}

int GetMapsArray(char[][] sArray, int iLen1, int iLen2, const char[] sMapcycle = "", const char[] sMustBeginWith = "", const char[] sMustContain = "", bool bStopIfExactMatch = true, bool bStripPrefixes = false, char[][] sArray2 = sArray)
{
    int  iHits;
    bool bExact;

    // search maps directory
    if (!strlen(sMapcycle))
    {
        char             sFile[2][256];
        DirectoryListing hDir = OpenDirectory("maps");
        FileType         iType;

        while (hDir.GetNext(sFile[0], sizeof(sFile[]), iType))
        {
            int iBsp = StrContains(sFile[0], ".bsp");

            if (iBsp == -1 || StrContains(sFile[0][iBsp + 1], ".") != -1 || iType != FileType_File) {
                continue;
            }

            sFile[0][iBsp] = '\0';

            if (bStripPrefixes) {
                strcopy(sFile[1], sizeof(sFile[]), DeprefixMap(sFile[0]));
            }

            if (strlen(sMustBeginWith) && StrContains(bStripPrefixes ? sFile[1] : sFile[0], sMustBeginWith, false) != 0) {
                continue;
            }

            if (strlen(sMustContain))
            {
                if (StrContains(sFile[0], sMustContain, false) == -1) {
                    continue;
                }

                if (StrEqual(sFile[0], sMustContain, false) || StrEqual(sFile[1], sMustContain, false))
                {
                    bExact = true;
                    if (bStopIfExactMatch)
                    {
                        strcopy(sArray[0], iLen2, sFile[view_as<int>(bStripPrefixes)]);

                        if (bStripPrefixes) {
                            strcopy(sArray2[0], iLen2, sFile[0]);
                        }

                        break;
                    }
                }
            }

            iHits++;

            if (iHits < iLen1)
            {
                strcopy(sArray[iHits - 1], iLen2, sFile[view_as<int>(bStripPrefixes)]);

                if (bStripPrefixes) {
                    strcopy(sArray2[iHits - 1], iLen2, sFile[0]);
                }
            }
        }

        hDir.Close();
    }

    // search mapcyclefile
    else
    {
        int  iLine;
        char sPath[PLATFORM_MAX_PATH];
        char sMap [2][256];
        File hFile;

        Format(sPath, sizeof(sPath), "cfg/%s", sMapcycle);

        if (!FileExists(sPath, true)) {
            LogError("Mapcycle \"%s\" is invalid - file not found!", sMapcycle);
            return 0;
        }

        hFile = OpenFile(sPath, "r");

        while (!hFile.EndOfFile() && hFile.ReadLine(sMap[0], sizeof(sMap[])))
        {
            iLine++;

            for (int i = 0; i < strlen(sMap[0]); i++)
            {
                // skip lines with special characters
                if (IsCharMB(sMap[0][i])) {
                    continue;
                }

                // cut out spaces
                else if (IsCharSpace(sMap[0][i])) {
                    sMap[0][i] = '\0';
                }
            }

            if (!strlen(sMap[0])) {
                // skip lines that were only spaces
                continue;
            }

            if (sMap[0][0] == ';' || sMap[0][0] == '/') {
                // ignore commented lines
                continue;
            }

            // log invalid maps
            if (!IsMapValid(sMap[0])) {
                LogError("[%s]:%02i] \"%s\" !! map not found !!", sPath, iLine, sMap[0]);
                continue;
            }

            if (bStripPrefixes) {
                strcopy(sMap[1], sizeof(sMap[]), DeprefixMap(sMap[0]));
            }

            if (strlen(sMustBeginWith) && StrContains(bStripPrefixes ? sMap[1] : sMap[0], sMustBeginWith, false) != 0) {
                continue;
            }

            if (strlen(sMustContain))
            {
                if (StrContains(sMap[0], sMustContain, false) == -1) {
                    continue;
                }

                if (StrEqual(sMap[0], sMustContain, false) || StrEqual(sMap[1], sMustContain, false))
                {
                    bExact = true;
                    if (bStopIfExactMatch)
                    {
                        strcopy(sArray[0], iLen2, sMap[view_as<int>(bStripPrefixes)]);

                        if (bStripPrefixes) {
                            strcopy(sArray2[0], iLen2, sMap[0]);
                        }

                        break;
                    }
                }
            }

            iHits++;

            if (iHits < iLen1)
            {
                strcopy(sArray[iHits - 1], iLen2, sMap[view_as<int>(bStripPrefixes)]);

                if (bStripPrefixes) {
                    strcopy(sArray2[iHits - 1], iLen2, sMap[0]);
                }
            }
        }

        hFile.Close();
    }

    if (bExact && bStopIfExactMatch) {
        return 1;
    }

    return iHits;
}

public Action T_MapChangeFailsafe(Handle hTimer, int iMapcount)
{
    if (gCore.iMapChanges > iMapcount) {
        return Plugin_Stop;
    }

    char sMap[MAX_MAP_LENGTH];
    int  i = 1;

    LogError("[%i] Map change failed! Check your mapcycles for missing maps or typos! Reverting to DefaultMap ...", i++);

    if (!GetConfigString(sMap, sizeof(sMap), "DefaultMap", "Gamemodes", gRound.sMode) || !IsMapValid(sMap))
    {
        LogError("[%i] DefaultMap for gamemode \"%s\" is undefined or unavailable! Reverting to DefaultMode ...", i++, gRound.sMode);
        SetGamemode(gCore.sDefaultMode);

        if (!GetConfigString(sMap, sizeof(sMap), "DefaultMap", "Gamemodes", gCore.sDefaultMode) || !IsMapValid(sMap))
        {
            LogError("[%i] DefaultMap for default gamemode \"%s\" is also undefined or unavailable!", i++, gCore.sDefaultMode);
            LogError("[%i] SHUTTING DOWN - Unrecoverable errors in XMS config.", i++);
            ServerCommand("quit");

            return Plugin_Stop;
        }
    }

    LogError("[%i] ... Now loading %s", i, sMap);
    ServerCommand("changelevel %s", sMap);

    return Plugin_Stop;
}

bool GetMapByAbbrev(char[] sOutput, int iLen, const char[] sAbbrev)
{
    return view_as<bool>(GetConfigString(sOutput, iLen, sAbbrev, "Maps", "Abbreviations") > 0);
}

char[] DeprefixMap(const char[] sMap)
{
    char sPrefix[16];
    char sResult[MAX_MAP_LENGTH];
    int  iPos   = SplitString(sMap, "_", sPrefix, sizeof(sPrefix));

    StrCat(sPrefix, sizeof(sPrefix), "_");

    if (iPos && IsItemInList(sPrefix, gCore.sRemoveMapPrefix)) {
        strcopy(sResult, sizeof(sResult), sMap[iPos]);
    }
    else {
        strcopy(sResult, sizeof(sResult), sMap);
    }

    return sResult;
}

/**************************************************************
 * MODE MANAGEMENT
 *************************************************************/
int GetModeForMap(char[] sOutput, int iLen, const char[] sMap)
{
    if (!GetConfigString(sOutput, iLen, sMap, "Maps", "DefaultModes"))
    {
        char sPrefix[16];

        SplitString(sMap, "_", sPrefix, sizeof(sPrefix));
        StrCat(sPrefix, sizeof(sPrefix), "_*");

        if (!GetConfigString(sOutput, iLen, sPrefix, "Maps", "DefaultModes"))
        {
            if (!strlen(gCore.sRetainModes)) {
                return -1;
            }

            strcopy(sOutput, iLen, gCore.sRetainModes);
            if (!strlen(gRound.sMode) || !IsItemInList(gRound.sMode, sOutput))
            {
                if (StrContains(sOutput, ",")) {
                    SplitString(sOutput, ",", sOutput, iLen);
                    return 0;
                }
            }

            strcopy(sOutput, iLen, gRound.sMode);
            return 0;
        }
    }
    return 1;
}

int GetModeCount()
{
    char sModes[32][MAX_MODE_LENGTH];
    return ExplodeString(gCore.sGamemodes, ",", sModes, 32, MAX_MODE_LENGTH);
}

int GetRandomMode(char[] sOutput, int iLen, bool bExcludeCurrent)
{
    char sModes[32][MAX_MODE_LENGTH];
    bool bFound;
    int  iCount = ExplodeString(gCore.sGamemodes, ",", sModes, 32, MAX_MODE_LENGTH);
    int  iRan;

    if (!iCount || (iCount == 1 && bExcludeCurrent)) {
        return 0;
    }

    do {
        iRan = Math_GetRandomInt(0, iCount);
        if (strlen(sModes[iRan]))
        {
            if (!bExcludeCurrent || !StrEqual(sModes[iRan], gRound.sMode)) {
                bFound = true;
            }
        }
    }
    while (!bFound && iCount > 1);

    strcopy(sOutput, iLen, sModes[iRan]);
    return 1;
}

bool GetModeFullName(char[] sBuffer, int iLen, const char[] sMode)
{
    char sName[64];

    if (GetConfigString(sName, sizeof(sName), "Name", "Gamemodes", sMode) == 1)
    {
        strcopy(sBuffer, iLen, sName);
        return true;
    }

    return false;
}

bool GetModeMapcycle(char[] sBuffer, int iLen, const char[] sMode)
{
    char sMapcycle[PLATFORM_MAX_PATH];

    if (GetConfigString(sMapcycle, sizeof(sMapcycle), "Mapcycle", "Gamemodes", sMode))
    {
        strcopy(sBuffer, iLen, sMapcycle);
        return true;
    }

    return false;
}

void SetGamemode(const char[] sMode)
{
    char sCommand[MAX_BUFFER_LENGTH];

    strcopy(gRound.sNextMode, sizeof(gRound.sNextMode), sMode);
    strcopy(gRound.sMode, sizeof(gRound.sMode), sMode);

    if (GetConfigString(sCommand, sizeof(sCommand), "Command", "Gamemodes", gRound.sMode)) {
        ServerCommand(sCommand);
    }
}

void SetMapcycle()
{
    char sMapcycle[PLATFORM_MAX_PATH];

    if (strlen(gCore.sEmptyMapcycle) && !GetClientCount2(false) && StrEqual(gCore.sDefaultMode, gRound.sMode)) {
        strcopy(sMapcycle, sizeof(sMapcycle), gCore.sEmptyMapcycle);
    }
    else if (!GetModeMapcycle(sMapcycle, sizeof(sMapcycle), gRound.sMode)) {
        Format(sMapcycle, sizeof(sMapcycle), "mapcycle_default.txt");
    }

    ServerCommand("mapcyclefile %s", sMapcycle);
}
