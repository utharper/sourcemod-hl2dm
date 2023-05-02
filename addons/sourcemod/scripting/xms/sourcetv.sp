/**************************************************************
 * DEMO RECORDING
 *************************************************************/
public Action T_StartRecord(Handle hTimer)
{
    StartRecord();
    return Plugin_Handled;
}

void StartRecord()
{
    if (!gConVar.tv_enable.BoolValue) {
        LogError("SourceTV is not active!");
    }
    else if (!gRound.bRecording) {
        ServerCommand("tv_name \"%s - %s\";tv_record %s/incomplete/%s", gCore.sServerName, gRound.sUID, gPath.sDemo, gRound.sUID);
        gRound.bRecording = true;
    }
    
    for (int iClient = 1; iClient < MaxClients; iClient++)
    {
        if (IsClientInGame(iClient) && IsClientSourceTV(iClient)) {
            ShowVGUIPanel(iClient, "specmenu", _, false);
            ShowVGUIPanel(iClient, "specgui", _, true);
        }
    }
}

public Action T_StopRecord(Handle hTimer, bool bEarly)
{
    StopRecord(bEarly);
    return Plugin_Handled;
}

void StopRecord(bool bDiscard)
{
    char sPath[2][PLATFORM_MAX_PATH];

    if (!gRound.bRecording) {
        return;
    }

    Format(sPath[0], sizeof(sPath[]), "%s/incomplete/%s.dem", gPath.sDemo, gRound.sUID);
    Format(sPath[1], sizeof(sPath[]), "%s/%s.dem", gPath.sDemo, gRound.sUID);

    ServerCommand("tv_stoprecord");
    gRound.bRecording = false;

    if (!bDiscard)
    {
        GenerateDemoTxt(sPath[1]);
        RenameFile(sPath[1], sPath[0], true);
        if (strlen(gPath.sDemoWeb)) {
            MC_PrintToChatAll("%t", "xms_announcedemo", gPath.sDemoWeb, gRound.sUID, gPath.sDemoWebExt);
        }
    }
    else {
        DeleteFile(sPath[0], true);
    }
}

// Generate accompanying .txt file:
void GenerateDemoTxt(const char[] sPath)
{
    char sPath2 [PLATFORM_MAX_PATH];
    char sTime  [32];
    char sTitle [256];
    char sPlayers[2][2048];
    bool bDuel = GetClientCount2(true, false, false) == 2;
    File hFile;

    Format(sPath2, PLATFORM_MAX_PATH, "%s.txt", sPath);
    FormatTime(sTime, sizeof(sTime), "%d %b %Y");

    if (gRound.bTeamplay) {
        Format(sPlayers[0], sizeof(sPlayers[]), "THE COMBINE [Score: %i]:\n", GetTeamScore(TEAM_COMBINE));
        Format(sPlayers[1], sizeof(sPlayers[]), "REBEL FORCES [Score: %i]:\n", GetTeamScore(TEAM_REBELS));
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        int z;

        if (!IsClientInGame(i) || IsFakeClient(i) || IsClientObserver(i)) {
            continue;
        }

        if (gRound.bTeamplay) {
            z = GetClientTeam(i) - 2;
        }

        Format(sPlayers[z], sizeof(sPlayers[]), "%s\"%N\" %s [%i kills, %i deaths]\n", sPlayers[z], i, AuthId(i), GetClientFrags(i), GetClientDeaths(i));

        if (bDuel) {
            Format(sTitle, sizeof(sTitle), "%s%N%s", sTitle, i, !strlen(sTitle) ? " vs " : "");
        }
    }

    if (gRound.bTeamplay) {
        Format(sTitle, sizeof(sTitle), "%s %iv%i - %s - %s", gRound.sMode, GetTeamClientCount(TEAM_REBELS), GetTeamClientCount(TEAM_COMBINE), gRound.sMap, sTime);
    }
    else if (bDuel) {
        Format(sTitle, sizeof(sTitle), "%s 1v1 (%s) - %s - %s", gRound.sMode, sTitle, gRound.sMap, sTime);
    }
    else {
        Format(sTitle, sizeof(sTitle), "%s ffa - %s - %s", gRound.sMode, gRound.sMap, sTime);
    }

    hFile = OpenFile(sPath2, "w", true);
    hFile.WriteLine(sTitle);
    hFile.WriteLine("");
    hFile.WriteLine(sPlayers[0]);

    if (gRound.bTeamplay) {
        hFile.WriteLine(sPlayers[1]);
    }

    hFile.WriteLine("Server: \"%s\" [%s:%i]", gCore.sServerName, gCore.sIPAddr, gCore.iPort);
    hFile.WriteLine("Version: %i [XMS v%s]", GameVersion(), PLUGIN_VERSION);
    hFile.Close();
}