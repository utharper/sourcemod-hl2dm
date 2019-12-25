#define PLUGIN_VERSION "1.14"
#define UPDATE_URL     "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_pause.upd"

public Plugin myinfo=
{
    name        = "XMS - Pause",
    version     = PLUGIN_VERSION,
    description = "Pause system for eXtended Match System",
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

#define PAUSETIME 60
#define SOUND_TIMER_COUNT "buttons/blip1.wav"
#define SOUND_TIMER_END "hl1/fvox/beep.wav"

int Pauser,
    RePauser,
    Return_state;

/******************************************************************/

public void OnPluginStart()
{
    RegConsoleCmd("sm_pause", Command_Pause, "Pause/unpause the game");
    AddCommandListener(LCommand_Pause, "pause");
    
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

public void OnClientPutInServer(int client)
{
    if(XMS_GetGamestate() == STATE_PAUSE)
    {
        RePauser = client;
        CreateTimer(0.1, T_RePause, client, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnClientDisconnect_Post(int client)
{
    if(GetClientCount(false) == 0)
    {
        Pauser = 0;
        RePauser = 0;
    }
}

public Action T_RePause(Handle timer, int client)
{
    if(IsClientConnected(client))
    {
        FakeClientCommand(client, "pause");
    }
}

public Action Command_Pause(int client, int args)
{
    FakeClientCommand(client, "pause");
}

public Action LCommand_Pause(int client, const char[] command, int argc)
{
    int gamestate = XMS_GetGamestate();
    
    if(client == 0)
    {
        XMS_SetGamestate(Return_state);
        return Plugin_Continue;
    }
    
    if(client == RePauser)
    {
        RePauser = 0;
        return Plugin_Continue;
    }
    
    if(IsClientObserver(client) && !IsClientAdmin(client) && client != Pauser)
    {
        CPrintToChat(client, "%s%sSpectators cannot use this command.", CLR_FAIL, CHAT_PREFIX); 
    }
    
    else switch(gamestate)
    {
        case STATE_MATCHWAIT: CPrintToChat(client, "%s%sWait until the match starts.", CLR_FAIL, CHAT_PREFIX);
        case STATE_MATCHEX:   CPrintToChat(client, "%s%sCan't pause during overtime!", CLR_FAIL, CHAT_PREFIX);
        case STATE_POST:      CPrintToChat(client, "%s%sThe match has ended.", CLR_FAIL, CHAT_PREFIX);
        case STATE_DEFAULT:   CPrintToChat(client, "%s%sYou can only pause the game during a match.", CLR_FAIL, CHAT_PREFIX);
        
        case STATE_PAUSE:
        {
            if(client == Pauser && client != RePauser)
            {
                PrintCenterTextAll(NULL_STRING);
                PlayGameSoundAll(SOUND_TIMER_END);
                CPrintToChatAllFrom(client, false, "%sMatch resumed.", CLR_MAIN);
                XMS_SetGamestate(Return_state);
                Pauser = 0;
            }
            else if(client != RePauser)
            {
                CPrintToChat(client, "%s%sOnly the player who paused the game can resume early.", CLR_FAIL, CHAT_PREFIX);
                return Plugin_Handled;
            }
            
            RePauser = 0;
            return Plugin_Continue;
        }
        case STATE_MATCH:
        {
            if(GetConVarBool(FindConVar("sv_pausable")))
            {
                PrintCenterTextAll("%i", PAUSETIME);
                CPrintToChatAllFrom(client, false, "%sMatch paused for up to %i seconds.", CLR_MAIN, PAUSETIME);
                Pauser = client;
                
                Return_state = gamestate;
                XMS_SetGamestate(STATE_PAUSE);
                
                CreateTimer(1.0, T_Unpause, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
                return Plugin_Continue;
            }
        }
    }
    
    return Plugin_Handled;
}

public Action T_Unpause(Handle timer, int client)
{
    static int iter;
    
    if(XMS_GetGamestate() != STATE_PAUSE)
    {
        iter = 0;
        return Plugin_Stop;
    }
    
    if(iter + 1 == PAUSETIME)
    {
        iter = 0;
        PrintCenterTextAll(NULL_STRING);
        PlayGameSoundAll(SOUND_TIMER_END);

        FakeClientCommand(IsClientInGame(client) ? client : 0, "pause");
        return Plugin_Stop;
    }
    
    PrintCenterTextAll("%i", PAUSETIME - 1 - iter);
    if(PAUSETIME - iter <= 10) PlayGameSoundAll(SOUND_TIMER_COUNT);
    
    iter++;
    return Plugin_Continue;
}