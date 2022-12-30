// compiled with SM 1.8 and gameme v4.5.1
// Fetching data causes a ton of rcon console spam. Use Cleaner [https://forums.alliedmods.net/showthread.php?p=1789738].
#pragma semicolon 1

#define PLUGIN_VERSION  "1.3"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/gameme_hud.upd"

public Plugin myinfo = {
    name              = "gameME Stats HUD",
    version           = PLUGIN_VERSION,
    description       = "Live scoreboard player stats via gameME data",
    author            = "harper",
    url               = PLUGIN_URL
};

/**************************************************************
 * INCLUDES
 *************************************************************/
#include <sourcemod>
#include <clientprefs>
#include <gameme>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <updater>

#pragma newdecls required
#include <jhl2dm>
#include <xms>

#define REQUIRE_PLUGIN
#include <gameme_hud>

/**************************************************************
 * GLOBAL VARS
 *************************************************************/
#define QUERYINTERVAL 1.0 // must be a whole number
#define HUDINTERVAL   1.0

Handle ghHud;
/*Cookie*/Handle gcColor[3];

int giStatsVisible[MAXPLAYERS + 1];
int giTop10Points [10];
int giTotalPlayers;

bool gbStayVisible[MAXPLAYERS + 1];
bool gbUsingXMS;

any  gValues      [32][MAXPLAYERS + 1];
char gsTop10Names [10][MAX_NAME_LENGTH];

/**************************************************************/

public int Native_StatsInitialised(Handle hPlugin, int iParams)
{
    return view_as<int>(giTotalPlayers > 0 && giTop10Points[0] > 0);
}

public int Native_IsPlayerRanked(Handle hPlugin, int iParams)
{
    return(view_as<int>(giTotalPlayers > 0 && gValues[GM_POINTS][GetNativeCell(1)] != 0));
}

public int Native_FetchTop10PlayerData(Handle hPlugin, int iParams)
{
    int iRank = GetNativeCell(1);

    if (iRank < 1 || iRank > 10 || !strlen(gsTop10Names[iRank])) {
        return -1;
    }

    SetNativeString(2, gsTop10Names[iRank - 1], GetNativeCell(3));
    return giTop10Points[iRank - 1];
}

public int Native_FetchPlayerData(Handle hPlugin, int iParams)
{
    char sValue[32];
    int  iClient = GetNativeCell(3);
    int  iField  = GetNativeCell(4);
    int  iBytes;

    if (iField == GM_HPK || iField == GM_PRE_HPK || iField == GM_ACCURACY || iField == GM_PRE_ACCURACY || iField == GM_KPD || iField == GM_PRE_KPD)
    {
        if (GetNativeCell(5)) {
            Format(sValue, sizeof(sValue), "%.0f", gValues[iClient][iField]);
        }
        else {
            Format(sValue, sizeof(sValue), "%.2f", gValues[iClient][iField]);
        }
    }
    else {
        Format(sValue, sizeof(sValue), "%i", gValues[iClient][iField]);
    }

    SetNativeString(1, sValue, GetNativeCell(2), true, iBytes);

    return iBytes;
}

/**************************************************************/

public APLRes AskPluginLoad2(Handle hPlugin, bool bLate, char[] sError, int iLen)
{
    CreateNative("gameME_StatsInitialised",     Native_StatsInitialised);
    CreateNative("gameME_IsPlayerRanked",       Native_IsPlayerRanked);
    CreateNative("gameME_FetchPlayerData",      Native_FetchPlayerData);
    CreateNative("gameME_FetchTop10PlayerData", Native_FetchTop10PlayerData);

    RegPluginLibrary("gameme_hud");
}

public void OnPluginStart()
{
    LoadTranslations("gameme_hud.phrases.txt");
    CreateConVar("gameme_hud_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    ghHud = CreateHudSynchronizer();

    for (int i = 1; i <= MaxClients; i++) {
        CreateTimer(HUDINTERVAL, T_Hud, i, TIMER_REPEAT);
        CreateTimer(QUERYINTERVAL, T_Stats, i, TIMER_REPEAT);
    }

    HookUserMessage(GetUserMessageId("VGUIMenu"), UserMsg_VGUIMenu, false);

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
    gbUsingXMS = LibraryExists("xms");

    if (gbUsingXMS) {
        gcColor[0] = FindClientCookie("hudcolor_r");
        gcColor[1] = FindClientCookie("hudcolor_g");
        gcColor[2] = FindClientCookie("hudcolor_b");
    }
    else {
        HookEvent("round_start", Event_RoundStart, EventHookMode_Post);
    }
}

public void OnClientPutInServer(int iClient)
{
    if (!IsFakeClient(iClient))
    {
        QueryGameMEStats("playerinfo", iClient, FetchPlayerData, 1);
        CreateTimer(1.0, T_AnnouncePlugin, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(1.0, T_Top10, TIMER_REPEAT);
    }
}

public Action Event_RoundStart(Event hEvent, const char[] sName, bool bDontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++) {
        SetPreValues(i);
    }
}

public void OnGamestateChanged(int iNewState, int iOldState)
{
    if (iNewState == GAME_DEFAULT || iNewState == GAME_MATCHWAIT)
    {
        for (int i = 1; i <= MaxClients; i++) {
            SetPreValues(i);
        }
    }
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAngles[3], int &iWeapon)
{
    static int iLastButtons[MAXPLAYERS + 1];

    if (IsClientConnected(iClient) && !IsFakeClient(iClient))
    {
        if (iButtons & IN_SCORE)
        {
            if (gbStayVisible[iClient]) {
                gbStayVisible[iClient] = false;
            }
        }

        giStatsVisible[iClient] = (
            gbStayVisible[iClient] ? 1
            : (iButtons & IN_SCORE) ?
                (!(iLastButtons[iClient] & IN_SCORE)) ? 2
                : 1
            : 0
        );

        iLastButtons[iClient] = iButtons;

        if (giStatsVisible[iClient] == 2) {
            ShowStats(iClient);
        }
    }
    else {
        iLastButtons[iClient] = 0;
    }
}

public Action UserMsg_VGUIMenu(UserMsg msg, Handle hMsg, const int[] iPlayers, int iNumPlayers, bool bReliable, bool bInit)
{
    char sMsg[10];
    BfReadString(hMsg, sMsg, sizeof(sMsg));

    if (StrEqual(sMsg, "scores"))
    {
        for (int i = 1; i <= MaxClients; i++) {
            gbStayVisible[i] = true;
        }
    }

    return Plugin_Continue;
}

public Action T_AnnouncePlugin(Handle hTimer, int iClient)
{
    static int iTimer;

    if (IsClientInGame(iClient) && iTimer < 9 && giTotalPlayers)
    {
        if (iTimer > 4 && (!gbUsingXMS || GetGamestate() != GAME_CHANGING)) {
            PrintCenterText(iClient, "\n~ gameME stats: tracking %i players ~", giTotalPlayers);
        }

        iTimer++;
        return Plugin_Continue;
    }

    iTimer = 0;
    return Plugin_Stop;
}

public Action T_Stats(Handle hTimer, int iClient)
{
    if (IsClientInGame(iClient) && !IsFakeClient(iClient)) {
        QueryGameMEStats("playerinfo", iClient, FetchPlayerData);
    }

    return Plugin_Continue;
}

public Action T_Top10(Handle hTimer)
{
    QueryGameMEStatsTop10("top10", -1, FetchTop10Data);
}

public Action T_Hud(Handle hTimer, int iClient)
{
    if (IsClientInGame(iClient) && !IsFakeClient(iClient) && giStatsVisible[iClient] && giStatsVisible[iClient] != 2) {
        ShowStats(iClient);
    }
    return Plugin_Continue;
}

void SetPreValues(int iClient)
{
    gbStayVisible[iClient] = false;

    for (int iParam = GM_PRE_RANK; iParam <= GM_PRE_KPD; iParam += 2) {
        gValues[iClient][iParam] = gValues[iClient][iParam - 1];
    }

    gValues[iClient][GM_MAPTIME] = 0;
}

void ShowStats(int iClient)
{
    int iTarget = (
        IsClientObserver(iClient) ? GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget")
        : iClient
    );

    if (iTarget > 1 && IsClientInGame(iTarget) && !IsFakeClient(iTarget) && giTotalPlayers)
    {
        int  iColor [3] = { 255, 177, 0 };
        char sTarget[MAX_NAME_LENGTH],
             sHud   [1024];

        if (gbUsingXMS)
        {
            for (int i = 0; i < 3; i++) {
                iColor[i] = clamp(GetClientCookieInt(iClient, gcColor[i]), 0, 255);
            }
        }

        GetClientName(iTarget, sTarget, sizeof(sTarget));

        Format(sHud, sizeof(sHud), "%T", "gameme_hud_display", iClient, sTarget, gValues[iTarget][GM_RANK], giTotalPlayers, Timestring(float(gValues[iTarget][GM_PRETIME] + gValues[iTarget][GM_MAPTIME]), false, false),
          gValues[iTarget][GM_KILLS], gValues[iTarget][GM_ROUNDKILLS], gValues[iTarget][GM_DEATHS], gValues[iTarget][GM_ROUNDDEATHS], gValues[iTarget][GM_HEADSHOTS], gValues[iTarget][GM_ROUNDHEADSHOTS],
          gValues[iTarget][GM_SUICIDES], gValues[iTarget][GM_ROUNDSUICIDES], RoundFloat(gValues[iTarget][GM_ACCURACY]), gValues[iTarget][GM_KILLSPREE]
        );

        SetHudTextParams(0.01, 0.37, 1.01, iColor[0], iColor[1], iColor[2], 255, 0, 0.0, 0.0, 0.0);
        ShowSyncHudText(iClient, ghHud, sHud);
    }
}

#pragma newdecls optional
public FetchPlayerData(iCommand, iPayload, iClient, &Handle: hDataPack) //?
#pragma newdecls required
{
    if (iClient > 0 && iCommand == RAW_MESSAGE_CALLBACK_PLAYER)
    {
        Handle hData = CloneHandle(hDataPack);

        ResetPack(hData);
        gValues[iClient][GM_RANK]      = ReadPackCell(hData);
        giTotalPlayers                 = ReadPackCell(hData);
        gValues[iClient][GM_POINTS]    = ReadPackCell(hData);
        gValues[iClient][GM_KILLS]     = ReadPackCell(hData);
        gValues[iClient][GM_DEATHS]    = ReadPackCell(hData);
        gValues[iClient][GM_KPD]       = ReadPackFloat(hData);
        gValues[iClient][GM_SUICIDES]  = ReadPackCell(hData);
        gValues[iClient][GM_HEADSHOTS] = ReadPackCell(hData);
        gValues[iClient][GM_HPK]       = ReadPackFloat(hData);
        gValues[iClient][GM_ACCURACY]  = ReadPackFloat(hData);
        gValues[iClient][GM_PRETIME]   = ReadPackCell(hData);
        for (int i = 0; i < 5; i++) {
            ReadPackCell(hData);
        }
        gValues[iClient][GM_KILLSPREE] = ReadPackCell(hData);
        gValues[iClient][GM_DEATHSPREE] = ReadPackCell(hData);

        gValues[iClient][GM_MAPTIME]       += RoundToNearest(QUERYINTERVAL);
        gValues[iClient][GM_PLAYTIME]       = gValues[iClient][GM_PRETIME]   + gValues[iClient][GM_MAPTIME];
        gValues[iClient][GM_ROUNDPOINTS]    = gValues[iClient][GM_POINTS]    - gValues[iClient][GM_PRE_POINTS];
        gValues[iClient][GM_ROUNDKILLS]     = gValues[iClient][GM_KILLS]     - gValues[iClient][GM_PRE_KILLS];
        gValues[iClient][GM_ROUNDDEATHS]    = gValues[iClient][GM_DEATHS]    - gValues[iClient][GM_PRE_DEATHS];
        gValues[iClient][GM_ROUNDSUICIDES]  = gValues[iClient][GM_SUICIDES]  - gValues[iClient][GM_PRE_SUICIDES];
        gValues[iClient][GM_ROUNDHEADSHOTS] = gValues[iClient][GM_HEADSHOTS] - gValues[iClient][GM_PRE_HEADSHOTS];

        CloseHandle(hData);

        if (iPayload) {
            SetPreValues(iClient);
        }
    }
}

#pragma newdecls optional
public FetchTop10Data(iCommand, iPayload, &Handle: hDataPack)
#pragma newdecls required
{
    if (iCommand == RAW_MESSAGE_CALLBACK_TOP10)
    {
        int    iTotal;
        Handle hData = CloneHandle(hDataPack);

        ResetPack(hData);
        iTotal = ReadPackCell(hData);

        if (iTotal)
        {
            for (int i = 0; i < iTotal; i++)
            {
                ReadPackCell(hData); // rank
                giTop10Points[i] = ReadPackCell(hData);
                ReadPackString(hData, gsTop10Names[i], MAX_NAME_LENGTH);
                ReadPackFloat(hData);
                ReadPackFloat(hData);
            }
        }

        CloseHandle(hData);
    }
}