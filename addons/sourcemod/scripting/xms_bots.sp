#define PLUGIN_VERSION "1.14"
#define UPDATE_URL     "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_bots.upd"
// Currently only supports a single bot in default mode -- leaves when player count exceeds 1

public Plugin myinfo=
{
    name        = "XMS - Bot",
    version     = PLUGIN_VERSION,
    description = "RCBot2 controller",
    author      = "harper",
    url         = "www.hl2dm.pro"
};

/******************************************************************/

#pragma semicolon 1
#include <sourcemod>
#include <morecolors>

#undef REQUIRE_PLUGIN
 #include <updater>
#define REQUIRE_PLUGIN

#pragma newdecls required
 #include <hl2dm-xms>
 
/******************************************************************/
 
bool PluginEnabled;
     
int BotClient;

/******************************************************************/

public void OnPluginStart()
{
    CreateTimer(1.0, T_CheckBots, _, TIMER_REPEAT);
    
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

public Action T_CheckBots(Handle timer)
{
    if(PluginEnabled)
    {
        if(BotClient && (GetRealClientCount() > 1 || GetRealClientCount() == 0))
        {
           KickBot();
        }
    }
    
    return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
    if(IsFakeClient(client)) BotClient = 0;
}

public void OnAllPluginsLoaded()
{
    PluginEnabled = BotsAvailable();
}

public void OnMapStart()
{
    PluginEnabled = BotsAvailable();
}

public void OnMapEnd()
{
    BotClient = 0;
}

public void OnClientPostAdminCheck(int client)
{
    if(PluginEnabled)
    {
        if(IsClientInGame(client))
        {
            if(!IsFakeClient(client))
            {
                if(GetRealClientCount(true) == 1)
                {
                    AddBot();
                }
                else
                {
                    KickBot();
                }
            }
            else
            {
                BotClient = client;
                CPrintToChatAllFrom(client, false, "Hi there, I'm a bot! {green}(beep)", CLR_MAIN);
                CPrintToChatAllFrom(client, false, "I'll play with you until more humans arrive!");
            }
        }
    }
}

public void OnClientDisconnect_Post(int client)
{
    if(PluginEnabled)
    {
        if(GetRealClientCount() == 2)
        {
            AddBot();
        }
    }
}

void AddBot()
{
    int state = XMS_GetGamestate();
    
    if(!BotClient)
    {
        if(state != STATE_POST && state != STATE_CHANGE)
        {
            ServerCommand("rcbotd addbot");
        }
    }
}

void KickBot()
{
    ServerCommand("rcbotd kickbot");
    BotClient = 0;
}

bool BotsAvailable()
{
    char gamemode[MAX_MODE_LENGTH],
         defaultmode[MAX_MODE_LENGTH],
         command[16];
    
    ServerCommandEx(command, sizeof(command), "rcbotd");
    if(!(StrContains(command, "Unknown command") == 0))
    {
        XMS_GetGamemode(gamemode, sizeof(gamemode));
        XMS_GetConfigString(defaultmode, sizeof(defaultmode), "$default", "MapModes");
        return StrEqual(gamemode, defaultmode);
    }
    else LogError("RCBot2 not running");
    
    return false;
}