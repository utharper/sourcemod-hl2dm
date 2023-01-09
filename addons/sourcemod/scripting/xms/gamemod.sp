#define BITS_SPRINT          0x00000001
#define OFFS_COLLISIONGROUP  500

int  giSpawnAmmo  [16][2];
char gsSpawnWeapon[16][32];
char gsModelPath  [19][70] =
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
    if (gRound.bUnlimitedAux)
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

    if (gRound.iState == GAME_MATCHWAIT)
    {
        SetEntityMoveType(iClient, MOVETYPE_NONE);
        CreateTimer(0.1, T_RemoveWeapons, iClient);
        return Plugin_Continue;
    }

    if (gRound.iSpawnHealth != -1) {
        SetEntProp(iClient, Prop_Data, "m_iHealth", gRound.iSpawnHealth > 0 ? gRound.iSpawnHealth : 1);
    }
    if (gRound.iSpawnArmor != -1) {
        SetEntProp(iClient, Prop_Data, "m_ArmorValue", gRound.iSpawnArmor > 0 ? gRound.iSpawnArmor : 0);
    }
    if (gRound.bDisableCollisions) {
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

    if (gClient[iClient].bForceKilled)
    {
        int iRagdoll = GetEntPropEnt(iClient, Prop_Send, "m_hRagdoll");

        if (iRagdoll >= 0 && IsValidEntity(iRagdoll)) {
            // remove ragdoll if plugin has killed the player
            RemoveEdict(iRagdoll);
        }

        gClient[iClient].bForceKilled = false;
    }
    else if (gRound.bReplenish)
    {
        int iAttacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
        CreateTimer(0.1, T_Replenish, iAttacker, TIMER_FLAG_NO_MAPCHANGE);
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
    gRound.fStartTime = GetGameTime();

    if (gRound.iState == GAME_MATCHWAIT)
    {
        for (int i = MaxClients; i < GetMaxEntities(); i++)
        {
            if (IsValidEntity(i) && Phys_IsPhysicsObject(i)) {
                Phys_EnableMotion(i, false); // Lock props on matchwait
            }
        }
    }

    return Plugin_Continue;
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
    if (StrEqual(sNewValue, "15")) { // trigger for some CTF maps
        Game_End();
    }
}

/**************************************************************
 * MODIFY MAP ENTITIES
 *************************************************************/
public void OnMapInit()
{
    char sKeys[4096];
    char sEntity[2][2048][256];

    if (EntityLump.Length() && GetConfigKeys(sKeys, sizeof(sKeys), "Gamemodes", gRound.sNextMode, "ReplaceEntities"))
    {
        int iReplacements = ExplodeString(sKeys, ",", sEntity[0], 2048, 256);

        for (int i = 0; i <= iReplacements; i++)
        {
            if (GetConfigString(sEntity[1][i], 256, sEntity[0][i], "Gamemodes", gRound.sNextMode, "ReplaceEntities") == 0) {
                // if no replacement entity is provided, 'beam' seems to work for null without triggering a console error.
                strcopy(sEntity[1][i], 256, "beam");
            }

        }

        for (int x = 0; x < EntityLump.Length(); x++)
        {
            char sClass[256];
            EntityLumpEntry e = EntityLump.Get(x);

            for (int y = -1; (y = e.GetNextKey("classname", sClass, sizeof(sClass), y)) != -1;)
            {
                for (int z = 0; z <= iReplacements; z++)
                {
                    if (strlen(sEntity[0][z]) && StrEqual(sClass, sEntity[0][z])) {
                        e.Update(y, NULL_STRING, sEntity[1][z]);
                    }
                }
            }
            delete e;
        }
    }
}

/**************************************************************
 * GENERAL
 *************************************************************/
void TryForceModel(int iClient)
{
    if (gRound.bTeamplay) {
        ClientCommand(iClient, "cl_playermodel models/police.mdl");
    }
    else {
        ClientCommand(iClient, "cl_playermodel models/humans/group03/%s_%02i.mdl", (Math_GetRandomInt(0, 1) ? "male" : "female"), Math_GetRandomInt(1, 7));
    }
}

void ClearProps()
{
    for (int iEnt = MaxClients; iEnt < GetMaxEntities(); iEnt++)
    {
        char sClass[64];

        if (!IsValidEntity(iEnt)) {
            continue;
        }

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
    gConVar.mp_restartgame.SetInt(iTime);
    PrintCenterTextAll("");
}

public Action T_RemoveWeapons(Handle hTimer, int iClient)
{
    if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
        Client_RemoveAllWeapons(iClient);
    }

    return Plugin_Handled;
}

public Action T_SetWeapons(Handle hTimer, int iClient)
{
    if (IsClientInGame(iClient) && IsPlayerAlive(iClient))
    {
        Client_RemoveAllWeapons(iClient);

        for (int i = 0; i < 16; i++)
        {
            if (!strlen(gsSpawnWeapon[i])) {
                break;
            }

            int iPrimary;
            int iSecondary;
            int iClip = (
                StrEqual(gsSpawnWeapon[i], "weapon_357", false)      ? 6
              : StrEqual(gsSpawnWeapon[i], "weapon_ar2", false)      ? 30
              : StrEqual(gsSpawnWeapon[i], "weapon_crossbow", false) ? 5
              : StrEqual(gsSpawnWeapon[i], "weapon_pistol", false)   ? 18
              : StrEqual(gsSpawnWeapon[i], "weapon_rpg", false)      ? 3
              : StrEqual(gsSpawnWeapon[i], "weapon_shotgun", false)  ? 6
              : StrEqual(gsSpawnWeapon[i], "weapon_slam", false)     ? 3
              : StrEqual(gsSpawnWeapon[i], "weapon_smg1", false)     ? 45
              : StrEqual(gsSpawnWeapon[i], "weapon_frag", false)     ? 2
              : -1
            );

            if (giSpawnAmmo[i][0] == -1)
            {
                if (StrEqual(gsSpawnWeapon[i], "weapon_ar2", false)) {
                    giSpawnAmmo[i][0] = 60;
                }
                else {
                    giSpawnAmmo[i][0] = iClip;
                }
            }

            if (StrEqual(gsSpawnWeapon[i], "weapon_slam", false)) {
                iSecondary = giSpawnAmmo[i][0];
            }
            else
            {
                iPrimary   = clamp(giSpawnAmmo[i][0], 0, 99999);
                iSecondary = clamp(giSpawnAmmo[i][1], 0, 99999);

                if (StrEqual(gsSpawnWeapon[i], "weapon_rpg", false) || StrEqual(gsSpawnWeapon[i], "weapon_frag", false)) {
                    iClip = -1;
                }
                else if (giSpawnAmmo[i][0] >= iClip && iClip != -1) {
                    iPrimary -= iClip;
                }
                else if(!StrEqual(gsSpawnWeapon[i], "weapon_crossbow")) {
                    iClip = iPrimary;
                    iPrimary = 0;
                }
            }

            Client_GiveWeaponAndAmmo(iClient, gsSpawnWeapon[i], false, iPrimary, iSecondary, iClip, -1);
        }
    }

    return Plugin_Handled;
}

public Action T_Replenish(Handle hTimer, int iClient)
{
    if (IsClientInGame(iClient) && IsPlayerAlive(iClient))
    {
        if (GetEntProp(iClient, Prop_Data, "m_iHealth") < gRound.iSpawnHealth) {
            SetEntProp(iClient, Prop_Data, "m_iHealth", gRound.iSpawnHealth);
        }

        if (GetEntProp(iClient, Prop_Data, "m_ArmorValue") < gRound.iSpawnArmor) {
            SetEntProp(iClient, Prop_Data, "m_ArmorValue", gRound.iSpawnArmor);
        }

        for (int i = 0; i < 16; i++)
        {
            int iWeapon = Client_GetWeapon(iClient, gsSpawnWeapon[i]);
            int iPrimary;
            int iSecondary;
            int iClip;

            if (!strlen(gsSpawnWeapon[i])) {
                break;
            }
            if (iWeapon == INVALID_ENT_REFERENCE) {
                continue;
            }

            Client_GetWeaponPlayerAmmo(iClient, gsSpawnWeapon[i], iPrimary, iSecondary);
            iClip = clamp(Weapon_GetPrimaryClip(iWeapon), 0, 99999);

            if (StrEqual(gsSpawnWeapon[i], "weapon_slam", false)) {
                Client_SetWeaponAmmo(iClient, gsSpawnWeapon[i], -1, giSpawnAmmo[i][0], -1, -1);
            }
            else
            {
                if (giSpawnAmmo[i][0] > (iPrimary + iClip)) {
                    Client_SetWeaponAmmo(iClient, gsSpawnWeapon[i], giSpawnAmmo[i][0] - iClip, -1, -1, -1);
                }

                if (giSpawnAmmo[i][1] > iSecondary) {
                    Client_SetWeaponAmmo(iClient, gsSpawnWeapon[i], -1, giSpawnAmmo[i][1], -1, -1);
                }
            }
        }

        ClientCommand(iClient, "playgamesound %s", SOUND_REPLENISH);
    }

    return Plugin_Handled;
}