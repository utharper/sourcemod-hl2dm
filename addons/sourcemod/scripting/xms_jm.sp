#define PLUGIN_VERSION "1.15"
#define UPDATE_URL     "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_jm.upd"

public Plugin myinfo=
{
    name        = "XMS - Gamemode: jm",
    version     = PLUGIN_VERSION,
    description = "Jump Map gamemode features",
    author      = "harper <www.hl2dm.pro>",
    url         = "www.hl2dm.pro"
};

/******************************************************************/

#pragma semicolon 1
#include <sourcemod>
#include <smlib>

#undef REQUIRE_PLUGIN
 #include <updater>
#define REQUIRE_PLUGIN

#pragma newdecls required
 #include <hl2dm-xms>
 
/******************************************************************/

#define BITS_SPRINT 0x00000001
#define OFFS_COLLISIONGROUP 500

bool PluginEnabled;

/******************************************************************/

public void OnPluginStart()
{
    HookEvent("player_spawn", Event_Player_Spawn, EventHookMode_Post);
    
    if(LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnMapStart()
{
    char gamemode[MAX_MODE_LENGTH];
    
    XMS_GetGamemode(gamemode, sizeof(gamemode));
    PluginEnabled = StrEqual(gamemode, "jm");
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(PluginEnabled)
    {
        int bits = GetEntProp(client, Prop_Send, "m_bitsActiveDevices");
        
        if(bits & BITS_SPRINT)
        {
            SetEntPropFloat(client, Prop_Data, "m_flSuitPowerLoad", 0.0);
            SetEntProp(client, Prop_Send, "m_bitsActiveDevices", bits & ~BITS_SPRINT);
        }       
    }
    
    return Plugin_Continue;
}

public Action Event_Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
    if(PluginEnabled)
    {
        int client = GetClientOfUserId(GetEventInt(event, "userid"));
        
        RequestFrame(NoCollide, client);
    }
    
    return Plugin_Continue;
}

void NoCollide(int client)
{
    SetEntData(client, OFFS_COLLISIONGROUP, 2, 4, true);
}
