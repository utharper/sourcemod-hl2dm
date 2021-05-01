#define PLUGIN_VERSION  "1.1"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/hl2dmfix.upd"

public Plugin myinfo = {
    name              = "hl2dmfix",
    version           = PLUGIN_VERSION,
    description       = "Various fixes and enhancements for HL2DM servers",
    author            = "harper, toizy, v952, sidezz",
    url               = PLUGIN_URL
};

/**************************************************************************************************/

#pragma semicolon 1
#pragma newdecls optional
#include <sourcemod>
#include <vphysics>
#include <sdkhooks>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <updater>
#define REQUIRE_PLUGIN

#pragma newdecls required
#include <jhl2dm>

/**************************************************************************************************/

ConVar ghConVarGravity;
ConVar ghConVarFalldamage;
ConVar ghConVarTeamplay;
StringMap gsmKills, gsmDeaths, gsmTeams;
bool gbRoundEnd;
bool gbMOTDExists;
bool gbTeamplay;

ConVar ghConVarTags;
bool gbModTags;

/**************************************************************************************************/

public void OnPluginStart()
{
    gsmKills = CreateTrie();
    gsmDeaths = CreateTrie();
    gsmTeams = CreateTrie();
    
    ghConVarFalldamage = FindConVar("mp_falldamage");
    ghConVarTeamplay = FindConVar("mp_teamplay");
    
    ghConVarGravity = FindConVar("sv_gravity");
    ghConVarGravity.AddChangeHook(OnGravityChanged);
    
    ghConVarTags = FindConVar("sv_tags");
    ghConVarTags.AddChangeHook(OnTagsChanged);
    
    gbMOTDExists = (FileExists("cfg/motd.txt") && FileSize("cfg/motd.txt") > 2);
    
    HookEvent("server_cvar", Event_GameMessage, EventHookMode_Pre);
    HookUserMessage(GetUserMessageId("TextMsg"), UserMsg_TextMsg, true);
    HookUserMessage(GetUserMessageId("VGUIMenu"), UserMsg_VGUIMenu, false);
    
    CreateConVar("hl2dmfix_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    AddPluginTag();
    
    if(LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnTagsChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    if(!gbModTags) {
        AddPluginTag();
    }
}

void AddPluginTag()
{
    char tags[128];
    ghConVarTags.GetString(tags, sizeof(tags));
  
    if(StrContains(tags, "hl2dmfix") == -1)
    {
        StrCat(tags, sizeof(tags), tags[0] != 0 ? ",hl2dmfix" : "hl2dmfix");
        gbModTags = true;
        ghConVarTags.SetString(tags);
        gbModTags = false;
    }
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    char args[MAX_SAY_LENGTH];
    bool loop;
    
    if(StrContains(sArgs, "#.#") == 0)
    {
        // Backwards compatibility for the old #.# command prefix
        args[0] = '!';
        strcopy(args[1], sizeof(args) - 1, sArgs[IsCharSpace(sArgs[3]) ? 4 : 3]);
        loop = true;
    }
    else {
        strcopy(args, sizeof(args), sArgs);
    }
    
    if(StrContains(args, "!") == 0 || StrContains(args, "/") == 0)
    {
        // remove case sensitivity for *ALL* commands
        for(int i = 1; i <= strlen(args); i++)
        {
            if(IsCharUpper(args[i])) {
                String_ToLower(args, args, sizeof(args));
                loop = true;
                break;
            }
        }       
    }
    
    else if(!gbTeamplay && StrEqual(command, "say_team", false))
    {
        // disable team chat in dm
        loop = true;
    }
    
    if(loop) {
        FakeClientCommandEx(client, "say %s", args);
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}

public Action UserMsg_TextMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
    char message[70];
    BfReadString(msg, message, sizeof(message), true);
    
    // block game chat spam

    if(StrContains(message, "more seconds before trying to switch") != -1 || StrContains(message, "Your player model is") != -1 || StrContains(message, "You are on team") != -1) {
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public void OnMapStart()
{
    gbTeamplay = ghConVarTeamplay.BoolValue;
    gbRoundEnd = false;
    CreateTimer(0.1, T_CheckPlayerStates, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
    gsmKills.Clear();
    gsmDeaths.Clear();
}

public Action Event_RoundStart(Handle event, const char[] name, bool noBroadcast)
{
    gsmTeams.Clear();
    gsmKills.Clear();
    gsmDeaths.Clear();
}

public void OnClientPutInServer(int client)
{   
    if(!IsClientSourceTV(client))
    {
        SDKHook(client, SDKHook_WeaponCanSwitchTo, Hook_WeaponCanSwitchTo);
        SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
        
        if(!gbMOTDExists) {
            // disable showing the MOTD panel if there's nothing to show
            CreateTimer(0.5, T_BlockConnectMOTD, client, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client)) {
        return Plugin_Continue;
    }
    
    if(IsClientObserver(client))
    {
        Handle ghMenu = StartMessageOne("VGUIMenu", client);
        int specMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        int specTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        
        // disable broken spectator menu >
        if(ghMenu != INVALID_HANDLE) {
            BfWriteString(ghMenu, "specmenu");
            BfWriteByte(ghMenu, 0);
            EndMessage();
        }
        
        // force free-look where appropriate - this removes the extra (pointless) third person spec mode >
        if(specMode == SPECMODE_ENEMYVIEW || specTarget <= 0 || !IsClientInGame(specTarget)) {
            SetEntProp(client, Prop_Data, "m_iObserverMode", SPECMODE_FREELOOK);
        }
        
        // fix bug where spectator can't move while free-looking >
        if(specMode == SPECMODE_FREELOOK) {
            SetEntityMoveType(client, MOVETYPE_NOCLIP);
        }
                
        // block spectator sprinting >
        buttons &= ~IN_SPEED;
        
        // also fixes 1hp bug >
        return Plugin_Changed;
    }
    
    
    if(!IsPlayerAlive(client)) {
        // no use when dead
        buttons &= ~IN_USE;
        return Plugin_Changed;        
    }
    
    // shotgun altfire lagcomp fix by V952
    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    char weaponClass[32];
    
    if(IsValidEdict(activeWeapon)) {
        GetEdictClassname(activeWeapon, weaponClass, sizeof(weaponClass));
        if(StrEqual(weaponClass, "weapon_shotgun") && (buttons & IN_ATTACK2) == IN_ATTACK2) {
            buttons |= IN_ATTACK;              
        }
    }
    
    // Block crouch standing-view exploit
    if((buttons & IN_DUCK) && GetEntProp(client, Prop_Send, "m_bDucked", 1) && GetEntProp(client, Prop_Send, "m_bDucking", 1)) {
        buttons ^= IN_DUCK;
    }
    
    return Plugin_Changed;
    
}

public void OnGravityChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    float newGravity[3];
    newGravity[2] -= StringToFloat(newValue);
    
    // force sv_gravity change to take effect immediately (by default, props retain the previous map's gravity)
    Phys_SetEnvironmentGravity(newGravity);
}

public Action Hook_OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if(damagetype & DMG_FALL) {
        // Fix mp_falldamage value not having any effect
        damage = ghConVarFalldamage.FloatValue;
    }
    else if(damagetype & DMG_BLAST) {
        // Remove explosion ringing noise for everyone (typically this is removed by competitive configs, which provides a significant advantage and cannot be prevented)
        damagetype = DMG_GENERIC;
    }
    else {
        return Plugin_Continue;
    }
    
    return Plugin_Changed;
}

public Action Hook_WeaponCanSwitchTo(int client, int weapon)
{
    // Hands animation fix by toizy
    SetEntityFlags(client, GetEntityFlags(client) | FL_ONGROUND);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    // env_sprite fix by sidezz
    if(StrEqual(classname, "env_sprite", false) || StrEqual(classname, "env_spritetrail", false)) {
        RequestFrame(GetSpriteData, EntIndexToEntRef(entity));
    }
}

void GetSpriteData(int ref)
{
    int sprite = EntRefToEntIndex(ref);
    
    if(IsValidEntity(sprite))
    {
        int nade = GetEntPropEnt(sprite, Prop_Data, "m_hAttachedToEntity");
        char class[32];
        
        if(nade == -1) {
            return;
        }
        
        GetEdictClassname(nade, class, sizeof(class));
        if(StrEqual(class, "npc_grenade_frag", false))
        {
            for(int i = MaxClients + 1; i < 2048; i++)
            {
                char otherClass[32];
                
                if(!IsValidEntity(i)) {
                    continue;
                }
                
                GetEdictClassname(i, otherClass, sizeof(otherClass));
                if(StrEqual(otherClass, "env_spritetrail", false) || StrEqual(otherClass, "env_sprite", false))
                {
                    if(GetEntPropEnt(i, Prop_Data, "m_hAttachedToEntity") == nade)
                    {
                        int glow = GetEntPropEnt(nade, Prop_Data, "m_pMainGlow"), 
                        trail = GetEntPropEnt(nade, Prop_Data, "m_pGlowTrail");
                        
                        if(i != glow && i != trail) {
                            AcceptEntityInput(i, "Kill");
                        }
                    }
                }
            }
        }
    }
}

public Action T_CheckPlayerStates(Handle timer)
{
    static bool wasAlive[MAXPLAYERS + 1] = false;
    static int wasTeam[MAXPLAYERS + 1] = -1;
    int teamScore[4];
    
    for(int i = 1; i <= MaxClients; i++)
    {   
        if(!IsClientInGame(i))
        {
            wasTeam[i] = -1;
            wasAlive[i] = false;
            continue;
        }
        
        if(IsClientSourceTV(i)) {
            continue;
        }
        
        int isTeam = GetClientTeam(i);
        bool isAlive = IsPlayerAlive(i);
        
        if(wasTeam[i] == -1)
        {
            int kills, deaths;
            gsmKills.GetValue(GetClientSteamID(i), kills);
            gsmDeaths.GetValue(GetClientSteamID(i), deaths);
            Client_SetScore(i, kills);
            Client_SetDeaths(i, deaths);
        }        
        
        else if(isTeam != wasTeam[i])
        {
            OnPlayerPostTeamChange(i, wasTeam[i], isTeam, wasAlive[i], isAlive);
        }
        
        wasTeam[i] = isTeam;
        wasAlive[i] = isAlive;
        teamScore[isTeam] += Client_GetScore(i);
    
        if(!gbRoundEnd) {
            SavePlayerState(i);
        }
    }
    
    // team score should reflect current team members
    for(int i = 1; i < 4; i++) {
        Team_SetScore(i, teamScore[i]);
    }
}


void SavePlayerStates()
{
    for (int i = 1; i <= MaxClients; i++) {
        if(IsClientInGame(i) && !IsClientSourceTV(i)) {
            SavePlayerState(i);
        }
    }
}

void SavePlayerState(int i)
{
    gsmKills.SetValue(GetClientSteamID(i), Client_GetScore(i));
    gsmDeaths.SetValue(GetClientSteamID(i), Client_GetDeaths(i));
    gsmTeams.SetValue(GetClientSteamID(i), (gbTeamplay ? GetClientTeam(i) : IsClientObserver(i) ? TEAM_SPECTATORS : TEAM_REBELS));        
}

void OnPlayerPostTeamChange(int client, int wasTeam, int isTeam, bool wasAlive, bool isAlive)
{
    if(!isAlive)
    {
        if(isTeam == TEAM_SPECTATORS)
        {
            if(gbTeamplay)
            {
                if(!wasAlive) {
                    // player was dead and joined spec, the game will record a kill, fix:
                    Client_SetScore(client, Client_GetScore(client) -1);
                }
                else {
                    // player was alive and joined spec, the game will record a death, fix:
                    Client_SetDeaths(client, Client_GetDeaths(client) -1);
                }
            }
        }
        else if(wasAlive) {
            // player was alive and changed team, the game will record a suicide, fix:
            Client_SetScore(client, Client_GetScore(client) +1);
            Client_SetDeaths(client, Client_GetDeaths(client) -1);
        }            
    }
}

public Action T_BlockConnectMOTD(Handle timer, int client)
{
    if(IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
    {
        Handle msg = StartMessageOne("VGUIMenu", client);
        if(msg != INVALID_HANDLE) {
            BfWriteString(msg, "info");
            BfWriteByte(msg, 0);
            EndMessage();
        }
    }
}

public Action UserMsg_VGUIMenu(UserMsg msg_id, Handle msg, const players[], int playersNum, bool reliable, bool init)
{
    char buffer[10];
    BfReadString(msg, buffer, sizeof(buffer));
    
    if(StrEqual(buffer, "scores")) {
        gbRoundEnd = true;
        RequestFrame(SavePlayerStates);
    }
    return Plugin_Continue;
}

public Action Event_GameMessage(Event event, const char[] name, bool dontBroadcast)
{
    // block Server cvar spam
    event.BroadcastDisabled = true;
}