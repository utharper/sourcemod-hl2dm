#define VOTE_RUN 0
#define VOTE_RUNNEXT 1
#define VOTE_RUNNEXT_AUTO 2
#define VOTE_RUNMULTI 3
#define VOTE_RUNMULTINEXT 4
#define VOTE_MATCH 5
#define VOTE_SHUFFLE 6
#define VOTE_INVERT 7
#define VOTE_CUSTOM 8

char gsVoteMotion[5][192];

/**************************************************************
 * VOTING
 *************************************************************/
public Action T_Voting(Handle hTimer)
{
    static bool bMultiChoice;
    static char sMotion[5][192];

    char sHud[1024];
    bool bContested,
         bDraw;
    int  iVotes,
         iAbstains,
         iTally[5],
         iPercent[5],
         iLead,
         iHighest;

    if (!gVoting.iStatus)
    {
        if (gVoting.iElapsed)
        {
            for (int i = 0; i < 5; i++) {
                sMotion[i] = "";
                gsVoteMotion[i] = "";
            }

            gVoting.iElapsed = 0;
        }

        return Plugin_Continue;
    }

    if (!gVoting.iElapsed)
    {
        // Prepare vote motion(s)
        bMultiChoice = view_as<bool>(strlen(gsVoteMotion[1]));

        if (gVoting.iType == VOTE_RUN || gVoting.iType == VOTE_RUNNEXT || gVoting.iType == VOTE_RUNNEXT_AUTO)
        {
            bool bCurrentModeOnly = true;
            int  iDisplayLen      = 40,
                 iCount,
                 iPos[5];

            for (int i = 0; i < 5; i++)
            {
                if (strlen(gsVoteMotion[i]))
                {
                    iPos[i] = SplitString(gsVoteMotion[i], ":", sMotion[i], sizeof(sMotion[]));

                    if (!StrEqual(gRound.sMode, sMotion[i])) {
                        bCurrentModeOnly = false;
                    }

                    iCount++;
                }
            }

            for (int i = 0; i < iCount; i++)
            {
                char sMap[MAX_MAP_LENGTH];
                strcopy(sMap, sizeof(sMap), DeprefixMap(gsVoteMotion[i][iPos[i]]));

                if (bCurrentModeOnly) {
                    strcopy(sMotion[i], sizeof(sMotion[]), sMap);
                }
                else if (!StrEqual(gRound.sMode, sMotion[i])) {
                    Format(sMotion[i], sizeof(sMotion[]), "%s:%s", sMotion[i], sMap);
                }
                else {
                    strcopy(sMotion[i], sizeof(sMotion[]), sMap);
                }
            }

            if (bMultiChoice) {
                iDisplayLen -= (iCount * 4);
            }

            for (int i = 0; i < iCount; i++)
            {
                if (strlen(sMotion[i]) > iDisplayLen) {
                    sMotion[i][iDisplayLen - 2] = '.';
                    sMotion[i][iDisplayLen - 1] = '.';
                    sMotion[i][iDisplayLen] = '\0';
                }
            }
        }
        else {
            for (int i = 0; i < 5; i++) {
                strcopy(sMotion[i], sizeof(sMotion[]), gsVoteMotion[i]);
            }
        }
    }

    // Tally votes:
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if (gVoting.iType != VOTE_MATCH || !IsClientObserver(iClient))
        {
            if (gClient[iClient].iVote != -1) {
                iTally[gClient[iClient].iVote]++;
                iVotes++;
            }
            else {
                iAbstains++;
            }
        }
    }

    for (int i = 0; i < 5; i++)
    {
        if (!bMultiChoice && i > 1) {
            break;
        }

        if (iTally[i] > iHighest) {
            iHighest = iTally[i];
            iLead = i;
            bDraw = false;
        }
        else if (iTally[i] == iHighest) {
            iLead = -1; // draw
            bDraw = true;
        }

        iPercent[i] = RoundToCeil(iTally[i] ? ( iTally[i] / iVotes * 100.0 ) : 0.0);
    }

    for (int i = 0; i < 5; i++)
    {
        if (i != iLead) {
            if (iLead < 0 || iAbstains + iTally[i] + (iAbstains ? 1 : 0) > iTally[iLead]) {
                bContested = true;
            }
        }
    }

    // Calculate result:
    if ((iLead > -1 && !bContested) || gVoting.iElapsed >= gVoting.iMaxTime)
    {
        if (bMultiChoice)
        {
            if (bDraw)
            {
                if (!iVotes && !IsGameOver()) {
                    // Nobody voted. Fail.
                    iLead = -1;
                }
                else {
                    // Draw. Pick winner at random from the first 2 equal choices
                    int iWinner[2] = {-1, -1};

                    for (int i = 0; i < 6; i++)
                    {
                        if (iTally[i] == iHighest)
                        {
                            if (iWinner[0] == -1) {
                                iWinner[0] = i;
                            }
                            else if (iWinner[1] == -1) {
                                iWinner[1] = i;
                            }
                            else {
                                break;
                            }
                        }
                    }

                    iLead = iWinner[Math_GetRandomInt(0, 1)];
                    MC_PrintToChatAll("%t", "xms_vote_draw", iLead + 1, sMotion[iLead]);
                }
            }
            else {
                    MC_PrintToChatAll("%t", "xms_vote_victory", iLead + 1, sMotion[iLead]);
            }
        }

        gVoting.iStatus = iLead > -1 ? 2 : -1;
    }


    // Format HUD :
    if (gVoting.iType == VOTE_RUN || gVoting.iType == VOTE_RUNNEXT) {
        Format(sHud, sizeof(sHud), "!run%s ", gVoting.iType == VOTE_RUNNEXT ? "Next" : "");
    }

    if (!bMultiChoice) {
        Format(sHud, sizeof(sHud), "%s%s (%i)\n▪ %s: %i (%i%%%%)\n▪ %s:  %i (%i%%%%)",
            sHud, sMotion[0], gVoting.iMaxTime - gVoting.iElapsed,
            iTally[1] >= iTally[0] ? "YES" : "yes", iTally[1], iPercent[1],
            iTally[0] > iTally[1]  ? "NO"  : "no" , iTally[0], iPercent[0]
        );
    }
    else
    {
        Format(sHud, sizeof(sHud), "%s(%i)", sHud, (gVoting.iMaxTime - gVoting.iElapsed) );

        for (int i = 0; i < 5; i++)
        {
            if (!strlen(sMotion[i])) {
                break;
            }

            char sMotionLead[192];

            if(iLead == i) {
                String_ToUpper(sMotion[i], sMotionLead, 192);
            }

            Format(sHud, sizeof(sHud), "%s\n▪ %s %s - %i", sHud, BigNumber(i+1), iLead == i ? sMotionLead : sMotion[i], iTally[i]);
        }
    }

    // Take action :
    switch(gVoting.iStatus)
    {
        case -1:
        {
            // vote failed
            SetHudTextParams(0.01, 0.11, 1.01, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
        }

        case 2:
        {
            // vote succeeded
            SetHudTextParams(0.01, 0.11, 1.01, 0, 255, 0, 255, 0, 0.0, 0.0, 0.0);

            switch(gVoting.iType)
            {
                case VOTE_SHUFFLE: {
                    ShuffleTeams();
                }

                case VOTE_INVERT: {
                    InvertTeams();
                }

                case VOTE_MATCH:
                {
                    if (!IsGameMatch()) {
                        Start();
                    }
                    else {
                        Cancel();
                    }
                }

                case VOTE_CUSTOM: {
                    // No action taken
                }

                default:
                {
                    int  i = (bMultiChoice ? iLead : 0);

                    gConVar.sm_nextmap.SetString(gsVoteMotion[i][SplitString(gsVoteMotion[i], ":", gRound.sNextMode, sizeof(gRound.sNextMode))]);

                    if (gVoting.iType != VOTE_RUN)
                    {
                        if (!bDraw) {
                            MC_PrintToChatAll("%t", "xmsc_run_next", gRound.sNextMode, DeprefixMap(gRound.sNextMap));
                        }
                    }
                    else
                    {
                        SetGamestate(GAME_CHANGING);
                        CreateTimer(1.0, T_Run, _, TIMER_REPEAT);
                    }
                }
            }
        }

        default: {
            // Vote is ongoing
        }
    }

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        char sHud2[1024];

        if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if (gVoting.iType == VOTE_RUNNEXT_AUTO) {
            Format(sHud2, sizeof(sHud2), "%T %s", "xms_autovote", iClient, sHud);
        }
        else {
            Format(sHud2, sizeof(sHud2), "%T - %s", "xms_vote", iClient, sHud);
        }

        if (gVoting.iStatus != 1)
        {
            if (!AreClientCookiesCached(iClient) || GetClientCookieInt(iClient, gSounds.cMisc) == 1 && gVoting.iType != VOTE_RUNNEXT_AUTO) {
                ClientCommand(iClient, "playgamesound %s", gVoting.iStatus == -1 ? SOUND_VOTEFAILED : SOUND_VOTESUCCESS);
            }
            else if (!bMultiChoice) {
                MC_PrintToChat(iClient, "%t", gVoting.iStatus == -1 ? "xms_vote_fail" : "xms_vote_success");
            }
        }
        else {
            int iColor[3];

            GetClientColors(iClient, iColor);
            SetHudTextParams(0.01, 0.11, 1.01, iColor[0], iColor[1], iColor[2], 255, view_as<int>(gVoting.iMaxTime - gVoting.iElapsed <= 5), 0.0, 0.0, 0.0);
        }

        ShowSyncHudText(iClient, gHud.hVote, sHud2);
    }

    if (gVoting.iStatus != 1) {
        gVoting.iStatus = 0;
    }

    gVoting.iElapsed++;
    return Plugin_Continue;
}

void CallVote(int iType, int iCaller)
{
    bool bMulti = (strlen(gsVoteMotion[1]) > 0);

    gClient[iCaller].iVoteTick = GetGameTickCount();
    gVoting.iStatus = 1;
    gVoting.iType   = iType;

    if (!bMulti) {
        gClient[iCaller].iVote = 1;
    }

    if (iCaller != 0) {
        MC_PrintToChatAllFrom(iCaller, false, "%t", "xmsc_callvote");
    }

    IfCookiePlaySoundAll(gSounds.cMisc, SOUND_VOTECALLED);

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if ( (iClient != iCaller || bMulti) && (!IsClientObserver(iClient) || iType != VOTE_MATCH) ) {
            gClient[iClient].iVote = -1;
            VotingMenu(iClient).Display(iClient, gVoting.iMaxTime);
        }
    }
}

void CallVoteFor(int iType, int iCaller, const char[] sMotion, any ...)
{
    VFormat(gsVoteMotion[0], sizeof(gsVoteMotion[]), sMotion, 4);
    CallVote(iType, iCaller);
}

void CallRandomMapVote()
{
    char sModes   [3][MAX_MODE_LENGTH],
         sChoices [5][MAX_MAP_LENGTH + MAX_MODE_LENGTH + 1],
         sCommand [512];

    for (int i = 0; i < 3; i++)
    {
        char sMapcycle[PLATFORM_MAX_PATH];

        // pick a mode
        if (i == 0) {
            // current mode for first 3 choices
            strcopy(sModes[i], sizeof(sModes[]), gRound.sMode);
        }
        else {
            // pick random
            do {
                if (!GetRandomMode(sModes[i], sizeof(sModes[]), true)) {
                    break;
                }
            }
            while (StrEqual(sModes[i], sModes[i - 1]));
        }

        // get mapcycle
        if (!GetConfigString(sMapcycle, sizeof(sMapcycle), "Mapcycle", "Gamemodes", sModes[i])) {
            continue;
        }

        // fetch available maps with GetMapsArray
        char sMaps[512][MAX_MAP_LENGTH];
        int  iHits = GetMapsArray(sMaps, 512, MAX_MAP_LENGTH, sMapcycle);

        if (iHits > 1)
        {
            for (int y = 0; y < 5; y++)
            {
                int iRan;

                if ( (i == 0 && y > 2) || (i == 1 && y != 3) || (i == 2 && y != 4) ) {
                    continue;
                }

                do {
                    // pick a random map
                    iRan = Math_GetRandomInt(0, iHits);
                }
                while (!strlen(sMaps[iRan]) || StrEqual(sMaps[iRan], gRound.sMap));

                Format(sChoices[y], sizeof(sChoices[]), "%s:%s", sModes[i], sMaps[iRan]);
                sMaps[iRan] = "";
            }
        }
    }

    for (int i = 0; i < 5; i++) {
        if (strlen(sChoices[i]) > 1) {
            Format(sCommand, sizeof(sCommand), "%s%s%s", sCommand, i > 0 ? "," : "", sChoices[i]);
        }
    }

    ServerCommand("runnext %s", sCommand);
    MC_PrintToChatAll("%t", "xms_autovote_chat");
}

int VoteTimeout(int iClient)
{
    int iTime;

    if (GetRealClientCount(true, false, true) > gVoting.iMinPlayers) {
        iTime = ( gVoting.iCooldown * Tickrate() + gClient[iClient].iVoteTick - GetGameTickCount() ) / Tickrate();
    }

    if (iTime < 0) {
        return 0;
    }

    return iTime;
}