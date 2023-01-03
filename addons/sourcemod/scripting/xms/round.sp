#define OVERTIME_TIME 1 // minutes

/**************************************************************
 * ROUND MANAGEMENT
 *************************************************************/
void SetGamestate(int iState)
{
    if (iState == gRound.iState) {
        return;
    }

    OnSetGamestate_Pre(iState);

    gRound.iState = iState;
    Forward_OnGamestateChanged(iState);

    OnSetGamestate_Post();
}

void OnSetGamestate_Pre(int iState)
{
    switch(iState)
    {
        case GAME_DEFAULT:
        {
            ServerCommand("sv_allow_point_servercommand always");
            if (IsGameMatch()) {
                OnMatchCancelled();
            }

            if (gRound.bRecording) {
                StopRecord(true);
            }

            if (gRound.bOvertime) {
                CreateOverTimer(0.0);
            }
        }

        case GAME_MATCHWAIT:
        {
            OnMatchPre();

            if (!gRound.bRecording) {
                GenerateGameID();
                CreateTimer(1.1, T_StartRecord, _, TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        case GAME_MATCH:
        {
            if (gRound.iState != GAME_PAUSED) {
                Forward_OnMatchStart();
                CreateOverTimer(2.9);
            }

        }

        case GAME_OVER:
        {
            OnRoundEnd(IsGameMatch());
            ServerCommand("sv_allow_point_servercommand disallow");

            if (gRound.bRecording) {
                CreateTimer(10.0, T_StopRecord, false, TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        case GAME_CHANGING:
        {
            if (gRound.iState == GAME_OVER) {
                CreateTimer(0.1, T_SoundFadeTrigger, _, TIMER_FLAG_NO_MAPCHANGE);

                if (gRound.bRecording) {
                    StopRecord(false);
                }
            }
            else if (gRound.bRecording) {
                StopRecord(true);
            }
        }
    }
}

void OnSetGamestate_Post()
{
    if (gRound.iState == GAME_CHANGING && gRound.bTeamplay) {
        InvertTeams();
    }
}

public Action T_LoadDefaults(Handle hTimer)
{
    if (!GetClientCount2(false))
    {
        if (!StrEqual(gRound.sMode, gCore.sDefaultMode))
        {
            SetGamemode(gCore.sDefaultMode);
            SetMapcycle();
            gConVar.sm_nextmap.SetString("");
            ServerCommand("changelevel_next");
        }
    }

    return Plugin_Handled;
}

public Action T_RestartMap(Handle hTimer)
{
    if (strlen(gRound.sMode)) {
        SetGamemode(gRound.sMode);
    }
    else {
        SetGamemode(gCore.sDefaultMode);
    }

    gConVar.sm_nextmap.SetString(gRound.sMap);
    ServerCommand("changelevel_next");
    gCore.bReady = true;

    return Plugin_Handled;
}

void GenerateGameID()
{
    FormatTime(gRound.sUID, sizeof(gRound.sUID), "%y%m%d%H%M");
    Format(gRound.sUID, sizeof(gRound.sUID), "%s-%s", gRound.sUID, gRound.sMap);
}

void OnMatchPre()
{
    char sStatus [MAX_BUFFER_LENGTH];
    char sCommand[MAX_BUFFER_LENGTH];

    ServerCommandEx(sStatus, sizeof(sStatus), "status");
    PrintToConsoleAll("\n\n\n%s\n\n\n", sStatus);

    if (GetConfigString(sCommand, sizeof(sCommand), "PreMatchCommand")) {
        ServerCommand(sCommand);
    }
}

public void OnMatchCancelled()
{
    ServerCommand("exec server");
    SetGamemode(gRound.sMode);
    Forward_OnMatchEnd(false);
}

public void OnRoundEnd(bool bMatch)
{
    gRound.fEndTime = GetGameTime();

    if (gConVar.mp_chattime.IntValue > 1 && !GetClientCount2(true))
    {
        // Nobody is in game, just skip to the next map
        ServerCommand("changelevel_next");
        return;
    }

    if (bMatch)
    {
        char sCommand[MAX_BUFFER_LENGTH];

        if (GetConfigString(sCommand, sizeof(sCommand), "PostMatchCommand")) {
            ServerCommand(sCommand);
        }

        Forward_OnMatchEnd(true);
    }

    if (gRound.iState != GAME_CHANGING)
    {
        if (gVoting.bAutomatic && !strlen(gRound.sNextMap) && gVoting.iStatus != 1)
        {
            if (gConVar.mp_chattime.IntValue <= gVoting.iMaxTime) {
                LogError("\"mp_chattime\" must be more than xms.cfg:\"VoteMaxTime\" !");
            }
            else {
                ServerCommand("runrandom");
            }
        }
        else if (strlen(gRound.sNextMap)) {
            MC_PrintToChatAll("%t", "xms_nextmap_announce", gRound.sNextMode, DeprefixMap(gRound.sNextMap), gConVar.mp_chattime.IntValue);
        }
    }

    PlayRoundEndMusic();
}

/**************************************************************
 * OVERTIME MANAGEMENT
 *************************************************************/
public void OnTimelimitChanged(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    if (gRound.bOvertime) {
        CreateOverTimer();
    }
}

void CreateOverTimer(float fDelay=0.0)
{
    if (gRound.hOvertime != INVALID_HANDLE) {
        KillTimer(gRound.hOvertime);
        gRound.hOvertime = INVALID_HANDLE;
    }

    gRound.hOvertime = CreateTimer(GetTimeRemaining(false) - 0.1 + fDelay, T_PreOvertime, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action T_PreOvertime(Handle hTimer)
{
    if (gRound.iState != GAME_OVERTIME && gRound.iState != GAME_MATCHEX)
    {
        if (GetClientCount2(true, true, false) > 1)
        {
            if (gRound.bTeamplay) {
                if (GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE) == 0 && GetTeamClientCount(TEAM_REBELS) && GetTeamClientCount(TEAM_COMBINE)) {
                    StartOvertime();
                }
            }
            else if (!GetTopPlayer(false)) {
                StartOvertime();
            }
        }

        gRound.hOvertime = INVALID_HANDLE;
    }
    else {
        MC_PrintToChatAll("%t", "xms_overtime_draw");
    }

    return Plugin_Stop;
}

void StartOvertime()
{
    gConVar.mp_timelimit.IntValue += OVERTIME_TIME;

    MC_PrintToChatAll("%t", "xms_overtime_start", gRound.bTeamplay ? "team" : "player");
    gConVar.mp_forcerespawn.BoolValue = true;

    CreateTimer(0.1, T_Overtime, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    if (gRound.iState == GAME_MATCH) {
        SetGamestate(GAME_MATCHEX);
    }
    else {
        SetGamestate(GAME_OVERTIME);
    }
}

public Action T_Overtime(Handle hTimer)
{
    int  iResult;
    char sName[MAX_NAME_LENGTH];

    if (gRound.iState != GAME_OVERTIME && gRound.iState != GAME_MATCHEX) {
        return Plugin_Stop;
    }

    if (gRound.bTeamplay)
    {
        iResult = GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE);

        if (iResult == 0) {
            return Plugin_Continue;
        }

        GetTeamName(iResult < 0 ? TEAM_COMBINE : TEAM_REBELS, sName, sizeof(sName));
        MC_PrintToChatAll("%t", "xms_overtime_teamwin", sName);
    }
    else
    {
        iResult = GetTopPlayer(false);

        if (!iResult) {
            return Plugin_Continue;
        }

        GetClientName(iResult, sName, sizeof(sName));

        MC_PrintToChatAll("%t", "xms_overtime_win", sName);
    }

    Game_End();

    return Plugin_Stop;
}