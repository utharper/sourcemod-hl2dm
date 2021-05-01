// compiled with SM 1.8 and gameme v4.5.1
#define PLUGIN_VERSION  "1.2"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/gameme_hud.upd"

public Plugin myinfo = {
    name              = "gameME Stats HUD",
    version           = PLUGIN_VERSION,
    description       = "Live scoreboard player stats via gameME data",
    author            = "harper",
    url               = PLUGIN_URL
};

/**************************************************************************************************/

#pragma semicolon 1
#pragma newdecls optional
#include <sourcemod>
#include <clientprefs>
#include <gameme>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <updater>
#define REQUIRE_PLUGIN

#pragma newdecls required
#include <jhl2dm>
#undef REQUIRE_PLUGIN
#include <xms>

/**************************************************************************************************/

Handle ghHud;

int giStatsVisible[MAXPLAYERS+1];
bool gbRoundEnd;
bool gbTeamplay;

int giTotalPlayers;
any gRank        [MAXPLAYERS+1],
    gPoints      [MAXPLAYERS+1],
    gKills       [MAXPLAYERS+1],
    gDeaths      [MAXPLAYERS+1],
    gSuicides    [MAXPLAYERS+1],
    gHeadshots   [MAXPLAYERS+1],
    gHpk         [MAXPLAYERS+1],
    gAccuracy    [MAXPLAYERS+1],
    gKillspree   [MAXPLAYERS+1],
    gDeathspree  [MAXPLAYERS+1],
    gKpd         [MAXPLAYERS+1],
    gPlaytime    [MAXPLAYERS+1],
    gSessiontime [MAXPLAYERS+1],
    gPrerank     [MAXPLAYERS+1],
    gPrepoints   [MAXPLAYERS+1],
    gPrekills    [MAXPLAYERS+1],
    gPredeaths   [MAXPLAYERS+1],
    gPresuicides [MAXPLAYERS+1],
    gPreheadshots[MAXPLAYERS+1],
    gPrehpk      [MAXPLAYERS+1],
    gPretime     [MAXPLAYERS+1],
    gPrekillspree[MAXPLAYERS+1],
    gPredeathspree[MAXPLAYERS+1];

bool gbUsingXms;
Handle ghCookieColor[3];
    
/**************************************************************************************************/

public void OnPluginStart() 
{   
    ghHud = CreateHudSynchronizer();
    
    for(int i = 1; i <= MaxClients; i++) {
        CreateTimer(1.0, T_Hud, i, TIMER_REPEAT);
        CreateTimer(1.0, T_Stats, i, TIMER_REPEAT);
    }
    
    HookUserMessage(GetUserMessageId("VGUIMenu"), UserMsg_VGUIMenu, false);
    
    if(LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
    
    CreateConVar("gameme_hud_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnClientPutInServer(int client)
{
    if(!IsFakeClient(client)) {
        QueryGameMEStats("playerinfo", client, QuerygameMEStatsCallback, 1);
        CreateTimer(1.0, T_AnnouncePlugin, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnAllPluginsLoaded() {
    gbUsingXms = LibraryExists("xms");
    
    if(gbUsingXms) {
        ghCookieColor[0] = FindClientCookie("hudcolor_r");
        ghCookieColor[1] = FindClientCookie("hudcolor_g");
        ghCookieColor[2] = FindClientCookie("hudcolor_b");
    }
}

public void OnMapStart()
{
    gbTeamplay = FindConVar("mp_teamplay").BoolValue;
    gbRoundEnd = false;
}

public Action T_AnnouncePlugin(Handle timer, int client)
{
    static int iter;
    
    if(IsClientInGame(client) && iter < 9 && giTotalPlayers)
    {
        if(iter > 6 && GetGamestate() != GAME_CHANGING) {
            PrintCenterText(client, "~ gameME Stats: Tracking %i players ~", giTotalPlayers);
        }
        iter++;
        return Plugin_Continue;
    }
    
    iter = 0;
    return Plugin_Stop;
}

public Action T_Stats(Handle timer, int client)
{
    if(IsClientInGame(client) && !IsFakeClient(client)) {
        QueryGameMEStats("playerinfo", client, QuerygameMEStatsCallback);
    }
    return Plugin_Continue;
}

public Action T_Hud(Handle timer, int client)
{
    if(IsClientInGame(client) && !IsFakeClient(client) && giStatsVisible[client] && giStatsVisible[client] != 2) {
        ShowStats(client);
    }
    return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    static int lastbuttons[MAXPLAYERS + 1];
    
    if(IsClientConnected(client) && !IsFakeClient(client))
    {
        giStatsVisible[client] = gbRoundEnd ? 1 : (buttons & IN_SCORE) ? (!(lastbuttons[client] & IN_SCORE)) ? 2 : 1 : 0;
        lastbuttons[client] = buttons;
        
        if(giStatsVisible[client] == 2) {
            ShowStats(client);
        }
    }
    else {
        lastbuttons[client] = 0;
    }
}

public void OnGamestateChanged(int new_state, int old_state)
{
    if(new_state == GAME_DEFAULT || new_state == GAME_MATCHWAIT)
    {
        for(int i = 1; i <= MaxClients; i++) {
            SetPreValues(i);
        }
    }
    else if(new_state == GAME_OVER)
    {
        if(old_state == GAME_MATCH || old_state == GAME_MATCHEX)
        {
            //TODO some way to track match results in stats?
            if(!gbTeamplay)
            {
                int winner = GetTopPlayer();
                if(winner) {
                    ServerCommand("gameme_action %i match_victory", winner);
                }
            }
            else
            {
                int winner = GetTopTeam();
                for(int i = 1; i <= MaxClients; i++)
                {  
                    if(IsClientInGame(i) && !IsFakeClient(i)) {
                        if(GetClientTeam(i) == winner) {
                            ServerCommand("gameme_action %i match_victory", i);
                        }
                    }
                }
            }
        }
    }
}

#pragma newdecls optional
public QuerygameMEStatsCallback(command, payload, client, &Handle: datapack) //?
#pragma newdecls required
{
    if(client > 0 && command == RAW_MESSAGE_CALLBACK_PLAYER)
    {
        Handle data = CloneHandle(datapack);
        ResetPack(data);

        gRank[client]      = ReadPackCell(data);
        giTotalPlayers     = ReadPackCell(data);
        gPoints[client]    = ReadPackCell(data);
        gKills[client]     = ReadPackCell(data);
        gDeaths[client]    = ReadPackCell(data);
        gKpd[client]       = ReadPackFloat(data);
        gSuicides[client]  = ReadPackCell(data);
        gHeadshots[client] = ReadPackCell(data);
        gHpk[client]       = ReadPackFloat(data);
        gAccuracy[client]  = ReadPackFloat(data);
        gPlaytime[client]  = ReadPackCell(data);
        
        for(int i = 0; i < 5; i++) {
            ReadPackCell(data);
        }
        
        gKillspree[client] = ReadPackCell(data);
        gDeathspree[client] = ReadPackCell(data);
        gSessiontime[client] += 1;

        CloseHandle(data);

        if(payload) {
            SetPreValues(client);
        }
    }
}

void SetPreValues(int i)
{
    gbRoundEnd        = false;
    gPrerank[i]       = gRank[i];
    gPrepoints[i]     = gPoints[i];
    gPrekills[i]      = gKills[i];
    gPredeaths[i]     = gDeaths[i];
    gPresuicides[i]   = gSuicides[i];
    gPreheadshots[i]  = gHeadshots[i];
    gPrehpk[i]        = gHpk[i];
    gPrekillspree[i]  = gKillspree[i];
    gPredeathspree[i] = gDeathspree[i];
    gPretime[i]       = gPlaytime[i];
    gSessiontime[i]   = 0;
}

void ShowStats(int client)
{
    int target = client;

    if(IsClientObserver(client)) {
        target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
    }
            
    if(target > 1 && IsClientInGame(target) && !IsFakeClient(target) && giTotalPlayers)
    {
        char time[32];
        int t = gPretime[target] + gSessiontime[target],
            h = t / 3600,
            s = t % 60,
            m = t / 60 - (h ? (h * 60) : 0), 
            d = RoundToFloor(float(h / 24)),
            
            r = gbUsingXms ? GetClientCookieInt(client, ghCookieColor[0], 0, 255) : 255,
            g = gbUsingXms ? GetClientCookieInt(client, ghCookieColor[1], 0, 255) : 177,
            b = gbUsingXms ? GetClientCookieInt(client, ghCookieColor[2], 0, 255) : 0;
            
        SetHudTextParams(0.01, 0.37, 1.01, r, g, b, 255, 0, 0.0, 0.0, 0.0);
            
        if(d) {
            h -= d * 24;
            Format(time, sizeof(time), "%id ", d);
        }
        Format(time, sizeof(time), "%s%ih %im %02is", time, h, m, s);
        
        ShowSyncHudText(client, ghHud, "%N\n rank %i of %i\n time: %s\n kills: %i (+%i)\n deaths: %i (+%i)\n headshots: %i (+%i)\n suicides: %i (+%i)\n avg accuracy: %.0f%%%\n best killspree: %i",
         target,
         gRank[target],
         giTotalPlayers,
         time,
         gKills[target],
         gKills[target] - gPrekills[target],
         gDeaths[target],
         gDeaths[target] - gPredeaths[target],
         gHeadshots[target],
         gHeadshots[target] - gPreheadshots[target],
         gSuicides[target],
         gSuicides[target] - gPresuicides[target],
         gAccuracy[target],
         gKillspree[target]
        );
    }
}

public Action UserMsg_VGUIMenu(UserMsg msg_id, Handle msg, const players[], int playersNum, bool reliable, bool init)
{
    char buffer[10];
    BfReadString(msg, buffer, sizeof(buffer));
    gbRoundEnd = StrEqual(buffer, "scores");
    
    return Plugin_Continue;
}