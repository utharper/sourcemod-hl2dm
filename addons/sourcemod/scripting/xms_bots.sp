#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION  "1.2"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xms_bots.upd"

public Plugin myinfo = {
    name              = "XMS - Bot Controller",
    version           = PLUGIN_VERSION,
    description       = "RCBot2 controller for XMS servers",
    // currently only supports a single bot -- automatically leaves when player count exceeds 1
    author            = "harper",
    url               = PLUGIN_URL
};

/**************************************************************
 * INCLUDES
 *************************************************************/
#include <sourcemod>
#include <morecolors>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <updater>

#define REQUIRE_PLUGIN
#include <jhl2dm>
#include <xms>

/**************************************************************
 * GLOBAL VARS
 *************************************************************/
int  giBotClient;
int  giState;
int  giJoinDelay;
int  giLeaveDelay;

bool gbEnabled;
bool gbContinue;
bool gbSourceTV;

char gsBotName[MAX_NAME_LENGTH];
char gsKnownMaps[8][MAX_MAP_LENGTH] =
{
    // the bot is familiar with these maps and shouldn't get stuck. (just stock maps for now)
    "dm_lockdown",
    "dm_overwatch",
    "dm_powerhouse",
    "dm_resistance",
    "dm_runoff",
    "dm_steamlab",
    "dm_underpass",
    "halls3"
};

/**************************************************************/

public void OnPluginStart()
{
    LoadTranslations("xms_bot.phrases.txt");

    CreateConVar("xms_bots_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    CreateTimer(1.0, T_CheckBots, _, TIMER_REPEAT);

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

    if (LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnAllPluginsLoaded()
{
    gbEnabled = BotsAvailable();
}

public void OnMapStart()
{
    gbEnabled  = BotsAvailable();
    gbSourceTV = FindConVar("tv_enable").BoolValue;
}

public void OnMapEnd()
{
    giBotClient = 0;
}

public void OnClientPutInServer(int iClient)
{
    if (gbEnabled && IsClientInGame(iClient) && IsFakeClient(iClient) && !IsClientSourceTV(iClient))
    {
        giBotClient = iClient;
        GetClientName(giBotClient, gsBotName, sizeof(gsBotName));
        CreateTimer(2.0, T_BotAnnounce, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
    if (!iClient || !giBotClient || !IsClientInGame(giBotClient)) {
        return Plugin_Continue;
    }

    if (StrContains(sArgs, "!") != 0 && StrContains(sArgs, "/") != 0 && !CommandExists(sArgs))
    {
        // not a command

        if (StrContains(sArgs, gsBotName, false) != -1 || Math_GetRandomInt(1, 2) == 2)
        {
            // Reply to 50% of chat, or if bot name is said
            CreateTimer(1.0, T_BotResponse, TIMER_FLAG_NO_MAPCHANGE);
        }
    }

    return Plugin_Continue;
}

public void OnGamestateChanged(int iNewState, int iOldState)
{
    if (iNewState == GAME_OVER)
    {
        if (giBotClient > 0 && IsClientInGame(giBotClient))
        {
            char sText[MAX_SAY_LENGTH];

            Format(sText, sizeof(sText), "xms_bot_end%i", Math_GetRandomInt(1, 2));
            Format(sText, sizeof(sText), "%T", sText, LANG_SERVER);

            MC_PrintToChatAllFrom(giBotClient, false, sText);
        }
    }
    else if (iOldState == GAME_CHANGING)
    {
        gbContinue = (giBotClient > 0 && IsClientInGame(giBotClient));
    }

    giState = iNewState;
}

public Action T_CheckBots(Handle hTimer)
{
    if (gbEnabled && (GetTimeElapsed() >= giJoinDelay || gbContinue))
    {
        int iTotal       = GetRealClientCount(true, true) - view_as<int>(gbSourceTV);
        int iPlayers     = GetRealClientCount(true, false);
        int iConnecting  = GetRealClientCount(false, false) - iPlayers;

        if (iPlayers == 1)
        {
            if (!iConnecting && giBotClient == 0)
            {
                giBotClient = -1;
                CreateTimer(1.0, T_BotAdd, _, TIMER_FLAG_NO_MAPCHANGE);
            }
        }
        else if (giBotClient)
        {
            CreateTimer(view_as<float>(clamp(giLeaveDelay, 0, 999)), T_BotRemove, _, TIMER_FLAG_NO_MAPCHANGE);
        }

        if (iTotal > iPlayers + 1)
        {
           LogMessage("More bots spawned than expected, kicking..");
           ServerCommand("rcbotd kickbot");
           giBotClient = FindBotClient();
        }
    }

    return Plugin_Continue;
}

public Action T_BotAdd(Handle hTimer)
{
    if (GetRealClientCount(true, false) == 1 && giState == GAME_DEFAULT) {
        ServerCommand("rcbotd addbot");
    }
    
    return Plugin_Handled;
}

public Action T_BotAnnounce(Handle hTimer)
{
    static int iTimer;
    static int iRan;

    if (giBotClient > 0 && IsClientInGame(giBotClient))
    {
        char sText[MAX_SAY_LENGTH];

        iRan = Math_GetRandomIntNot(1, 3, iRan);

        if (gbContinue)
        {
            bool bKnownMap;
            char sMap[MAX_MAP_LENGTH];

            GetCurrentMap(sMap, sizeof(sMap));
            for (int i = 0; i < sizeof(gsKnownMaps); i++)
            {
                if (StrEqual(sMap, gsKnownMaps[i])) {
                    bKnownMap = true;
                }
            }

            Format(sText, sizeof(sText), "xms_bot_%sknownmap%i", bKnownMap ? "" : "un", iRan);
            Format(sText, sizeof(sText), "%T", sText, LANG_SERVER);
            MC_PrintToChatAllFrom(giBotClient, false, sText);

            return Plugin_Stop;
        }
        else
        {
            if (iTimer == 0)
            {
                Format(sText, sizeof(sText), "xms_bot_greet%i", iRan);
                Format(sText, sizeof(sText), "%T", sText, LANG_SERVER);
                MC_PrintToChatAllFrom(giBotClient, false, sText);
            }
            else if (iTimer >= 2)
            {
                Format(sText, sizeof(sText), "xms_bot_play%i", iRan);
                Format(sText, sizeof(sText), "%T", sText, LANG_SERVER);
                MC_PrintToChatAllFrom(giBotClient, false, sText);

                iTimer = 0;
                return Plugin_Stop;
            }

            iTimer++;
        }
    }
    
    return Plugin_Continue;
}

public Action T_BotRemove(Handle hTimer)
{
    static int iRan;

    if (GetRealClientCount(true, false) != 1 && giState == GAME_DEFAULT)
    {
        if (giBotClient > 0 && IsClientInGame(giBotClient))
        {
            char sText[MAX_SAY_LENGTH];

            iRan = Math_GetRandomIntNot(1, 3, iRan);

            Format(sText, sizeof(sText), "xms_bot_quit%i", iRan);
            Format(sText, sizeof(sText), "%T", sText, LANG_SERVER);
            MC_PrintToChatAllFrom(giBotClient, false, sText);

            ServerCommand("rcbotd kickbot");
            giBotClient = 0;
        }
    }
    
    return Plugin_Handled;
}

public Action T_BotTaunt(Handle hTimer)
{
    static int iText;

    if (IsClientInGame(giBotClient))
    {
        char sText[MAX_SAY_LENGTH];

        iText = Math_GetRandomIntNot(1, 6, iText);

        Format(sText, sizeof(sText), "xms_bot_taunt%i", iText);
        Format(sText, sizeof(sText), "%T", sText, LANG_SERVER);
        MC_PrintToChatAllFrom(giBotClient, false, sText);
    }

    return Plugin_Stop;
}

public Action T_BotDeath(Handle hTimer, bool bSuicide)
{
    static int iText;

    if (IsClientInGame(giBotClient))
    {
        char sText[MAX_SAY_LENGTH];

        iText = Math_GetRandomIntNot(1, bSuicide ? 3 : 6, iText);

        Format(sText, sizeof(sText), "xms_bot_%s%i", bSuicide ? "suicide" : "death", iText);
        Format(sText, sizeof(sText), "%T", sText, LANG_SERVER);
        MC_PrintToChatAllFrom(giBotClient, false, sText);
    }

    return Plugin_Stop;
}

public Action T_BotResponse(Handle hTimer)
{
    static int iText;

    if (IsClientInGame(giBotClient))
    {
        char sText[MAX_SAY_LENGTH];

        iText = Math_GetRandomIntNot(1, 7, iText);

        Format(sText, sizeof(sText), "xms_bot_response%i", iText);
        Format(sText, sizeof(sText), "%T", sText, LANG_SERVER);
        MC_PrintToChatAllFrom(giBotClient, false, sText);
    }

    return Plugin_Stop;
}

public Action Event_PlayerDeath(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
    if (!gbEnabled || !giBotClient) {
        return Plugin_Continue;
    }

    bool bBotAttacker = (giBotClient == GetClientOfUserId(GetEventInt(hEvent, "attacker")));
    bool bBotVictim   = (giBotClient == GetClientOfUserId(GetEventInt(hEvent, "userid")));

    if (bBotAttacker && bBotVictim)
    {
        // suicide
        CreateTimer(1.0, T_BotDeath, true, TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (bBotAttacker)
    {
        // player killed by bot, 33% chance to taunt
        if (Math_GetRandomInt(1, 3) == 1) {
            CreateTimer(1.0, T_BotTaunt, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
    else if (bBotVictim)
    {
        // bot killed by player, 33% chance to comment
        if (Math_GetRandomInt(1, 3) == 1) {
            CreateTimer(1.0, T_BotDeath, false, TIMER_FLAG_NO_MAPCHANGE);
        }
    }

    return Plugin_Continue;
}

bool BotsAvailable()
{
    static bool bBotSupport;

    char sCurrentMode   [MAX_MODE_LENGTH];
    char sSupportedModes[192];
    char sCommand       [16];

    if (!bBotSupport)
    {
        ServerCommandEx(sCommand, sizeof(sCommand), "rcbotd");

        if (!(StrContains(sCommand, "Unknown command") == 0)) {
            bBotSupport = true;
        }
        else {
            LogError("RCBot2 not running");
        }
    }

    if (bBotSupport)
    {
        GetGamemode(sCurrentMode, sizeof(sCurrentMode));
        if (GetConfigString(sSupportedModes, sizeof(sSupportedModes), "Gamemodes", "Bots"))
        {
            giJoinDelay  = GetConfigInt("JoinDelay", "Bots");
            giLeaveDelay = GetConfigInt("QuitDelay", "Bots");

            if (IsItemDistinctInList(sCurrentMode, sSupportedModes)) {
                return true;
            }
        }
    }

    return false;
}

int FindBotClient()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientConnected(i) && IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i)) {
            return i;
        }
    }

    return 0;
}