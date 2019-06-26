#define PLUGIN_NAME			"XMS - Chat Messages"
#define PLUGIN_VERSION		"1.12"
#define PLUGIN_DESCRIPTION	"Removes game chat spam and sends a welcome message"
#define PLUGIN_AUTHOR		"harper"
#define PLUGIN_URL			"hl2dm.pro"

#pragma semicolon 1
#include <sourcemod>
#include <morecolors>

#pragma newdecls required
#include <hl2dm_xms>

char ServerURL[64];

/******************************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{	
	XMS_GetConfigString(ServerURL, sizeof(ServerURL), "ServerURL");
	
	HookEvent("server_cvar", EventHandler, EventHookMode_Pre);
	HookEvent("player_connect_client", EventHandler, EventHookMode_Pre);
	HookEvent("player_disconnect", EventHandler, EventHookMode_Pre);
	HookEvent("player_team", EventHandler, EventHookMode_Pre);
	HookEvent("player_changename", EventHandler, EventHookMode_Pre);
	
	HookUserMessage(GetUserMessageId("TextMsg"), UserMsg_TextMsg, true);
}

public void OnClientPostAdminCheck(int client)
{
	CPrintToChatAll("%s%N joined the server", CLR_INFO, client);
	CreateTimer(1.0, T_Welcome, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action T_Welcome(Handle timer, int client)
{
	CPrintToChat(client, "%s%sCommands: !run,!list,!start,!stop,!pause", CLR_MAIN, CHAT_PREFIX);
	CPrintToChat(client, "%s%sJoin our community: %s%s", CLR_MAIN, CHAT_PREFIX, CLR_HIGH, ServerURL);
}

public Action EventHandler(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(StrEqual(name, "player_disconnect"))
	{
		CPrintToChatAll("%s%N disconnected", CLR_INFO, client);
	}
	else if(StrEqual(name, "player_changename"))
	{
		char newname[MAX_NAME_LENGTH];
		
		GetEventString(event, "newname", newname, sizeof(newname));
		CPrintToChatAll("%s%N changed name to \"%s\"", CLR_INFO, client, newname);
	}
	
	event.BroadcastDisabled = true;
	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// Fix chat when paused
	if(XMS_GetGamestate() == STATE_PAUSE)
	{
		CPrintToChatAllFrom(client, StrEqual(command, "say_team", false), sArgs);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action UserMsg_TextMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	char message[70];
	
	BfReadString(msg, message, sizeof(message), true);
	if(StrContains(message, "more seconds before trying to switch") != -1 || StrContains(message, "Your player model is") != -1 || StrContains(message, "You are on team") != -1)
	{
		// block game spam
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}
