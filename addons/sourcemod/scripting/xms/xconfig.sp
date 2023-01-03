/**************************************************************
 * NATIVES
 *************************************************************/
public int Native_GetConfigString(Handle hPlugin, int iParams)
{
    char sValue[1024];
    char sKey  [32];
    char sInKey[32];

    gCore.kConfig.Rewind();
    GetNativeString(3, sKey, sizeof(sKey));

    for (int i = 4; i <= iParams; i++)
    {
        GetNativeString(i, sInKey, sizeof(sInKey));

        if (!strlen(sInKey)) {
            continue;
        }

        if (!gCore.kConfig.JumpToKey(sInKey)) {
            return -1;
        }
    }

    if (gCore.kConfig.GetString(sKey, sValue, sizeof(sValue)))
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
    char sValue[32];
    char sKey  [32];
    char sInKey[4][32];

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
    char sKeys [1024];
    char sInKey[32];
    int  iCount;

    gCore.kConfig.Rewind();

    for (int i = 3; i <= iParams; i++)
    {
        GetNativeString(i, sInKey, sizeof(sInKey));
        if (!gCore.kConfig.JumpToKey(sInKey)) {
            return -1;
        }
    }

    if (gCore.kConfig.GotoFirstSubKey(false))
    {
        do {
            gCore.kConfig.GetSectionName(sKeys[strlen(sKeys)], sizeof(sKeys));
            sKeys[strlen(sKeys)] = ',';
            iCount++;
        }
        while (gCore.kConfig.GotoNextKey(false));

        sKeys[strlen(sKeys) - 1] = 0;
        SetNativeString(1, sKeys, GetNativeCell(2));

        return iCount;
    }

    return -1;
}

/**************************************************************
 * CONFIG PARSING
 *************************************************************/
void LoadConfigValues()
{
    gCore.kConfig = new KeyValues("xms");
    gCore.kConfig.ImportFromFile(gPath.sConfig);

    if (!GetConfigKeys(gCore.sGamemodes, sizeof(gCore.sGamemodes), "Gamemodes") || !GetConfigString(gCore.sDefaultMode, sizeof(gCore.sDefaultMode), "DefaultMode")) {
        LogError("xms.cfg missing or corrupted!");
    }

    // Core settings:
    if (GetConfigString(gCore.sServerMessage, sizeof(gCore.sServerMessage), "MenuMessage") == 1) {
        FormatMenuMessage(gCore.sServerMessage, gCore.sServerMessage, sizeof(gCore.sServerMessage));
    }

    GetConfigString(gPath.sDemo           , sizeof(gPath.sDemo)           , "DemoFolder");
    GetConfigString(gPath.sDemoWeb        , sizeof(gPath.sDemoWeb)        , "DemoURL");
    GetConfigString(gPath.sDemoWebExt     , sizeof(gPath.sDemoWebExt)     , "DemoExtension");
    GetConfigString(gCore.sServerName     , sizeof(gCore.sServerName)     , "ServerName");
    GetConfigString(gCore.sRetainModes    , sizeof(gCore.sRetainModes)    , "RetainModes");
    GetConfigString(gCore.sRemoveMapPrefix, sizeof(gCore.sRemoveMapPrefix), "StripPrefix", "Maps");
    GetConfigString(gCore.sEmptyMapcycle  , sizeof(gCore.sEmptyMapcycle)  , "EmptyMapcycle");

    gCore.iAdFrequency       = GetConfigInt("Frequency", "ServerAds");
    gCore.iRevertTime        = GetConfigInt("RevertTime");
    gVoting.iMinPlayers      = GetConfigInt("VoteMinPlayers");
    gVoting.iMaxTime         = GetConfigInt("VoteMaxTime");
    gVoting.iCooldown        = GetConfigInt("VoteCooldown");
    gVoting.bAutomatic       = GetConfigInt("AutoVoting") == 1;

    // Gamemode settings:
    gRound.iSpawnHealth      = GetConfigInt("SpawnHealth",  "Gamemodes", gRound.sMode);
    gRound.iSpawnArmor       = GetConfigInt("SpawnSuit",    "Gamemodes", gRound.sMode);
    gRound.bOvertime         = GetConfigInt("Overtime",     "Gamemodes", gRound.sMode) == 1;
    gRound.bDisableCollisions= GetConfigInt("NoCollisions", "Gamemodes", gRound.sMode) == 1;
    gRound.bUnlimitedAux     = GetConfigInt("UnlimitedAux", "Gamemodes", gRound.sMode) == 1;
    gRound.bDisableProps     = GetConfigInt("DisableProps", "Gamemodes", gRound.sMode) == 1;
    gRound.bReplenish        = GetConfigInt("Replenish",    "Gamemodes", gRound.sMode) == 1;
    gHud.bSelfKeys           = GetConfigInt("Selfkeys",     "Gamemodes", gRound.sMode) == 1;

    // Weapon settings:
    char sWeapons[512];
    char sWeapon [16][32];
    char sAmmo   [2][6];

    if (GetConfigString(sWeapons, sizeof(sWeapons), "SpawnWeapons", "Gamemodes", gRound.sMode))
    {
        for (int i = 0; i < ExplodeString(sWeapons, ",", sWeapon, 16, 32); i++)
        {
            int iPos[2];

            iPos[0] = SplitString(sWeapon[i], "(", gsSpawnWeapon[i], sizeof(gsSpawnWeapon[]));

            if (iPos[0] != -1)
            {
                iPos[1] = SplitString(sWeapon[i][iPos[0]], "-", sAmmo[0], sizeof(sAmmo[]));
                if (iPos[1] == -1) {
                    strcopy(sAmmo[0], sizeof(sAmmo[]), sWeapon[i][iPos[0]]);
                    sAmmo[0][strlen(sAmmo[0])-1] = 0;
                }
                else {
                    strcopy(sAmmo[1], sizeof(sAmmo[]), sWeapon[i][iPos[0]+iPos[1]]);
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