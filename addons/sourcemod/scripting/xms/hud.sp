void GetClientColors(int iClient, int iColors[3])
{
    for (int i = 0; i < 3; i++) {
        iColors[i] = clamp(GetClientCookieInt(iClient, gHud.cColors[i]), 0, 255);
    }
}

/**************************************************************
 * PRESSED KEYS HUD
 *************************************************************/
public Action T_KeysHud(Handle hTimer)
{
    if (gRound.iState == GAME_OVER || gRound.iState == GAME_CHANGING || gRound.iState == GAME_PAUSED) {
        return Plugin_Continue;
    }

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        char sHud[1024];
        int  iTarget,
             iColor[3];

        if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if (GetClientButtons(iClient) & IN_SCORE || (!IsClientObserver(iClient) && !gHud.bSelfKeys)) {
            continue;
        }

        if (IsClientObserver(iClient)) {
            iTarget = GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget");
        }
        else {
            iTarget = iClient;
        }

        GetClientColors(iClient, iColor);

        if (GetEntProp(iClient, Prop_Send, "m_iObserverMode") != 7 && iTarget > 0 && IsClientConnected(iTarget) && IsClientInGame(iTarget))
        {
            int   iButtons = GetClientButtons(iTarget);
            float fAngles[3];

            GetClientAbsAngles(iClient, fAngles);

            if (!gHud.bSelfKeys) {
                Format(sHud, sizeof(sHud), "health: %i   suit: %i\n", GetClientHealth(iTarget), GetClientArmor(iTarget));
            }

            Format(sHud, sizeof(sHud), "%svel: %03i  %s   %0.1fº\n%s         %s          %s\n%s     %s     %s", sHud,
              GetClientVelocity(iTarget),
              (iButtons & IN_FORWARD)   ? "↑"       : "  ",
              fAngles[1],
              (iButtons & IN_MOVELEFT)  ? "←"       : "  ",
              (iButtons & IN_SPEED)     ? "+SPRINT" : "        ",
              (iButtons & IN_MOVERIGHT) ? "→"       : "  ",
              (iButtons & IN_DUCK)      ? "+DUCK"   : "    ",
              (iButtons & IN_BACK)      ? "↓"       : "  ",
              (iButtons & IN_JUMP)      ? "+JUMP"   : "    "
            );

            SetHudTextParams(-1.0, 0.7, 0.3, iColor[0], iColor[1], iColor[2], 255, 0, 0.0, 0.0, 0.0);
        }
        else {
            SetHudTextParams(-1.0, -0.02, 0.3, iColor[0], iColor[1], iColor[2], 255, 0, 0.0, 0.0, 0.0);
            Format(sHud, sizeof(sHud), "%T\n%T", "xms_hud_spec1", iClient, "xms_hud_spec2", iClient);
        }

        ShowSyncHudText(iClient, gHud.hKeys, sHud);
    }

    return Plugin_Continue;
}

/**************************************************************
 * TIMELEFT HUD
 *************************************************************/
public Action T_TimeHud(Handle hTimer)
{
    static int iTimer;

    bool bRed = (gRound.iState == GAME_OVERTIME || gRound.iState == GAME_MATCHEX);
    char sHud[48];

    if (gRound.iState == GAME_MATCHWAIT || gRound.iState == GAME_CHANGING || gRound.iState == GAME_PAUSED)
    {
        Format(sHud, sizeof(sHud), ". . %s%s%s", iTimer >= 20 ? ". " : "", iTimer >= 15 ? ". " : "", iTimer >= 10 ? "." : "");
        iTimer++;
        if (iTimer >= 25) {
            iTimer = 0;
        }
    }

    else if (gRound.iState != GAME_OVER && gConVar.mp_timelimit.BoolValue)
    {
        float fTime = GetTimeRemaining(false);

        Format(sHud, sizeof(sHud), "%s%s", sHud, Timestring(fTime, fTime < 10, true));
        bRed = (fTime < 60);
    }

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || (IsFakeClient(iClient) && !IsClientSourceTV(iClient)) ) {
            continue;
        }

        char sHud2[48];
        bool bMargin = IsClientObserver(iClient) && !IsClientSourceTV(iClient);

        strcopy(sHud2, sizeof(sHud2), sHud);

        if (gRound.iState == GAME_OVER) {
            Format(sHud2, sizeof(sHud2), "%T", "xms_hud_gameover", iClient);
        }
        else if (gRound.iState == GAME_MATCHEX || gRound.iState == GAME_OVERTIME) {
            Format(sHud2, sizeof(sHud2), "%T\n%s", "xms_hud_overtime", iClient, sHud);
        }

        if (strlen(sHud2))
        {
            if (bRed) {
                SetHudTextParams(-1.0, bMargin ? 0.03 : 0.01, 0.3, 220, 10, 10, 255, 0, 0.0, 0.0, 0.0);
            }
            else
            {
                int iColor[3];

                GetClientColors(iClient, iColor);
                SetHudTextParams(-1.0, bMargin ? 0.03 : 0.01, 0.3, iColor[0], iColor[1], iColor[2], 255, 0, 0.0, 0.0, 0.0);
            }

            ShowSyncHudText(iClient, gHud.hTime, sHud2);
        }
    }

    return Plugin_Continue;
}

/**************************************************************
 * XMS ATTRIBUTION
 *************************************************************/
public Action T_AnnouncePlugin(Handle hTimer, int iClient)
{
    static int i;

    if (IsClientInGame(iClient) && i < 4)
    {
        PrintCenterText(iClient, "~ eXtended Match System by harper ~");
        i++;
        return Plugin_Continue;
    }

    i = 0;
    return Plugin_Stop;
}

/**************************************************************
 * VOTING HUD
 *************************************************************/
// contained within voting.sp:T_Voting