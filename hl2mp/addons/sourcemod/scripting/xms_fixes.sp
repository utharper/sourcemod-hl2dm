#define PLUGIN_NAME         "XMS - Game Fixes & Enhancements"
#define PLUGIN_VERSION      "1.13"
#define PLUGIN_DESCRIPTION  "Various game bugfixes, fixed scoring and team locking"
#define PLUGIN_AUTHOR       "harper, V952, toizy, sidezz"
#define PLUGIN_URL          "HL2DM.PRO"
#define UPDATE_URL          "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_fixes.upd"

#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <sdktools>
#include <sdkhooks>
#include <vphysics>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <updater>

#define REQUIRE_PLUGIN
#pragma newdecls required
#include <hl2dm-xms>

int         AllowClient;
            
bool        AntiRagdoll[MAXPLAYERS + 1];

StringMap   Id_kills,
            Id_deaths,
            Id_team;
            
bool        ClientInit[MAXPLAYERS + 1];

/******************************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{   
    HookEvent("round_start", Event_RoundStart);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath);
    HookConVarChange(FindConVar("sv_gravity"), OnGravityChanged);
    
    AddCommandListener(OnClientRequestTeam, "jointeam");
    AddCommandListener(OnClientRequestTeam, "spectate");
    
    Id_kills = CreateTrie();
    Id_deaths = CreateTrie();
    Id_team = CreateTrie();
    
    if(LibraryExists("updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnMapStart()
{
    CreateTimer(0.1, T_CheckPlayerStates, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientConnected(int client)
{
    if(!IsClientSourceTV(client))
    {
        // police model by default - nobody wants to be the gleaming white combine model
        // Have to execute this immediately on connect, or it doesn't work
        if(XMS_IsGameTeamplay()) ClientCommand(client, "cl_playermodel models/police.mdl");
        
        // if dm set everyone to rebel
        else ClientCommand(client, "cl_playermodel models/humans/group03/%s_%02i.mdl", (GetRandomInt(0, 1) ? "male" : "female"), GetRandomInt(1, 7));
    }
}

public void OnClientPutInServer(int client)
{
    if(!IsClientSourceTV(client))
    {
        // Instantly join spec before we determine the correct team
        AllowClient = client;
        AntiRagdoll[client] = true;
        FakeClientCommandEx(client, "jointeam %i", TEAM_SPECTATORS);
        
        SDKHook(client, SDKHook_WeaponCanSwitchTo, Hook_WeaponCanSwitchTo);
        SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    }
}

public void OnClientDisconnect(int client)
{
    ClientInit[client] = false;
}

public void OnGamestateChanged(int new_state, int old_state)
{
    if(new_state == STATE_CHANGE)
    {
        Id_kills.Clear();
        Id_deaths.Clear();
    }
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(!IsFakeClient(client))
    {
        if(IsClientObserver(client))
        {
            int     specMode = GetEntProp(client, Prop_Send, "m_iObserverMode"),
                    specTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
                    
            Handle  hMenu = StartMessageOne("VGUIMenu", client);
            
            // disable broken spectator menu
            if(hMenu != INVALID_HANDLE)
            {
                BfWriteString(hMenu, "specmenu");
                BfWriteByte(hMenu, 0);
                EndMessage();
            }
            
            // force freelook where appropriate
            if(specMode == 6 || ((specTarget <= 0 || !IsClientInGame(specTarget)) && specMode != 7)) {
                SetEntProp(client, Prop_Send, "m_iObserverMode", 7); }
            
            // block spectator sprinting
            buttons &= ~IN_SPEED;
            
            return Plugin_Changed; // fix health update bug
        }
        else
        {
            // shotgun altfire lagcomp fix provided by v952
            int     activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
            char    weaponClass[32];
            
            if(activeWeapon != -1 && GetEdictClassname(activeWeapon, weaponClass, sizeof(weaponClass))
                && !strcmp(weaponClass, "weapon_shotgun") && (buttons & IN_ATTACK2) == IN_ATTACK2
            ){
                buttons |= IN_ATTACK;
                return Plugin_Changed;
            }
        }
    }

    return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    // env_sprite fix provided by sidezz
    if(StrEqual(classname, "env_sprite", false) || StrEqual(classname, "env_spritetrail", false))
    {
        RequestFrame(GetSpriteData, EntIndexToEntRef(entity));
    }
}

public Action Hook_WeaponCanSwitchTo(int client, int weapon) 
{
    // Hands animation fix provided by toizy
    SetEntityFlags(client, GetEntityFlags(client) | FL_ONGROUND);
}

public Action Hook_OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    // Fix mp_falldamage value not having any effect
    if(damagetype & DMG_FALL)
    {
        damage = GetConVarFloat(FindConVar("mp_falldamage"));
        return Plugin_Changed;
    }
    return Plugin_Continue;
}

public Action Event_RoundStart(Handle event, const char[] name, bool noBroadcast)
{
    if(XMS_GetGamestate() == STATE_MATCHWAIT)
    {
        for (int i = MaxClients; i < GetMaxEntities(); i++)
        {
            if (IsValidEntity(i) && Phys_IsPhysicsObject(i))
            {
                // Lock props on matchwait
                Phys_EnableMotion(i, false);
            }
        }
    }
    
    Id_kills.Clear();
    Id_deaths.Clear();
    Id_team.Clear();
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if(XMS_GetGamestate() == STATE_MATCHWAIT)
    {
        SetEntityMoveType(client, MOVETYPE_NONE);
        CreateTimer(0.1, T_RemoveWeapons, client);
    }
    
    return Plugin_Continue;
}

public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{   
    int client = GetClientOfUserId(GetEventInt(event,"userid"));
    
    if(AntiRagdoll[client])
    {
        int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
        
        if(ragdoll >= 0 && IsValidEntity(ragdoll)) RemoveEdict(ragdoll);
        AntiRagdoll[client] = false;
    }
    
    return Plugin_Continue;
}

public void OnGravityChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    float newGravity[3]; 
    newGravity[2] -= StringToFloat(newValue);
    
    // Set correct prop gravity without requiring mapchange
    Phys_SetEnvironmentGravity(newGravity);
}

public Action OnClientRequestTeam(int client, const char[] command, int args)
{
    int state = XMS_GetGamestate();
    int team = (StrEqual(command, "jointeam", false) ? GetCmdArgInt(1) : TEAM_SPECTATORS);
    
    if(AllowClient == client) AllowClient = 0;
    else if(state == STATE_PAUSE || state == STATE_MATCH || state == STATE_MATCHEX || state == STATE_MATCHWAIT)
    {
        CPrintToChat(client, "%s%sTeams are locked during a match.", CLR_FAIL, CHAT_PREFIX);
        return Plugin_Handled;
    }
    else if(XMS_IsGameTeamplay() && team == TEAM_COMBINE) ClientCommand(client, "cl_playermodel models/police.mdl");
    
    return Plugin_Continue;
}

public Action T_RemoveWeapons(Handle timer, int client)
{
    Client_RemoveAllWeapons(client);
}

public Action T_TeamChange(Handle timer, int client)
{
    int team = -1,
        state = XMS_GetGamestate();

    if(!IsClientInGame(client)) return Plugin_Stop;
    if(state == STATE_PAUSE) return Plugin_Continue;
    
    Id_team.GetValue(SteamID(client), team);
    
    if(team <= TEAM_UNASSIGNED && XMS_IsGameTeamplay())
    {
        if(state == STATE_DEFAULT)
        {   // balance teams, if equal then choose at random
            int r = GetTeamClientCount(TEAM_REBELS),
                c = GetTeamClientCount(TEAM_COMBINE);

            team = r > c ? TEAM_COMBINE : c > r ? TEAM_REBELS : GetRandomInt(0, 1) ? TEAM_REBELS : TEAM_COMBINE;                
        }
        else return Plugin_Stop;
    }
    
    if  (team != GetClientTeam(client) && 
        (team != -1 || (state != STATE_MATCH && state != STATE_MATCHWAIT && state != STATE_MATCHWAIT)) &&
        (team != TEAM_UNASSIGNED || !XMS_IsGameTeamplay())
    ){
        AllowClient = client;
        AntiRagdoll[client] = IsPlayerAlive(client);
        
        FakeClientCommandEx(client, "jointeam %i", XMS_IsGameTeamplay() ? team : TEAM_REBELS);
    }
    
    ClientInit[client] = true;
    
    return Plugin_Stop;
}

public Action T_CheckPlayerStates(Handle timer)
{       
    static int wasTeam[MAXPLAYERS + 1] = -1;
    static bool wasAlive[MAXPLAYERS + 1] = false;
    int teamScore[4];

    if(XMS_GetGamestate() != STATE_CHANGE)
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(!IsClientInGame(i))
            {
                wasTeam[i] = -1;
                wasAlive[i] = false;
                continue;
            }
                
            if(IsClientSourceTV(i)) continue;
            
            int team = GetClientTeam(i);
            bool isAlive = IsPlayerAlive(i);
                
            // client has just connected
            if(wasTeam[i] == -1)
            {
                int kills,
                    deaths;
                    
                Id_kills.GetValue(SteamID(i), kills);
                Id_deaths.GetValue(SteamID(i), deaths);
                Client_SetScore(i, kills);
                Client_SetDeaths(i, deaths);
                
                CreateTimer(1.0, T_TeamChange, i, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);          
            }
                
            else if(team != wasTeam[i] && !isAlive)
            {
                // player was in a team and changed
                if(team == TEAM_SPECTATORS)
                {
                    if(XMS_IsGameTeamplay())
                    {
                        if(!wasAlive[i]) 
                        {
                            // player was dead and joined spec, the game will record a kill, fix:
                            Client_SetScore(i, Client_GetScore(i) - 1);
                        }
                        else if(wasAlive[i] && XMS_IsGameTeamplay())
                        {
                            // player was alive and joined spec, the game will record a death, fix:
                            Client_SetDeaths(i, Client_GetDeaths(i) - 1);
                        }
                    }
                }
                else if(wasAlive[i])
                {
                    // player was alive and changed team, the game will record a suicide, fix:
                    Client_SetScore(i, Client_GetScore(i) + 1);
                    Client_SetDeaths(i, Client_GetDeaths(i) - 1);
                }   
            }
            
            wasTeam[i] = team;
            wasAlive[i] = isAlive;
            teamScore[team] += Client_GetScore(i);
            
            if(ClientInit[i])
            {
                // Save player states
                Id_kills.SetValue(SteamID(i), Client_GetScore(i));
                Id_deaths.SetValue(SteamID(i), Client_GetDeaths(i));    
                Id_team.SetValue(SteamID(i), (XMS_IsGameTeamplay() ? GetClientTeam(i) : IsClientObserver(i) ? TEAM_SPECTATORS : TEAM_UNASSIGNED));          
            }
        }
            
        // now fix team score
        for(int i = 1; i < 4; i++)
        {
            Team_SetScore(i, teamScore[i]);
        }
    }
    
    return Plugin_Continue;
}

void GetSpriteData(int ref)
{
    int sprite = EntRefToEntIndex(ref);
    
    if(IsValidEntity(sprite))
    {
        int nade = GetEntPropEnt(sprite, Prop_Data, "m_hAttachedToEntity");
        char class[32];
        
        if(nade == -1) return;
        
        GetEdictClassname(nade, class, sizeof(class));
        if(StrEqual(class, "npc_grenade_frag", false))
        {
            for(int i = MaxClients + 1; i < 2048; i++)
            {
                char otherClass[32];

                if(!IsValidEntity(i)) continue;
                
                GetEdictClassname(i, otherClass, sizeof(otherClass));
                if(StrEqual(otherClass, "env_spritetrail", false) || StrEqual(otherClass, "env_sprite", false))
                {
                    if(GetEntPropEnt(i, Prop_Data, "m_hAttachedToEntity") == nade)
                    {
                        int glow = GetEntPropEnt(nade, Prop_Data, "m_pMainGlow");
                        int trail = GetEntPropEnt(nade, Prop_Data, "m_pGlowTrail");
                        
                        if(i != glow && i != trail)
                        {
                            AcceptEntityInput(i, "Kill");
                        }
                    }
                }
            }
        }
    }
}

char[] SteamID(int client)
{
    char id[32];
    
    GetClientAuthId(client, AuthId_Engine, id, sizeof(id));
    return id;
}
