/**************************************************************
 * TEAM MANAGEMENT
 *************************************************************/
void ShuffleTeams(bool bBroadcast=true)
{
    int iCount = GetClientCount2(true, true, false);
    int iClient;
    int iTeam [MAXPLAYERS + 1];
    int iTeams[2];

    do
    {
        do
        {
            iClient = Math_GetRandomInt(1, MaxClients);

            if (!IsClientInGame(iClient) || IsClientObserver(iClient)) {
                iTeam[iClient] = -1;
            }
            else
            {
                iTeam[iClient] = (
                    iTeams[0] > iTeams[1] ? TEAM_COMBINE
                  : iTeams[1] > iTeams[0] ? TEAM_REBELS
                  : Math_GetRandomInt(TEAM_COMBINE, TEAM_REBELS)
                );

                iTeams[0] += view_as<int>(iTeam[iClient] == TEAM_REBELS);
                iTeams[1] += view_as<int>(iTeam[iClient] == TEAM_COMBINE);
                iCount--;

                if (IsGameOver() && !IsFakeClient(iClient)) {
                    gRound.mTeams.SetValue(AuthId(iClient), iTeam[iClient]);
                }
                else
                {
                    if (iTeam[iClient] != GetClientTeam(iClient)) {
                        ForceTeamSwitch(iClient, iTeam[iClient]);
                    }

                    if (bBroadcast)
                    {
                        char sName[MAX_TEAM_NAME_LENGTH];

                        GetTeamName(iTeam[iClient], sName, sizeof(sName));
                        MC_PrintToChat(iClient, "%t", "xms_team_assigned", sName);
                    }
                }
            }
        }
        while (iTeam[iClient] == 0);
    }
    while (iCount);
}

void InvertTeams(bool bBroadcast=true)
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsClientObserver(iClient)) {
            continue;
        }

        int iTeam = GetClientTeam(iClient) == TEAM_REBELS ? TEAM_COMBINE : TEAM_REBELS;

        if (IsGameOver() && !IsFakeClient(iClient)) {
            gRound.mTeams.SetValue(AuthId(iClient), iTeam);
        }
        else
        {
            ForceTeamSwitch(iClient, iTeam);

            if (bBroadcast)
            {
                char sName[MAX_TEAM_NAME_LENGTH];

                GetTeamName(iTeam, sName, sizeof(sName));
                MC_PrintToChat(iClient, "%t", "xms_team_assigned", sName);
            }
        }
    }
}

int GetOptimalTeam()
{
    int iTeam = TEAM_REBELS;

    if (gRound.bTeamplay)
    {
        int iCount[2];

        iCount[0] = GetTeamClientCount(TEAM_REBELS);
        iCount[1] = GetTeamClientCount(TEAM_COMBINE);

        iTeam = (
            iCount[0] > iCount[1]  ? TEAM_COMBINE
          : iCount[1] > iCount[0]  ? TEAM_REBELS
          : Math_GetRandomInt(0,1) ? TEAM_REBELS
          : TEAM_COMBINE
        );
    }

    return iTeam;
}

public Action T_CheckPlayerStates(Handle hTimer)
{
    static int iWasTeam[MAXPLAYERS + 1] = {-1, ...};

    if (gRound.iState == GAME_CHANGING) {
        return Plugin_Continue;
    }

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        int iTeam;

        if (!IsClientInGame(iClient))
        {
            if (iWasTeam[iClient] > TEAM_SPECTATORS && IsGameMatch())
            {
                // Participant in match disconnected
                if (gRound.iState != GAME_PAUSED)
                {
                    ServerCommand("pause");
                    MC_PrintToChatAll("%t", "xms_auto_pause");
                    IfCookiePlaySoundAll(gSounds.cMisc, SOUND_COMMANDFAIL);
                }
            }

            iWasTeam[iClient] = -1;
            continue;
        }

        if (IsClientSourceTV(iClient)) {
            continue;
        }

        iTeam = GetClientTeam(iClient);

        if (iWasTeam[iClient] == -1)
        {
            // New player. Auto assign a team.
            CreateTimer(1.0, T_TeamAutoAssign, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        }
        else if (iTeam != iWasTeam[iClient])
        {
            if (gSpecialClient.iAllowed != iClient && ( IsGameMatch() || gRound.iState == GAME_OVERTIME || gRound.iState == GAME_OVER || ( iTeam == TEAM_SPECTATORS && !IsClientObserver(iClient) ) || ( iTeam != TEAM_SPECTATORS && IsClientObserver(iClient) ) ) )
            {
                // Client has changed teams during match, or is a bugged spectator. Usually caused by changing playermodel.
                ForceTeamSwitch(iClient, iWasTeam[iClient]);
                continue;
            }
        }

        iWasTeam[iClient] = iTeam;

        if (gClient[iClient].bReady && !IsGameOver()) {
            gRound.mTeams.SetValue(AuthId(iClient), iTeam);
        }
    }

    return Plugin_Continue;
}

public Action T_TeamAutoAssign(Handle hTimer, int iClient)
{
    int iTeam;

    if (!IsClientInGame(iClient)) {
        return Plugin_Stop;
    }
    else if (gRound.iState == GAME_PAUSED || IsGameOver()) {
        return Plugin_Continue;
    }

    gRound.mTeams.GetValue(AuthId(iClient), iTeam);

    if (IsGameMatch()) {
        MC_PrintToChat(iClient, "%t", "xmsc_teamchange_deny");
    }
    else if (iTeam)
    {
        if (iTeam == TEAM_SPECTATORS) {
            MC_PrintToChat(iClient, "%t", "xms_auto_spectate");
        }
        else {
            ForceTeamSwitch(iClient, iTeam);
        }
    }
    else {
        ForceTeamSwitch(iClient, GetOptimalTeam());
    }

    gClient[iClient].bReady = true;
    return Plugin_Stop;
}

void ForceTeamSwitch(int iClient, int iTeam)
{
    gSpecialClient.iAllowed       = iClient;
    gClient[iClient].bForceKilled = IsPlayerAlive(iClient);

    FakeClientCommandEx(iClient, "jointeam %i", iTeam);
}