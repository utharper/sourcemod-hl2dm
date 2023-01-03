#define MENU_ROWLEN        32
#define XMENU_REFRESH_WAIT 30 // Time since last menu action to attempt refresh
#define XMENU_REFRESH_BASE 2  // Time to refresh base menu (workaround for 'Close')

/**************************************************************
 * NATIVES
 *************************************************************/
public int Native_XMenu(Handle hPlugin, int iParams)
{
    int         iClient     = GetNativeCell(1),
                iPage       = 0,
                iOptions    [2];
    bool        bBackButton = GetNativeCell(2),
                bExitButton,
                bNumbered   = GetNativeCell(3),
                bNextButton;
    char        sCommandBase[64],
                sCommandBack[64],
                sTitle      [64],
                sMessage    [1024];
    KeyValues   kPanel      [64];
    StringMap   mMenu       = CreateTrie();
    DataPack    dOptions    = view_as<DataPack>(GetNativeCell(7));
    DataPackPos dOptionsEnd = GetPackPosition(dOptions);

    GetNativeString(4, sCommandBase, sizeof(sCommandBase));
    GetNativeString(5, sTitle, sizeof(sTitle));
    GetNativeString(6, sMessage, sizeof(sMessage));

    for (int i = strlen(sCommandBase); i > 0; i--)
    {
        if (IsCharSpace(sCommandBase[i]))
        {
            strcopy(sCommandBack, sizeof(sCommandBack), sCommandBase);
            sCommandBack[i] = '\0';
            break;
        }
    }

    dOptions.Reset();

    do // Loop through pages
    {
        char sOption [256],
             sCommand[128];

        iOptions[0]     = 0;
        kPanel  [iPage] = new KeyValues("menu");

        // Add back button at top of page:
        if (iPage >= 1)
        {
            bExitButton = bBackButton;
            bBackButton = true;
        }

        if (bExitButton)
        {
            Format(sOption, sizeof(sOption), "%T", bBackButton ? "xmenu_exit" : "xmenu_back", iClient);

            kPanel[iPage].JumpToKey("1", true);
            kPanel[iPage].SetString("msg"    , sOption);
            kPanel[iPage].SetString("command", sCommandBack);
            kPanel[iPage].Rewind();

            iOptions[0]++;
        }

        if (bBackButton)
        {
            Format(sOption, sizeof(sOption), "%T", "xmenu_back", iClient);

            kPanel[iPage].JumpToKey(bExitButton ? "2" : "1", true);
            kPanel[iPage].SetString("msg"    , sOption);
            kPanel[iPage].SetString("command", iPage >= 1 ? "sm_xmenu_back" : sCommandBack);
            kPanel[iPage].Rewind();

            iOptions[0]++;
        }

        // Loop through options:
        for (int i = iOptions[0] + 1; i <= 8; i++)
        {
            if (GetPackPosition(dOptions) == dOptionsEnd)
            {
                // Pack is finished.
                bNextButton = false;
                break;
            }

            if (i == 8)
            {
                // Max number of options is reached, paginate:
                bNextButton = true;
                break;
            }

            // Fetch option from pack:
            dOptions.ReadString(sOption, sizeof(sOption));

            if (!strlen(sOption)) {
                bNextButton = false;
                break;
            }

            iOptions[0]++;
            iOptions[1]++;

            // Fetch or generate command:
            int iPos = StrContains(sOption, ";");

            if (iPos != -1) {
                Format(sCommand, sizeof(sCommand), "%s %s", sCommandBase, sOption[iPos+1]);
                sOption[iPos] = '\0';
            }
            else {
                Format(sCommand, sizeof(sCommand), "%s %i", sCommandBase, iOptions[1]);
            }

            // Append option number to name:
            if (bNumbered) {
                Format(sOption,  sizeof(sOption), "%i. %s", iOptions[1] , sOption);
            }

            // Save values:
            kPanel[iPage].JumpToKey(IntToChar(iOptions[0]), true);
            kPanel[iPage].SetString("msg"    , sOption);
            kPanel[iPage].SetString("command", sCommand);
            kPanel[iPage].Rewind();
        }

        // Add next button at bottom of page:
        if (bNextButton)
        {
            Format(sOption, sizeof(sOption), "%T", "xmenu_next", iClient);

            kPanel[iPage].JumpToKey(IntToChar(iOptions[0] + 1), true);
            kPanel[iPage].SetString("msg"    , sOption);
            kPanel[iPage].SetString("command", "sm_xmenu_next");
            kPanel[iPage].Rewind();
        }

        iPage++;
    }
    while (GetPackPosition(dOptions) != dOptionsEnd && iPage < 64);

    dOptions.Close();

    // Record the number of pages:
    mMenu.SetValue("count", iPage);
    mMenu.SetValue("type" , DialogType_Menu);

    // Set basic page options and add them to map:
    for (int i = 0; i < iPage; i++)
    {
        char sPageTitle[64];

        if (iPage > 1) {
            Format(sPageTitle , sizeof(sPageTitle), "%s (%i/%i)", sTitle, i + 1, iPage);
        }
        else {
            strcopy(sPageTitle, sizeof(sPageTitle), sTitle);
        }

        kPanel[i].SetString ("title", sPageTitle);
        kPanel[i].SetNum    ("level", 1); // ?
        kPanel[i].SetString ("msg"  , sMessage);

        // Save:
        mMenu.SetValue(IntToChar(i + 1), kPanel[i]);
    }

    return view_as<int>(mMenu);
}

public int Native_XMenuQuick(Handle hPlugin, int iParams)
{
    int      iClient    = GetNativeCell(1),
             iTranslate = GetNativeCell(2);
    char     sCommandBase[64],
             sTitle      [64],
             sMessage    [1024];
    DataPack dOptions   = CreateDataPack();

    GetNativeString(5, sCommandBase, sizeof(sCommandBase));
    GetNativeString(6, sTitle      , sizeof(sTitle));
    GetNativeString(7, sMessage    , sizeof(sMessage));

    if (iTranslate >= 1)
    {
        if (iTranslate < 5) {
            AttemptTranslation(sTitle, sizeof(sTitle), iClient);
        }

        if (iTranslate >= 2 && iTranslate != 4 && iTranslate != 7) {
            AttemptTranslation(sMessage, sizeof(sMessage), iClient);
        }
    }

    dOptions.Reset();

    for (int i = 8; i <= iParams; i++)
    {
        char sOption[2][512];
        GetNativeString(i, sOption[0], sizeof(sOption[]));

        if (strlen(sOption[0]))
        {
            if (iTranslate >= 3 && iTranslate != 6)
            {
                int iPos = StrContains(sOption[0], ";");

                if (iPos != -1) {
                    strcopy(sOption[1], sizeof(sOption[]), sOption[0][iPos+1]);
                    sOption[0][iPos] = '\0';
                }

                AttemptTranslation(sOption[0], sizeof(sOption[]), iClient);

                if (iPos != -1) {
                    Format(sOption[0], sizeof(sOption[]), "%s;%s", sOption[0], sOption[1]);
                }
            }

            dOptions.WriteString(sOption[0]);
        }
    }

    return view_as<int>(XMenu(iClient, GetNativeCell(3), GetNativeCell(4), sCommandBase, sTitle, sMessage, dOptions));
}

public int Native_XMenuBox(Handle hPlugin, int iParams)
{
    int       iType  = GetNativeCell(4);
    char      sCommandBase[64],
              sTitle      [64],
              sMessage    [MAX_BUFFER_LENGTH];
    StringMap mMenu  = CreateTrie();
    KeyValues kPanel = new KeyValues("menu");

    GetNativeString(1, sCommandBase, sizeof(sCommandBase));
    GetNativeString(2, sTitle      , sizeof(sTitle));
    GetNativeString(3, sMessage    , sizeof(sMessage));

    kPanel.SetString("title"  , sTitle);
    kPanel.SetString("msg"    , sMessage);
    kPanel.SetString("command", sCommandBase);
    kPanel.SetNum   ("level"  , 1);

    mMenu.SetValue("count"    , 1);
    mMenu.SetValue("type"     , iType);
    mMenu.SetValue("1"        , kPanel);

    return view_as<int>(mMenu);
}

/**************************************************************
 * MENU LOGIC
 *************************************************************/
public Action XMenuAction(int iClient, int iArgs)
{
    int  iMenuId;
    char sParam[3][256];
    bool bSilent;

    if (iClient == 0) {
        return Plugin_Handled;
    }

    if (iArgs)
    {
        iMenuId = GetCmdArgInt(1);

        if (iMenuId == -1) {
            bSilent = true;
            iMenuId = 0;
        }

        for (int i = 2; i < iArgs + 1; i++)
        {
            if (i >= 5) {
                break;
            }

            GetCmdArg(i, sParam[i - 2], sizeof(sParam[]));
        }
    }

    gClient[iClient].iMenuRefresh = XMENU_REFRESH_WAIT;

    switch (iMenuId)
    {
        // Base menu
        case 0:
        {
            if (iArgs <= 1)
            {
                bool bLan = FindConVar("sv_lan").BoolValue;
                char sTitle[64],
                     sMessage[1024],
                     sModeName[32];

                Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_0", iClient, PLUGIN_VERSION);
                if (strlen(gRound.sModeDescription)) {
                    Format(sModeName, sizeof(sModeName), "(%s)", gRound.sModeDescription);
                }
                Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_0", iClient, gRound.sMode, sModeName, gRound.sMap, gCore.sServerName, GameVersion(), PLUGIN_VERSION, Tickrate(), bLan ? "local" : "dedicated", gCore.sServerMessage);

                gClient[iClient].mMenu = XMenuQuick(iClient, 7, false, false, "sm_xmenu 0", sTitle, sMessage, !IsGameMatch() ? "xmenu0_team" : "xmenu0_pause;pause",
                  "xmenu0_vote", "xmenu0_players", "xmenu0_settings", "xmenu0_switch", IsClientAdmin(iClient) ? "xmenu0_admin" : "xmenu0_report;report"
                );

                XMenuDisplay(gClient[iClient].mMenu, iClient, -1, bSilent);
            }
            else if (StrEqual(sParam[0], "pause"))
            {
                FakeClientCommand(iClient, "pause");
                FakeClientCommand(iClient, "sm_xmenu 0");
            }
            else if (StrEqual(sParam[0], "report"))
            {
                FakeClientCommand(iClient, "sm_xmenu 7 menu");
            }
            else {
                FakeClientCommand(iClient, "sm_xmenu %s", sParam[0]);
                return Plugin_Handled;
            }

            gClient[iClient].iMenuRefresh = XMENU_REFRESH_BASE;
        }

        // Change Team menu
        case 1:
        {
            if (iArgs == 1)
            {
                char sTitle  [64],
                     sMessage[512];
                DataPack dOptions = CreateDataPack();

                dOptions.Reset();

                Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_1", iClient);
                Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_1", iClient);

                for (int i = 3; i > 0; i--)
                {
                    char sOption[64];

                    if (!gRound.bTeamplay && i == TEAM_COMBINE) {
                        continue;
                    }

                    GetTeamName(i, sOption, sizeof(sOption));
                    Format(sOption, sizeof(sOption), "%s;%i", sOption, i);

                    dOptions.WriteString(sOption);
                }

                gClient[iClient].mMenu = XMenu(iClient, true, false, "sm_xmenu 1", sTitle, sMessage, dOptions);
                XMenuDisplay(gClient[iClient].mMenu, iClient);
            }
            else
            {
                FakeClientCommand(iClient, "jointeam %s", sParam[0]);
                FakeClientCommand(iClient, "sm_xmenu 0");
            }
        }

        // Call Vote menu
        case 2:
        {
            if (iArgs == 1)
            {
                char sMessage[1024],
                     sOptions[8][64];

                Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_2", iClient, gVoting.iMinPlayers);

                if (!IsGameMatch())
                {
                    Format(sOptions[0], sizeof(sOptions[]), "xmenu2_map;selectmap");
                    Format(sOptions[1], sizeof(sOptions[]), "xmenu2_mode;selectmode");
                    Format(sOptions[2], sizeof(sOptions[]), "xmenu2_random;runrandom");
                    Format(sOptions[3], sizeof(sOptions[]), "xmenu2_start;start");

                    if (gRound.bTeamplay) {
                        Format(sOptions[4], sizeof(sOptions[]), "xmenu2_shuffle;shuffle");
                        Format(sOptions[5], sizeof(sOptions[]), "xmenu2_invert;invert");
                    }
                }
                else {
                    Format(sOptions[0], sizeof(sOptions[]), "xmenu2_cancel;cancel");
                }

                gClient[iClient].mMenu = XMenuQuick(iClient, 4, true, false, "sm_xmenu 2", "xmenutitle_2", sMessage, sOptions[0], sOptions[1], sOptions[2], sOptions[3], sOptions[4]);
            }

            else if (StrContains(sParam[0], "selectmap") != -1)
            {
                bool     bMode;
                char     sMode       [MAX_MODE_LENGTH],
                         sCommandBase[256],
                         sOption     [512],
                         sTitle      [64],
                         sMessage    [512];
                DataPack dOptions = CreateDataPack();

                dOptions.Reset();

                if (StrContains(sParam[0], "selectmap") == 0) {
                    strcopy(sMode, sizeof(sMode), gRound.sMode);
                }
                else {
                    SplitString(sParam[0], "-", sMode, sizeof(sMode));
                    bMode = true;
                }

                Format(sCommandBase, sizeof(sCommandBase), "sm_xmenu 2 %s-selectmap", sMode);

                // Main menu
                if (strlen(sParam[1]) < 2)
                {
                    int  iResults;
                    bool bLetter = (StrContains(sParam[0], "byletter") != -1);
                    char sResults[256][MAX_MAP_LENGTH*2],
                         sMapcycle[PLATFORM_MAX_PATH];

                    GetModeMapcycle(sMapcycle, sizeof(sMapcycle), sMode);

                    if (!bLetter)
                    {
                        if (bMode)
                        {
                            if (IsItemDistinctInList(gRound.sMode, gCore.sRetainModes) && IsItemDistinctInList(sMode, gCore.sRetainModes)) {
                                Format(sOption, sizeof(sOption), "%T;%s", "xmenu2_map_keep", iClient, gRound.sMap);
                                dOptions.WriteString(sOption);
                            }
                        }

                        Format(sOption, sizeof(sOption), "%T;byletter", "xmenu2_map_sort", iClient, sMode);
                        dOptions.WriteString(sOption);
                    }

                    do
                    {
                        char sMap[2][256][MAX_MAP_LENGTH];
                        int  iCount = GetMapsArray(sMap[0], 256, MAX_MAP_LENGTH, sMapcycle, sParam[1], _, false, true, sMap[1]);

                        for (int i = 0; i <= iCount; i++) {
                            Format(sResults[iResults + i], sizeof(sResults[]), "%s;%s", sMap[0][i], sMap[1][i]);
                        }

                        iResults += iCount;
                    }
                    while (String_IsNumeric(sParam[1]) && !StrEqual(sParam[1], "9") && Format(sParam[1], sizeof(sParam[]), "%i", StringToInt(sParam[1]) + 1)); // byletter 0-9

                    SortStrings(sResults, clamp(iResults, 0, 256), Sort_Ascending);

                    for (int i = 0; i < clamp(iResults, 0, 256); i++) {
                        dOptions.WriteString(sResults[i]);
                    }

                    if (!bLetter)
                    {
                        Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_2_map", iClient, iResults, sMode);

                        if (bMode) {
                            Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_2_modemap", iClient, sMode);
                        }
                        else {
                            Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_2_map", iClient);
                        }
                    }
                    else {
                        Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_2_map_byletter", iClient, iResults, String_IsNumeric(sParam[1]) ? "0-9" : sParam[1]);
                        Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_2_mapfilter", iClient, sParam[1]);
                    }

                    gClient[iClient].mMenu = XMenu(iClient, true, true, sCommandBase, sTitle, sMessage, dOptions);
                }

                // Letter select menu
                else if (StrEqual(sParam[1], "byletter"))
                {
                    char sLetters[26] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                         sLetter[2];

                    Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_2_map_filter", iClient);

                    dOptions.WriteString("0-9;0");

                    for (int i = 0; i < sizeof(sLetters); i++)
                    {
                        strcopy(sLetter, sizeof(sLetter), sLetters[i]);
                        Format(sOption, sizeof(sOption), "%s;%s", sLetter, sLetter);
                        dOptions.WriteString(sOption);
                    }

                    StrCat(sCommandBase, sizeof(sCommandBase), "-byletter");
                    Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_2_mapfilter", iClient, "");

                    gClient[iClient].mMenu = XMenu(iClient, true, false, sCommandBase, sTitle, sMessage, dOptions);
                }

                // confirmation menu
                else if (StrEqual(sParam[2], "confirm"))
                {
                    Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_2_mapconfirm", iClient, sMode, sParam[1]);
                    Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_2_mapconfirm", iClient, sMode, sParam[1], sMode, sParam[1]);
                    Format(sCommandBase, sizeof(sCommandBase), "sm_xmenu 2 %s-selectmap %s", sMode, sParam[1]);

                    Format(sOption, sizeof(sOption), "%T;now", "xmenu2_map_now", iClient);
                    dOptions.WriteString(sOption);

                    Format(sOption, sizeof(sOption), "%T;next", "xmenu2_map_next", iClient);
                    dOptions.WriteString(sOption);

                    gClient[iClient].mMenu = XMenu(iClient, true, false, sCommandBase, sTitle, sMessage, dOptions);
                }

                // take action
                else
                {
                    if (!strlen(sParam[2])) {
                        FakeClientCommand(iClient, "sm_xmenu 2 %s-selectmap %s confirm", sMode, sParam[1]);
                    }
                    else {
                        FakeClientCommand(iClient, "%s %s:%s", StrEqual(sParam[2], "now") ? "run" : "runnext", sMode, sParam[1]);
                        FakeClientCommand(iClient, "sm_xmenu 0");
                    }

                    dOptions.Close();
                    return Plugin_Handled;
                }
            }

            else if (StrEqual(sParam[0], "selectmode"))
            {
                if (iArgs == 2)
                {
                    char     sModes  [64][MAX_MODE_LENGTH],
                             sOption [128],
                             sTitle  [64],
                             sMessage[512];
                    DataPack dOptions = CreateDataPack();

                    dOptions.Reset();

                    ExplodeString(gCore.sGamemodes, ",", sModes, 64, MAX_MODE_LENGTH, false);

                    for (int i = 0; i < 64; i++)
                    {
                        if (!strlen(sModes[i])) {
                            break;
                        }

                        if (!StrEqual(sModes[i], gRound.sMode))
                        {
                            char sModeName[32];

                            if (GetModeFullName(sModeName, sizeof(sModeName), sModes[i])) {
                                Format(sModeName, sizeof(sModeName), "(%s)", sModeName);
                            }
                            Format(sOption, sizeof(sOption), "%s %s;%s", sModes[i], sModeName, sModes[i]);
                            dOptions.WriteString(sOption);
                        }
                    }

                    Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_2_mode", iClient, gRound.sMode);
                    Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_2_mode", iClient);

                    gClient[iClient].mMenu = XMenu(iClient, true, false, "sm_xmenu 2 selectmode", sTitle, sMessage, dOptions);
                }
                else
                {
                    FakeClientCommand(iClient, "sm_xmenu 2 %s-selectmap", sParam[1]);
                    return Plugin_Handled;
                }
            }

            else if (StrEqual(sParam[0], "start"))
            {
                if (iArgs == 2) {
                    gClient[iClient].mMenu = XMenuQuick(iClient, 3, true, false, "sm_xmenu 2 start", "xmenutitle_2_start", "xmenumsg_2_start", GetRealClientCount(true, false, false) > 1 ? "xmenu2_start_confirm" : "xmenu2_start_deny");
                }
                else {
                    FakeClientCommand(iClient, sParam[0]);
                    FakeClientCommand(iClient, "sm_xmenu 0");
                }
            }

            else
            {
                FakeClientCommand(iClient, sParam[0]);
                FakeClientCommand(iClient, "sm_xmenu 0");
                return Plugin_Handled;
            }

            XMenuDisplay(gClient[iClient].mMenu, iClient);
        }

        // Player Info menu
        case 3:
        {
            if (iArgs == 1)
            {
                char     sMessage[1024],
                         sTitle  [64];
                DataPack dOptions = CreateDataPack();

                dOptions.Reset();

                Format(sMessage, sizeof(sMessage), "%T", IsClientAdmin(iClient) ? "xmenumsg_3_admin" : "xmenumsg_3", iClient);
                Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_3", iClient);

                for (int i = 1; i <= MaxClients; i++)
                {
                    char sOption[64];

                    if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
                    {
                        Format(sOption, sizeof(sOption), "%N >;%i", i, i);
                        dOptions.WriteString(sOption);
                    }
                }

                if (gCore.bRanked && gameME_StatsInitialised())
                {
                    char sTop10Names[6][MAX_NAME_LENGTH],
                         sTop10List [512];

                    for (int i = 1; i < 6; i++)
                    {
                        int iPoints = gameME_FetchTop10PlayerData(i, sTop10Names[i], sizeof(sTop10Names[]));

                        if (strlen(sTop10Names[i]) > 23) {
                            sTop10Names[i][20] = '.';
                            sTop10Names[i][21] = '.';
                            sTop10Names[i][22] = '.';
                            sTop10Names[i][23] = '\0';
                        }
                        Format(sTop10List, sizeof(sTop10List), "%s#%i - %s (%i%s)\n", sTop10List, i, sTop10Names[i], iPoints, i == 1 ? " points" : "");
                    }

                    Format(sMessage, sizeof(sMessage), "%s\n\n%T", sMessage, "xmenumsg_3_gameme", iClient, sTop10List);
                }

                gClient[iClient].mMenu = XMenu(iClient, true, false, "sm_xmenu 3", sTitle, sMessage, dOptions);
            }

            // sParam[0] is a client
            else if (!strlen(sParam[1]))
            {
                int      iTarget  = StringToInt(sParam[0]);
                char     sTarget     [MAX_NAME_LENGTH],
                         sOption     [64],
                         sMessage    [1024],
                         sTitle      [64],
                         sCommandBase[64];
                DataPack dOptions = CreateDataPack();

                dOptions.Reset();

                Format(sTitle, sizeof(sTitle), "%T > %N", "xmenutitle_3", iClient, iTarget);
                Format(sCommandBase, sizeof(sCommandBase), "sm_xmenu 3 %i", iTarget);
                GetClientName(iTarget, sTarget, sizeof(sTarget));

                Format(sOption, sizeof(sOption), "%T;profile", "xmenu3_profile", iClient);
                dOptions.WriteString(sOption);

                if (IsClientAdmin(iClient, ADMFLAG_GENERIC))
                {
                    if (IsClientObserver(iTarget))
                    {
                        if (IsGameMatch()) {
                            Format(sOption, sizeof(sOption), "%T;allow", "xmenu3_allow", iClient);
                            dOptions.WriteString(sOption);
                        }
                    }
                    else {
                        Format(sOption, sizeof(sOption), "%T;forcespec", "xmenu3_forcespec", iClient);
                        dOptions.WriteString(sOption);
                    }

                    if (IsClientAdmin(iClient, ADMFLAG_CHAT)) {
                        Format(sOption, sizeof(sOption), "%T;mute", !BaseComm_IsClientMuted(iTarget) ? "xmenu3_mute" : "xmenu3_unmute", iClient);
                        dOptions.WriteString(sOption);
                    }

                    if (IsClientAdmin(iClient, ADMFLAG_KICK)) {
                        Format(sOption, sizeof(sOption), "%T;kick", "xmenu3_kick", iClient);
                        dOptions.WriteString(sOption);
                    }

                    if (IsClientAdmin(iClient, ADMFLAG_BAN)) {
                        Format(sOption, sizeof(sOption), "%T;ban", "xmenu3_ban", iClient);
                        dOptions.WriteString(sOption);
                    }
                }

                if (gCore.bRanked && gameME_StatsInitialised() && gameME_IsPlayerRanked(iTarget))
                {
                    Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_3_player_gameme", iClient, sTarget, GetClientUserId(iTarget), UnbufferedAuthId(iTarget),
                      gameME_FetchPlayerChar(iTarget, GM_RANK), gameME_FetchPlayerChar(iTarget, GM_POINTS), Timestring(gameME_FetchPlayerFloat(iTarget, GM_PLAYTIME)), gameME_FetchPlayerChar(iTarget, GM_KILLS),
                      gameME_FetchPlayerChar(iTarget, GM_DEATHS), gameME_FetchPlayerChar(iTarget, GM_KPD), gameME_FetchPlayerChar(iTarget, GM_HEADSHOTS), gameME_FetchPlayerChar(iTarget, GM_SUICIDES),
                      gameME_FetchPlayerChar(iTarget, GM_ACCURACY, true), gameME_FetchPlayerChar(iTarget, GM_KILLSPREE)
                    );
                }
                else {
                    Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_3_player", iClient, sTarget, GetClientUserId(iTarget), UnbufferedAuthId(iTarget));
                }

                gClient[iClient].mMenu = XMenu(iClient, true, false, sCommandBase, sTitle, sMessage, dOptions);
            }

            else
            {
                int iTarget   = StringToInt(sParam[0]),
                    iTargetId = GetClientUserId(iTarget);

                if (StrEqual(sParam[1], "kick")) {
                    FakeClientCommand(iClient, "sm_kick #%i", iTargetId);
                    FakeClientCommand(iClient, "sm_xmenu 3");
                }
                else if (StrEqual(sParam[1], "ban")) {
                    FakeClientCommand(iClient, "sm_ban #%i 1440 Banned for 24 hours", iTargetId);
                    FakeClientCommand(iClient, "sm_xmenu 3");
                }
                else if (StrEqual(sParam[1], "mute")) {
                    FakeClientCommand(iClient, "sm_%s #%i", BaseComm_IsClientMuted(iTarget) ? "unmute" : "mute", iTargetId);
                    FakeClientCommand(iClient, "sm_xmenu 3 %i", iTarget);
                }
                else
                {
                    FakeClientCommand(iClient, "%s %i", sParam[1], iTargetId);

                    if (StrEqual(sParam[1], "forcespec")) {
                        FakeClientCommand(iClient, "sm_xmenu 3 %i", iTarget);
                    }
                    else {
                        XMenuDisplay(gClient[iClient].mMenu, iClient);
                    }
                }

                IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_ACTIVATED);
                return Plugin_Handled;
            }

            XMenuDisplay(gClient[iClient].mMenu, iClient);
        }

        // Settings menu
        case 4:
        {
            if (iArgs == 1)
            {
                char     sOption [64],
                         sTitle  [64],
                         sMessage[512];
                DataPack dOptions = CreateDataPack();

                dOptions.Reset();

                Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_4", iClient);
                Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_4", iClient);

                Format(sOption, sizeof(sOption), "%T;model", "xmenu4_model", iClient);
                dOptions.WriteString(sOption);

                if (CommandExists("sm_fov")) {
                    Format(sOption, sizeof(sOption), "%T;fov", "xmenu4_fov", iClient);
                    dOptions.WriteString(sOption);
                }

                Format(sOption, sizeof(sOption), "%T;hudcolor", "xmenu4_hudcolor", iClient);
                dOptions.WriteString(sOption);

                Format(sOption, sizeof(sOption), "xmenu4_music%s", GetClientCookieInt(iClient, gSounds.cMusic) == 1 ? "1" : "0");
                Format(sOption, sizeof(sOption), "%T;music", sOption, iClient);
                dOptions.WriteString(sOption);

                Format(sOption, sizeof(sOption), "xmenu4_sound%s", GetClientCookieInt(iClient, gSounds.cMisc) == 1 ? "1" : "0");
                Format(sOption, sizeof(sOption), "%T;sound", sOption, iClient);
                dOptions.WriteString(sOption);

                gClient[iClient].mMenu = XMenu(iClient, true, false, "sm_xmenu 4", sTitle, sMessage, dOptions);
            }

            else if (StrEqual(sParam[0], "model"))
            {
                if (iArgs == 2)
                {
                    char     sTitle  [64],
                             sMessage[512],
                             sOption [140];
                    DataPack dOptions = CreateDataPack();

                    dOptions.Reset();

                    Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_4_model", iClient);
                    Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_4_model", iClient);

                    for (int i = 0; i < sizeof(gsModelPath); i++)
                    {
                        File_GetFileName(gsModelPath[i], sOption, sizeof(sOption));
                        Format(sOption, sizeof(sOption), "%s;%s", sOption, gsModelPath[i]);
                        dOptions.WriteString(sOption);
                    }

                    gClient[iClient].mMenu = XMenu(iClient, true, true, "sm_xmenu 4 model", sTitle, sMessage, dOptions);
                }
                else
                {
                    ClientCommand(iClient, "cl_playermodel %s", sParam[1]);
                    FakeClientCommand(iClient, "sm_xmenu 4");
                    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_ACTIVATED);
                    return Plugin_Handled;
                }
            }

            else if (StrEqual(sParam[0], "fov"))
            {
                if (iArgs == 2)
                {
                    int      iDefault = FindConVar("xfov_defaultfov").IntValue,
                             iMin     = FindConVar("xfov_minfov").IntValue,
                             iMax     = FindConVar("xfov_maxfov").IntValue;
                    char     sOption [64],
                             sTitle  [64],
                             sMessage[512];
                    DataPack dOptions = CreateDataPack();

                    dOptions.Reset();

                    Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_4_fov", iClient);
                    Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_4_fov", iClient);

                    for (int i = iMin; i <= iMax; i += 5)
                    {
                        if (i == iDefault) {
                            Format(sOption, sizeof(sOption), "%i (default);%i", i, i);
                        }
                        else {
                            Format(sOption, sizeof(sOption), "%i;%i", i, i);
                        }

                        dOptions.WriteString(sOption);
                    }

                    gClient[iClient].mMenu = XMenu(iClient, true, false, "sm_xmenu 4 fov", sTitle, sMessage, dOptions);
                }
                else
                {
                    FakeClientCommand(iClient, "fov %s", sParam[1]);
                    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_ACTIVATED);

                    FakeClientCommand(iClient, "sm_xmenu 4");
                    return Plugin_Handled;
                }
            }

            else if (StrEqual(sParam[0], "hudcolor"))
            {
                if (iArgs == 2)
                {
                    gClient[iClient].mMenu =
                        XMenuQuick(iClient, 3, true, false, "sm_xmenu 4 hudcolor", "xmenutitle_4_hudcolor", "xmenumsg_4_hudcolor",
                          "xmenu4_hudcolor_yellow;255177000", "xmenu4_hudcolor_cyan;000255255", "xmenu4_hudcolor_blue;100100255", "xmenu4_hudcolor_green;075255075",
                          "xmenu4_hudcolor_red;220010010", "xmenu4_hudcolor_white;255255255", "xmenu4_hudcolor_pink;238130238"
                        );
                }
                else
                {
                    char sColor[3][4];

                    strcopy(sColor[0], 4, sParam[1]);
                    strcopy(sColor[1], 4, sParam[1][3]);
                    strcopy(sColor[2], 4, sParam[1][6]);
                    FakeClientCommand(iClient, "hudcolor %s %s %s", sColor[0], sColor[1], sColor[2]);
                    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_ACTIVATED);

                    FakeClientCommand(iClient, "sm_xmenu 4");
                    return Plugin_Handled;
                }
            }

            else if (StrEqual(sParam[0], "music"))
            {
                if (IsCookieEnabled(gSounds.cMusic, iClient)) {
                    SetClientCookie(iClient, gSounds.cMusic, "-1");
                    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_DEACTIVATED);
                }
                else {
                    SetClientCookie(iClient, gSounds.cMusic, "1");
                    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_ACTIVATED);
                }

                FakeClientCommand(iClient, "sm_xmenu 4");
                return Plugin_Handled;
            }

            else if (StrEqual(sParam[0], "sound"))
            {
                if (IsCookieEnabled(gSounds.cMisc, iClient)) {
                    SetClientCookie(iClient, gSounds.cMisc, "-1");
                    ClientCommand(iClient, "playgamesound %s", SOUND_DEACTIVATED);
                }
                else {
                    SetClientCookie(iClient, gSounds.cMisc, "1");
                    ClientCommand(iClient, "playgamesound %s", SOUND_ACTIVATED);
                }

                FakeClientCommand(iClient, "sm_xmenu 4");
                return Plugin_Handled;
            }

            XMenuDisplay(gClient[iClient].mMenu, iClient);
        }

        case 5: // Switch
        {
            if (iArgs == 1)
            {
                int iServers;
                char sOption [322],
                     sMessage[512],
                     sTitle  [64],
                     sServers[4096],
                     sServer [64][64];

                DataPack dOptions = CreateDataPack();
                dOptions.Reset();

                Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_5", iClient);
                Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_5", iClient);

                iServers = GetConfigKeys(sServers, sizeof(sServers), "OtherServers");
                ExplodeString(sServers, ",", sServer, iServers, 64);

                if (!iServers) {
                    dOptions.WriteString("No servers listed");
                }
                else for (int i = 0; i < iServers; i++)
                {
                    char sAddress[256];

                    GetConfigString(sAddress, sizeof(sAddress), sServer[i], "OtherServers");
                    Format(sOption, sizeof(sOption), "%s;%s", sServer[i], sAddress);
                    dOptions.WriteString(sOption);
                }

                gClient[iClient].mMenu = XMenu(iClient, true, false, "sm_xmenu 5", sTitle, sMessage, dOptions);
            }
            else
            {
                if (strlen(sParam[0]) > 1)
                {
                    char sAddress[256];

                    Format(sAddress, sizeof(sAddress), "%s:%s", sParam[0], sParam[2]);
                    DisplayAskConnectBox(iClient, 30.0, sAddress);
                }
                else
                {
                    IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
                    FakeClientCommand(iClient, "sm_xmenu 0");
                    return Plugin_Handled;
                }
            }

            XMenuDisplay(gClient[iClient].mMenu, iClient);
        }

        case 6: // Management
        {
            if (!IsClientAdmin(iClient)) {
                return Plugin_Handled;
            }

            if (iArgs == 1)
            {
                gClient[iClient].mMenu = XMenuQuick(iClient, 3, true, false, "sm_xmenu 6", "xmenutitle_6", "xmenumsg_6", "xmenu6_specall;specall",
                  "xmenu6_reloadadmins;reloadadmins", "xmenu6_reloadplugin;reloadxms", "xmenu6_restart;restart", "xmenu6_feedback;feedback");
            }
            else if (StrEqual(sParam[0], "restart"))
            {
                ServerCommand("_restart");
                return Plugin_Handled;
            }
            else if (StrEqual(sParam[0], "feedback"))
            {
                if (FileExists(gPath.sFeedback))
                {
                    char sFeedback[MAX_BUFFER_LENGTH],
                         sTitle[64];


                    File hFile = OpenFile(gPath.sFeedback, "r");

                    hFile.ReadString(sFeedback, sizeof(sFeedback));
                    hFile.Close();

                    Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_6_feedback", iClient);

                    gClient[iClient].mMenu = XMenuBox("", sTitle, sFeedback, DialogType_Text);
                    gClient[iClient].iMenuRefresh = 0;
                }
            }
            else
            {
                if (StrEqual(sParam[0], "specall")) {
                    FakeClientCommand(iClient, "forcespec @all");
                }
                else if (StrEqual(sParam[0], "reloadadmins")) {
                    ServerCommand("sm_reloadadmins");
                }
                else if (StrEqual(sParam[0], "reloadxms")) {
                    ServerCommand("sm plugins reload xms");
                }

                IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_ACTIVATED);
            }

            XMenuDisplay(gClient[iClient].mMenu, iClient);
        }

        case 7: // Report
        {
            static char sPrevious[4096];

            if (StrEqual(sParam[0], "menu"))
            {
                char sTitle  [64],
                     sMessage[64];

                Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_7", iClient);
                Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_7", iClient);

                gClient[iClient].mMenu = XMenuBox("sm_xmenu 7", sTitle, sMessage);
                XMenuDisplay(gClient[iClient].mMenu, iClient);
                return Plugin_Handled;
            }

            else if (iArgs > 1)
            {
                char sFeedback[4096];

                GetCmdArgString(sFeedback, sizeof(sFeedback));

                if (!StrEqual(sFeedback, sPrevious)) // fix for double entry if client hits enter
                {
                    char sName[MAX_NAME_LENGTH],
                         sId  [32],
                         sInfo[256];
                    File hFile = OpenFile(gPath.sFeedback, "a");

                    GetClientName(iClient, sName, sizeof(sName));
                    GetClientAuthId(iClient, AuthId_Engine, sId, sizeof(sId));
                    Format(sInfo, sizeof(sInfo), "%s --- %s %s says:", gRound.sUID, sName, sId);

                    hFile.WriteLine("");
                    hFile.WriteLine(sInfo);
                    hFile.WriteLine(sFeedback[1]);
                    hFile.Close();

                    Forward_OnClientFeedback(sFeedback[2], sName, sId, gRound.sUID);
                    strcopy(sPrevious, sizeof(sPrevious), sFeedback);
                }
            }

            FakeClientCommand(iClient, "sm_xmenu 0");
        }
    }

    return Plugin_Handled;
}

/**************************************************************
 * MENU DISPLAY
 *************************************************************/
void XMenuDisplay(StringMap mMenu, int iClient, int iPage = -1, bool bSilent = false)
{
    int        iColor[3];
    char       sPage[3];
    DialogType iType;
    KeyValues  kMenu;

    if (iPage == -1)
    {
        iPage = XMenuCurrentPage(mMenu);
        if (!iPage) {
            iPage = 1;
        }
    }
    IntToString(iPage, sPage, sizeof(sPage));

    GetClientColors(iClient, iColor);

    mMenu.GetValue(sPage , kMenu);
    mMenu.GetValue("type", iType);

    mMenu.SetValue("current", iPage);
    kMenu.SetNum("time", 99999);
    kMenu.SetColor("color", iColor[0], iColor[1], iColor[2], 255);

    CreateDialog(iClient, kMenu, iType);

    if (!bSilent) {
        IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_MENUACTION);
    }
}

// Display next page:
public Action XMenuNext(int iClient, int iArgs)
{
    int iPage = XMenuCurrentPage(gClient[iClient].mMenu) + 1;

    if (iPage <= XMenuPageCount(iClient)){
        XMenuDisplay(gClient[iClient].mMenu, iClient, iPage);
    }
    
    gClient[iClient].iMenuRefresh = XMENU_REFRESH_WAIT;
    
    return Plugin_Handled;
}

// Display previous page:
public Action XMenuBack(int iClient, int iArgs)
{
    int iPage = XMenuCurrentPage(gClient[iClient].mMenu) - 1;

    if (iPage >= 1) {
        XMenuDisplay(gClient[iClient].mMenu, iClient, iPage);
    }
    
    gClient[iClient].iMenuRefresh = XMENU_REFRESH_WAIT;
    
    return Plugin_Handled;
}

// Attempt to display root menu:
public void ShowMenuIfVisible(QueryCookie cookie, int iClient, ConVarQueryResult result, char[] sCvarName, char[] sCvarValue)
{
    if (IsClientConnected(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient))
    {
        if (!StringToInt(sCvarValue))
        {
            if (gClient[iClient].iMenuStatus == 0)
            {
                MC_PrintToChat(iClient, "%t", "xmenu_fail");
                IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_COMMANDFAIL);
                gClient[iClient].iMenuStatus = 1;
            }
        }
        else
        {
            if (gClient[iClient].iMenuStatus != 2)
            {
                MC_PrintToChat(iClient, "%t", "xmenu_announce");
                gClient[iClient].iMenuStatus = 2;
            }
    
            FakeClientCommand(iClient, "sm_xmenu -1");
        }
    }
}

// Timer to (re)attempt displaying root menu:
public Action T_MenuRefresh(Handle hTimer)
{
    if (gCore.bReady)
    {
        for (int iClient = 1; iClient <= MaxClients; iClient++)
        {
            if (gClient[iClient].iMenuRefresh <= 0)
            {
                if (IsClientConnected(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient))
                {
    
                    if (!gVoting.iStatus || gClient[iClient].iVote != -1) {
                        QueryClientConVar(iClient, "cl_showpluginmessages", ShowMenuIfVisible, iClient);
                    }
                }
            }
            else {
                gClient[iClient].iMenuRefresh--;
            }
        }
     }

    return Plugin_Continue;
}
 
// Constrain message to remain visible at default menu size. Only used for "MenuMessage" in xms.cfg
int FormatMenuMessage(const char[] sMsg, char[] sOutput, int iMaxlen)
{
    int  iRows;
    char sArray[5][192];

    if (strcopy(sArray[0], sizeof(sArray[]), sMsg) > MENU_ROWLEN || StrContains(sArray[0], "\\n"))
    {
        for (int iRow = 0; iRow < 5; iRow++)
        {
            int iLen = strlen(sArray[iRow]);

            for (int i = 0; i < iLen; i++)
            {
                bool bCut;
                int  iCut = 0,
                     iNewlPos = StrContains(sArray[iRow][i], "\\n");

                if (iNewlPos == 0) {
                    bCut = true;
                    iCut = (sArray[iRow][i + 2] == ' ' ? 3 : 2);
                }
                else if (iNewlPos != -1 && (iNewlPos + i <= (MENU_ROWLEN + 2))) {
                    continue;
                }
                else
                {
                    if (sArray[iRow][i] == ' ')
                    {
                        int iNext = StrContains(sArray[iRow][i + 1], " "); // next word length
                        
                        if (!iNext) {
                            iNext = StrContains(sArray[iRow][i + 1], "\\");
                            if (iNext == -1 || sArray[iRow][i + iNext + 2] != 'n') {
                                iNext = iLen - i;
                            }
                        }

                        bCut = (iNext + i) >= MENU_ROWLEN;
                        iCut = 1;
                    }
                    else if (i == MENU_ROWLEN) {
                        bCut = true;
                    }
                }

                if (bCut)
                {
                    if (iRows < 4) {
                        strcopy(sArray[iRow + 1], sizeof(sArray[]), sArray[iRow][i + iCut]);
                        iRows = iRow + 1;
                    }
                    sArray[iRow][i] = '\0';
                    break;
                }
                else if (iRow == 4 && iLen > MENU_ROWLEN) {
                    sArray[iRow][MENU_ROWLEN - 2] = '.';
                    sArray[iRow][MENU_ROWLEN - 1] = '.';
                    sArray[iRow][MENU_ROWLEN]     = '\0';
                }
            }
        }

        strcopy(sOutput, iMaxlen, sArray[0]);

        for (int iRow = 1; iRow <= iRows; iRow++) {
            StrCat(sOutput, iMaxlen, "\n");
            StrCat(sOutput, iMaxlen, sArray[iRow]);
        }

        return strlen(sOutput);
    }
    else {
        return strcopy(sOutput, iMaxlen, sMsg);
    }
}

int XMenuCurrentPage(StringMap mMenu)
{
    int iPage;
    mMenu.GetValue("current", iPage);
    return iPage;
}

int XMenuPageCount(int iClient)
{
    int iCount;
    gClient[iClient].mMenu.GetValue("count", iCount);
    return iCount;
}