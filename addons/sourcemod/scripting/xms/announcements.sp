/**************************************************************
 * CHAT ANNOUNCEMENTS
 *************************************************************/
public Action T_Welcome(Handle hTimer, int iClient)
{
    static int i;

    i++;

    if (!IsClientInGame(iClient)) {
        if (i >= 100) {
            return Plugin_Stop;
        }
    }
    else {
        MC_PrintToChat(iClient, "%T", "xms_welcome", iClient, gCore.sServerName);
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public Action T_Adverts(Handle hTimer)
{
    static int i = 1;

    char sText[MAX_SAY_LENGTH];

    if (!GetRealClientCount() || IsGameMatch()) {
        return Plugin_Continue;
    }

    IntToString(i, sText, sizeof(sText));
    if (!GetConfigString(sText, sizeof(sText), sText, "ServerAds"))
    {
        if (i != -1 && !GetConfigString(sText, sizeof(sText), "1", "ServerAds")) {
            return Plugin_Stop;
        }
        i = 1;
    }

    MC_PrintToChatAll("%t", "xms_serverad", sText);
    i++;

    return Plugin_Continue;
}