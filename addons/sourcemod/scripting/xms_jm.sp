#define PLUGIN_NAME			"XMS - jm Gamemode"
#define PLUGIN_VERSION		"1.12"
#define PLUGIN_DESCRIPTION	"Jump Map gamemode features"
#define PLUGIN_AUTHOR		"harper"
#define PLUGIN_URL			"hl2dm.pro"

#define BITS_SPRINT			0x00000001
#define OFFS_COLLISIONGROUP	500

#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required
#include <hl2dm_xms>

bool PluginEnabled;

/******************************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_Player_Spawn, EventHookMode_Post);
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
