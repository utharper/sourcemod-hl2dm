#define PLUGIN_NAME         "XMS - Chat Messages"
#define PLUGIN_VERSION      "1.13"
#define PLUGIN_DESCRIPTION  "Removes game chat spam and sends a welcome message"
#define PLUGIN_AUTHOR       "harper"
#define PLUGIN_URL          "HL2DM.PRO"
#define UPDATE_URL          "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_chat.upd"

#pragma semicolon 1
#include <sourcemod>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <updater>

#define REQUIRE_PLUGIN
#pragma newdecls required
#include <hl2dm-xms>

char WelcomeMsg[4][MAX_SAY_LENGTH];

/******************************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{    
    HookEvent("server_cvar", EventHandler, EventHookMode_Pre);
    HookEvent("player_connect_client", EventHandler, EventHookMode_Pre);
    HookEvent("player_disconnect", EventHandler, EventHookMode_Pre);
    HookEvent("player_team", EventHandler, EventHookMode_Pre);
    HookEvent("player_changename", EventHandler, EventHookMode_Pre);
    
    HookUserMessage(GetUserMessageId("TextMsg"), UserMsg_TextMsg, true);
    
    if(LibraryExists("updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnAllPluginsLoaded()
{   
    XMS_GetConfigString(WelcomeMsg[0], MAX_SAY_LENGTH, "Line1", "WelcomeMessage");
    XMS_GetConfigString(WelcomeMsg[1], MAX_SAY_LENGTH, "Line2", "WelcomeMessage");
    XMS_GetConfigString(WelcomeMsg[2], MAX_SAY_LENGTH, "Line3", "WelcomeMessage");
    XMS_GetConfigString(WelcomeMsg[3], MAX_SAY_LENGTH, "Line4", "WelcomeMessage");
}

public void OnClientPostAdminCheck(int client)
{
    CPrintToChatAll("%s%N joined the server", CLR_INFO, client);
    CreateTimer(1.0, T_WelcomeMessage, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action T_WelcomeMessage(Handle timer, int client)
{
    for(int i = 0; i <= 3; i++)
    {
        if(strlen(WelcomeMsg[i]))
        {
            CPrintToChat(client, "%s%s%s", CLR_MAIN, CHAT_PREFIX, WelcomeMsg[i]);
        }            
    }
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
