#pragma dynamic 2097152
#pragma semicolon 1

#define PLUGIN_VERSION     "1.92"
#define PLUGIN_URL         "www.hl2dm.community"
#define PLUGIN_UPDATE      "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xms.upd"

public Plugin myinfo = {
    name                 = "XMS (eXtended Match System)",
    version              = PLUGIN_VERSION,
    description          = "Multi-gamemode match plugin for competitive HL2DM servers",
    author               = "harper",
    url                  = PLUGIN_URL
};

/**************************************************************
 * INCLUDES
 *************************************************************/
#include <sourcemod>
#include <clientprefs>
#include <steamtools>
#include <smlib>
#include <sdkhooks>
#include <vphysics>
#include <morecolors>
#include <basecomm>

#undef REQUIRE_PLUGIN
#include <updater>
#tryinclude <gameme_hud>

#define REQUIRE_PLUGIN
#pragma newdecls required
#include <jhl2dm>
#include <xms>

/**************************************************************
 * DEFINITIONS
 *************************************************************/
#define BITS_SPRINT          0x00000001
#define OFFS_COLLISIONGROUP  500
#define MENU_ROWLEN          32

#define OVERTIME_TIME        1
#define DELAY_ACTION         4

#define SOUND_CONNECT        "friends/friend_online.wav"
#define SOUND_DISCONNECT     "friends/friend_join.wav"
#define SOUND_ACTIONPENDING  "buttons/blip1.wav"
#define SOUND_ACTIONCOMPLETE "hl1/fvox/beep.wav"
#define SOUND_COMMANDFAIL    "resource/warning.wav"
#define SOUND_ACTIVATED      "hl1/fvox/activated.wav"
#define SOUND_DEACTIVATED    "hl1/fvox/deactivated.wav"
#define SOUND_MENUACTION     "weapons/slam/buttonclick.wav"

#define SOUND_VOTECALLED     "xms/votecall.wav"
#define SOUND_VOTEFAILED     "xms/votefail.wav"
#define SOUND_VOTESUCCESS    "xms/voteaccept.wav"
#define SOUND_GG             "xms/gg.mp3"

enum(+=1)
{
    VOTE_RUN, VOTE_RUNNEXT, VOTE_RUNNEXT_AUTO, VOTE_RUNMULTI, VOTE_RUNMULTINEXT,
    VOTE_MATCH, VOTE_SHUFFLE, VOTE_INVERT, VOTE_CUSTOM
}

char gsMusicPath[6][PLATFORM_MAX_PATH] =
{
    "music/hl2_song14.mp3",
    "music/hl2_song20_submix0.mp3",
    "music/hl2_song15.mp3",
    "music/hl1_song25_remix3.mp3",
    "music/hl1_song10.mp3",
    "music/hl2_song12_long.mp3"
};

char gsModelPath[19][70] =
{
    "models/combine_soldier.mdl",
    "models/combine_soldier_prisonguard.mdl",
    "models/combine_super_soldier.mdl",
    "models/police.mdl",
    "models/humans/group03/female_01.mdl",
    "models/humans/group03/female_02.mdl",
    "models/humans/group03/female_03.mdl",
    "models/humans/group03/female_04.mdl",
    "models/humans/group03/female_06.mdl",
    "models/humans/group03/female_07.mdl",
    "models/humans/group03/male_01.mdl",
    "models/humans/group03/male_02.mdl",
    "models/humans/group03/male_03.mdl",
    "models/humans/group03/male_04.mdl",
    "models/humans/group03/male_05.mdl",
    "models/humans/group03/male_06.mdl",
    "models/humans/group03/male_07.mdl",
    "models/humans/group03/male_08.mdl",
    "models/humans/group03/male_09.mdl"
};

/**************************************************************
 * GLOBAL VARS
 *************************************************************/
int         giGamestate,
            giOvertime,
            giAllowClient,
            giPauseClient,
            giSpawnHealth,
            giSpawnSuit,
            giSpawnAmmo     [16][2],
            giClientMenuType[MAXPLAYERS + 1],
            giClientVote    [MAXPLAYERS + 1],
            giClientVoteTick[MAXPLAYERS + 1],
            giVoteMinPlayers,
            giVoteMaxTime,
            giVoteCooldown,
            giVoteType,
            giVoteStatus,
            giAdFrequency,
            giShowKeys;

bool        gbPluginReady,
            gbModTags,
            gbGameME,
            gbClientInit    [MAXPLAYERS + 1],
            gbClientKill    [MAXPLAYERS + 1],
            gbAutoVoting,
            gbTeamplay,
            gbDisableProps,
            gbDisableCollisions,
            gbUnlimitedAux,
            gbRecording,
            gbNextMapChosen,
            gbStockMapsIfEmpty;

float       gfPretime,
            gfEndtime;

char        gsConfigPath  [PLATFORM_MAX_PATH],
            gsFeedbackPath[PLATFORM_MAX_PATH],
            gsDemoPath    [PLATFORM_MAX_PATH],
            gsGameId      [128],
            gsMap         [MAX_MAP_LENGTH],
            gsNextMap     [MAX_MAP_LENGTH],
            gsMode        [MAX_MODE_LENGTH],
            gsModeName    [32],
            gsNextMode    [MAX_MODE_LENGTH],
            gsValidModes  [512],
            gsRetainModes [512],
            gsDefaultMode [MAX_MODE_LENGTH],
            gsVoteMotion  [5][192],
            gsSpawnWeapon [16][32],
            gsServerName  [32],
            gsServerMsg   [192],
            gsDemoURL     [PLATFORM_MAX_PATH],
            gsDemoFileExt [8],
            gsStripPrefix [512];

Handle      ghForwardGamestateChanged,
            ghForwardMatchStart,
            ghForwardMatchEnd,
            ghForwardFeedback,
            ghTimeHud,
            ghVoteHud,
            ghKeysHud,
            ghOvertimer = INVALID_HANDLE,
            ghCookieMusic,
            ghCookieSounds,
            ghCookieColors[3];

ConVar      ghConVarTags,
            ghConVarTimelimit,
            ghConVarTeamplay,
            ghConVarChattime,
            ghConVarFF,
            ghConVarPausable,
            ghConVarTv,
            ghConVarNextmap,
            ghConVarRestart;

KeyValues   gkConfig;

StringMap   gmTeams,
            gmMenu          [MAXPLAYERS + 1];

/**************************************************************
 * NATIVES
 *************************************************************/
public int Native_GetConfigString(Handle hPlugin, int iParams)
{
    char sValue[1024],
         sKey  [32],
         sInKey[32];

    gkConfig.Rewind();
    GetNativeString(3, sKey, sizeof(sKey));

    for (int i = 4; i <= iParams; i++)
    {
        GetNativeString(i, sInKey, sizeof(sInKey));

        if (!strlen(sInKey)) {
            continue;
        }

        if (!gkConfig.JumpToKey(sInKey)) {
            return -1;
        }
    }

    if (gkConfig.GetString(sKey, sValue, sizeof(sValue)))
    {
        if (!strlen(sValue)) {
            return 0;
        }

        SetNativeString(1, sValue, GetNativeCell(2));
        return 1;
    }

    return -1;
}

public int Native_GetConfigInt(Handle hPlugin, int iParams)
{
    char sValue[32],
         sKey  [32],
         sInKey[4][32];

    GetNativeString(1, sKey, sizeof(sKey));

    for (int i = 2; i <= iParams; i++) {
        GetNativeString(i, sInKey[i - 2], sizeof(sInKey[]));
    }

    if (GetConfigString(sValue, sizeof(sValue), sKey, sInKey[0], sInKey[1], sInKey[2], sInKey[3])) {
        return StringToInt(sValue);
    }

    return -1;
}

public int Native_GetConfigKeys(Handle hPlugin, int iParams)
{
    char sKeys [1024],
         sInKey[32];
    int  iCount;

    gkConfig.Rewind();

    for (int i = 3; i <= iParams; i++)
    {
        GetNativeString(i, sInKey, sizeof(sInKey));
        if (!gkConfig.JumpToKey(sInKey)) {
            return -1;
        }
    }

    if (gkConfig.GotoFirstSubKey(false))
    {
        do {
            gkConfig.GetSectionName(sKeys[strlen(sKeys)], sizeof(sKeys));
            sKeys[strlen(sKeys)] = ',';
            iCount++;
        }
        while (gkConfig.GotoNextKey(false));

        sKeys[strlen(sKeys) - 1] = 0;
        SetNativeString(1, sKeys, GetNativeCell(2));

        return iCount;
    }

    return -1;
}

public int Native_GetGamestate(Handle hPlugin, int iParams)
{
    return giGamestate;
}

public int Native_GetGamemode(Handle hPlugin, int iParams)
{
    int iBytes;

    SetNativeString(1, gsMode, GetNativeCell(2), true, iBytes);
    return iBytes;
}

public int Native_GetGameID(Handle hPlugin, int iParams)
{
    int iBytes;

    SetNativeString(1, gsGameId, GetNativeCell(2), true, iBytes);
    return iBytes;
}

public int Native_GetTimeRemaining(Handle hPlugin, int iParams)
{
    float fTime = (ghConVarTimelimit.FloatValue * 60 - GetGameTime() + gfPretime);

    if (GetNativeCell(1))
    {
        if (giGamestate == GAME_OVER) {
            return view_as<int>(ghConVarChattime.FloatValue - (GetGameTime() - gfEndtime));
        }
        return view_as<int>(fTime + ghConVarChattime.FloatValue);
    }

    return view_as<int>(fTime);
}

public int Native_GetTimeElapsed(Handle hPlugin, int iParams)
{
    return view_as<int>(GetGameTime() - gfPretime);
}

public int Native_XMenu(Handle hPlugin, int iParams)
{
    int         iClient     = GetNativeCell(1),
                iPage       = 0,
                iOptions[2] = 0;
    bool        bBackButton = GetNativeCell(2),
                bExitButton,
                bNumbered   = GetNativeCell(3),
                bNextButton;
    char        sCommandBase[64],
                sCommandBack[64],
                sTitle      [64],
                sMessage    [1024];
    KeyValues   kPanel [64];
    StringMap   mMenu       = CreateTrie();
    DataPack    dOptions    = view_as<DataPack>(GetNativeCell(7));
    DataPackPos dOptionsEnd = GetPackPosition(dOptions);

    GetNativeString(4, sCommandBase, sizeof(sCommandBase));
    GetNativeString(5, sTitle,   sizeof(sTitle));
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
        char sOption[256],
             sCommand[128];

        iOptions[0]   = 0;
        kPanel[iPage] = new KeyValues("menu");

        // Add back button at top of page:
        if (iPage >= 1)
        {
            if (bBackButton) {
                bExitButton = true;
            }
            bBackButton = true;
        }

        if (bExitButton)
        {
            Format(sOption, sizeof(sOption), "%T", bBackButton ? "xmenu_exit" : "xmenu_back", iClient);

            kPanel[iPage].JumpToKey("1", true);
            kPanel[iPage].SetString("msg", sOption);
            kPanel[iPage].SetString("command", sCommandBack);
            kPanel[iPage].Rewind();

            iOptions[0]++;
        }

        if (bBackButton)
        {
            Format(sOption, sizeof(sOption), "%T", "xmenu_back", iClient);

            kPanel[iPage].JumpToKey(bExitButton ? "2" : "1", true);
            kPanel[iPage].SetString("msg", sOption);
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
                Format(sCommand, sizeof(sCommand), "%s %i" , sCommandBase, iOptions[1]);
            }

            // Append option number to name:
            if (bNumbered) {
                Format(sOption,  sizeof(sOption), "%i. %s", iOptions[1], sOption);
            }

            // Save values:
            kPanel[iPage].JumpToKey(IntToChar(iOptions[0]), true);
            kPanel[iPage].SetString("msg", sOption);
            kPanel[iPage].SetString("command", sCommand);
            kPanel[iPage].Rewind();
        }

        // Add next button at bottom of page:
        if (bNextButton)
        {
            Format(sOption, sizeof(sOption), "%T", "xmenu_next", iClient);

            kPanel[iPage].JumpToKey(IntToChar(iOptions[0] + 1), true);
            kPanel[iPage].SetString("msg", sOption);
            kPanel[iPage].SetString("command", "sm_xmenu_next");
            kPanel[iPage].Rewind();
        }

        iPage++;
    }
    while (GetPackPosition(dOptions) != dOptionsEnd && iPage < 64);

    dOptions.Close();

    // Record the number of pages:
    mMenu.SetValue("count", iPage);
    mMenu.SetValue("type", DialogType_Menu);

    // Set basic page options and add them to map:
    for (int i = 0; i < iPage; i++)
    {
        char sPageTitle[64];

        if (iPage > 1) {
            Format(sPageTitle, sizeof(sPageTitle), "%s (%i/%i)", sTitle, i + 1, iPage);
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
    GetNativeString(6, sTitle, sizeof(sTitle));
    GetNativeString(7, sMessage, sizeof(sMessage));

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
    GetNativeString(2, sTitle, sizeof(sTitle));
    GetNativeString(3, sMessage, sizeof(sMessage));

    kPanel.SetString("title", sTitle);
    kPanel.SetString("msg", sMessage);
    kPanel.SetString("command", sCommandBase);
    kPanel.SetNum("level", 1);

    mMenu.SetValue("count", 1);
    mMenu.SetValue("type", iType);
    mMenu.SetValue("1", kPanel);

    return view_as<int>(mMenu);
}

/**************************************************************
 * FORWARDS
 *************************************************************/
void Forward_OnGamestateChanged(int iState)
{
    Call_StartForward(ghForwardGamestateChanged);
    Call_PushCell(iState);
    Call_PushCell(giGamestate);
    Call_Finish();
}

void Forward_OnMatchStart()
{
    Call_StartForward(ghForwardMatchStart);
    Call_Finish();
}

void Forward_OnMatchEnd(bool bCompleted)
{
    Call_StartForward(ghForwardMatchEnd);
    Call_PushCell(view_as<int>(bCompleted));
    Call_Finish();
}

void Forward_OnClientFeedback(const char[] sFeedback, const char[] sName, const char[] sID, const char[] sGameID)
{
    Call_StartForward(ghForwardFeedback);
    Call_PushString(sFeedback);
    Call_PushString(sName);
    Call_PushString(sID);
    Call_PushString(sGameID);
    Call_Finish();
}

/**************************************************************
 * CORE
 *************************************************************/
public APLRes AskPluginLoad2(Handle hPlugin, bool bLate, char[] sError, int iLen)
{
    CreateNative("GetConfigKeys",    Native_GetConfigKeys);
    CreateNative("GetConfigString",  Native_GetConfigString);
    CreateNative("GetConfigInt",     Native_GetConfigInt);
    CreateNative("GetGamestate",     Native_GetGamestate);
    CreateNative("GetGamemode",      Native_GetGamemode);
    CreateNative("GetTimeRemaining", Native_GetTimeRemaining);
    CreateNative("GetTimeElapsed",   Native_GetTimeElapsed);
    CreateNative("GetGameID",        Native_GetGameID);
    CreateNative("XMenu",            Native_XMenu);
    CreateNative("XMenuQuick",       Native_XMenuQuick);
    CreateNative("XMenuBox",         Native_XMenuBox);

    ghForwardMatchStart       = CreateGlobalForward("OnMatchStart",       ET_Event);
    ghForwardMatchEnd         = CreateGlobalForward("OnMatchEnd",         ET_Event, Param_Cell);
    ghForwardGamestateChanged = CreateGlobalForward("OnGamestateChanged", ET_Event, Param_Cell, Param_Cell);
    ghForwardFeedback         = CreateGlobalForward("OnClientFeedback",   ET_Event, Param_String, Param_String, Param_String, Param_String);

    RegPluginLibrary("xms");
}

public void OnPluginStart()
{
    CreateConVar("xms_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    BuildPath(Path_SM, gsConfigPath,   PLATFORM_MAX_PATH, "configs/xms.cfg");
    BuildPath(Path_SM, gsFeedbackPath, PLATFORM_MAX_PATH, "logs/xms_feedback.log");
    LoadTranslations("common.phrases.txt");
    LoadTranslations("xms.phrases.txt");
    LoadTranslations("xms_menu.phrases.txt");
    RegisterColors();

    gmTeams   = CreateTrie();
    ghKeysHud = CreateHudSynchronizer();
    ghTimeHud = CreateHudSynchronizer();
    ghVoteHud = CreateHudSynchronizer();

    ghCookieMusic     = RegClientCookie("xms_endmusic",   "Enable music at the end of each map",       CookieAccess_Public);
    ghCookieSounds    = RegClientCookie("xms_miscsounds", "Enable beeps and other XMS command sounds", CookieAccess_Public);
    ghCookieColors[0] = RegClientCookie("hudcolor_r",     "HUD color red value",                       CookieAccess_Public);
    ghCookieColors[1] = RegClientCookie("hudcolor_g",     "HUD color green value",                     CookieAccess_Public);
    ghCookieColors[2] = RegClientCookie("hudcolor_b",     "HUD color blue value",                      CookieAccess_Public);

    ghConVarTv       = FindConVar("tv_enable");
    ghConVarPausable = FindConVar("sv_pausable");
    ghConVarTeamplay = FindConVar("mp_teamplay");
    ghConVarChattime = FindConVar("mp_chattime");
    ghConVarRestart  = FindConVar("mp_restartgame");
    ghConVarFF       = FindConVar("mp_friendlyfire");
    ghConVarNextmap  = FindConVar("sm_nextmap");
    ghConVarTags     = FindConVar("sv_tags");
    ghConVarTimelimit = FindConVar("mp_timelimit");

    ghConVarRestart.  AddChangeHook(OnGameRestarting);
    ghConVarNextmap.  AddChangeHook(OnNextmapChanged);
    ghConVarTags.     AddChangeHook(OnTagsChanged);
    ghConVarTimelimit.AddChangeHook(OnTimelimitChanged);
    HookEvents();
    AddCommandListener(OnMapChanging, "changelevel");
    AddCommandListener(OnMapChanging, "changelevel_next");

    RegisterMainCommands();
    // Internal use commands:
    RegConsoleCmd("sm_xmenu",      XMenuAction);
    RegConsoleCmd("sm_xmenu_back", XMenuBack);
    RegConsoleCmd("sm_xmenu_next", XMenuNext);

    AddPluginTag();
    LoadConfigValues();

    CreateTimer(0.1, T_KeysHud, _, TIMER_REPEAT);
    CreateTimer(0.1, T_TimeHud, _, TIMER_REPEAT);
    CreateTimer(1.0, T_Voting,  _, TIMER_REPEAT);

    if (giAdFrequency) {
        CreateTimer(float(giAdFrequency), T_Adverts, _, TIMER_REPEAT);
    }

    if (LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }

    #if defined _gameme_hud_included
        if (LibraryExists("gameme_hud")) {
            gbGameME = true;
        }
    #endif
}

void AddPluginTag()
{
    char sTags[128];

    ghConVarTags.GetString(sTags, sizeof(sTags));

    if (StrContains(sTags, "xms") == -1)
    {
        StrCat(sTags, sizeof(sTags), sTags[0] != 0 ? ",xms" : "xms");
        gbModTags = true;
        ghConVarTags.SetString(sTags);
        gbModTags = false;
    }
}

void LoadConfigValues()
{
    gkConfig = new KeyValues("xms");
    gkConfig.ImportFromFile(gsConfigPath);

    // Core settings:
    if (!GetConfigKeys(gsValidModes, sizeof(gsValidModes), "Gamemodes") || !GetConfigString(gsDefaultMode, sizeof(gsDefaultMode), "DefaultMode")) {
        LogError("xms.cfg missing or corrupted!");
    }

    if (GetConfigString(gsServerMsg, sizeof(gsServerMsg), "MenuMessage") == 1) {
        FormatMenuMessage(gsServerMsg, gsServerMsg, sizeof(gsServerMsg));
    }

    GetConfigString(gsDemoPath,    sizeof(gsDemoPath),    "DemoFolder");
    GetConfigString(gsDemoURL,     sizeof(gsDemoURL),     "DemoURL");
    GetConfigString(gsDemoFileExt, sizeof(gsDemoFileExt), "DemoExtension");
    GetConfigString(gsServerName,  sizeof(gsServerName),  "ServerName");
    GetConfigString(gsRetainModes, sizeof(gsRetainModes), "RetainModes");
    GetConfigString(gsStripPrefix, sizeof(gsStripPrefix), "StripPrefix", "Maps");

    giAdFrequency       = GetConfigInt("Frequency", "ServerAds");
    giVoteMinPlayers    = GetConfigInt("VoteMinPlayers");
    giVoteMaxTime       = GetConfigInt("VoteMaxTime");
    giVoteCooldown      = GetConfigInt("VoteCooldown");
    gbAutoVoting        = GetConfigInt("AutoVoting") == 1;
    gbStockMapsIfEmpty  = GetConfigInt("UseStockMapsIfEmpty") == 1;

    // Gamemode settings:
    giSpawnHealth       = GetConfigInt("SpawnHealth",  "Gamemodes", gsMode);
    giSpawnSuit         = GetConfigInt("SpawnSuit",    "Gamemodes", gsMode);
    gbDisableCollisions = GetConfigInt("NoCollisions", "Gamemodes", gsMode) == 1;
    gbUnlimitedAux      = GetConfigInt("UnlimitedAux", "Gamemodes", gsMode) == 1;
    gbDisableProps      = GetConfigInt("DisableProps", "Gamemodes", gsMode) == 1;
    giOvertime          = GetConfigInt("Overtime",     "Gamemodes", gsMode) == 1;
    giShowKeys          = GetConfigInt("Selfkeys",     "Gamemodes", gsMode);

    // Weapon settings:
    char sWeapons[512],
         sWeapon [16][32],
         sAmmo   [2][6];

    if (GetConfigString(sWeapons, sizeof(sWeapons), "SpawnWeapons", "Gamemodes", gsMode))
    {
        for (int i = 0; i < ExplodeString(sWeapons, ",", sWeapon, 16, 32); i++)
        {
            int pos = SplitString(sWeapon[i], "(", gsSpawnWeapon[i], sizeof(gsSpawnWeapon[]));
            if (pos != -1)
            {
                int pos2 = SplitString(sWeapon[i][pos], "-", sAmmo[0], sizeof(sAmmo[]));
                if (pos2 == -1) {
                    strcopy(sAmmo[0], sizeof(sAmmo[]), sWeapon[i][pos]);
                    sAmmo[0][strlen(sAmmo[0])-1] = 0;
                }
                else {
                    strcopy(sAmmo[1], sizeof(sAmmo[]), sWeapon[i][pos+pos2]);
                    sAmmo[1][strlen(sAmmo[1])-1] = 0;
                }
            }
            else {
                strcopy(gsSpawnWeapon[i], sizeof(gsSpawnWeapon[]), sWeapon[i]);
            }

            for (int z = 0; z < 2; z++) {
                if (!StringToIntEx(sAmmo[z], giSpawnAmmo[i][z])) {
                    giSpawnAmmo[i][z] = -1;
                }
            }
        }
    }
    else {
        gsSpawnWeapon[0] = "default";
    }
}

public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }

    #if defined _gameme_hud_included
        if (StrEqual(sName, "gameme_hud")) {
            gbGameME = true;
        }
    #endif
}

public void OnLibraryRemoved(const char[] sName)
{
    #if defined _gameme_hud_included
        if (StrEqual(sName, "gameme_hud")) {
            gbGameME = false;
        }
    #endif
}

public void OnAllPluginsLoaded()
{
    if (!gbPluginReady) {
        // Restart on first load - avoids issues with SourceTV (etc)
        CreateTimer(1.0, T_RestartMap, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (!LibraryExists("hl2dmfix")) {
        LogError("hl2dmfix is not loaded !");
    }
}

/**************************************************************
 * COMMANDS
 *************************************************************/
void RegisterMainCommands()
{
    RegConsoleCmd("menu",        Cmd_Menu,     "Display the XMS menu");
    RegConsoleCmd("list",        Cmd_MapList,  "View list of available maps");
    RegConsoleCmd("maplist",     Cmd_MapList,  "View list of available maps");
    RegConsoleCmd("run",         Cmd_Run,      "[Vote to] change the current map");
    RegConsoleCmd("runnow",      Cmd_Run,      "[Vote to] change the current map");
    RegConsoleCmd("runnext",     Cmd_Run,      "[Vote to] set the next map");
    RegConsoleCmd("start",       Cmd_Start,    "[Vote to] start a match");
    RegConsoleCmd("cancel",      Cmd_Cancel,   "[Vote to] cancel the match");
    RegConsoleCmd("shuffle",     Cmd_Shuffle,  "[Vote to] shuffle teams");
    RegConsoleCmd("invert",      Cmd_Invert,   "[Vote to] invert the teams");
    RegConsoleCmd("profile",     Cmd_Profile,  "View player's steam profile");
    RegConsoleCmd("showprofile", Cmd_Profile,  "View player's steam profile");
    RegConsoleCmd("model",       Cmd_Model,    "Change player model");
    RegConsoleCmd("hudcolor",    Cmd_HudColor, "Change HUD color");
    RegConsoleCmd("vote",        Cmd_Vote,     "Call a custom yes/no vote");

    RegConsoleCmd("yes",         Cmd_CastVote, "Vote YES");
    RegConsoleCmd("no",          Cmd_CastVote, "Vote NO");
    for (int i = 1; i <= 5; i++) {
        RegConsoleCmd(IntToChar(i), Cmd_CastVote, "Vote for option");
    }

    RegAdminCmd("forcespec", AdminCmd_Forcespec, ADMFLAG_GENERIC, "force a player to spectate");
    RegAdminCmd("allow",     AdminCmd_AllowJoin, ADMFLAG_GENERIC, "allow a player to join the match");

    // Listen for commands (overrides):
    AddCommandListener(ListenCmd_Team,  "jointeam");
    AddCommandListener(ListenCmd_Team,  "spectate");
    AddCommandListener(ListenCmd_Pause, "pause");
    AddCommandListener(ListenCmd_Pause, "unpause");
    AddCommandListener(ListenCmd_Pause, "setpause");
    AddCommandListener(Listen_Basecommands, "timeleft");
    AddCommandListener(Listen_Basecommands, "nextmap");
    AddCommandListener(Listen_Basecommands, "currentmap");
    AddCommandListener(Listen_Basecommands, "ff");
}

// Command: menu
// Open the XMS menu
public Action Cmd_Menu(int iClient, int iArgs)
{
    giClientMenuType[iClient] = 0;
    QueryClientConVar(iClient, "cl_showpluginmessages", ShowMenuIfVisible, iClient);
    return Plugin_Handled;
}

// Command: maplist <mode or "all">
// Display a list of available maps
public Action Cmd_MapList(int iClient, int iArgs)
{
    char sMode[MAX_MODE_LENGTH],
         sMapcycle[PLATFORM_MAX_PATH],
         sMaps[512][MAX_MAP_LENGTH];
    int  iCount;
    bool bAll;

    if (!iArgs) {
        strcopy(sMode, sizeof(sMode), gsMode);
    }
    else
    {
        GetCmdArg(1, sMode, sizeof(sMode));
        bAll = StrEqual(sMode, "all");

        if (!bAll && !IsValidGamemode(sMode))
        {
            MC_ReplyToCommand(iClient, "%t", "xmsc_list_invalid", sMode);
            IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
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
    MC_ReplyToCommand(iClient, "%t", "xmsc_list_modes", gsValidModes);

    return Plugin_Handled;
}


// Command: run[next] <mode>:<map>[,<mode>:<map>,<mode>:<map> ...]
// Change the map and/or gamemode. Now supports multiple choice voting
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
    else if (giVoteStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (giGamestate == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_paused");
    }
    else if (giGamestate == GAME_MATCH) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (giGamestate == GAME_CHANGING) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else {
        bProceed = true;
    }

    if (!bProceed)
    {
        if (iArgs) {
            IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
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
                IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
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
                    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
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

            if (StrEqual(gsMode, sMode) && !bMulti)
            {
                // Fail - same gamemode as current.
                MC_ReplyToCommand(iClient, "%t", "xmsc_run_denymode", sMode);
                IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
                return Plugin_Handled;
            }

            // Detect map:
            if (!(GetConfigString(sMap, sizeof(sMap), "DefaultMap", "Gamemodes", sMode) && IsMapValid(sMap) && !( IsItemDistinctInList(gsMode, gsRetainModes) && IsItemDistinctInList(sMode, gsRetainModes) ) )) {
                strcopy(sMap, sizeof(sMap), gsMap);
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
                    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
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
    if (!bMulti && ( GetRealClientCount() < giVoteMinPlayers || giVoteMinPlayers <= 0 || iClient == 0 ) )
    {
        // No vote required
        strcopy(gsNextMode, sizeof(gsNextMode), sResultMode[0]);
        ghConVarNextmap.SetString(sResultMap[0]);

        if (iVoteType == VOTE_RUN)
        {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_run_now", sResultMode[0], DeprefixMap(sResultMap[0]));

            // Run:
            SetGamestate(GAME_CHANGING);
            CreateTimer(1.0, T_Run, _, TIMER_REPEAT);
        }
        else {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_run_next", sResultMode[0], DeprefixMap(sResultMap[0]));
            gbNextMapChosen = true;
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
        strcopy(sMap, sizeof(sMap), DeprefixMap(gsNextMap));
    }
    else if (iTimer == DELAY_ACTION)
    {
        PrintCenterTextAll("");
        strcopy(gsMode, sizeof(gsMode), gsNextMode);
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

        PrintCenterText(iClient, "%s%T", sPreText, "xms_loading", iClient, gsNextMode, sMap, DELAY_ACTION - iTimer);
        IfCookiePlaySound(ghCookieSounds, iClient, ( DELAY_ACTION - iTimer > 1 ? SOUND_ACTIONPENDING : SOUND_ACTIONCOMPLETE ) );
    }

    iTimer++;

    return Plugin_Continue;
}


// Command: start
// Start a competitive match on supported gamemodes
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
    else if (giVoteStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (!IsModeMatchable(gsMode)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_start_denygamemode", gsMode);
    }
    else if (giGamestate == GAME_MATCH || giGamestate == GAME_MATCHEX || giGamestate == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (giGamestate == GAME_CHANGING || giGamestate == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else if (giGamestate == GAME_OVER || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else
    {
        if (GetRealClientCount(true, false, false) < giVoteMinPlayers || giVoteMinPlayers <= 0 || iClient == 0) {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xms_started");
            Start();
        }
        else {
            CallVoteFor(VOTE_MATCH, iClient, "start match");
        }
        return Plugin_Handled;
    }

    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
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
        IfCookiePlaySoundAll(ghCookieSounds, SOUND_ACTIONCOMPLETE);
        iTimer = 0;

        return Plugin_Stop;
    }

    PrintCenterTextAll("%t", "xms_starting", DELAY_ACTION - iTimer);
    IfCookiePlaySoundAll(ghCookieSounds, SOUND_ACTIONPENDING);
    iTimer++;

    return Plugin_Continue;
}


// Command: cancel
// Cancel an ongoing competitive match
public Action Cmd_Cancel(int iClient, int iArgs)
{
    if (iClient == 0) {
        Cancel();
        return Plugin_Handled;
    }
    else if (giVoteStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (giGamestate == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_paused");
    }
    else if (giGamestate == GAME_DEFAULT || giGamestate == GAME_OVERTIME) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_nomatch");
    }
    else if (giGamestate == GAME_MATCHEX) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_cancel_matchex");
    }
    else if (giGamestate == GAME_CHANGING || giGamestate == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else if (giGamestate == GAME_OVER || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else {
        if (GetRealClientCount() < giVoteMinPlayers || giVoteMinPlayers <= 0)
        {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xms_cancelled");
            Cancel();
        }
        else {
            CallVoteFor(VOTE_MATCH, iClient, "cancel match");
        }
        return Plugin_Handled;
    }

    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
    return Plugin_Handled;
}

void Cancel()
{
    SetGamestate(GAME_DEFAULT);
    Game_Restart();
}


// Admin Command: forcespec <player>
// Force a player to spectate
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

        IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
    }

    return Plugin_Handled;
}


// Admin Command: allow <player>
// Allow a player into an ongoing match
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
                giAllowClient = iTarget;
                FakeClientCommand(iTarget, "join");
                MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_allow_success", sName);
            }
            else {
                MC_ReplyToCommand(iClient, "%t", "xmsc_allow_fail", sName);
                IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
            }
        }
    }

    return Plugin_Handled;
}


// Command: pause
// Pause (or unpause) the match
public Action ListenCmd_Pause(int iClient, const char[] sCommand, int iArgs)
{
    if (!ghConVarPausable.BoolValue) {
        return Plugin_Handled;
    }

    if (iClient == 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i)) {
                giPauseClient = i;
                break;
            }
        }

        if (!giPauseClient) {
            ReplyToCommand(0, "Cannot pause when no players are in the server!");
        }
        else {
            FakeClientCommand(giPauseClient, "pause");
        }

        return Plugin_Handled;
    }

    if (iClient == giPauseClient)
    {
        if (giGamestate == GAME_PAUSED) {
            SetGamestate(GAME_MATCH);
        }
        else {
            SetGamestate(GAME_PAUSED);
        }

        return Plugin_Continue;
    }

    if (!IsClientAdmin(iClient))
    {
        if (IsClientObserver(iClient) && iClient != giPauseClient) {
            MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
            return Plugin_Handled;
        }
    }

    if (giGamestate == GAME_PAUSED) {
        IfCookiePlaySoundAll(ghCookieSounds, SOUND_ACTIONCOMPLETE);
        MC_PrintToChatAllFrom(iClient, false, "%t", "xms_match_resumed");
        SetGamestate(GAME_MATCH);
        return Plugin_Continue;
    }
    else if (giGamestate == GAME_MATCH) {
        IfCookiePlaySoundAll(ghCookieSounds, SOUND_ACTIONCOMPLETE);
        MC_PrintToChatAllFrom(iClient, false, "%t", "xms_match_paused");
        SetGamestate(GAME_PAUSED);
        return Plugin_Continue;
    }
    else if (giGamestate == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_nomatch");
    }
    else if (giGamestate == GAME_MATCHEX) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_cancel_matchex");
    }
    else if (giGamestate == GAME_OVER) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_nomatch");
    }

    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);

    return Plugin_Handled;
}


// Command: model <name>
// Change player model
public Action Cmd_Model(int iClient, int iArgs)
{
    char sName[70];

    if (!iArgs)
    {
        if (giClientMenuType[iClient] == 2) {
            ModelMenu(iClient).Display(iClient, MENU_TIME_FOREVER);
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


// Command: jointeam / spectate
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

    if (giAllowClient == iClient) {
        giAllowClient = 0;
    }
    else if (GetClientTeam(iClient) == iTeam)
    {
        char sName[MAX_TEAM_NAME_LENGTH];

        GetTeamName(iTeam, sName, sizeof(sName));
        MC_PrintToChat(iClient, "%t", "xmsc_teamchange_same", sName);
        IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
    }
    else if (IsGameMatch())
    {
        MC_PrintToChat(iClient, "%t", "xmsc_teamchange_deny");
        IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);

        return Plugin_Handled;
    }
    else if (gbTeamplay && iTeam == TEAM_COMBINE)
    {
        // try to force police model
        ClientCommand(iClient, "cl_playermodel models/police.mdl");
    }

    return Plugin_Continue;
}


// Command: profile <player>
// Display a player's steam profile
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
        IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
    }

    return Plugin_Handled;
}


// Command: hudcolor <rrr> <ggg> <bbb>
// Set color for hud text elements (timeleft, spectator hud, etc)
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
            SetClientCookie(iClient, ghCookieColors[i], sColor[i]);
        }
    }

    return Plugin_Handled;
}


// Command: vote <motion>
// Call a custom yes/no vote
public Action Cmd_Vote(int iClient, int iArgs)
{
    if (!iArgs) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_callvote_usage");
    }
    else if (giVoteStatus) {
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


// Command: [yes/no/1/2/3/4/5]
// Vote on the current motion
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

    if (giVoteStatus != 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_castvote_deny");
    }
    else if (IsClientObserver(iClient) && giVoteType == VOTE_MATCH) {
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
            giClientVote[iClient] = iVote;
            PrintToConsoleAll("%t", "xmsc_castvote", sName, sVote);
        }

        return Plugin_Handled;
    }

    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);

    return Plugin_Handled;
}


// Command: shuffle
// Shuffle teams randomly
public Action Cmd_Shuffle(int iClient, int iArgs)
{
    if (!gbTeamplay) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_noteams");
    }
    else if (iClient == 0)
    {
        ShuffleTeams();
        return Plugin_Handled;
    }
    else if (giVoteStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (giGamestate == GAME_MATCH || giGamestate == GAME_MATCHEX || giGamestate == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (giGamestate == GAME_CHANGING || giGamestate == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else if (giGamestate == GAME_OVER || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else
    {
        if (GetRealClientCount(true, false, false) < giVoteMinPlayers || giVoteMinPlayers <= 0 || iClient == 0) {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_shuffle");
            ShuffleTeams();
        }
        else {
            CallVoteFor(VOTE_SHUFFLE, iClient, "shuffle teams");
        }
        return Plugin_Handled;
    }

    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
    return Plugin_Handled;
}


// Command: invert
// Move all players to the opposite teams
public Action Cmd_Invert(int iClient, int iArgs)
{
    if (!gbTeamplay) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_noteams");
    }
    else if (iClient == 0)
    {
        InvertTeams();
        return Plugin_Handled;
    }
    else if (giVoteStatus) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_deny");
    }
    else if (VoteTimeout(iClient)  && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_vote_timeout", VoteTimeout(iClient));
    }
    else if (IsClientObserver(iClient) && !IsClientAdmin(iClient)) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_spectator");
    }
    else if (giGamestate == GAME_MATCH || giGamestate == GAME_MATCHEX || giGamestate == GAME_PAUSED) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_match");
    }
    else if (giGamestate == GAME_CHANGING || giGamestate == GAME_MATCHWAIT) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_changing");
    }
    else if (giGamestate == GAME_OVER || GetTimeRemaining(false) < 1) {
        MC_ReplyToCommand(iClient, "%t", "xmsc_deny_over");
    }
    else
    {
        if (GetRealClientCount(true, false, false) < giVoteMinPlayers || giVoteMinPlayers <= 0 || iClient == 0) {
            MC_PrintToChatAllFrom(iClient, false, "%t", "xmsc_invert");
            InvertTeams();
        }
        else {
            CallVoteFor(VOTE_INVERT, iClient, "invert teams");
        }
        return Plugin_Handled;
    }

    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
    return Plugin_Handled;
}


// Command: say
// Chat command overrides
public Action OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
    bool bCommand = (StrContains(sArgs, "!") == 0 || StrContains(sArgs, "/") == 0);

    if (iClient == 0)
    {
        // spam be gone
        return Plugin_Handled;
    }
    else if (giGamestate == GAME_PAUSED && !bCommand)
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
    else if (StrEqual(sArgs, "gg", false) && ( giGamestate == GAME_OVER || giGamestate == GAME_CHANGING ) )
    {
        IfCookiePlaySoundAll(ghCookieSounds, SOUND_GG);

        return Plugin_Continue;
    }
    else if (giVoteStatus == 1)
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


// Basecommands overrides
public Action Listen_Basecommands(int iClient, const char[] sCommand, int iArgs)
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
        float fTime  = GetTimeRemaining(giGamestate == GAME_OVER);
        int   iHours = RoundToNearest(fTime) / 3600,
              iSecs  = RoundToNearest(fTime) % 60,
              iMins  = RoundToNearest(fTime) / 60 - (iHours ? (iHours * 60) : 0);

        if (giGamestate != GAME_CHANGING)
        {
            if (giGamestate == GAME_OVER)
            {
                if (bBroadcast) {
                    MC_PrintToChatAll("%t", "xmsc_timeleft_over", iSecs);
                }
                else {
                    MC_PrintToChat(iClient, "%t", "xmsc_timeleft_over", iSecs);
                }
            }
            else if (ghConVarTimelimit.IntValue)
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
        if (bBroadcast) {
            MC_PrintToChatAll("%t", "xmsc_nextmap", gsNextMode, DeprefixMap(gsNextMap));
        }
        else {
            MC_PrintToChat(iClient, "%t", "xmsc_nextmap", gsNextMode, DeprefixMap(gsNextMap));
        }
    }
    else if (StrEqual(sCommand, "currentmap"))
    {
        if (bBroadcast) {
            MC_PrintToChatAll("%t", "xmsc_currentmap", gsMode, DeprefixMap(gsMap));
        }
        else {
            MC_PrintToChat(iClient, "%t", "xmsc_currentmap", gsMode, DeprefixMap(gsMap));
        }
    }
    else if (StrEqual(sCommand, "ff"))
    {
        if (gbTeamplay)
        {
            if (bBroadcast) {
                MC_PrintToChatAll("%t", "xmsc_ff", ghConVarFF.BoolValue ? "enabled" : "disabled");
            }
            else {
                MC_PrintToChat(iClient, "%t", "xmsc_ff", ghConVarFF.BoolValue ? "enabled" : "disabled");
            }
        }
    }
}

/**************************************************************
 * CLIENTS
 *************************************************************/
public void OnClientConnected(int iClient)
{
    if (!IsClientSourceTV(iClient)) {
        TryForceModel(iClient);
    }
}

public void OnClientPutInServer(int iClient)
{
    if (giGamestate == GAME_PAUSED)
    {
        giPauseClient = iClient;
        CreateTimer(0.1, T_RePause, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }

    if (giGamestate != GAME_MATCH && giGamestate != GAME_MATCHEX && giGamestate != GAME_MATCHWAIT)
    {
        char sName[MAX_NAME_LENGTH];
        GetClientName(iClient, sName, sizeof(sName));
        MC_PrintToChatAll("%t", "xms_join", sName);
    }

    if (!IsFakeClient(iClient))
    {
        CreateTimer(1.0, T_AnnouncePlugin, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

        // play connect sound
        if (!(giGamestate == GAME_MATCH || giGamestate == GAME_MATCHEX || giGamestate == GAME_MATCHWAIT)) {
            IfCookiePlaySoundAll(ghCookieSounds, SOUND_CONNECT);
        }

        // cancel sound fade in case of early map change
        ClientCommand(iClient, "soundfade 0 0 0 0");
    }

    if (!IsClientSourceTV(iClient))
    {
        // instantly join spec before we determine the correct team
        giAllowClient = iClient;
        gbClientKill[iClient] = true;
        FakeClientCommandEx(iClient, "jointeam %i", TEAM_SPECTATORS);
    }
}

public void OnClientCookiesCached(int iClient)
{
    if (GetClientCookieInt(iClient, ghCookieMusic) != 0) {
        return;
    }

    // Set default values
    SetClientCookie(iClient, ghCookieMusic,     "1");
    SetClientCookie(iClient, ghCookieSounds,    "1");
    SetClientCookie(iClient, ghCookieColors[0], "255");
    SetClientCookie(iClient, ghCookieColors[1], "177");
    SetClientCookie(iClient, ghCookieColors[2], "0");
}

void GetClientColors(int iClient, int iColors[3])
{
    for (int i = 0; i < 3; i++) {
        iColors[i] = clamp(GetClientCookieInt(iClient, ghCookieColors[i]), 0, 255);
    }
}

public void OnClientPostAdminCheck(int iClient)
{
    if (IsFakeClient(iClient)) {
        return;
    }

    giClientMenuType[iClient] = 0;
    CreateTimer(1.1, T_AttemptInitMenu, iClient, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.1, T_Welcome,         iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int iClient)
{
    if (!IsFakeClient(iClient))
    {
        if (GetRealClientCount(IsGameMatch()) == 1 && giGamestate != GAME_CHANGING) {
            // Last player has disconnected, revert to defaults
            LoadDefaults();
        }
        else if (gbClientInit[iClient] && !IsGameMatch()) {
            IfCookiePlaySoundAll(ghCookieSounds, SOUND_DISCONNECT);
        }
    }

    gbClientInit[iClient] = false;
    giClientMenuType[iClient] = 0;
    giClientVoteTick[iClient] = 0;
}

public void OnClientDisconnect_Post(int iClient)
{
    if (iClient == giPauseClient || GetRealClientCount(false) == 0) {
        giPauseClient = 0;
    }
}

/**************************************************************
 * MAP MANAGEMENT
 *************************************************************/
public Action T_RestartMap(Handle hTimer)
{
    SetGamemode(gsDefaultMode);
    ghConVarNextmap.SetString(gsMap);
    ServerCommand("changelevel_next");
    gbPluginReady = true;
}

public Action OnLevelInit(const char[] sMap, char sEntities[2097152])
{
    char sKeys[4096],
         sEntity[2][2048][512];

    if (!strlen(sEntities) || !GetConfigKeys(sKeys, sizeof(sKeys), "Gamemodes", gsNextMode, "ReplaceEntities")) {
        return Plugin_Continue;
    }

    for (int i = 0; i <= ExplodeString(sKeys, ",", sEntity[0], 2048, 512); i++)
    {
        if (GetConfigString(sEntity[1][i], 512, sEntity[0][i], "Gamemodes", gsNextMode, "ReplaceEntities") == 1) {
            ReplaceString(sEntities, sizeof(sEntities), sEntity[0][i], sEntity[1][i], false);
        }
    }

    return Plugin_Changed;
}

public void OnMapStart()
{
    char sModeDesc[32];

    if (!gbPluginReady) {
        return;
    }

    GetCurrentMap(gsMap, sizeof(gsMap));
    strcopy(gsNextMode, sizeof(gsNextMode), gsMode);

    strcopy(sModeDesc, sizeof(sModeDesc), gsMode);
    if(GetConfigString(gsModeName, sizeof(gsModeName), "Name", "Gamemodes", gsMode) == 1) {
        Format(sModeDesc, sizeof(sModeDesc), "%s (%s)", sModeDesc, gsModeName);
    }
    else {
        gsModeName[0] = '\0';
    }
    Steam_SetGameDescription(sModeDesc);

    PrepareSound(SOUND_GG);
    PrepareSound(SOUND_VOTECALLED);
    PrepareSound(SOUND_VOTEFAILED);
    PrepareSound(SOUND_VOTESUCCESS);
    for (int i = 0; i < 6; i++) {
        PrepareSound(gsMusicPath[i]);
    }

    LoadConfigValues();
    GenerateGameID();
    SetGamestate(GAME_DEFAULT);
    SetGamemode(gsMode);

    gfPretime = GetGameTime() - 1.0;
    giVoteStatus = 0;
    gbNextMapChosen = false;

    if (giOvertime == 1) {
        CreateOverTimer();
    }

    if (gbDisableProps) {
        RequestFrame(ClearProps);
    }

    CreateTimer(0.1, T_CheckPlayerStates, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void GenerateGameID()
{
    FormatTime(gsGameId, sizeof(gsGameId), "%y%m%d%H%M");
    Format(gsGameId, sizeof(gsGameId), "%s-%s", gsGameId, gsMap);
}

public Action OnMapChanging(int iClient, const char[] sCommand, int iArgs)
{
    if (gbPluginReady && iClient == 0 && (iArgs || StrEqual(sCommand, "changelevel_next")) )
    {
        SetGamestate(GAME_CHANGING);
        SetGamemode(gsNextMode);
    }
}

public void OnMapEnd()
{
    gbTeamplay = ghConVarTeamplay.BoolValue;
    giOvertime = 0;
    ghOvertimer = INVALID_HANDLE;
}

bool GetMapByAbbrev(char[] sOutput, int iLen, const char[] sAbbrev)
{
    return view_as<bool>(GetConfigString(sOutput, iLen, sAbbrev, "Maps", "Abbreviations") > 0);
}

char DeprefixMap(const char[] sMap)
{
    char sPrefix[16],
         sResult[MAX_MAP_LENGTH];
    int  iPos = SplitString(sMap, "_", sPrefix, sizeof(sPrefix));

    StrCat(sPrefix, sizeof(sPrefix), "_");

    if (iPos && IsItemDistinctInList(sPrefix, gsStripPrefix)) {
        strcopy(sResult, sizeof(sResult), sMap[iPos]);
    }
    else {
        strcopy(sResult, sizeof(sResult), sMap);
    }

    return sResult;
}

int GetMapsArray(char[][] sArray, int iLen1, int iLen2, const char[] sMapcycle = "", const char[] sMustBeginWith = "", const char[] sMustContain = "", bool bStopIfExactMatch = true, bool bStripPrefixes = false, char[][] sArray2 = NULL_STRING)
{
    int  iHits;
    bool bExact;

    // search maps directory
    if (!strlen(sMapcycle))
    {
        char             sFile[2][256];
        DirectoryListing hDir = OpenDirectory("maps");
        FileType         iType;

        while (hDir.GetNext(sFile[0], sizeof(sFile[]), iType))
        {
            int iBsp = StrContains(sFile[0], ".bsp");

            if (iBsp == -1 || StrContains(sFile[0][iBsp + 1], ".") != -1 || iType != FileType_File) {
                continue;
            }

            sFile[0][iBsp] = '\0';

            if (bStripPrefixes) {
                strcopy(sFile[1], sizeof(sFile[]), DeprefixMap(sFile[0]));
            }

            if (strlen(sMustBeginWith) && StrContains(bStripPrefixes ? sFile[1] : sFile[0], sMustBeginWith, false) != 0) {
                continue;
            }

            if (strlen(sMustContain))
            {
                if (StrContains(sFile[0], sMustContain, false) == -1) {
                    continue;
                }

                if (StrEqual(sFile[0], sMustContain, false) || StrEqual(sFile[1], sMustContain, false))
                {
                    bExact = true;
                    if (bStopIfExactMatch)
                    {
                        strcopy(sArray[0], iLen2, sFile[view_as<int>(bStripPrefixes)]);

                        if (bStripPrefixes) {
                            strcopy(sArray2[0], iLen2, sFile[0]);
                        }

                        break;
                    }
                }
            }

            iHits++;

            if (iHits < iLen1)
            {
                strcopy(sArray[iHits - 1], iLen2, sFile[view_as<int>(bStripPrefixes)]);

                if (bStripPrefixes) {
                    strcopy(sArray2[iHits - 1], iLen2, sFile[0]);
                }
            }
        }

        hDir.Close();
    }

    // search mapcyclefile
    else
    {
        char sPath[PLATFORM_MAX_PATH],
             sMap [2][MAX_MAP_LENGTH];
        File hFile;

        Format(sPath, sizeof(sPath), "cfg/%s", sMapcycle);

        if (!FileExists(sPath, true)) {
            LogError("Mapcyclefile `%s` is invalid!", sMapcycle);
            return 0;
        }

        hFile = OpenFile(sPath, "r");

        while (!hFile.EndOfFile() && hFile.ReadLine(sMap[0], sizeof(sMap[])))
        {
            if (sMap[0][0] == ';' || !IsCharAlpha(sMap[0][0])) {
                continue;
            }

            for (int i = 0; i < strlen(sMap[0]); i++)
            {
                if (IsCharSpace(sMap[0][i])) {
                    sMap[0][i] = '\0';
                    break;
                }
            }

            if (!IsMapValid(sMap[0])) {
                LogError("Map `%s` in Mapcyclefile `%s` is invalid!", sMap, sPath);
                continue;
            }

            if (bStripPrefixes) {
                strcopy(sMap[1], sizeof(sMap[]), DeprefixMap(sMap[0]));
            }

            if (strlen(sMustBeginWith) && StrContains(bStripPrefixes ? sMap[1] : sMap[0], sMustBeginWith, false) != 0) {
                continue;
            }

            if (strlen(sMustContain))
            {
                if (StrContains(sMap[0], sMustContain, false) == -1) {
                    continue;
                }

                if (StrEqual(sMap[0], sMustContain, false) || StrEqual(sMap[1], sMustContain, false))
                {
                    bExact = true;
                    if (bStopIfExactMatch)
                    {
                        strcopy(sArray[0], iLen2, sMap[view_as<int>(bStripPrefixes)]);

                        if (bStripPrefixes) {
                            strcopy(sArray2[0], iLen2, sMap[0]);
                        }

                        break;
                    }
                }
            }

            iHits++;

            if (iHits < iLen1)
            {
                strcopy(sArray[iHits - 1], iLen2, sMap[view_as<int>(bStripPrefixes)]);

                if (bStripPrefixes) {
                    strcopy(sArray2[iHits - 1], iLen2, sMap[0]);
                }
            }
        }

        hFile.Close();
    }

    if (bExact && bStopIfExactMatch) {
        return 1;
    }

    return iHits;
}

/**************************************************************
 * MODE MANAGEMENT
 *************************************************************/
int GetModeForMap(char[] sOutput, int iLen, const char[] sMap)
{
    if (!GetConfigString(sOutput, iLen, sMap, "Maps", "DefaultModes"))
    {
        char sPrefix[16];

        SplitString(sMap, "_", sPrefix, sizeof(sPrefix));
        StrCat(sPrefix, sizeof(sPrefix), "_*");

        if (!GetConfigString(sOutput, iLen, sPrefix, "Maps", "DefaultModes"))
        {
            if (!strlen(gsRetainModes)) {
                return -1;
            }

            strcopy(sOutput, iLen, gsRetainModes);
            if (!strlen(gsMode) || !IsItemDistinctInList(gsMode, sOutput))
            {
                if (StrContains(sOutput, ",")) {
                    SplitString(sOutput, ",", sOutput, iLen);
                    return 0;
                }
            }

            strcopy(sOutput, iLen, gsMode);
            return 0;
        }
    }
    return 1;
}

int GetRandomMode(char[] sOutput, int iLen, bool bExcludeCurrent)
{
    char sModes[32][MAX_MODE_LENGTH];
    bool bFound;
    int  iCount = ExplodeString(gsValidModes, ",", sModes, 32, MAX_MODE_LENGTH),
         iRan;

    if (!iCount || (iCount == 1 && bExcludeCurrent)) {
        return 0;
    }

    do {
        iRan = Math_GetRandomInt(0, iCount);
        if (strlen(sModes[iRan]))
        {
            if (!bExcludeCurrent || !StrEqual(sModes[iRan], gsMode)) {
                bFound = true;
            }
        }
    }
    while (!bFound && iCount > 1);

    strcopy(sOutput, iLen, sModes[iRan]);
    return 1;
}

bool GetModeFullName(char[] sBuffer, int iLen, const char[] sMode)
{
    char sName[64];

    if (GetConfigString(sName, sizeof(sName), "Name", "Gamemodes", sMode) == 1)
    {
        strcopy(sBuffer, iLen, sName);
        return true;
    }

    return false;
}

bool GetModeMapcycle(char[] sBuffer, int iLen, const char[] sMode)
{
    char sMapcycle[PLATFORM_MAX_PATH];

    if (GetConfigString(sMapcycle, sizeof(sMapcycle), "Mapcycle", "Gamemodes", sMode))
    {
        strcopy(sBuffer, iLen, sMapcycle);
        return true;
    }

    return false;
}

void SetGamemode(const char[] sMode)
{
    char sCommand[MAX_BUFFER_LENGTH];

    strcopy(gsNextMode, sizeof(gsNextMode), sMode);
    strcopy(gsMode, sizeof(gsMode), sMode);

    if (GetConfigString(sCommand, sizeof(sCommand), "Command", "Gamemodes", gsMode)) {
        ServerCommand(sCommand);
    }
}

void SetMapcycle()
{
    char sMapcycle[PLATFORM_MAX_PATH];

    if (!GetModeMapcycle(sMapcycle, sizeof(sMapcycle), gsMode) || (gbStockMapsIfEmpty && GetRealClientCount(false, false) <= 1 && StrEqual(gsDefaultMode, gsMode)) ) {
        Format(sMapcycle, sizeof(sMapcycle), "mapcycle_default.txt");
    }

    ServerCommand("mapcyclefile %s", sMapcycle);
}

/**************************************************************
 * TEAM MANAGEMENT
 *************************************************************/
int GetOptimalTeam()
{
    int iTeam = TEAM_REBELS;

    if (gbTeamplay)
    {
        int iCount[2];

        iCount[0] = GetTeamClientCount(TEAM_REBELS);
        iCount[1] = GetTeamClientCount(TEAM_COMBINE);

        iTeam = (
            iCount[0] > iCount[1] ? TEAM_COMBINE
            : iCount[1] > iCount[0] ? TEAM_REBELS
            : Math_GetRandomInt(0,1) ? TEAM_REBELS : TEAM_COMBINE
        );
    }

    return iTeam;
}

void ForceTeamSwitch(int iClient, int iTeam)
{
    giAllowClient = iClient;
    gbClientKill[iClient] = IsPlayerAlive(iClient);
    FakeClientCommandEx(iClient, "jointeam %i", iTeam);
}

void TryForceModel(int iClient)
{
    if (gbTeamplay) {
        ClientCommand(iClient, "cl_playermodel models/police.mdl");
    }
    else {
        ClientCommand(iClient, "cl_playermodel models/humans/group03/%s_%02i.mdl", (Math_GetRandomInt(0, 1) ? "male" : "female"), Math_GetRandomInt(1, 7));
    }
}

void InvertTeams(bool bBroadcast=true)
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsClientObserver(iClient)) {
            continue;
        }

        int iTeam = GetClientTeam(iClient) == TEAM_REBELS ? TEAM_COMBINE
                                            : TEAM_REBELS;

        if (IsGameOver() && !IsFakeClient(iClient))
        {
            char sId[32];

            GetClientAuthId(iClient, AuthId_Engine, sId, sizeof(sId));
            gmTeams.SetValue(sId, iTeam);
        }
        else
        {
            ForceTeamSwitch(iClient, iTeam);

            if (bBroadcast)
            {
                char sName[MAX_TEAM_NAME_LENGTH];

                GetTeamName(iTeam, sName, sizeof(sName));
                MC_PrintToChat(iClient, "%t", "xms_team_assigned", sName);
            }
        }
    }
}

void ShuffleTeams(bool bBroadcast=true)
{
    int iCount = GetRealClientCount(true, true, false),
        iClient,
        iTeam [MAXPLAYERS + 1],
        iTeams[2];

    do
    {
        do
        {
            iClient = Math_GetRandomInt(1, MaxClients);

            if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsClientObserver(iClient)) {
                iTeam[iClient] = -1;
            }
            else
            {
                iTeam[iClient] = (
                    iTeams[0] > iTeams[1] ? TEAM_COMBINE
                    : iTeams[1] > iTeams[0] ? TEAM_REBELS
                    : Math_GetRandomInt(TEAM_COMBINE, TEAM_REBELS)
                );

                iTeams[0] += view_as<int>(iTeam[iClient] == TEAM_REBELS);
                iTeams[1] += view_as<int>(iTeam[iClient] == TEAM_COMBINE);
                iCount--;

                if (IsGameOver() && !IsFakeClient(iClient))
                {
                    char sId[32];

                    GetClientAuthId(iClient, AuthId_Engine, sId, sizeof(sId));
                    gmTeams.SetValue(sId, iTeam[iClient]);
                }
                else
                {
                    if (iTeam[iClient] != GetClientTeam(iClient)) {
                        ForceTeamSwitch(iClient, iTeam[iClient]);
                    }

                    if (bBroadcast) {
                        char sName[MAX_TEAM_NAME_LENGTH];
                        GetTeamName(iTeam[iClient], sName, sizeof(sName));
                        MC_PrintToChat(iClient, "%t", "xms_team_assigned", sName);
                    }
                }
            }
        }
        while (iTeam[iClient] == 0);
    }
    while (iCount);
}

public Action T_CheckPlayerStates(Handle hTimer)
{
    static int iWasTeam[MAXPLAYERS + 1] = -1;

    if (giGamestate == GAME_CHANGING) {
        return Plugin_Continue;
    }

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        int iTeam;

        if (!IsClientInGame(iClient))
        {
            if (iWasTeam[iClient] > TEAM_SPECTATORS && IsGameMatch())
            {
                // Participant in match disconnected
                if (giGamestate != GAME_PAUSED)
                {
                    ServerCommand("pause");
                    MC_PrintToChatAll("%t", "xms_auto_pause");
                    IfCookiePlaySoundAll(ghCookieSounds, SOUND_COMMANDFAIL);
                }
            }

            iWasTeam[iClient] = -1;
            continue;
        }

        if (IsClientSourceTV(iClient)) {
            continue;
        }

        iTeam = GetClientTeam(iClient);

        if (iWasTeam[iClient] == -1)
        {
            // New player. Auto assign a team.
            CreateTimer(1.0, T_TeamAutoAssign, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        }
        else if (iTeam != iWasTeam[iClient])
        {
            if (giAllowClient != iClient && ( IsGameMatch() || giGamestate == GAME_OVER || ( iTeam == TEAM_SPECTATORS && !IsClientObserver(iClient) ) || ( iTeam != TEAM_SPECTATORS && IsClientObserver(iClient) ) ) )
            {
                // Client has changed teams during match, or is a bugged spectator
                // Usually caused by changing playermodel
                ForceTeamSwitch(iClient, iWasTeam[iClient]);
                continue;
            }
        }

        iWasTeam[iClient] = iTeam;

        if (gbClientInit[iClient] && !IsGameOver()) {
            gmTeams.SetValue(UnbufferedAuthId(iClient), iTeam);
        }
    }

    return Plugin_Continue;
}

public Action T_TeamAutoAssign(Handle hTimer, int iClient)
{
    int iTeam;

    if (!IsClientInGame(iClient)) {
        return Plugin_Stop;
    }

    if (giGamestate == GAME_PAUSED || IsGameOver()) {
        return Plugin_Continue;
    }

    gmTeams.GetValue(UnbufferedAuthId(iClient), iTeam);

    if (IsGameMatch()) {
        MC_PrintToChat(iClient, "%t", "xmsc_teamchange_deny");
    }
    else if (iTeam)
    {
        if (iTeam == TEAM_SPECTATORS) {
            MC_PrintToChat(iClient, "%t", "xms_auto_spectate");
        }
        else {
            ForceTeamSwitch(iClient, iTeam);
        }
    }
    else {
        ForceTeamSwitch(iClient, GetOptimalTeam());
    }

    gbClientInit[iClient] = true;
    return Plugin_Stop;
}

/**************************************************************
 * GAME ROUND STUFF
 *************************************************************/
void OnMatchPre()
{
    char sStatus[MAX_BUFFER_LENGTH],
         sCommand[MAX_BUFFER_LENGTH];

    ServerCommandEx(sStatus, sizeof(sStatus), "status");
    PrintToConsoleAll("\n\n\n%s\n\n\n", sStatus);

    if (GetConfigString(sCommand, sizeof(sCommand), "PreMatchCommand")) {
        ServerCommand(sCommand);
    }
}

void OnMatchStart()
{
    Forward_OnMatchStart();
}

void OnMatchCancelled()
{
    ServerCommand("exec server");
    SetGamemode(gsMode);
    Forward_OnMatchEnd(false);
}

void OnRoundEnd(bool bMatch)
{
    gfEndtime = GetGameTime();

    if (bMatch)
    {
        char sCommand[MAX_BUFFER_LENGTH];

        if (GetConfigString(sCommand, sizeof(sCommand), "PostMatchCommand")) {
            ServerCommand(sCommand);
        }

        Forward_OnMatchEnd(true);
    }

    if (giOvertime == 2)
    {
        MC_PrintToChatAll("%t", "xms_overtime_draw");
        giOvertime = 1;
    }

    if (giGamestate != GAME_CHANGING)
    {
        if (gbAutoVoting && !gbNextMapChosen && giVoteStatus != 1)
        {
            if (ghConVarChattime.IntValue <= giVoteMaxTime) {
                LogError("\"mp_chattime\" must be more than xms.cfg:\"VoteMaxTime\" !");
            }
            else {
                CallRandomMapVote();
            }
        }
        else if (strlen(gsNextMap)) {
            MC_PrintToChatAll("%t", "xms_nextmap_announce", gsNextMode, DeprefixMap(gsNextMap), ghConVarChattime.IntValue);
        }
    }

    PlayRoundEndMusic();
}

void ClearProps()
{
    for (int iEnt = MaxClients; iEnt < GetMaxEntities(); iEnt++)
    {
        if (!IsValidEntity(iEnt)) {
            continue;
        }

        char sClass[64];
        GetEntityClassname(iEnt, sClass, sizeof(sClass));

        if (StrContains(sClass, "prop_physics") == 0) {
            AcceptEntityInput(iEnt, "kill");
        }
    }
}

void SetNoCollide(int iClient)
{
    SetEntData(iClient, OFFS_COLLISIONGROUP, 2, 4, true);
}

void Game_Restart(int iTime = 1)
{
    ghConVarRestart.SetInt(iTime);
    PrintCenterTextAll("");
}

void SetGamestate(int iState)
{
    if (iState == giGamestate) {
        return;
    }

    // pre actions
    switch(iState)
    {
        case GAME_DEFAULT:
        {
            ServerCommand("sv_allow_point_servercommand always");
            if (IsGameMatch()) {
                OnMatchCancelled();
            }

            if (gbRecording) {
                StopRecord(true);
            }

            if (giOvertime == 1) {
                CreateOverTimer(0.0);
            }
        }

        case GAME_MATCHWAIT:
        {
            OnMatchPre();

            if (giOvertime == 2) {
                giOvertime = 1;
            }

            if (!gbRecording) {
                GenerateGameID();
                CreateTimer(1.1, T_StartRecord, _, TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        case GAME_MATCH:
        {
            if (giGamestate != GAME_PAUSED) {
                OnMatchStart();
                CreateOverTimer(2.9);
            }

        }

        case GAME_OVER:
        {
            OnRoundEnd(IsGameMatch());
            ServerCommand("sv_allow_point_servercommand disallow");

            if (gbRecording) {
                CreateTimer(10.0, T_StopRecord, false, TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        case GAME_CHANGING:
        {
            if (giGamestate == GAME_OVER) {
                CreateTimer(0.1, T_SoundFadeTrigger, _, TIMER_FLAG_NO_MAPCHANGE);

                if (gbRecording) {
                    StopRecord(false);
                }
            }
            else if (gbRecording) {
                StopRecord(true);
            }

            //if (gbTeamplay) {
            //    InvertTeams();
            //}
        }
    }

    giGamestate = iState;
    Forward_OnGamestateChanged(iState);

    // post actions
    if (giGamestate == GAME_CHANGING && gbTeamplay) {
        InvertTeams();
    }
}

void LoadDefaults()
{
    SetGamemode(gsDefaultMode);
    SetMapcycle();
    ghConVarNextmap.SetString("");
    ServerCommand("changelevel_next");
}

public Action T_RePause(Handle hTimer)
{
    static int i;

    if (giPauseClient > 0 && IsClientConnected(giPauseClient)) {
        FakeClientCommand(giPauseClient, "pause");
    }

    i++;

    if (i == 2)
    {
        giPauseClient = 0;
        i = 0;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public Action T_RemoveWeapons(Handle hTimer, int iClient)
{
    Client_RemoveAllWeapons(iClient);
}

public Action T_SetWeapons(Handle hTimer, int iClient)
{
    Client_RemoveAllWeapons(iClient);

    for (int i = 0; i < 16; i++)
    {
        if (!strlen(gsSpawnWeapon[i])) {
            break;
        }

        if (giSpawnAmmo[i][0] == -1 && giSpawnAmmo[i][1] == -1) {
            Client_GiveWeapon(iClient, gsSpawnWeapon[i], false);
        }
        else if (StrEqual(gsSpawnWeapon[i], "weapon_rpg") || StrEqual(gsSpawnWeapon[i], "weapon_frag")) {
            Client_GiveWeaponAndAmmo(iClient, gsSpawnWeapon[i], false, giSpawnAmmo[i][0], giSpawnAmmo[i][1], -1, -1);
        }
        else if (StrEqual(gsSpawnWeapon[i], "weapon_slam")) {
            Client_GiveWeaponAndAmmo(iClient, gsSpawnWeapon[i], false, -1, giSpawnAmmo[i][0], -1, -1);
        }
        else {
            Client_GiveWeaponAndAmmo(iClient, gsSpawnWeapon[i], false, giSpawnAmmo[i][0], giSpawnAmmo[i][1], 0, 0);
        }
    }
}

/**************************************************************
 * EVENTS
 *************************************************************/
void HookEvents()
{
    HookEvent("player_changename",     Event_GameMessage, EventHookMode_Pre);
    HookEvent("player_connect_client", Event_GameMessage, EventHookMode_Pre);
    HookEvent("player_team",           Event_GameMessage, EventHookMode_Pre);
    HookEvent("player_connect",        Event_GameMessage, EventHookMode_Pre);
    HookEvent("player_disconnect",     Event_GameMessage, EventHookMode_Pre);
    HookEvent("round_start",           Event_RoundStart,  EventHookMode_Post);
    HookEvent("player_death",          Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_spawn",          Event_PlayerSpawn, EventHookMode_Post);

    HookUserMessage(GetUserMessageId("TextMsg"),  UserMsg_TextMsg,  true);
    HookUserMessage(GetUserMessageId("VGUIMenu"), UserMsg_VGUIMenu, false);
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAngles[3], int &iWeapon)
{
    if (gbUnlimitedAux)
    {
        int iBits = GetEntProp(iClient, Prop_Send, "m_bitsActiveDevices");

        if (iBits & BITS_SPRINT) {
            SetEntPropFloat(iClient, Prop_Data, "m_flSuitPowerLoad", 0.0);
            SetEntProp(iClient, Prop_Send, "m_bitsActiveDevices", iBits & ~BITS_SPRINT);
        }
    }

    return Plugin_Changed;
}

public Action Event_PlayerSpawn(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));

    if (IsFakeClient(iClient)) {
        return Plugin_Continue;
    }

    if (giGamestate == GAME_MATCHWAIT)
    {
        SetEntityMoveType(iClient, MOVETYPE_NONE);
        CreateTimer(0.1, T_RemoveWeapons, iClient);
        return Plugin_Continue;
    }

    if (giSpawnHealth != -1) {
        SetEntProp(iClient, Prop_Data, "m_iHealth", giSpawnHealth > 0 ? giSpawnHealth : 1);
    }
    if (giSpawnSuit != -1) {
        SetEntProp(iClient, Prop_Data, "m_ArmorValue", giSpawnSuit > 0 ? giSpawnSuit : 0);
    }
    if (gbDisableCollisions) {
        RequestFrame(SetNoCollide, iClient);
    }
    if (!StrEqual(gsSpawnWeapon[0], "default")) {
        CreateTimer(0.1, T_SetWeapons, iClient);
    }

    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));

    if (gbClientKill[iClient])
    {
        int iRagdoll = GetEntPropEnt(iClient, Prop_Send, "m_hRagdoll");

        if (iRagdoll >= 0 && IsValidEntity(iRagdoll)) {
            // remove ragdoll if plugin has killed the player
            RemoveEdict(iRagdoll);
        }

        gbClientKill[iClient] = false;
    }

    return Plugin_Continue;
}

public Action Event_GameMessage(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));

    if (iClient && IsClientInGame(iClient))
    {
        if (!IsGameMatch() || GetClientTeam(iClient) != TEAM_SPECTATORS)
        {
            char sName[MAX_NAME_LENGTH];
            GetClientName(iClient, sName, sizeof(sName));

            if (StrEqual(sEvent, "player_disconnect"))
            {
                char sReason[32];
                GetEventString(hEvent, "reason", sReason, sizeof(sReason));
                MC_PrintToChatAll("%t", IsGameMatch() ? "xms_disconnect_match" : "xms_disconnect", sName, sReason);
            }
            else if (StrEqual(sEvent, "player_changename"))
            {
                char sNew[MAX_NAME_LENGTH];
                GetEventString(hEvent, "newname", sNew, sizeof(sNew));
                MC_PrintToChatAll("%t", "xms_changename", sName, sNew);
            }
        }
    }

    // block other messages
    hEvent.BroadcastDisabled = true;

    return Plugin_Continue;
}

public Action Event_RoundStart(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
    gfPretime = GetGameTime();

    if (giGamestate == GAME_MATCHWAIT)
    {
        for (int i = MaxClients; i < GetMaxEntities(); i++)
        {
            if (IsValidEntity(i) && Phys_IsPhysicsObject(i)) {
                Phys_EnableMotion(i, false); // Lock props on matchwait
            }
        }
    }
}

public Action UserMsg_TextMsg(UserMsg msg, Handle hMsg, const int[] iPlayers, int iNumPlayers, bool bReliable, bool bInit)
{
    char sMsg[70];

    BfReadString(hMsg, sMsg, sizeof(sMsg), true);
    if (StrContains(sMsg, "[SM] Time remaining for map") != -1 || StrContains(sMsg, "[SM] No timelimit for map") != -1 || StrContains(sMsg, "[SM] This is the last round!!") != -1)
    {
        // block game chat spam
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public Action UserMsg_VGUIMenu(UserMsg msg, Handle hMsg, const int[] iPlayers, int iNumPlayers, bool bReliable, bool bInit)
{
    char sMsg[10];

    BfReadString(hMsg, sMsg, sizeof(sMsg));
    if (StrEqual(sMsg, "scores")) {
        RequestFrame(SetGamestate, GAME_OVER);
    }

    return Plugin_Continue;
}

public void OnGameRestarting(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    if (StrEqual(sNewValue, "15")) {
        // trigger for some CTF maps
        Game_End();
    }
}

public void OnTagsChanged(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    if (!gbModTags) {
        AddPluginTag();
    }
}

public void OnTimelimitChanged(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    if (giOvertime == 1) {
        CreateOverTimer();
    }
}

public void OnNextmapChanged(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    strcopy(gsNextMap, sizeof(gsNextMap), sNewValue);
}

/**************************************************************
 * ANNOUNCEMENT TIMERS
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
        MC_PrintToChat(iClient, "%T", "xms_welcome", iClient, gsServerName);
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

/**************************************************************
 * ENDMUSIC
 *************************************************************/
void PlayRoundEndMusic()
{
    static int iRan;

    float fTime = ghConVarChattime.IntValue - 4.5;

    iRan = Math_GetRandomIntNot(0, 5, iRan);

    for (int iClient = 1; iClient <= MaxClients; iClient++) {
        if (IsCookieEnabled(ghCookieMusic, iClient)) {
            QueryClientConVar(iClient, "snd_musicvolume", PlayMusicAtClientVolume, iRan);
        }
    }
    CreateTimer(fTime < 5 ? 0.1 : fTime, T_SoundFadeTrigger, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void PlayMusicAtClientVolume(QueryCookie cookie, int iClient, ConVarQueryResult result, const char[] sName, const char[] sValue, int iPos)
{
    float fVolume = StringToFloat(sValue);

    if (fVolume < 0 || fVolume > 1) {
        fVolume = 0.5;
    }

    EmitSoundToClient(iClient, gsMusicPath[iPos], _, _, _, _, fVolume);
}

public Action T_SoundFadeTrigger(Handle hTimer)
{
    ClientCommandAll("soundfade 100 1 0 5");
    SetGamestate(GAME_CHANGING);
}

/**************************************************************
 * MISC SOUNDS
 *************************************************************/
void PrepareSound(const char[] sName)
{
    char sPath[PLATFORM_MAX_PATH];

    Format(sPath, sizeof(sPath), "sound/%s", sName);
    PrecacheSound(sName);
    AddFileToDownloadsTable(sPath);
}

void IfCookiePlaySound(Handle hCookie, int iClient, const char[] sFile, bool bUnset=true)
{
    if (IsCookieEnabled(hCookie, iClient, bUnset)) {
        ClientCommand(iClient, "playgamesound %s", sFile);
    }
}

void IfCookiePlaySoundAll(Handle hCookie, const char[] sFile, bool bUnset=true)
{
    for (int iClient = 1; iClient <= MaxClients; iClient++) {
        IfCookiePlaySound(hCookie, iClient, sFile, bUnset);
    }
}

/**************************************************************
 * VOTING
 *************************************************************/
public Action T_Voting(Handle hTimer)
{
    static int  iSeconds;
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

    if (!giVoteStatus)
    {
        if (iSeconds)
        {
            for (int i = 0; i < 5; i++) {
                sMotion[i] = "";
                gsVoteMotion[i] = "";
            }

            iSeconds = 0;
        }

        return Plugin_Continue;
    }

    if (!iSeconds)
    {
        // Prepare vote motion(s)
        bMultiChoice = view_as<bool>(strlen(gsVoteMotion[1]));

        if (giVoteType == VOTE_RUN || giVoteType == VOTE_RUNNEXT || giVoteType == VOTE_RUNNEXT_AUTO)
        {
            bool bCurrentModeOnly = true;
            int  iDisplayLen      = 32,
                 iCount,
                 iPos[5];

            for (int i = 0; i < 5; i++)
            {
                if (strlen(gsVoteMotion[i]))
                {
                    iPos[i] = SplitString(gsVoteMotion[i], ":", sMotion[i], sizeof(sMotion[]));

                    if (!StrEqual(gsMode, sMotion[i])) {
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
                else if (!StrEqual(gsMode, sMotion[i])) {
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

        if (giVoteType != VOTE_MATCH || !IsClientObserver(iClient))
        {
            if (giClientVote[iClient] != -1) {
                iTally[giClientVote[iClient]]++;
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

        iPercent[i] = RoundToNearest(iTally[i] ? iTally[i] / iVotes * 100.0 : 0.0);
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
    if ((iLead > -1 && !bContested) || iSeconds >= giVoteMaxTime)
    {
        if (bMultiChoice && bDraw)
        {
            if (!iVotes && !IsGameOver()) {
                // Nobody voted. Fail.
                iLead = -1;
            }
            else {
                // Draw. Pick winner at random from the first 2 equal choices
                int iWinner[2] = -1;

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

        giVoteStatus = iLead > -1 ? 2 : -1;
    }

    // Format HUD :
    if (giVoteType == VOTE_RUN || giVoteType == VOTE_RUNNEXT) {
        Format(sHud, sizeof(sHud), "!run%s ", giVoteType == VOTE_RUNNEXT ? "Next" : "");
    }

    if (!bMultiChoice) {
        Format(sHud, sizeof(sHud), "%s%s (%i)\n▪ %s: %i (%i%%%%)\n▪ %s:  %i (%i%%%%)",
            sHud, sMotion[0], giVoteMaxTime - iSeconds,
            iTally[1] >= iTally[0] ? "YES" : "yes", iTally[1], iPercent[1],
            iTally[0] > iTally[1]  ? "NO"  : "no" , iTally[0], iPercent[0]
        );
    }
    else
    {
        Format(sHud, sizeof(sHud), "%s(%i)", sHud, giVoteMaxTime - iSeconds);
        for (int i = 0; i < 5; i++)
        {
            if (strlen(sMotion[i])) {
                Format(sHud, sizeof(sHud), "%s\n▪ %s %s - %i (%i%%%%)", sHud, BigNumber(i+1), iLead == i ? Char_Uppify(sMotion[i]) : sMotion[i], iTally[i], iPercent[i]);
            }
        }
    }

    /*
    Format(sHud, sizeof(sHud), "%s\n▪ abstain: %i", sHud, iAbstains);

    if (giVoteStatus == 1) {
        Format(sHud, sizeof(sHud), "%s\n%is remaining..", sHud, giVoteMaxTime - iSeconds);
        for (int i = 5; i <= giVoteMaxTime; i += 5) {
            if (giVoteMaxTime - i >= iSeconds) {
                StrCat(sHud, sizeof(sHud), ".");
            }
        }
    }
    */

    // Take action :
    switch(giVoteStatus)
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

            switch(giVoteType)
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
                    char sMode[MAX_MODE_LENGTH],
                         sMap [MAX_MAP_LENGTH];
                    int i = ( bMultiChoice ? iLead : 0 );

                    strcopy(sMap, sizeof(sMap), gsVoteMotion[i][SplitString(gsVoteMotion[i], ":", sMode, sizeof(sMode))]);
                    strcopy(gsNextMode, sizeof(gsNextMode), sMode);
                    ghConVarNextmap.SetString(sMap);

                    if (giVoteType != VOTE_RUN)
                    {
                        if (!bDraw) {
                            MC_PrintToChatAll("%t", "xmsc_run_next", sMode, DeprefixMap(sMap));
                        }

                        gbNextMapChosen = true;
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

        if (giVoteType == VOTE_RUNNEXT_AUTO) {
            Format(sHud2, sizeof(sHud2), "%T %s", "xms_autovote", iClient, sHud);
        }
        else {
            Format(sHud2, sizeof(sHud2), "%T - %s", "xms_vote", iClient, sHud);
        }

        if (giVoteStatus != 1)
        {
            if (!AreClientCookiesCached(iClient) || GetClientCookieInt(iClient, ghCookieSounds) == 1 && giVoteType != VOTE_RUNNEXT_AUTO) {
                ClientCommand(iClient, "playgamesound %s", giVoteStatus == -1 ? SOUND_VOTEFAILED : SOUND_VOTESUCCESS);
            }
            else if (!bMultiChoice) {
                MC_PrintToChat(iClient, "%t", giVoteStatus == -1 ? "xms_vote_fail" : "xms_vote_success");
            }
        }
        else {
            int iColor[3];

            GetClientColors(iClient, iColor);
            SetHudTextParams(0.01, 0.11, 1.01, iColor[0], iColor[1], iColor[2], 255, view_as<int>(giVoteMaxTime - iSeconds <= 5), 0.0, 0.0, 0.0);
        }

        ShowSyncHudText(iClient, ghVoteHud, sHud2);
    }

    if (giVoteStatus != 1) {
        giVoteStatus = 0;
    }

    iSeconds++;
    return Plugin_Continue;
}

void CallVote(int iType, int iCaller)
{
    bool bMulti = (strlen(gsVoteMotion[1]) > 0);

    giClientVoteTick[iCaller] = GetGameTickCount();
    giVoteStatus = 1;
    giVoteType   = iType;

    if (!bMulti) {
        giClientVote[iCaller] = 1;
    }

    if (iCaller != 0) {
        MC_PrintToChatAllFrom(iCaller, false, "%t", "xmsc_callvote");
    }

    IfCookiePlaySoundAll(ghCookieSounds, SOUND_VOTECALLED);

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if ( (iClient != iCaller || bMulti) && (!IsClientObserver(iClient) || iType != VOTE_MATCH) ) {
            giClientVote[iClient] = -1;
            VotingMenu(iClient).Display(iClient, MENU_TIME_FOREVER);
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
            strcopy(sModes[i], sizeof(sModes[]), gsMode);
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
                while (!strlen(sMaps[iRan]) || StrEqual(sMaps[iRan], gsMap));

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
}

int VoteTimeout(int iClient)
{
    int iTime;

    if (GetRealClientCount(true, false, true) > giVoteMinPlayers) {
        iTime = ( giVoteCooldown * Tickrate() + giClientVoteTick[iClient] - GetGameTickCount() ) / Tickrate();
    }

    if (iTime < 0) {
        return 0;
    }

    return iTime;
}

/**************************************************************
 * OTHER HUD ELEMENTS
 *************************************************************/
public Action T_KeysHud(Handle hTimer)
{
    if (giGamestate == GAME_OVER || giGamestate == GAME_CHANGING || giGamestate == GAME_PAUSED) {
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

        if (GetClientButtons(iClient) & IN_SCORE || (!IsClientObserver(iClient) && !giShowKeys)) {
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

            if (giShowKeys != 2) {
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

        ShowSyncHudText(iClient, ghKeysHud, sHud);
    }

    return Plugin_Continue;
}

public Action T_TimeHud(Handle hTimer)
{
    static int iTimer;

    bool bRed = (giOvertime == 2);
    char sHud[48];

    if (giGamestate == GAME_MATCHWAIT || giGamestate == GAME_CHANGING || giGamestate == GAME_PAUSED)
    {
        Format(sHud, sizeof(sHud), ". . %s%s%s", iTimer >= 20 ? ". " : "", iTimer >= 15 ? ". " : "", iTimer >= 10 ? "." : "");
        iTimer++;
        if (iTimer >= 25) {
            iTimer = 0;
        }
    }

    else if (giGamestate != GAME_OVER && ghConVarTimelimit.BoolValue)
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

        if (giGamestate == GAME_OVER) {
            Format(sHud2, sizeof(sHud2), "%T", "xms_hud_gameover", iClient);
        }
        else if (giGamestate == GAME_MATCHEX || giGamestate == GAME_OVERTIME) {
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

            ShowSyncHudText(iClient, ghTimeHud, sHud2);
        }
    }
}

/**************************************************************
 * OVERTIME
 *************************************************************/
void CreateOverTimer(float fDelay=0.0)
{
    if (ghOvertimer != INVALID_HANDLE) {
        KillTimer(ghOvertimer);
        ghOvertimer = INVALID_HANDLE;
    }

    ghOvertimer = CreateTimer(GetTimeRemaining(false) - 0.1 + fDelay, T_PreOvertime, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action T_PreOvertime(Handle hTimer)
{
    if (GetRealClientCount(true, true, false) > 1)
    {
        if (gbTeamplay) {
            if (GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE) == 0 && GetTeamClientCount(TEAM_REBELS) && GetTeamClientCount(TEAM_COMBINE)) {
                StartOvertime();
            }
        }
        else if (!GetTopPlayer(false)) {
            StartOvertime();
        }
    }

    ghOvertimer = INVALID_HANDLE;
}

void StartOvertime()
{
    giOvertime = 2;
    ghConVarTimelimit.IntValue += OVERTIME_TIME;

    if (gbTeamplay || GetRealClientCount(true, false, false) == 2) {
        MC_PrintToChatAll("%t", "xms_overtime_start1", gbTeamplay ? "team" : "player");
    }
    else {
        MC_PrintToChatAll("%t", "xms_overtime_start2");
    }

    CreateTimer(0.1, T_Overtime, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    if (giGamestate == GAME_MATCH) {
        SetGamestate(GAME_MATCHEX);
    }
    else {
        SetGamestate(GAME_OVERTIME);
    }
}

public Action T_Overtime(Handle hTimer)
{
    int  iResult;
    char sName[MAX_NAME_LENGTH];

    if (giOvertime != 2) {
        return Plugin_Stop;
    }

    if (gbTeamplay)
    {
        iResult = GetTeamScore(TEAM_REBELS) - GetTeamScore(TEAM_COMBINE);

        if (iResult == 0) {
            return Plugin_Continue;
        }

        GetTeamName(iResult < 0 ? TEAM_COMBINE : TEAM_REBELS, sName, sizeof(sName));
        MC_PrintToChatAll("%t", "xms_overtime_teamwin", sName);
    }
    else
    {
        iResult = GetTopPlayer(false);

        if (!iResult) {
            return Plugin_Continue;
        }

        GetClientName(iResult, sName, sizeof(sName));

        MC_PrintToChatAll("%t", "xms_overtime_win", sName);
    }

    Game_End();
    giOvertime = 1;

    return Plugin_Stop;
}

/**************************************************************
 * SOURCETV
 *************************************************************/
public Action T_StartRecord(Handle hTimer)
{
    StartRecord();
}

void StartRecord()
{
    if (!ghConVarTv.BoolValue) {
        LogError("SourceTV is not active!");
    }

    if (!gbRecording) {
        ServerCommand("tv_name \"%s - %s\";tv_record %s/incomplete/%s", gsServerName, gsGameId, gsDemoPath, gsGameId);
        gbRecording = true;
    }
}

public Action T_StopRecord(Handle hTimer, bool bEarly)
{
    StopRecord(bEarly);
}

void StopRecord(bool bDiscard)
{
    char sPath[2][PLATFORM_MAX_PATH];

    if (!gbRecording) {
        return;
    }

    Format(sPath[0], sizeof(sPath[]), "%s/incomplete/%s.dem", gsDemoPath, gsGameId);
    Format(sPath[1], sizeof(sPath[]), "%s/%s.dem", gsDemoPath, gsGameId);

    ServerCommand("tv_stoprecord");
    gbRecording = false;

    if (!bDiscard)
    {
        GenerateDemoTxt(sPath[1]);
        RenameFile(sPath[1], sPath[0], true);
        if (strlen(gsDemoURL)) {
            MC_PrintToChatAll("%t", "xms_announcedemo", gsDemoURL, gsGameId, gsDemoFileExt);
        }
    }
    else {
        DeleteFile(sPath[0], true);
    }
}

void GenerateDemoTxt(const char[] sPath)
{
    static char sHost[16];
    static int  iPort;

    char sPath2 [PLATFORM_MAX_PATH],
         sTime  [32],
         sTitle [256],
         sPlayers[2][2048];
    bool bDuel = GetRealClientCount(true, false, false) == 2;
    File hFile;

    if (!strlen(sHost)) {
        FindConVar("ip").GetString(sHost, sizeof(sHost));
        iPort = FindConVar("hostport").IntValue;
    }

    Format(sPath2, PLATFORM_MAX_PATH, "%s.txt", sPath);
    FormatTime(sTime, sizeof(sTime), "%d %b %Y");

    if (gbTeamplay) {
        Format(sPlayers[0], sizeof(sPlayers[]), "THE COMBINE [Score: %i]:\n", GetTeamScore(TEAM_COMBINE));
        Format(sPlayers[1], sizeof(sPlayers[]), "REBEL FORCES [Score: %i]:\n", GetTeamScore(TEAM_REBELS));
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        int z;

        if (!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i) || IsClientObserver(i)) {
            continue;
        }

        if (gbTeamplay) {
            z = GetClientTeam(i) - 2;
        }

        Format(sPlayers[z], sizeof(sPlayers[]), "%s\"%N\" %s [%i kills, %i deaths]\n", sPlayers[z], i, UnbufferedAuthId(i), GetClientFrags(i), GetClientDeaths(i));

        if (bDuel) {
            Format(sTitle, sizeof(sTitle), "%s%N%s", sTitle, i, !strlen(sTitle) ? " vs " : "");
        }
    }

    if (gbTeamplay) {
        Format(sTitle, sizeof(sTitle), "%s %iv%i - %s - %s", gsMode, GetTeamClientCount(TEAM_REBELS), GetTeamClientCount(TEAM_COMBINE), gsMap, sTime);
    }
    else if (bDuel) {
        Format(sTitle, sizeof(sTitle), "%s 1v1 (%s) - %s - %s", gsMode, sTitle, gsMap, sTime);
    }
    else {
        Format(sTitle, sizeof(sTitle), "%s ffa - %s - %s", gsMode, gsMap, sTime);
    }

    hFile = OpenFile(sPath2, "w", true);
    hFile.WriteLine(sTitle);
    hFile.WriteLine("");
    hFile.WriteLine(sPlayers[0]);

    if (gbTeamplay) {
        hFile.WriteLine(sPlayers[1]);
    }

    hFile.WriteLine("Server: \"%s\" [%s:%i]", gsServerName, sHost, iPort);
    hFile.WriteLine("Version: %i [XMS v%s]", GameVersion(), PLUGIN_VERSION);
    hFile.Close();
}

/**************************************************************
 * MENUS
 *************************************************************/
public void ShowMenuIfVisible(QueryCookie cookie, int iClient, ConVarQueryResult result, char[] sCvarName, char[] sCvarValue)
{
    if (!StringToInt(sCvarValue))
    {
        if (giClientMenuType[iClient] == 0)
        {
            MC_PrintToChat(iClient, "%t", "xmenu_fail");
            IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);

            // keep trying in the background
            CreateTimer(2.0, T_AttemptInitMenu, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            giClientMenuType[iClient] = 1;
        }
    }
    else
    {
        MC_PrintToChat(iClient, "%t", "xmenu_announce");
        giClientMenuType[iClient] = 2;
        FakeClientCommand(iClient, "sm_xmenu 0");
    }
}

public Action T_AttemptInitMenu(Handle hTimer, int iClient)
{
    if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient) || giClientMenuType[iClient] == 2) {
        return Plugin_Stop;
    }

    QueryClientConVar(iClient, "cl_showpluginmessages", ShowMenuIfVisible, iClient);
    return Plugin_Continue;
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
    gmMenu[iClient].GetValue("count", iCount);
    return iCount;
}

void XMenuDisplay(StringMap mMenu, int iClient, int iPage=-1)
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

    mMenu.GetValue(sPage, kMenu);
    mMenu.GetValue("type", iType);

    mMenu.SetValue("current", iPage);
    kMenu.SetNum("time", 99999);
    kMenu.SetColor("color", iColor[0], iColor[1], iColor[2], 255);

    CreateDialog(iClient, kMenu, iType);
    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_MENUACTION);
}

public Action XMenuBack(int iClient, int iArgs)
{
    int iPage = XMenuCurrentPage(gmMenu[iClient]) - 1;

    if (iPage >= 1) {
        XMenuDisplay(gmMenu[iClient], iClient, iPage);
    }
    return Plugin_Handled;
}

public Action XMenuNext(int iClient, int iArgs)
{
    int iPage = XMenuCurrentPage(gmMenu[iClient]) + 1;

    if (iPage <= XMenuPageCount(iClient)){
        XMenuDisplay(gmMenu[iClient], iClient, iPage);
    }
    return Plugin_Handled;
}

// Menu logic:
public Action XMenuAction(int iClient, int iArgs)
{
    int  iMenuId;
    char sParam[3][256];

    if (iClient == 0) {
        return Plugin_Handled;
    }

    if (iArgs)
    {
        iMenuId = GetCmdArgInt(1);

        for (int i = 2; i < iArgs + 1; i++)
        {
            if (i >= 5) {
                break;
            }

            GetCmdArg(i, sParam[i - 2], sizeof(sParam[]));
        }
    }

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
                if(strlen(gsModeName)) {
                    Format(sModeName, sizeof(sModeName), "(%s)", gsModeName);
                }
                Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_0", iClient, gsMode, sModeName, gsMap, gsServerName, GameVersion(), PLUGIN_VERSION, Tickrate(), bLan ? "local" : "dedicated", gsServerMsg);

                gmMenu[iClient] = XMenuQuick(iClient, 7, false, false, "sm_xmenu 0", sTitle, sMessage, !IsGameMatch() ? "xmenu0_team" : "xmenu0_pause;pause",
                  "xmenu0_vote", "xmenu0_players", "xmenu0_settings", "xmenu0_switch", "xmenu0_admin", "xmenu0_report;report"
                );

                XMenuDisplay(gmMenu[iClient], iClient);
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
            }
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

                    if (!gbTeamplay && i == TEAM_COMBINE) {
                        continue;
                    }

                    GetTeamName(i, sOption, sizeof(sOption));
                    Format(sOption, sizeof(sOption), "%s;%i", sOption, i);

                    dOptions.WriteString(sOption);
                }

                gmMenu[iClient] = XMenu(iClient, true, false, "sm_xmenu 1", sTitle, sMessage, dOptions);
                XMenuDisplay(gmMenu[iClient], iClient);
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

                Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_2", iClient, giVoteMinPlayers);

                if (!IsGameMatch())
                {
                    Format(sOptions[0], sizeof(sOptions[]), "xmenu2_map;selectmap");
                    Format(sOptions[1], sizeof(sOptions[]), "xmenu2_mode;selectmode");
                    Format(sOptions[2], sizeof(sOptions[]), "xmenu2_start;start");

                    if (gbTeamplay) {
                        Format(sOptions[3], sizeof(sOptions[]), "xmenu2_shuffle;shuffle");
                        Format(sOptions[4], sizeof(sOptions[]), "xmenu2_invert;invert");
                    }
                }
                else {
                    Format(sOptions[0], sizeof(sOptions[]), "xmenu2_cancel;cancel");
                }

                gmMenu[iClient] = XMenuQuick(iClient, 4, true, false, "sm_xmenu 2", "xmenutitle_2", sMessage, sOptions[0], sOptions[1], sOptions[2], sOptions[3], sOptions[4]);
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
                    strcopy(sMode, sizeof(sMode), gsMode);
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
                            if (IsItemDistinctInList(gsMode, gsRetainModes) && IsItemDistinctInList(sMode, gsRetainModes)) {
                                Format(sOption, sizeof(sOption), "%T;%s", "xmenu2_map_keep", iClient, gsMap);
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

                    gmMenu[iClient] = XMenu(iClient, true, true, sCommandBase, sTitle, sMessage, dOptions);
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

                    gmMenu[iClient] = XMenu(iClient, true, false, sCommandBase, sTitle, sMessage, dOptions);
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

                    gmMenu[iClient] = XMenu(iClient, true, false, sCommandBase, sTitle, sMessage, dOptions);
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

                    ExplodeString(gsValidModes, ",", sModes, 64, MAX_MODE_LENGTH, false);

                    for (int i = 0; i < 64; i++)
                    {
                        if (!strlen(sModes[i])) {
                            break;
                        }

                        if (!StrEqual(sModes[i], gsMode))
                        {
                            char sModeName[32];

                            if(GetModeFullName(sModeName, sizeof(sModeName), sModes[i])) {
                                Format(sModeName, sizeof(sModeName), "(%s)", sModeName);
                            }
                            Format(sOption, sizeof(sOption), "%s %s;%s", sModes[i], sModeName, sModes[i]);
                            dOptions.WriteString(sOption);
                        }
                    }

                    Format(sMessage, sizeof(sMessage), "%T", "xmenumsg_2_mode", iClient, gsMode);
                    Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_2_mode", iClient);

                    gmMenu[iClient] = XMenu(iClient, true, false, "sm_xmenu 2 selectmode", sTitle, sMessage, dOptions);
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
                    gmMenu[iClient] = XMenuQuick(iClient, 3, true, false, "sm_xmenu 2 start", "xmenutitle_2_start", "xmenumsg_2_start", GetRealClientCount(true, false, false) > 1 ? "xmenu2_start_confirm" : "xmenu2_start_deny");
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

            XMenuDisplay(gmMenu[iClient], iClient);
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

                if (gbGameME && gameME_StatsInitialised())
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

                gmMenu[iClient] = XMenu(iClient, true, false, "sm_xmenu 3", sTitle, sMessage, dOptions);
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

                if (gbGameME && gameME_StatsInitialised() && gameME_IsPlayerRanked(iTarget))
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

                gmMenu[iClient] = XMenu(iClient, true, false, sCommandBase, sTitle, sMessage, dOptions);
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
                        XMenuDisplay(gmMenu[iClient], iClient);
                    }
                }

                IfCookiePlaySound(ghCookieSounds, iClient, SOUND_ACTIVATED);
                return Plugin_Handled;
            }

            XMenuDisplay(gmMenu[iClient], iClient);
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

                Format(sOption, sizeof(sOption), "xmenu4_music%s", GetClientCookieInt(iClient, ghCookieMusic) == 1 ? "1" : "0");
                Format(sOption, sizeof(sOption), "%T;music", sOption, iClient);
                dOptions.WriteString(sOption);

                Format(sOption, sizeof(sOption), "xmenu4_sound%s", GetClientCookieInt(iClient, ghCookieSounds) == 1 ? "1" : "0");
                Format(sOption, sizeof(sOption), "%T;sound", sOption, iClient);
                dOptions.WriteString(sOption);

                gmMenu[iClient] = XMenu(iClient, true, false, "sm_xmenu 4", sTitle, sMessage, dOptions);
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

                    gmMenu[iClient] = XMenu(iClient, true, true, "sm_xmenu 4 model", sTitle, sMessage, dOptions);
                }
                else
                {
                    ClientCommand(iClient, "cl_playermodel %s", sParam[1]);
                    FakeClientCommand(iClient, "sm_xmenu 4");
                    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_ACTIVATED);
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

                    gmMenu[iClient] = XMenu(iClient, true, false, "sm_xmenu 4 fov", sTitle, sMessage, dOptions);
                }
                else
                {
                    FakeClientCommand(iClient, "fov %s", sParam[1]);
                    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_ACTIVATED);

                    FakeClientCommand(iClient, "sm_xmenu 4");
                    return Plugin_Handled;
                }
            }

            else if (StrEqual(sParam[0], "hudcolor"))
            {
                if (iArgs == 2)
                {
                    gmMenu[iClient] =
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
                    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_ACTIVATED);

                    FakeClientCommand(iClient, "sm_xmenu 4");
                    return Plugin_Handled;
                }
            }

            else if (StrEqual(sParam[0], "music"))
            {
                if (IsCookieEnabled(ghCookieMusic, iClient)) {
                    SetClientCookie(iClient, ghCookieMusic, "-1");
                    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_DEACTIVATED);
                }
                else {
                    SetClientCookie(iClient, ghCookieMusic, "1");
                    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_ACTIVATED);
                }

                FakeClientCommand(iClient, "sm_xmenu 4");
                return Plugin_Handled;
            }

            else if (StrEqual(sParam[0], "sound"))
            {
                if (IsCookieEnabled(ghCookieSounds, iClient)) {
                    SetClientCookie(iClient, ghCookieSounds, "-1");
                    ClientCommand(iClient, "playgamesound %s", SOUND_DEACTIVATED);
                }
                else {
                    SetClientCookie(iClient, ghCookieSounds, "1");
                    ClientCommand(iClient, "playgamesound %s", SOUND_ACTIVATED);
                }

                FakeClientCommand(iClient, "sm_xmenu 4");
                return Plugin_Handled;
            }

            XMenuDisplay(gmMenu[iClient], iClient);
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

                gmMenu[iClient] = XMenu(iClient, true, false, "sm_xmenu 5", sTitle, sMessage, dOptions);
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
                    IfCookiePlaySound(ghCookieSounds, iClient, SOUND_COMMANDFAIL);
                    FakeClientCommand(iClient, "sm_xmenu 0");
                    return Plugin_Handled;
                }
            }

            XMenuDisplay(gmMenu[iClient], iClient);
        }

        case 6: // Management
        {
            if (!IsClientAdmin(iClient)) {
                return Plugin_Handled;
            }

            if (iArgs == 1)
            {
                gmMenu[iClient] = XMenuQuick(iClient, 3, true, false, "sm_xmenu 6", "xmenutitle_6", "xmenumsg_6", "xmenu6_specall;specall",
                  "xmenu6_reloadadmins;reloadadmins", "xmenu6_reloadplugin;reloadxms", "xmenu6_restart;restart", "xmenu6_feedback;feedback");
            }
            else if (StrEqual(sParam[0], "restart"))
            {
                ServerCommand("_restart");
                return Plugin_Handled;
            }
            else if (StrEqual(sParam[0], "feedback"))
            {
                if (FileExists(gsFeedbackPath))
                {
                    char sFeedback[MAX_BUFFER_LENGTH],
                         sTitle[64];


                    File hFile = OpenFile(gsFeedbackPath, "r");

                    hFile.ReadString(sFeedback, sizeof(sFeedback));
                    hFile.Close();

                    Format(sTitle, sizeof(sTitle), "%T", "xmenutitle_6_feedback", iClient);

                    gmMenu[iClient] = XMenuBox("", sTitle, sFeedback, DialogType_Text);
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

                IfCookiePlaySound(ghCookieSounds, iClient, SOUND_ACTIVATED);
            }

            XMenuDisplay(gmMenu[iClient], iClient);
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

                gmMenu[iClient] = XMenuBox("sm_xmenu 7", sTitle, sMessage);
                XMenuDisplay(gmMenu[iClient], iClient);
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
                    File hFile = OpenFile(gsFeedbackPath, "a");

                    GetClientName(iClient, sName, sizeof(sName));
                    GetClientAuthId(iClient, AuthId_Engine, sId, sizeof(sId));
                    Format(sInfo, sizeof(sInfo), "%s --- %s %s says:", gsGameId, sName, sId);

                    hFile.WriteLine("");
                    hFile.WriteLine(sInfo);
                    hFile.WriteLine(sFeedback[1]);
                    hFile.Close();

                    Forward_OnClientFeedback(sFeedback[2], sName, sId, gsGameId);
                    strcopy(sPrevious, sizeof(sPrevious), sFeedback);
                }
            }

            FakeClientCommand(iClient, "sm_xmenu 0");
        }
    }

    return Plugin_Handled;
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
                int  iCut = 0;
                int  iNewlPos = StrContains(sArray[iRow][i], "\\n");

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
            StrCat(sOutput, iMaxlen, "\n  ");
            StrCat(sOutput, iMaxlen, sArray[iRow]);
        }

        return strlen(sOutput);
    }
    else {
        return strcopy(sOutput, iMaxlen, sMsg);
    }
}

// Haven't found a way to refresh my XMenu on clients (change what is on their screen without them having to select an option)
// So below still using the built in menu type, for voting and !model command
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

        FakeClientCommand(iClient, "sm_xmenu 0");
    }
}

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
            IfCookiePlaySound(ghCookieSounds, iClient, SOUND_ACTIVATED);
        }

        FakeClientCommand(iClient, "sm_xmenu 0");
    }
}

// END