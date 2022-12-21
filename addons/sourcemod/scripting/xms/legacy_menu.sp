/**************************************************************
 * VOTE CHOICE MENU
 *************************************************************/
Menu VotingMenu(int iClient)
{
    Menu hMenu  = new Menu(VotingMenuAction);
    bool bMulti = view_as<bool>(strlen(gsVoteMotion[1]));
    char sOption[128];

    if (!bMulti)
    {
        Format(sOption, sizeof(sOption), "%T", "xms_menu_decision", iClient, gsVoteMotion[0]);
        hMenu.SetTitle(sOption);
        Format(sOption, sizeof(sOption), "%T", "xms_menu_decision_yes", iClient);
        hMenu.AddItem("yes", sOption);
        Format(sOption, sizeof(sOption), "%T", "xms_menu_decision_no", iClient);
        hMenu.AddItem("no", sOption);
    }
    else
    {
        Format(sOption, sizeof(sOption), "%T", "xms_menu_decision_multi", iClient);
        hMenu.SetTitle(sOption);

        for (int i = 1; i < 6; i++)
        {
            if (strlen(gsVoteMotion[i - 1])) {
                hMenu.AddItem(IntToChar(i), gsVoteMotion[i - 1]);
            }
        }
    }

    Format(sOption, sizeof(sOption), "%T", "xms_menu_decision_abstain", iClient);
    hMenu.AddItem("abstain", sOption);

    return hMenu;
}

public int VotingMenuAction(Menu hMenu, MenuAction iAction, int iClient, int iParam)
{
    if (iClient > 0 && IsClientConnected(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient))
    {
        if (iAction == MenuAction_Select)
        {
            char sCommand[8];
            hMenu.GetItem(iParam, sCommand, sizeof(sCommand));

            FakeClientCommand(iClient, sCommand);
        }

        gClient[iClient].iMenuRefresh = 0;
    }

    return 1;
}

/**************************************************************
 * MODEL CHOICE MENU
 *************************************************************/
Menu ModelMenu(int iClient)
{
    Menu hMenu = new Menu(ModelMenuAction);
    char sFile[70],
         sTitle[512];

    Format(sTitle, sizeof(sTitle), "%T", "xms_menu_model", iClient);
    hMenu.SetTitle(sTitle);

    for (int i = 0; i < sizeof(gsModelPath); i++) {
        File_GetFileName(gsModelPath[i], sFile, sizeof(sFile));
        hMenu.AddItem(gsModelPath[i], sFile);
    }

    return hMenu;
}

public int ModelMenuAction(Menu hMenu, MenuAction iAction, int iClient, int iParam)
{
    if (iClient > 0 && IsClientConnected(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient))
    {
        if (iAction == MenuAction_Select)
        {
            char sCommand[70];
            hMenu.GetItem(iParam, sCommand, sizeof(sCommand));

            ClientCommand(iClient, "cl_playermodel %s", sCommand);
            IfCookiePlaySound(gSounds.cMisc, iClient, SOUND_ACTIVATED);
        }

        gClient[iClient].iMenuRefresh = 0;
    }

    return 1;
}