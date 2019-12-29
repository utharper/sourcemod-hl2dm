#define PLUGIN_VERSION "1.15"
#define UPDATE_URL     "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_bots.upd"
// Currently only supports a single bot in default mode -- leaves when player count exceeds 1

public Plugin myinfo=
{
    name        = "XMS - Bot",
    version     = PLUGIN_VERSION,
    description = "RCBot2 controller",
    author      = "harper <www.hl2dm.pro>",
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

#define MIN_MAP_TIME 20

bool PluginEnabled;
     
int BotClient,
    Gamestate;

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

public void OnGamestateChanged(int new_state, int old_state)
{
    Gamestate = new_state;
}

public Action T_CheckBots(Handle timer)
{
    if(PluginEnabled && XMS_GetTimeElapsed() >= MIN_MAP_TIME)
    {
        int inGame     = GetRealClientCount(true, false),
            connecting = GetRealClientCount(false, false) - inGame;

        if(inGame == 1)
        {
            if(!connecting && BotClient == 0)
            {
                BotClient = -1;
                CreateTimer(5.0, T_AddBot, _, TIMER_FLAG_NO_MAPCHANGE);
            }
        }
        else if(BotClient)
        {
            CreateTimer(5.0, T_DelBot, _, TIMER_FLAG_NO_MAPCHANGE);
        }
        
        if(GetRealClientCount(true, true) > (GetRealClientCount(true, false) + (BotClient ? 1 : 0)))
        {
           LogMessage("More bots spawned than expected, kicking..");
           ServerCommand("rcbotd kickbot");
        }
    }
    
    return Plugin_Continue;
}

public Action T_AddBot(Handle timer)
{
    if(GetRealClientCount(true, false) == 1 && Gamestate == STATE_DEFAULT)
    {
        ServerCommand("rcbotd addbot");
    }
}

public Action T_DelBot(Handle timer)
{
    if(GetRealClientCount(true, false) != 1 && Gamestate == STATE_DEFAULT)
    {
        if(BotClient && IsClientInGame(BotClient))
        {
            CPrintToChatAllFrom(BotClient, false, "I'll be back...");
            ServerCommand("rcbotd kickbot");
            BotClient = 0;
        }
    }
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

public void OnClientPutInServer(int client)
{
    if(PluginEnabled)
    {
        if(IsClientInGame(client))
        {
            if(IsFakeClient(client) && !IsClientSourceTV(client))
            {
                BotClient = client;
                CreateTimer(1.0, T_AnnounceBot, _, TIMER_REPEAT);            
            }
        }
    }
}

public Action T_AnnounceBot(Handle timer)
{
    static int iter;
    
    if(BotClient > 0)
    {
        if(IsClientInGame(BotClient))
        {
            if(iter == 0)
            {
                CPrintToChatAllFrom(BotClient, false, "Hi there, I'm a bot! {green}(beep)", CHAT_MAIN);
                iter++;
            }
            else
            {
                CPrintToChatAllFrom(BotClient, false, "I'll play with you until more humans arrive!");        
                iter = 0;
                return Plugin_Stop;
            }
        }
    }
    return Plugin_Continue;
}

bool BotsAvailable()
{
    static bool RCBot2Running;
    
    char gamemode[MAX_MODE_LENGTH],
         defaultmode[MAX_MODE_LENGTH],
         command[16];
    
    if(!RCBot2Running)
    {
        ServerCommandEx(command, sizeof(command), "rcbotd");
        if(!(StrContains(command, "Unknown command") == 0))
        {
            RCBot2Running = true;
        }
        else LogError("RCBot2 not running");
    }
    
    if(RCBot2Running)
    {
        XMS_GetGamemode(gamemode, sizeof(gamemode));
        XMS_GetConfigString(defaultmode, sizeof(defaultmode), "$default", "MapModes");
        return StrEqual(gamemode, defaultmode);        
    }
    
    return false;
}