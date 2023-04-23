#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION  "1.3"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xfix.upd"

public Plugin myinfo = {
    name              = "xFix - HL2DM Fixes & Enhancements",
    version           = PLUGIN_VERSION,
    description       = "Various fixes and enhancements for HL2DM servers",
    author            = "harper, toizy, v952, sidezz",
    url               = PLUGIN_URL
};

/**************************************************************
 * INCLUDES
 *************************************************************/
#include <sourcemod>
#include <vphysics>
#include <sdkhooks>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <updater>

#define REQUIRE_PLUGIN
#include <jhl2dm>

/**************************************************************
 * GLOBAL VARS
 *************************************************************/
enum struct _gConVar
{
    ConVar sv_gravity;
    ConVar mp_falldamage;
    ConVar mp_teamplay;
    ConVar sv_tags;
}
_gConVar gConVar;

bool gbRoundEnd;
bool gbMOTDExists;
bool gbTeamplay;
bool gbModtags;

StringMap gmKills;
StringMap gmDeaths;
StringMap gmTeams;

/**************************************************************/

public APLRes AskPluginLoad2(Handle hPlugin, bool bLate, char[] sError, int iLen)
{
    RegPluginLibrary("xfix");
    return APLRes_Success;
}

public void OnPluginStart()
{
    gmKills  = CreateTrie();
    gmDeaths = CreateTrie();
    gmTeams  = CreateTrie();

    gConVar.mp_falldamage = FindConVar("mp_falldamage");
    gConVar.mp_teamplay   = FindConVar("mp_teamplay");
    gConVar.sv_gravity    = FindConVar("sv_gravity");
    gConVar.sv_tags       = FindConVar("sv_tags");

    gConVar.sv_gravity.AddChangeHook(OnGravityChanged);
    gConVar.sv_tags.AddChangeHook(OnTagsChanged);

    HookEvent("server_cvar", Event_GameMessage, EventHookMode_Pre);
    HookUserMessage(GetUserMessageId("TextMsg"),  UserMsg_TextMsg,  true);
    HookUserMessage(GetUserMessageId("VGUIMenu"), UserMsg_VGUIMenu, false);
    AddNormalSoundHook(OnNormalSound);

    if (LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }

    CreateConVar("xfix_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    AddPluginTag();
}

public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnTagsChanged(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    if (!gbModtags) {
        AddPluginTag();
    }
}

void AddPluginTag()
{
    char sTags[128];

    gConVar.sv_tags.GetString(sTags, sizeof(sTags));

    if (StrContains(sTags, "xFix") == -1)
    {
        StrCat(sTags, sizeof(sTags), sTags[0] != 0 ? ",xFix" : "xFix");
        gbModtags = true;
        gConVar.sv_tags.SetString(sTags);
        gbModtags = false;
    }
}

public Action OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
    char sArgs2[MAX_SAY_LENGTH];
    bool bLoop;

    if (StrContains(sArgs, "#.#") == 0)
    {
        // Backwards compatibility for the old #.# command prefix
        sArgs2[0] = '!';
        strcopy(sArgs2[1], sizeof(sArgs2) - 1, sArgs[IsCharSpace(sArgs[3]) ? 4 : 3]);
        bLoop = true;
    }
    else {
        strcopy(sArgs2, sizeof(sArgs2), sArgs);
    }

    if (StrContains(sArgs2, "!") == 0 || StrContains(sArgs2, "/") == 0)
    {
        // remove case sensitivity for *ALL* commands
        for (int i = 1; i <= strlen(sArgs2); i++)
        {
            if (IsCharUpper(sArgs2[i]))
            {
                String_ToLower(sArgs2, sArgs2, sizeof(sArgs2));
                bLoop = true;
                break;
            }
        }
    }

    else if (!gbTeamplay && StrEqual(sCommand, "say_team", false))
    {
        // disable team chat in dm
        bLoop = true;
    }

    if (bLoop) {
        FakeClientCommandEx(iClient, "say %s", sArgs2);
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public Action UserMsg_TextMsg(UserMsg msg, Handle hMsg, const int[] iPlayers, int iNumPlayers, bool bReliable, bool bInit)
{
    char sMessage[70];

    BfReadString(hMsg, sMessage, sizeof(sMessage), true);
    if (StrContains(sMessage, "more seconds before trying to switch") != -1 || StrContains(sMessage, "Your player model is") != -1 || StrContains(sMessage, "You are on team") != -1)
    {
        // block game chat spam
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public void OnMapStart()
{
    gbMOTDExists = (FileExists("cfg/motd.txt") && FileSize("cfg/motd.txt") > 2);
    gbTeamplay   = gConVar.mp_teamplay.BoolValue;
    gbRoundEnd   = false;

    CreateTimer(0.1, T_CheckPlayerStates, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
    gmKills.Clear();
    gmDeaths.Clear();
}

public Action Event_RoundStart(Handle hEvent, const char[] sEvent, bool bDontBroadcast)
{
    gmTeams.Clear();
    gmKills.Clear();
    gmDeaths.Clear();

    return Plugin_Continue;
}

public void OnClientPutInServer(int iClient)
{
    if (!IsClientSourceTV(iClient))
    {
        SDKHook(iClient, SDKHook_WeaponCanSwitchTo, Hook_WeaponCanSwitchTo);
        SDKHook(iClient, SDKHook_OnTakeDamage,      Hook_OnTakeDamage);

        if (!gbMOTDExists)
        {
            // disable showing the MOTD panel if there's nothing to show
            CreateTimer(0.5, T_BlockConnectMOTD, iClient, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAngles[3], int &iWeapon)
{
    if (!IsClientConnected(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
        return Plugin_Continue;
    }

    if (IsClientObserver(iClient))
    {
        int    iMode   = GetEntProp(iClient, Prop_Send, "m_iObserverMode"),
               iTarget = GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget");
        Handle hMenu   = StartMessageOne("VGUIMenu", iClient);

        // disable broken spectator menu >
        if (hMenu != INVALID_HANDLE) {
            BfWriteString(hMenu, "specmenu");
            BfWriteByte(hMenu, 0);
            EndMessage();
        }

        // force free-look where appropriate - this removes the extra (pointless) third person spec mode >
        if (iMode == SPECMODE_ENEMYVIEW || iTarget <= 0 || !IsClientInGame(iTarget)) {
            SetEntProp(iClient, Prop_Data, "m_iObserverMode", SPECMODE_FREELOOK);
        }

        // fix bug where spectator can't move while free-looking >
        if (iMode == SPECMODE_FREELOOK) {
            SetEntityMoveType(iClient, MOVETYPE_NOCLIP);
        }

        // block spectator sprinting >
        iButtons &= ~IN_SPEED;

        // also fixes 1hp bug >
        return Plugin_Changed;
    }


    if (!IsPlayerAlive(iClient))
    {
        // no use when dead >
        iButtons &= ~IN_USE;
        return Plugin_Changed;
    }

    // shotgun altfire lagcomp fix by V952 >
    int  iActiveWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
    char sWeapon[32];

    if (IsValidEdict(iActiveWeapon))
    {
        GetEdictClassname(iActiveWeapon, sWeapon, sizeof(sWeapon));

        if (StrEqual(sWeapon, "weapon_shotgun") && (iButtons & IN_ATTACK2) == IN_ATTACK2) {
            iButtons |= IN_ATTACK;
        }
    }

    // Block crouch standing-view exploit >
    if ((iButtons & IN_DUCK) && GetEntProp(iClient, Prop_Send, "m_bDucked", 1) && GetEntProp(iClient, Prop_Send, "m_bDucking", 1)) {
        iButtons ^= IN_DUCK;
    }

    return Plugin_Changed;
}

public void OnGravityChanged(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    float fGravity[3];

    fGravity[2] -= StringToFloat(sNewValue);

    // force sv_gravity change to take effect immediately (by default, props retain the previous map's gravity) >
    Phys_SetEnvironmentGravity(fGravity);
}

public Action Hook_OnTakeDamage(int iClient, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType)
{
    if (iDamageType & DMG_FALL)
    {
        // Fix mp_falldamage value not having any effect >
        fDamage = gConVar.mp_falldamage.FloatValue;
    }
    else if (iDamageType & DMG_BLAST)
    {
        // Remove explosion ringing noise for everyone
        // (typically this is removed by competitive configs, which provides a significant advantage and cannot be prevented)
        iDamageType = DMG_GENERIC;
    }
    else {
        return Plugin_Continue;
    }

    return Plugin_Changed;
}

public Action Hook_WeaponCanSwitchTo(int iClient, int iWeapon)
{
    // Hands animation fix by toizy >
    SetEntityFlags(iClient, GetEntityFlags(iClient) | FL_ONGROUND);

    return Plugin_Changed;
}

public void OnEntityCreated(int iEntity, const char[] sEntity)
{
    // env_sprite fix by sidezz >
    if (StrEqual(sEntity, "env_sprite", false) || StrEqual(sEntity, "env_spritetrail", false)) {
        RequestFrame(GetSpriteData, EntIndexToEntRef(iEntity));
    }

    return;
}

public Action OnNormalSound(int iClients[MAXPLAYERS], int &iNumClients, char sSample[PLATFORM_MAX_PATH], int &iEntity, int &iChannel, float &fVolume, int &iLevel, int &iPitch, int &iFlags, char sEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (iEntity > 1 && iEntity <= MaxClients && IsClientInGame(iEntity))
    {
        if (StrContains(sSample, "npc/metropolice/die", false) != -1) {
            Format(sSample, sizeof(sSample), "npc/combine_soldier/die%i.wav", GetRandomInt(1, 3));
            return Plugin_Changed;
        }
    }

    return Plugin_Continue;
}

void GetSpriteData(int iRef)
{
    int iSprite = EntRefToEntIndex(iRef);

    if (IsValidEntity(iSprite))
    {
        int  iNade = GetEntPropEnt(iSprite, Prop_Data, "m_hAttachedToEntity");
        char sClass[32];

        if (iNade == -1) {
            return;
        }

        GetEdictClassname(iNade, sClass, sizeof(sClass));

        if (StrEqual(sClass, "npc_grenade_frag", false))
        {
            for (int i = MaxClients + 1; i < 2048; i++)
            {
                char sOtherClass[32];

                if (!IsValidEntity(i)) {
                    continue;
                }

                GetEdictClassname(i, sOtherClass, sizeof(sOtherClass));

                if (StrEqual(sOtherClass, "env_spritetrail", false) || StrEqual(sOtherClass, "env_sprite", false))
                {
                    if (GetEntPropEnt(i, Prop_Data, "m_hAttachedToEntity") == iNade)
                    {
                        int iGlow  = GetEntPropEnt(iNade, Prop_Data, "m_pMainGlow"),
                            iTrail = GetEntPropEnt(iNade, Prop_Data, "m_pGlowTrail");

                        if (i != iGlow && i != iTrail) {
                            AcceptEntityInput(i, "Kill");
                        }
                    }
                }
            }
        }
    }
}

public Action T_CheckPlayerStates(Handle hTimer)
{
    static bool bWasAlive[MAXPLAYERS + 1] = {false};
    static int  iWasTeam[MAXPLAYERS + 1]  = {-1};

    int iTeamScore[4];

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient))
        {
            iWasTeam[iClient]  = -1;
            bWasAlive[iClient] = false;
            continue;
        }

        if (IsClientSourceTV(iClient)) {
            continue;
        }

        int  iTeam  = GetClientTeam(iClient);
        bool bAlive = IsPlayerAlive(iClient);

        if (iWasTeam[iClient] == -1)
        {
            int iKills,
                iDeaths;

            gmKills.GetValue(AuthId(iClient), iKills);
            gmDeaths.GetValue(AuthId(iClient), iDeaths);

            Client_SetScore(iClient, iKills);
            Client_SetDeaths(iClient, iDeaths);
        }
        else if (iTeam != iWasTeam[iClient]) {
            OnPlayerPostTeamChange(iClient, iTeam, bWasAlive[iClient], bAlive);
        }

        iWasTeam[iClient]  = iTeam;
        bWasAlive[iClient] = bAlive;
        iTeamScore[iTeam] += Client_GetScore(iClient);

        if (!gbRoundEnd) {
            SavePlayerState(iClient);
        }
    }

    // team scores should reflect current team members
    for (int i = 1; i < 4; i++) {
        Team_SetScore(i, iTeamScore[i]);
    }

    return Plugin_Continue;
}

void SavePlayerStates()
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (IsClientInGame(iClient) && !IsClientSourceTV(iClient)) {
            SavePlayerState(iClient);
        }
    }
}

void SavePlayerState(int iClient)
{
    int  iTeam;
    char sId[32];

    GetClientAuthId(iClient, AuthId_Engine, sId, sizeof(sId));
    iTeam = (
        gbTeamplay ? GetClientTeam(iClient)
        : IsClientObserver(iClient) ? TEAM_SPECTATORS
        : TEAM_REBELS
    );

    gmKills.SetValue (sId, Client_GetScore(iClient));
    gmDeaths.SetValue(sId, Client_GetDeaths(iClient));
    gmTeams.SetValue (sId, iTeam);
}

void OnPlayerPostTeamChange(int iClient, int iTeam, bool bWasAlive, bool bIsAlive)
{
    if (!bIsAlive)
    {
        if (iTeam == TEAM_SPECTATORS)
        {
            if (gbTeamplay)
            {
                if (!bWasAlive) {
                    // player was dead and joined spec, the game will record a kill, fix:
                    Client_SetScore(iClient, Client_GetScore(iClient) -1);
                }
                else {
                    // player was alive and joined spec, the game will record a death, fix:
                    Client_SetDeaths(iClient, Client_GetDeaths(iClient) -1);
                }
            }
        }
        else if (bWasAlive) {
            // player was alive and changed team, the game will record a suicide, fix:
            Client_SetScore(iClient, Client_GetScore(iClient) +1);
            Client_SetDeaths(iClient, Client_GetDeaths(iClient) -1);
        }
    }
}

public Action T_BlockConnectMOTD(Handle hTimer, int iClient)
{
    if (IsClientConnected(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient))
    {
        Handle hMsg = StartMessageOne("VGUIMenu", iClient);

        if (hMsg != INVALID_HANDLE)
        {
            BfWriteString(hMsg, "info");
            BfWriteByte(hMsg, 0);
            EndMessage();
        }
    }

    return Plugin_Handled;
}

public Action UserMsg_VGUIMenu(UserMsg msg, Handle hMsg, const int[] iPlayers, int iNumPlayers, bool bReliable, bool bInit)
{
    char sMsg[10];

    BfReadString(hMsg, sMsg, sizeof(sMsg));
    if (StrEqual(sMsg, "scores")) {
        gbRoundEnd = true;
        RequestFrame(SavePlayerStates);
    }

    return Plugin_Continue;
}

public Action Event_GameMessage(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
    // block Server cvar spam
    hEvent.BroadcastDisabled = true;

    return Plugin_Changed;
}