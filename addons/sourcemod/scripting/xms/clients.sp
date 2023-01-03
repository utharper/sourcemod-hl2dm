/**************************************************************
 * CLIENT MANAGEMENT
 *************************************************************/
public void OnClientConnected(int iClient)
{
    if (!IsClientSourceTV(iClient)) {
        TryForceModel(iClient);
    }
}

public void OnClientPutInServer(int iClient)
{
    if (gRound.iState == GAME_PAUSED)
    {
        gSpecialClient.iPauser = iClient;
        CreateTimer(0.1, T_RePause, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }

    if (gRound.iState != GAME_MATCH && gRound.iState != GAME_MATCHEX && gRound.iState != GAME_MATCHWAIT)
    {
        char sName[MAX_NAME_LENGTH];

        GetClientName(iClient, sName, sizeof(sName));
        MC_PrintToChatAll("%t", "xms_join", sName);
    }

    if (!IsFakeClient(iClient))
    {
        CreateTimer(1.0, T_AnnouncePlugin, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

        // play connect sound
        if (!(gRound.iState == GAME_MATCH || gRound.iState == GAME_MATCHEX || gRound.iState == GAME_MATCHWAIT)) {
            IfCookiePlaySoundAll(gSounds.cMisc, SOUND_CONNECT);
        }

        // cancel sound fade in case of early map change
        ClientCommand(iClient, "soundfade 0 0 0 0");
    }

    if (!IsClientSourceTV(iClient))
    {
        // instantly join spec before we determine the correct team
        gSpecialClient.iAllowed = iClient;
        gClient[iClient].bForceKilled = true;
        FakeClientCommandEx(iClient, "jointeam %i", TEAM_SPECTATORS);
    }
}

public void OnClientCookiesCached(int iClient)
{
    if (GetClientCookieInt(iClient, gSounds.cMusic) != 0) {
        return;
    }

    // Set default values
    SetClientCookie(iClient, gSounds.cMusic,     "1");
    SetClientCookie(iClient, gSounds.cMisc,    "1");
    SetClientCookie(iClient, gHud.cColors[0], "255");
    SetClientCookie(iClient, gHud.cColors[1], "177");
    SetClientCookie(iClient, gHud.cColors[2], "0");
}

public void OnClientPostAdminCheck(int iClient)
{
    if (IsFakeClient(iClient)) {
        return;
    }

    gClient[iClient].iMenuStatus = 0;
    CreateTimer(0.1, T_Welcome, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int iClient)
{
    if (!IsFakeClient(iClient))
    {
        if (GetClientCount2(IsGameMatch()) == 1 && gRound.iState != GAME_CHANGING)
        {
            if (IsGameMatch()) {
                CreateTimer(1.0, T_RestartMap, _, TIMER_FLAG_NO_MAPCHANGE);
            }
            else if (gCore.iRevertTime)
            {
                // Last player has disconnected, revert to defaults
                CreateTimer(float(gCore.iRevertTime), T_LoadDefaults);
            }
        }
        else if (gClient[iClient].bReady && !IsGameMatch()) {
            IfCookiePlaySoundAll(gSounds.cMisc, SOUND_DISCONNECT);
        }
    }

    gClient[iClient].bReady = false;
    gClient[iClient].iMenuStatus = 0;
    gClient[iClient].iVoteTick = 0;
}

public void OnClientDisconnect_Post(int iClient)
{
    if (iClient == gSpecialClient.iPauser || GetClientCount2(false) == 0) {
        gSpecialClient.iPauser = 0;
    }
}