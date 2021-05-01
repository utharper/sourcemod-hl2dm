// currently only supports a single bot -- automatically leaves when player count exceeds 1
#define PLUGIN_VERSION  "1.1"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xms_bots.upd"

public Plugin myinfo = {
    name              = "XMS - Bots",
    version           = PLUGIN_VERSION,
    description       = "RCBot2 controller",
    author            = "harper",
    url               = PLUGIN_URL
};

/**************************************************************************************************/

#pragma semicolon 1
#pragma newdecls optional
#include <sourcemod>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <updater>
#define REQUIRE_PLUGIN

#pragma newdecls required
#include <jhl2dm>
#include <xms>

/**************************************************************************************************/

#define MIN_MAP_TIME 10

bool gbEnabled;
bool gbContinue;
int giBotClient;
int giState;

char gsKnownMaps[8][MAX_MAP_LENGTH] = {
    // the bot is familiar with these maps and shouldn't get stuck. (just stock maps for now)
    "dm_lockdown",
    "dm_overwatch",
    "dm_powerhouse",
    "dm_resistance",
    "dm_runoff",
    "dm_steamlab",
    "dm_underpass",
    "halls3"
};

/**************************************************************************************************/

public void OnPluginStart()
{
    CreateTimer(1.0, T_CheckBots, _, TIMER_REPEAT);
    
    if(LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
    
    CreateConVar("xms_bots_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnGamestateChanged(int new_state, int old_state)
{
    if(new_state == GAME_OVER) {
        if(giBotClient > 0 && IsClientInGame(giBotClient)) {
            MC_PrintToChatAllFrom(giBotClient, false, "gg!");
        }
    }
    else if(new_state == GAME_CHANGING) {
        gbContinue = (giBotClient > 0 && IsClientInGame(giBotClient));
    }
    
    giState = new_state;
}

public Action T_CheckBots(Handle timer)
{
    if(gbEnabled && (GetTimeElapsed() >= MIN_MAP_TIME || gbContinue))
    {
        int inGame = GetRealClientCount(true, false),
            connecting = GetRealClientCount(false, false) - inGame;

        if(inGame == 1)
        {
            if(!connecting && giBotClient == 0) {
                giBotClient = -1;
                CreateTimer(5.0, T_AddBot, _, TIMER_FLAG_NO_MAPCHANGE);
            }
        }
        else if(giBotClient) {
            CreateTimer(5.0, T_DelBot, _, TIMER_FLAG_NO_MAPCHANGE);
        }
        
        if(GetRealClientCount(true, true) > (GetRealClientCount(true, false) + (giBotClient ? 1 : 0)) ) {
           LogMessage("More bots spawned than expected, kicking..");
           ServerCommand("rcbotd kickbot");
        }
    }
    
    return Plugin_Continue;
}

public Action T_AddBot(Handle timer)
{
    if(GetRealClientCount(true, false) == 1 && giState == GAME_DEFAULT) {
        ServerCommand("rcbotd addbot");
    }
}

public Action T_DelBot(Handle timer)
{
    if(GetRealClientCount(true, false) != 1 && giState == GAME_DEFAULT)
    {
        if(giBotClient > 0 && IsClientInGame(giBotClient))
        {
            MC_PrintToChatAllFrom(giBotClient, false, "Bye for now!");
            ServerCommand("rcbotd kickbot");
            giBotClient = 0;
        }
    }
}

public void OnAllPluginsLoaded()
{
    gbEnabled = BotsAvailable();
}

public void OnMapStart()
{
    gbEnabled = BotsAvailable();
}

public void OnMapEnd()
{
    giBotClient = 0;
}

public void OnClientPutInServer(int client)
{
    if(gbEnabled)
    {
        if(IsClientInGame(client))
        {
            if(IsFakeClient(client) && !IsClientSourceTV(client)) {
                giBotClient = client;
                CreateTimer(2.0, T_AnnounceBot, _, TIMER_REPEAT);            
            }
        }
    }
}

public Action T_AnnounceBot(Handle timer)
{
    static int iter = 0;
    
    if(giBotClient > 0 && IsClientInGame(giBotClient))
    {
        if(gbContinue)
        {
            char currentmap[MAX_MAP_LENGTH];
            GetCurrentMap(currentmap, sizeof(currentmap));
            
            bool knownMap;
            for(int i = 0; i < sizeof(gsKnownMaps); i++) {
                if(StrEqual(currentmap, gsKnownMaps[i])) {
                    knownMap = true;
                }
            }
            
            if(knownMap) {
                MC_PrintToChatAllFrom(giBotClient, false, "yay! i'm pretty good on this map.");
            }
            else {
                MC_PrintToChatAllFrom(giBotClient, false, "hmm.. i don't know this map very well. i'll try to learn it.");
            }
            
            return Plugin_Stop;
        }
        else
        {
            if(iter == 0) {
                MC_PrintToChatAllFrom(giBotClient, false, "hey there, i'm a bot! {green}(beep)");
            }
            else if(iter >= 2) {
                MC_PrintToChatAllFrom(giBotClient, false, "i'll play with you, until another human arrives :)");     
                iter = 0;
                return Plugin_Stop;
            }
            iter++;
        }
    }
    return Plugin_Continue;
}

bool BotsAvailable()
{
    static bool RCBot2Running;
    
    char gamemode[MAX_MODE_LENGTH], botmodes[192], command[16];
    
    if(!RCBot2Running)
    {
        ServerCommandEx(command, sizeof(command), "rcbotd");
        if(!(StrContains(command, "Unknown command") == 0)) {
            RCBot2Running = true;
        }
        else LogError("RCBot2 not running");
    }
    
    if(RCBot2Running)
    {
        GetGamemode(gamemode, sizeof(gamemode));
        GetConfigString(botmodes, sizeof(botmodes), "botModes", "bots");
        if(IsItemDistinctInList(gamemode, botmodes)) {
            return true;
        }
    }
    
    return false;
}