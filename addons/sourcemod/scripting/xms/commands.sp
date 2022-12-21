#define DELAY_ACTION 4 // "loading dm_lockdown in DELAY_ACTION seconds"

void RegisterCommands()
{
    // Public commands:
    RegConsoleCmd("menu"       , Cmd_Menu,     "Display the XMS menu");
    RegConsoleCmd("maplist"    , Cmd_Maplist,  "View list of available maps");
    RegConsoleCmd("list"       , Cmd_Maplist,  "View list of available maps");
    RegConsoleCmd("run"        , Cmd_Run,      "[Vote to] change the current map");
    RegConsoleCmd("runnow"     , Cmd_Run,      "[Vote to] change the current map");
    RegConsoleCmd("runnext"    , Cmd_Run,      "[Vote to] set the next map");
    RegConsoleCmd("start"      , Cmd_Start,    "[Vote to] start a match");
    RegConsoleCmd("cancel"     , Cmd_Cancel,   "[Vote to] cancel the match");
    RegConsoleCmd("shuffle"    , Cmd_Shuffle,  "[Vote to] shuffle teams");
    RegConsoleCmd("invert"     , Cmd_Invert,   "[Vote to] invert the teams");
    RegConsoleCmd("votekick"   , Cmd_Votekick, "[Vote to] kick player");
    RegConsoleCmd("votemute"   , Cmd_Votemute, "[Vote to] mute player voice");
    RegConsoleCmd("profile"    , Cmd_Profile,  "View player's steam profile");
    RegConsoleCmd("model"      , Cmd_Model,    "Change player model");
    RegConsoleCmd("hudcolor"   , Cmd_HudColor, "Change HUD color");
    RegConsoleCmd("vote"       , Cmd_CallVote, "Call a custom yes/no vote");
    RegConsoleCmd("yes"        , Cmd_CastVote, "Vote YES");
    RegConsoleCmd("no"         , Cmd_CastVote, "Vote NO");
    for (int i = 1; i <= 5; i++) {
        RegConsoleCmd(IntToChar(i), Cmd_CastVote, "Vote for option");
    }

    // Admin commands:
    RegAdminCmd("forcespec", AdminCmd_Forcespec, ADMFLAG_GENERIC, "force a player to spectate");
    RegAdminCmd("allow"    , AdminCmd_AllowJoin, ADMFLAG_GENERIC, "allow a player to join the match");

    // Listen for commands (overrides):
    AddCommandListener(ListenCmd_Team , "jointeam");
    AddCommandListener(ListenCmd_Team , "spectate");
    AddCommandListener(ListenCmd_Pause, "pause");
    AddCommandListener(ListenCmd_Pause, "unpause");
    AddCommandListener(ListenCmd_Pause, "setpause");
    AddCommandListener(ListenCmd_Base , "timeleft");
    AddCommandListener(ListenCmd_Base , "nextmap");
    AddCommandListener(ListenCmd_Base , "currentmap");
    AddCommandListener(ListenCmd_Base , "ff");
    
    // Internal plugin use:
    RegConsoleCmd("sm_xmenu"     , XMenuAction);
    RegConsoleCmd("sm_xmenu_back", XMenuBack);
    RegConsoleCmd("sm_xmenu_next", XMenuNext);
    
    AddCommandListener(OnMapChanging, "changelevel");
    AddCommandListener(OnMapChanging, "changelevel_next");
}

/**************************************************************
 * COMMAND: MENU
 * (Re)open the XMS menu.
 *************************************************************/
public Action Cmd_Menu(int iClient, int iArgs)
{
    gClient[iClient].iMenuStatus = 0;
    QueryClientConVar(iClient, "cl_showpluginmessages", ShowMenuIfVisible, iClient);
    return Plugin_Handled;
}

/**************************************************************
 * COMMAND: MAPLIST <mode or "all">
 * Display a list of available maps.
 *************************************************************/
public Action Cmd_Maplist(int iClient, int iArgs)
{
    char sMode[MAX_MODE_LENGTH],
         sMapcycle[PLATFORM_MAX_PATH],
         sMaps[512][MAX_MAP_LENGTH];
    int  iCount;
    bool bAll;

    if (!iArgs) {
        strcopy(sMode, sizeof(sMode), gRound.sMode);
    }
    else
    {
        GetCmdArg(1, sMode, sizeof(sMode));
        bAll = StrEqual(sMode, "all");

        if (!bAll && !IsValidGamemode(sMode))
        {
            MC_ReplyToCommand(iClient, "%t", "xmsc_list_invalid", sMode);
            IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
            return Plugin_Handled;
        }
    }

    GetModeMapcycle(sMapcycle, sizeof(sMapcycle), sMode);

    if (bAll) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_list_pre_all");
    }
    else {
        MC_ReplyToCommand(iClient, "%t", "xmsc_list_pre", sMode);
    }

    iCount = GetMapsArray(sMaps, 512, MAX_MAP_LENGTH, sMapcycle, _, _, false, bAll);
    SortStrings(sMaps, clamp(iCount, 0, 512), Sort_Ascending);

    for (int i = 0; i < iCount; i++)
    {
        if (!strlen(sMaps[i])) {
            break;
        }

        MC_ReplyToCommand(iClient, "> {I}%s", sMaps[i]);
    }

    MC_ReplyToCommand(iClient, "%t", "xmsc_list_post", iCount);
    MC_ReplyToCommand(iClient, "%t", "xmsc_list_modes", gCore.sGamemodes);

    return Plugin_Handled;
}

/**************************************************************
 * COMMANDS: RUN / RUNNEXT <mode>:<map> [,<mode>:<map>,<mode>:<map> ...]
 * Change the map and/or gamemode. Supports multiple choice voting.
 *************************************************************/
public Action Cmd_Run(int iClient, int iArgs)
{
    static int iFailCount [MAXPLAYERS+1],
               iMultiCount[MAXPLAYERS+1];

    int iVoteType;
    bool bMulti,
         bProceed;
    char sParam     [5][512],               // <mode>:<map> OR <map>:<mode> OR <mode> OR <map>
         sResultMode[5][MAX_BUFFER_LENGTH], // processed mode parameter(s)
         sResultMap [5][MAX_BUFFER_LENGTH], // processed map parameter(s)
         sCommand[16];

    GetCmdArg(0, sCommand, sizeof(sCommand));

    iVoteType = (
        StrContains(sCommand, "runnext", false) == 0 ?
            iClient == 0 ? VOTE_RUNNEXT_AUTO
            : VOTE_RUNNEXT
        : VOTE_RUN
    );

    // Initial checks
    if (!iArgs) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_run_usage");
    }
    else if (gVoting.iStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (gRound.iState == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_paused");
    }
    else if (gRound.iState == GAME_MATCH) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (gRound.iState == GAME_CHANGING) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else {
        bProceed = true;
    }

    if (!bProceed)
    {
        if (iArgs) {
            IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
        }
        return Plugin_Handled;
    }

    // Get and preformat params
    GetCmdArgString(sParam[0], sizeof(sParam[]));
    String_ToLower(sParam[0], sParam[0], sizeof(sParam[]));

    int iPos[3];
    do
    {
        iPos[0] = SplitString(sParam[0][iPos[2]], ",", sParam[iPos[1]], sizeof(sParam[]));
        ReplaceString(sParam[iPos[1]], sizeof(sParam[]), " ", ":");

        if (iPos[0] > 1)
        {
            iPos[2] += iPos[0];
            if (sParam[0][iPos[2]] == ' ') {
                iPos[2]++;
            }

            iPos[1]++;

            if (iPos[1] < 5) {
                strcopy(sParam[iPos[1]], sizeof(sParam[]), sParam[0][iPos[2]]);
            }
            else {
                MC_ReplyToCommand(iClient, "%t", "xmsc_run_denyparams");
                IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
                return Plugin_Handled;
            }
        }
    }
    while (iPos[0] > 1 && iPos[1] < 5);

    bMulti = strlen(sParam[1]) > 0;

    // Match params to results:
    for (int i = 0; i < 5; i++)
    {
        if (!strlen(sParam[i])) {
            break;
        }

        char sMode[MAX_MODE_LENGTH],
             sMap [MAX_MAP_LENGTH];
        bool bModeMatched,
             bMapMatched;
        int  iSplit = SplitString(sParam[i], ":", sMode, sizeof(sMode));

        if (iSplit > 0) {
            sMode[iSplit - 1] = '\0';
        }
        else {
            strcopy(sMode, sizeof(sMode), sParam[i]);
        }

        bModeMatched = IsValidGamemode(sMode);

        if (!bModeMatched)
        {
            // Did not match, so the first part must be the map.
            strcopy(sMap, sizeof(sMap), sMode);

            if (iSplit > 0)
            {
                strcopy(sMode, sizeof(sMode), sParam[i][iSplit]);
                if (!IsValidGamemode(sMode))
                {
                    // Fail - multiple params, but neither of them is a valid mode.
                    MC_ReplyToCommand(iClient, "%t", "xmsc_run_notfound", sMode);
                    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
                    return Plugin_Handled;
                }

                bModeMatched = true;
            }
        }
        else if (iSplit > 0)
        {
            // Matched the mode, second part is the map.
            strcopy(sMap, sizeof(sMap), sParam[i][iSplit]);
        }
        else
        {
            // Matched the mode but no map was provided.

            if (StrEqual(gRound.sMode, sMode) && !bMulti)
            {
                // Fail - same gamemode as current.
                MC_ReplyToCommand(iClient, "%t", "xmsc_run_denymode", sMode);
                IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
                return Plugin_Handled;
            }

            // Detect map:
            if (!(GetConfigString(sMap, sizeof(sMap), "DefaultMap", "Gamemodes", sMode) && IsMapValid(sMap) && !( IsItemDistinctInList(gRound.sMode, gCore.sRetainModes) && IsItemDistinctInList(sMode, gCore.sRetainModes) ) )) {
                strcopy(sMap, sizeof(sMap), gRound.sMap);
            }

            bMapMatched = true;
        }

        if (!bMapMatched)
        {
            int iHits[2];
            char sHits      [256][MAX_MAP_LENGTH],
                 sOutput    [140],
                 sFullOutput[600];

            if (GetMapByAbbrev(sResultMap[i], MAX_MAP_LENGTH, sMap) && IsMapValid(sResultMap[i])) {
                bMapMatched = true;
            }
            else
            {
                iHits[0] = GetMapsArray(sHits, 256, MAX_MAP_LENGTH, "", "", sMap, true, false);

                if (iHits[0] == 1) {
                    strcopy(sResultMap[i], sizeof(sResultMap[]), sHits[0]);
                }
                else if (!bMulti)
                {
                    for (int iHit = 0; iHit < iHits[0]; iHit++)
                    {
                        // pass more results to console
                        Format(sFullOutput, sizeof(sFullOutput), "%s　%s", sFullOutput, sHits[iHit]);

                        if (GetCmdReplySource() != SM_REPLY_TO_CONSOLE)
                        {
                            char sQuery2[256];
                            Format(sQuery2, sizeof(sQuery2), "{H}%s{I}", sMap);
                            ReplaceString(sHits[iHit], sizeof(sHits[]), sMap, sQuery2, false);

                            if (strlen(sOutput) + strlen(sHits[iHit]) + (!iHits[1] ? 0 : 3) < 140) {
                                Format(sOutput, sizeof(sOutput), "%s%s%s", sOutput, !iHits[1] ? "" : ", ", sHits[iHit]);
                                iHits[1]++;
                            }
                        }
                    }
                }

                bMapMatched = (iHits[0] == 1);
            }

            if (!bMapMatched)
            {
                if (iHits[0] == 0)
                {
                    iFailCount[iClient]++;
                    MC_ReplyToCommand(iClient, "%t", "xmsc_run_notfound", sMap);
                    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
                }
                else if (bMulti) {
                    MC_ReplyToCommand(iClient, "%t", "xmsc_run_found_multi", iHits[0], sMap);
                }
                else
                {
                    if (GetCmdReplySource() != SM_REPLY_TO_CONSOLE) {
                        MC_ReplyToCommand(iClient, "%t", "xmsc_run_found", sOutput, iHits[0] - iHits[1]);
                    }

                    PrintToConsole(iClient, "%t", "xmsc_run_results", sMap, sFullOutput, iHits[0]);
                    iMultiCount[iClient]++;
                }

                if (iMultiCount[iClient] >= 3 && iHits[0] != 1 && iHits[0] > iHits[1] && GetCmdReplySource() != SM_REPLY_TO_CONSOLE) {
                    MC_ReplyToCommand(iClient, "%t", "xmsc_run_tip1");
                    iMultiCount[iClient] = 0;
                }
                else if (iFailCount[iClient] >= 3) {
                    MC_ReplyToCommand(iClient, "%t", "xmsc_run_tip2");
                    iFailCount[iClient] = 0;
                }

                return Plugin_Handled;
            }

        }
        else {
            strcopy(sResultMap[i], sizeof(sResultMap[]), sMap);
        }

        if (!bModeMatched) {
            GetModeForMap(sResultMode[i], sizeof(sResultMode[]), sResultMap[i]);
            bModeMatched = true;
        }
        else {
            strcopy(sResultMode[i], sizeof(sResultMode[]), sMode);
        }
    }

    // Take action
    if (!bMulti && ( GetRealClientCount() < gVoting.iMinPlayers || gVoting.iMinPlayers <= 0 || iClient == 0 ) )
    {
        // No vote required
        strcopy(gRound.sNextMode, sizeof(gRound.sNextMode), sResultMode[0]);
        gConVar.sm_nextmap.SetString(sResultMap[0]);

        if (iVoteType == VOTE_RUN)
        {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_run_now", sResultMode[0], DeprefixMap(sResultMap[0]));

            // Run:
            SetGamestate(GAME_CHANGING);
            CreateTimer(1.0, T_Run, _, TIMER_REPEAT);
        }
        else {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_run_next", sResultMode[0], DeprefixMap(sResultMap[0]));
        }
    }
    else
    {
        // Vote required
        for (int i = 0; i < 5; i++)
        {
            if (strlen(sResultMode[i])) {
                Format(gsVoteMotion[i], sizeof(gsVoteMotion[]), "%s:%s", sResultMode[i], sResultMap[i]);
            }
        }

        CallVote(iVoteType, iClient);
    }

    return Plugin_Handled;
}

public Action T_Run(Handle hTimer)
{
    static char sMap[MAX_MAP_LENGTH];
    static int  iTimer;

    char sPreText[32];

    if (!iTimer) {
        strcopy(sMap, sizeof(sMap), DeprefixMap(gRound.sNextMap));
    }
    else if (iTimer == DELAY_ACTION)
    {
        PrintCenterTextAll("");
        strcopy(gRound.sMode, sizeof(gRound.sMode), gRound.sNextMode);
        SetMapcycle();
        ServerCommand("changelevel_next");
        iTimer = 0;

        return Plugin_Stop;
    }

    for (int i = 0; i < iTimer; i++) {
        StrCat(sPreText, sizeof(sPreText), "\n");
    }

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientConnected(iClient) || !IsClientInGame(iClient) | IsFakeClient(iClient)) {
            continue;
        }

        PrintCenterText(iClient, "%s%T", sPreText, "xms_loading", iClient, gRound.sNextMode, sMap, DELAY_ACTION - iTimer);
        IfCookiePlaySound(gSounds.cMisc, iClient, ( DELAY_ACTION - iTimer > 1 ? SOUND_ACTIONPENDING : SOUND_ACTIONCOMPLETE ) );
    }

    iTimer++;

    return Plugin_Continue;
}

/**************************************************************
 * COMMAND: START
 * Start a competitive match (on supported gamemodes).
 *************************************************************/
public Action Cmd_Start(int iClient, int iArgs)
{
    if (iClient == 0)
    {
        Start();
        return Plugin_Handled;
    }
    else if (GetRealClientCount(true, false, false) <= 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_start_deny");
    }
    else if (gVoting.iStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (!IsModeMatchable(gRound.sMode)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_start_denygamemode", gRound.sMode);
    }
    else if (gRound.iState == GAME_MATCH || gRound.iState == GAME_MATCHEX || gRound.iState == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (gRound.iState == GAME_CHANGING || gRound.iState == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else if (gRound.iState == GAME_OVER || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else
    {
        if (GetRealClientCount(true, false, false) < gVoting.iMinPlayers || gVoting.iMinPlayers <= 0 || iClient == 0) {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xms_started");
            Start();
        }
        else {
            CallVoteFor(VOTE_MATCH, iClient, "start match");
        }
        return Plugin_Handled;
    }

    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    return Plugin_Handled;
}

void Start()
{
    SetGamestate(GAME_MATCHWAIT);
    Game_Restart();
    CreateTimer(1.0, T_Start, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action T_Start(Handle hTimer)
{
    static int iTimer;

    if (iTimer == DELAY_ACTION - 1) {
        SetGamestate(GAME_MATCH);
        Game_Restart();
    }
    else if (iTimer == DELAY_ACTION)
    {
        PrintCenterTextAll("");
        IfCookiePlaySoundAll(gSounds.cMisc, SOUND_ACTIONCOMPLETE);
        iTimer = 0;

        return Plugin_Stop;
    }

    PrintCenterTextAll("%t", "xms_starting", DELAY_ACTION - iTimer);
    IfCookiePlaySoundAll(gSounds.cMisc, SOUND_ACTIONPENDING);
    iTimer++;

    return Plugin_Continue;
}

/**************************************************************
 * COMMAND: CANCEL
 * Cancel an ongoing competitive match.
 *************************************************************/
public Action Cmd_Cancel(int iClient, int iArgs)
{
    if (iClient == 0) {
        Cancel();
        return Plugin_Handled;
    }
    else if (gVoting.iStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (gRound.iState == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_paused");
    }
    else if (gRound.iState == GAME_DEFAULT || gRound.iState == GAME_OVERTIME) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_nomatch");
    }
    else if (gRound.iState == GAME_MATCHEX) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_cancel_matchex");
    }
    else if (gRound.iState == GAME_CHANGING || gRound.iState == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else if (gRound.iState == GAME_OVER || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else {
        if (GetRealClientCount() < gVoting.iMinPlayers || gVoting.iMinPlayers <= 0)
        {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xms_cancelled");
            Cancel();
        }
        else {
            CallVoteFor(VOTE_MATCH, iClient, "cancel match");
        }
        return Plugin_Handled;
    }

    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    return Plugin_Handled;
}

void Cancel()
{
    SetGamestate(GAME_DEFAULT);
    Game_Restart();
}

/**************************************************************
 * (ADMIN) COMMAND: FORCESPEC <player>
 * Force a player to spectate.
 *************************************************************/
public Action AdminCmd_Forcespec(int iClient, int iArgs)
{
    char sArg[5];

    if (!iArgs) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_forcespec_usage");
        return Plugin_Handled;
    }

    GetCmdArg(1, sArg, sizeof(sArg));

    if (StrEqual(sArg, "@all"))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (i == iClient || !IsClientConnected(i) || !IsClientInGame(i) || IsClientObserver(i)) {
                continue;
            }

            ChangeClientTeam(i, TEAM_SPECTATORS);
            MC_PrintToChat(i, "%t", "xmsc_forcespec_warning");
        }

        MC_ReplyToCommand(iClient, "%t", "xmsc_forcespec_success", sArg);
    }
    else
    {
        int iTarget = ClientArgToTarget(iClient, 1);

        if (iTarget != -1)
        {
            char sName[MAX_NAME_LENGTH];
            GetClientName(iTarget, sName, sizeof(sName));

            if (!IsClientObserver(iTarget))
            {
                ChangeClientTeam(iTarget, TEAM_SPECTATORS);
                MC_PrintToChat(iTarget, "%t", "xmsc_forcespec_warning");
                MC_ReplyToCommand(iClient, "%t", "xmsc_forcespec_success", sName);
                return Plugin_Handled;
            }
            else {
                MC_ReplyToCommand(iClient, "%t", "xmsc_forcespec_fail", sName);
            }
        }

        IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    }

    return Plugin_Handled;
}

/**************************************************************
 * (ADMIN) COMMAND: ALLOW <player>
 * Allows a player to join an ongoing match.
 *************************************************************/
public Action AdminCmd_AllowJoin(int iClient, int iArgs)
{
    if (!IsGameMatch()) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_nomatch");
    }
    if (!iArgs) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_allow_usage");
    }
    else
    {
        int iTarget = ClientArgToTarget(iClient, 1);
        if (iTarget > 0)
        {
            char sName[MAX_NAME_LENGTH];
            GetClientName(iTarget, sName, sizeof(sName));

            if (GetClientTeam(iTarget) == TEAM_SPECTATORS)
            {
                gSpecialClient.iAllowed = iTarget;
                FakeClientCommand(iTarget, "join");
                MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_allow_success", sName);
            }
            else {
                MC_ReplyToCommand(iClient, "%t", "xmsc_allow_fail", sName);
                IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
            }
        }
    }

    return Plugin_Handled;
}

/**************************************************************
 * COMMAND: PAUSE
 * Pause and unpause the match
 *************************************************************/
public Action ListenCmd_Pause(int iClient, const char[] sCommand, int iArgs)
{
    if (!gConVar.sv_pausable.BoolValue) {
        return Plugin_Handled;
    }

    if (iClient == 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i)) {
                gSpecialClient.iPauser = i;
                break;
            }
        }

        if (!gSpecialClient.iPauser) {
            ReplyToCommand(0, "Cannot pause when no players are in the server!");
        }
        else {
            FakeClientCommand(gSpecialClient.iPauser, "pause");
        }

        return Plugin_Handled;
    }

    if (iClient == gSpecialClient.iPauser)
    {
        if (gRound.iState == GAME_PAUSED) {
            SetGamestate(GAME_MATCH);
        }
        else {
            SetGamestate(GAME_PAUSED);
        }

        return Plugin_Continue;
    }

    if (!IsClientAdmin(iClient))
    {
        if (IsClientObserver(iClient) && iClient != gSpecialClient.iPauser) {
            MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
            return Plugin_Handled;
        }
    }

    if (gRound.iState == GAME_PAUSED) {
        IfCookiePlaySoundAll(gSounds.cMisc, SOUND_ACTIONCOMPLETE);
        MC_PrintToChatAllFrom(iClient, false, "%t", "xms_match_resumed");
        SetGamestate(GAME_MATCH);
        return Plugin_Continue;
    }
    else if (gRound.iState == GAME_MATCH) {
        IfCookiePlaySoundAll(gSounds.cMisc, SOUND_ACTIONCOMPLETE);
        MC_PrintToChatAllFrom(iClient, false, "%t", "xms_match_paused");
        SetGamestate(GAME_PAUSED);
        return Plugin_Continue;
    }
    else if (gRound.iState == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_nomatch");
    }
    else if (gRound.iState == GAME_MATCHEX) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_cancel_matchex");
    }
    else if (gRound.iState == GAME_OVER) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_nomatch");
    }

    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);

    return Plugin_Handled;
}

public Action T_RePause(Handle hTimer)
{
    static int i;

    if (gSpecialClient.iPauser > 0 && IsClientConnected(gSpecialClient.iPauser)) {
        FakeClientCommand(gSpecialClient.iPauser, "pause");
    }

    i++;

    if (i == 2)
    {
        gSpecialClient.iPauser = 0;
        i = 0;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

/**************************************************************
 * COMMAND: MODEL <path>
 * Manually set player model (or opens model change menu)
 *************************************************************/
public Action Cmd_Model(int iClient, int iArgs)
{
    char sName[70];

    if (!iArgs)
    {
        if (gClient[iClient].iMenuStatus == 2) {
            gClient[iClient].iMenuRefresh = 30;
            ModelMenu(iClient).Display(iClient, 30);
        }
        else {
            MC_PrintToChat(iClient, "%t", "xmenu_fail");
        }
    }
    else
    {
        GetCmdArg(1, sName, sizeof(sName));

        if (StrContains(sName, "/") == -1) {
            Format(sName, sizeof(sName), "%s/%s", StrContains(sName, "male") > -1 ? "models/humans/group03" : "models", sName);
        }

        ClientCommand(iClient, "cl_playermodel %s%s", sName, StrContains(sName, ".mdl") == -1 ? ".mdl" : "");
    }

    return Plugin_Handled;
}

/**************************************************************
 * COMMANDS: JOINTEAM / SPECTATE
 *************************************************************/
public Action ListenCmd_Team(int iClient, const char[] sCommand, int iArgs)
{
    int iTeam = TEAM_SPECTATORS;

    if (StrEqual(sCommand, "jointeam", false))
    {
        if (!iArgs) {
            return Plugin_Continue;
        }

        iTeam = GetCmdArgInt(1);
    }

    if (gSpecialClient.iAllowed == iClient) {
        gSpecialClient.iAllowed = 0;
    }
    else if (GetClientTeam(iClient) == iTeam)
    {
        char sName[MAX_TEAM_NAME_LENGTH];

        GetTeamName(iTeam, sName, sizeof(sName));
        MC_PrintToChat(iClient, "%t", "xmsc_teamchange_same", sName);
        IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    }
    else if (IsGameMatch())
    {
        MC_PrintToChat(iClient, "%t", "xmsc_teamchange_deny");
        IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);

        return Plugin_Handled;
    }
    else if (gRound.bTeamplay && iTeam == TEAM_COMBINE)
    {
        // try to force police model
        ClientCommand(iClient, "cl_playermodel models/police.mdl");
    }

    return Plugin_Continue;
}

/**************************************************************
 * COMMAND: PROFILE <player>
 * Display a player's steam profile in the MOTD window.
 *************************************************************/
public Action Cmd_Profile(int iClient, int iArgs)
{
    if (!iArgs) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_profile_usage");
        return Plugin_Handled;
    }

    char sAddr[128];
    int  iTarget = ClientArgToTarget(iClient, 1);

    if (iTarget != -1)
    {
        Format(sAddr, sizeof(sAddr), "https://steamcommunity.com/profiles/%s", UnbufferedAuthId(iTarget, AuthId_SteamID64));

        // have to load a blank page first for it to work:
        ShowMOTDPanel(iClient, "Loading", "about:blank", MOTDPANEL_TYPE_URL);
        ShowMOTDPanel(iClient, "Steam Profile", sAddr, MOTDPANEL_TYPE_URL);
    }
    else {
        IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    }

    return Plugin_Handled;
}

/**************************************************************
 * COMMAND: HUDCOLOR <RRR> <GGG> <BBB>
 * Set color for hud text elements (timehud, keyshud, votehud).
 *************************************************************/
public Action Cmd_HudColor(int iClient, int iArgs)
{
    if (iArgs != 3) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_hudcolor_usage");
    }
    else
    {
        char sArgs [13],
             sColor[3][4];

        GetCmdArgString(sArgs, sizeof(sArgs));
        ExplodeString(sArgs, " ", sColor, 3, 4);

        for (int i = 0; i < 3; i++) {
            Format(sColor[i], sizeof(sColor[]), "%03i", StringToInt(sColor[i]));
            SetClientCookie(iClient, gHud.cColors[i], sColor[i]);
        }
    }

    return Plugin_Handled;
}

/**************************************************************
 * COMMAND: VOTE <motion>
 * Calls a custom vote.
 *************************************************************/
public Action Cmd_CallVote(int iClient, int iArgs)
{
    if (!iArgs) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_callvote_usage");
    }
    else if (gVoting.iStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_callvote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_callvote_denywait", VoteTimeout(iClient));
    }
    else
    {
        char sMotion[64];
        GetCmdArgString(sMotion, sizeof(sMotion));

        if (StrContains(sMotion, "run", false) == 0) {
            bool bNext = StrContains(sMotion, "runnext", false) == 0;
            FakeClientCommandEx(iClient, "say !%s %s", bNext ? "runnext" : "run", sMotion[bNext ? 8 : 4]);
        }
        else if (StrEqual(sMotion, "cancel") || StrEqual(sMotion, "shuffle") || StrEqual(sMotion, "invert")) {
            FakeClientCommandEx(iClient, "say !%s", sMotion);
        }
        else {
            CallVoteFor(VOTE_CUSTOM, iClient, sMotion);
        }
    }

    return Plugin_Handled;
}

/**************************************************************
 * COMMANDS: YES / NO / 1 / 2 / 3 / 4 / 5
 * Vote on the current motion
 *************************************************************/
public Action Cmd_CastVote(int iClient, int iArgs)
{
    char sVote[4];
    GetCmdArg(0, sVote, sizeof(sVote));

    int iVote;
    bool bNumeric = String_IsNumeric(sVote),
         bMulti   = (strlen(gsVoteMotion[1]) > 0);

    iVote = (
        bNumeric ? StringToInt(sVote) - 1
        : view_as<int>(StrEqual(sVote, "yes", false))
    );

    if (gVoting.iStatus != 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_castvote_deny");
    }
    else if (IsClientObserver(iClient) && gVoting.iType == VOTE_MATCH) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_castvote_denyspec");
    }
    else if (!bMulti && bNumeric) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_castvote_denymulti");
    }
    else if (bMulti && !bNumeric) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_castvote_denybinary");
    }
    else
    {
        if (!(bNumeric && !strlen(gsVoteMotion[iVote])))
        {
            char sName[MAX_NAME_LENGTH];

            GetClientName(iClient, sName, sizeof(sName));
            gClient[iClient].iVote = iVote;
            PrintToConsoleAll("%t", "xmsc_castvote", sName, sVote);
        }

        return Plugin_Handled;
    }

    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    gClient[iClient].iMenuRefresh = 0;
    
    return Plugin_Handled;
}

/**************************************************************
 * COMMAND: SHUFFLE
 * Shuffle player teams randomly
 *************************************************************/
public Action Cmd_Shuffle(int iClient, int iArgs)
{
    if (!gRound.bTeamplay) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_noteams");
    }
    else if (iClient == 0)
    {
        ShuffleTeams();
        return Plugin_Handled;
    }
    else if (gVoting.iStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (gRound.iState == GAME_MATCH || gRound.iState == GAME_MATCHEX || gRound.iState == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (gRound.iState == GAME_CHANGING || gRound.iState == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else if (gRound.iState == GAME_OVER || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else
    {
        if (GetRealClientCount(true, false, false) < gVoting.iMinPlayers || gVoting.iMinPlayers <= 0 || iClient == 0) {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_shuffle");
            ShuffleTeams();
        }
        else {
            CallVoteFor(VOTE_SHUFFLE, iClient, "shuffle teams");
        }
        return Plugin_Handled;
    }

    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    return Plugin_Handled;
}

/**************************************************************
 * COMMAND: INVERT
 * Switch all players to the opposite teams
 *************************************************************/
public Action Cmd_Invert(int iClient, int iArgs)
{
    if (!gRound.bTeamplay) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_noteams");
    }
    else if (iClient == 0)
    {
        InvertTeams();
        return Plugin_Handled;
    }
    else if (gVoting.iStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (gRound.iState == GAME_MATCH || gRound.iState == GAME_MATCHEX || gRound.iState == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (gRound.iState == GAME_CHANGING || gRound.iState == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else if (gRound.iState == GAME_OVER || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else
    {
        if (GetRealClientCount(true, false, false) < gVoting.iMinPlayers || gVoting.iMinPlayers <= 0 || iClient == 0) {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_invert");
            InvertTeams();
        }
        else {
            CallVoteFor(VOTE_INVERT, iClient, "invert teams");
        }
        return Plugin_Handled;
    }

    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    return Plugin_Handled;
}

/**************************************************************
 * COMMAND: VOTEKICK
 * (Vote to) kick player
 *************************************************************/
public Action Cmd_Votekick(int iClient, int iArgs)
{
    if (!iArgs) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_votekick_usage");
    }
    
    int iTarget = ClientArgToTarget(iClient, 1);
    
    if (iTarget == -1)
    {
        return Plugin_Handled;
    }
    else if (iClient == 0)
    {
        KickClient(iTarget, "%T", "xms_adminkicked", iTarget);
        return Plugin_Handled;
    }
    else if (gVoting.iStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (gRound.iState == GAME_MATCH || gRound.iState == GAME_MATCHEX || gRound.iState == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (gRound.iState == GAME_CHANGING || gRound.iState == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else
    {
        CallVoteFor(VOTE_KICK, iClient, "kick %i:\"%N\"", iTarget, iTarget);
        return Plugin_Handled;
    }

    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    return Plugin_Handled;
}

/**************************************************************
 * COMMAND: VOTEMUTE
 * (Vote to) mute player
 *************************************************************/
public Action Cmd_Votemute(int iClient, int iArgs)
{
    if (!iArgs) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_votemute_usage");
    }
    
    int iTarget = ClientArgToTarget(iClient, 1);
    
    if (iTarget == -1)
    {
        return Plugin_Handled;
    }
    else if (iClient == 0)
    {
        Client_Mute(iTarget);
        return Plugin_Handled;
    }
    else if (Client_IsMuted(iTarget)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_votemute_already");
    }
    else if (gVoting.iStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (gRound.iState == GAME_MATCH || gRound.iState == GAME_MATCHEX || gRound.iState == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (gRound.iState == GAME_CHANGING || gRound.iState == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else
    {
        CallVoteFor(VOTE_MUTE, iClient, "mute %i:\"%N\"", iTarget, iTarget);
        return Plugin_Handled;
    }

    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
    return Plugin_Handled;
}

/**************************************************************
 * SAY COMMAND OVERRIDES
 *************************************************************/
public Action OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
    bool bCommand = (StrContains(sArgs, "!") == 0 || StrContains(sArgs, "/") == 0);

    if (iClient == 0)
    {
        // spam be gone
        return Plugin_Handled;
    }
    else if (gRound.iState == GAME_PAUSED && !bCommand)
    {
        // fix chat when paused
        MC_PrintToChatAllFrom(iClient, StrEqual(sCommand, "say_team", false), sArgs);

        return Plugin_Stop;
    }
    else if (bCommand)
    {
        // backwards compatibility for PMS commands
        if (StrContains(sArgs, "cm") == 1) {
            FakeClientCommandEx(iClient, "say !run%s", sArgs[3]);
        }
        else if (StrContains(sArgs, "tp ") == 1 || StrContains(sArgs, "teamplay ") == 1)
        {
            if (StrContains(sArgs, " on") != -1 || StrContains(sArgs, " 1") != -1) {
                FakeClientCommandEx(iClient, "say !run tdm");
            }
            else if (StrContains(sArgs, " off") != -1 || StrContains(sArgs, " 0") != -1) {
                FakeClientCommandEx(iClient, "say !run dm");
            }
        }
        else if (StrEqual(sArgs[1], "cf") || StrEqual(sArgs[1], "coinflip") || StrEqual(sArgs[1], "flip")) {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_coinflip", Math_GetRandomInt(0, 1) ? "Heads" : "Tails");
        }

        // VG run compatability
        else if (StrContains(sArgs, "run") == 1 && (StrEqual(sArgs[5], "1v1") || StrEqual(sArgs[5], "2v2") || StrEqual(sArgs[5], "3v3") || StrEqual(sArgs[5], "4v4") || StrEqual(sArgs[5], "duel"))) {
            FakeClientCommandEx(iClient, "say !start");
        }

        // more minor commands
        else if (StrEqual(sArgs[1], "stop")) {
            FakeClientCommandEx(iClient, "say !cancel");
        }
        else if (StrEqual(sArgs[1], "pause") || StrEqual(sArgs[1], "unpause")) {
            FakeClientCommandEx(iClient, "pause");
        }
        else if (StrContains(sArgs, "jointeam ") == 1) {
            FakeClientCommandEx(iClient, "jointeam %s", sArgs[10]);
        }
        else if (StrEqual(sArgs[1], "join")) {
            FakeClientCommand(iClient, "jointeam %i", GetOptimalTeam());
        }
        else if (StrEqual(sArgs[1], "spec") || StrEqual(sArgs[1], "spectate")) {
            FakeClientCommandEx(iClient, "spectate");
        }
        else {
            return Plugin_Continue;
        }

        return Plugin_Stop;
    }
    else if (StrEqual(sArgs, "timeleft") || StrEqual(sArgs, "nextmap") || StrEqual(sArgs, "currentmap") || StrEqual(sArgs, "ff"))
    {
        Basecommands_Override(iClient, sArgs, true);

        return Plugin_Stop;
    }
    else if (StrEqual(sArgs, "gg", false) && ( gRound.iState == GAME_OVER || gRound.iState == GAME_CHANGING ) )
    {
        IfCookiePlaySoundAll(gSounds.cMisc, SOUND_GG);

        return Plugin_Continue;
    }
    else if (gVoting.iStatus == 1)
    {
        if (StrEqual(sArgs, "yes") || StrEqual(sArgs, "no") || StrEqual(sArgs, "1") || StrEqual(sArgs, "2") || StrEqual(sArgs, "3") || StrEqual(sArgs, "4") || StrEqual(sArgs, "5"))
        {
            bool bMulti   = strlen(gsVoteMotion[1]) > 0,
                 bNumeric = String_IsNumeric(sArgs);

            if (!bMulti && !bNumeric || bMulti && bNumeric)
            {
                FakeClientCommandEx(iClient, sArgs);

                return Plugin_Stop;
            }
        }
    }

    return Plugin_Continue;
}

/**************************************************************
 * BASECOMMANDS OVERRIDES
 *************************************************************/
public Action ListenCmd_Base(int iClient, const char[] sCommand, int iArgs)
{
    if (IsClientConnected(iClient) && IsClientInGame(iClient)) {
        Basecommands_Override(iClient, sCommand, false);
    }

    return Plugin_Stop; // doesn't work for timeleft, blocked in TextMsg
}

void Basecommands_Override(int iClient, const char[] sCommand, bool bBroadcast)
{
    if (bBroadcast) {
        MC_PrintToChatAllFrom(iClient, false, sCommand);
    }

    if (StrEqual(sCommand, "timeleft"))
    {
        float fTime  = GetTimeRemaining(gRound.iState == GAME_OVER);
        int   iHours = RoundToNearest(fTime) / 3600,
              iSecs  = RoundToNearest(fTime) % 60,
              iMins  = RoundToNearest(fTime) / 60 - (iHours ? (iHours * 60) : 0);

        if (gRound.iState != GAME_CHANGING)
        {
            if (gRound.iState == GAME_OVER)
            {
                if (bBroadcast) {
                    MC_PrintToChatAll("%t", "xmsc_timeleft_over", iSecs);
                }
                else {
                    MC_PrintToChat(iClient, "%t", "xmsc_timeleft_over", iSecs);
                }
            }
            else if (gConVar.mp_timelimit.IntValue)
            {
                if (bBroadcast) {
                    MC_PrintToChatAll("%t", "xmsc_timeleft", iHours, iMins, iSecs);
                }
                else {
                    MC_PrintToChat(iClient, "%t", "xmsc_timeleft", iHours, iMins, iSecs);
                }
            }
            else
            {
                if (bBroadcast) {
                    MC_PrintToChatAll("%t", "xmsc_timeleft_none");
                }
                else {
                    MC_PrintToChat(iClient, "%t", "xmsc_timeleft_none");
                }
            }
        }
    }
    else if (StrEqual(sCommand, "nextmap"))
    {
        if (!strlen(gRound.sNextMap))
        {
            if (bBroadcast) {
                MC_PrintToChatAll("%t", "xmsc_nextmap_none");
            }
            else {
                MC_PrintToChat(iClient, "%t", "xmsc_nextmap_none");
            }
        }
        else
        {
            if (bBroadcast) {
                MC_PrintToChatAll("%t", "xmsc_nextmap", gRound.sNextMode, DeprefixMap(gRound.sNextMap));
            }
            else {
                MC_PrintToChat(iClient, "%t", "xmsc_nextmap", gRound.sNextMode, DeprefixMap(gRound.sNextMap));
            }
        }
    }
    else if (StrEqual(sCommand, "currentmap"))
    {
        if (bBroadcast) {
            MC_PrintToChatAll("%t", "xmsc_currentmap", gRound.sMode, DeprefixMap(gRound.sMap));
        }
        else {
            MC_PrintToChat(iClient, "%t", "xmsc_currentmap", gRound.sMode, DeprefixMap(gRound.sMap));
        }
    }
    else if (StrEqual(sCommand, "ff"))
    {
        if (gRound.bTeamplay)
        {
            if (bBroadcast) {
                MC_PrintToChatAll("%t", "xmsc_ff", gConVar.mp_friendlyfire.BoolValue ? "enabled" : "disabled");
            }
            else {
                MC_PrintToChat(iClient, "%t", "xmsc_ff", gConVar.mp_friendlyfire.BoolValue ? "enabled" : "disabled");
            }
        }
    }
}