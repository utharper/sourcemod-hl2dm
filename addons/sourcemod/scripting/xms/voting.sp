#define VOTE_RUN        0 // !run
#define VOTE_RUNNEXT    1 // !runnext
#define VOTE_RUNAUTO    2 // AutoVoting
#define VOTE_RUNRANDOM  3 // !runrandom
#define VOTE_MATCH      4 // !start
#define VOTE_SHUFFLE    5 // !shuffle
#define VOTE_INVERT     6 // !invert
#define VOTE_CUSTOM     7 // !vote
#define VOTE_KICK       8 // !votekick
#define VOTE_MUTE       9 // !votemute

char gsVoteMotion[5][192];

/**************************************************************
 * VOTING
 *************************************************************/
public Action T_Voting(Handle hTimer)
{
    static bool bMultiChoice;
    static char sMotion[5][192];
    static int  iTarget;

    char sHud[1024];
    bool bContested;
    bool bDraw;
    int  iVotes;
    int  iAbstains;
    int  iLead;
    int  iHighest;
    int  iTally[5];

    if (!gVoting.iStatus)
    {
        if (gVoting.iElapsed)
        {
            for (int i = 0; i < 5; i++) {
                sMotion[i] = "";
                gsVoteMotion[i] = "";
            }

            gVoting.iElapsed = 0;
            iTarget = 0;
            iTally =  { 0, 0, 0, 0, 0 };
        }

        return Plugin_Continue;
    }

    if (!gVoting.iElapsed)
    {
        // Prepare vote motion(s)
        bMultiChoice = view_as<bool>(strlen(gsVoteMotion[1]));

        if (gVoting.iType == VOTE_RUN || gVoting.iType == VOTE_RUNNEXT || gVoting.iType == VOTE_RUNAUTO || gVoting.iType == VOTE_RUNRANDOM)
        {
            bool bCurrentModeOnly = true;
            int  iDisplayLen      = 40;
            int  iCount;
            int  iPos[5];

            if (gVoting.iType == VOTE_RUNRANDOM) {
                Format(sMotion[0], sizeof(sMotion[]), "Don't change");
                iCount++;
            }

            for (int i = view_as<int>(gVoting.iType == VOTE_RUNRANDOM); i < 5; i++)
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

            for (int i = view_as<int>(gVoting.iType == VOTE_RUNRANDOM); i < iCount; i++)
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

        if (gVoting.iType == VOTE_KICK || gVoting.iType == VOTE_MUTE)
        {
            switch (iTarget)
            {
                case -1: {
                    gVoting.iStatus = -1;
                }

                case 0: {
                    char sTarget[8];
                    SplitString(sMotion[0], ":", sTarget, sizeof(sTarget));
                    strcopy(sTarget, sizeof(sTarget), sTarget[StrContains(sTarget, " ") + 1]);
                    iTarget = StringToInt(sTarget);
                }

                default:
                {
                    if (!IsClientInGame(iTarget)) {
                        iTarget = -1;
                    }
                }
            }
        }
    }

    // Tally votes:
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if ( (!IsGameMatch() && gVoting.iType != VOTE_MATCH) || !IsClientObserver(iClient))
        {
            if (gClient[iClient].iVote != -1)
            {
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
                if (!iVotes && !IsGameOver()) // Nobody voted. Fail.
                {
                    iLead = -1;
                }
                else
                {
                    if (gVoting.iType == VOTE_RUNRANDOM) {
                        iLead = 0; // no change
                    }
                    else // Draw. Pick winner at random from the first 2 equal choices
                    {
                        int iWinner[2] = {-1, -1};

                        for (int i = 0; i < 5; i++)
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
                    }

                    MC_PrintToChatAll("%t", "xms_vote_draw", iLead + 1, sMotion[iLead]);
                }
            }
            else {
                MC_PrintToChatAll("%t", "xms_vote_victory", iLead + 1, sMotion[iLead]);
            }
        }
        
        else if (iLead == 0) {
            iLead = -1;
        }

        gVoting.iStatus = iLead > (-1 + view_as<int>(gVoting.iType == VOTE_RUNRANDOM)) ? 2 : -1;
    }


    // Format HUD :
    if (gVoting.iType == VOTE_RUN || gVoting.iType == VOTE_RUNNEXT) {
        Format(sHud, sizeof(sHud), "!run%s ", gVoting.iType == VOTE_RUNNEXT ? "Next" : "");
    }

    if (!bMultiChoice) {
        Format(sHud, sizeof(sHud), "%s%s (%i)\n▪ %s: %i (%i%%%%)\n▪ %s:  %i (%i%%%%)", sHud, sMotion[0], gVoting.iMaxTime - gVoting.iElapsed,
            (iTally[1] >= iTally[0] ? "YES" : "yes"), iTally[1],
            (iTally[0] > iTally[1]  ? "NO"  : "no"), iTally[0]
        );
    }
    else
    {
        Format(sHud, sizeof(sHud), "%s(%i)", sHud, (gVoting.iMaxTime - gVoting.iElapsed) );

        for (int i = 0; i < 5; i++)
        {
            char sMotionLead[192];

            if (!strlen(sMotion[i])) {
                break;
            }
            else if (iLead == i) {
                String_ToUpper(sMotion[i], sMotionLead, 192);
            }

            Format(sHud, sizeof(sHud), "%s\n▪ %s %s - %i", sHud, BigNumber(i+1), iLead == i ? sMotionLead : sMotion[i], iTally[i]);
        }
    }

    // Take action :
    switch(gVoting.iStatus)
    {
        case -1: // vote failed
        {
            SetHudTextParams(0.01, 0.11, 1.01, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
        }

        case 2: // vote succeeded
        {
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

                case VOTE_KICK:
                {
                    KickClient(iTarget, "%T", "xms_votekicked", iTarget);
                }

                case VOTE_MUTE:
                {
                    Client_Mute(iTarget);
                }

                case VOTE_CUSTOM: {
                    // No action taken
                }

                default:
                {
                    int i = (bMultiChoice ? iLead : 0);

                    gConVar.sm_nextmap.SetString(gsVoteMotion[i][SplitString(gsVoteMotion[i], ":", gRound.sNextMode, sizeof(gRound.sNextMode))]);

                    if (gVoting.iType != VOTE_RUN && gVoting.iType != VOTE_RUNRANDOM)
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

        default: {} // Vote is ongoing
    }

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        char sHud2[1024];

        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if (gVoting.iType == VOTE_RUNAUTO) {
            Format(sHud2, sizeof(sHud2), "%T %s", "xms_autovote", iClient, sHud);
        }
        else {
            Format(sHud2, sizeof(sHud2), "%T - %s", "xms_vote", iClient, sHud);
        }

        if (gVoting.iStatus != 1)
        {
            if (!AreClientCookiesCached(iClient) || GetClientCookieInt(iClient, gSounds.cMisc) == 1 && gVoting.iType != VOTE_RUNAUTO) {
                ClientCommand(iClient, "playgamesound %s", gVoting.iStatus == -1 ? SOUND_VOTEFAILED : SOUND_VOTESUCCESS);
            }
            else if (!bMultiChoice) {
                MC_PrintToChat(iClient, "%t", gVoting.iStatus == -1 ? "xms_vote_fail" : "xms_vote_success");
            }
        }
        else
        {
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
    gVoting.iStatus            = 1;
    gVoting.iType              = iType;

    if (!bMulti) {
        gClient[iCaller].iVote = 1;
    }

    if (iCaller != 0) {
        MC_PrintToChatAllFrom(iCaller, false, "%t", "xmsc_callvote");
    }
    else if (iType == VOTE_RUNAUTO) {
        MC_PrintToChatAll("%t", "xms_autovote_chat");
    }

    IfCookiePlaySoundAll(gSounds.cMisc, SOUND_VOTECALLED);

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if ( (iClient != iCaller || bMulti) && (!IsClientObserver(iClient) || iType != VOTE_MATCH) )
        {
            gClient[iClient].iVote        = -1;
            gClient[iClient].iMenuRefresh = gVoting.iMaxTime;

            CreateTimer(0.1, T_VotingMenu, iClient, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

void CallVoteFor(int iType, int iCaller, const char[] sMotion, any ...)
{
    VFormat(gsVoteMotion[0], sizeof(gsVoteMotion[]), sMotion, 4);
    CallVote(iType, iCaller);
}

int VoteTimeout(int iClient)
{
    int iTime;

    if (GetClientCount2(true, false, true) > gVoting.iMinPlayers) {
        iTime = ( gVoting.iCooldown * Tickrate() + gClient[iClient].iVoteTick - GetGameTickCount() ) / Tickrate();
    }

    if (iTime < 0) {
        return 0;
    }

    return iTime;
}