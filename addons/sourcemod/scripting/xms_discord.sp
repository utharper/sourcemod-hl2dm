//#define PLUGIN_DEBUG
#define PLUGIN_VERSION  "1.2"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xms_discord.upd"

public Plugin myinfo = {
    name              = "XMS - Discord",
    version           = PLUGIN_VERSION,
    description       = "Broadcasts competitive match results to Discord server",
    author            = "harper",
    url               = PLUGIN_URL
};

/**************************************************************************************************/

#define PLUGIN_DEBUG
#pragma dynamic 131072
#pragma semicolon 1
#pragma newdecls optional
#include <sourcemod>
#include <steamworks>

#undef REQUIRE_PLUGIN
#include <updater>
#define REQUIRE_PLUGIN

#pragma newdecls required
#include <jhl2dm>
#include <xms>

/**************************************************************************************************/

char gsWebhook[99][PLATFORM_MAX_PATH];
char gsServerName[32];
char gsDemoURL[PLATFORM_MAX_PATH];
char gsDemoExtension[8];
char gsGameID[128];
char gsMap[MAX_MAP_LENGTH];
char gsMode[MAX_MODE_LENGTH];
char gsModeName[32];
char gsPlayerURL[PLATFORM_MAX_PATH];
char gsThumbsURL[PLATFORM_MAX_PATH];
char gsFooterText[256];
char gsFlagCode[3];
bool gbTeamplay;

/**************************************************************************************************/

public void OnPluginStart()
{
    CreateConVar("xms_discord_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    
    #if defined PLUGIN_DEBUG
    RegServerCmd("discord_push", Command_Push, "Manually push match report to Discord server");
    #endif
    
    if(LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnAllPluginsLoaded()
{
    GetConfigString(gsServerName, sizeof(gsServerName), "serverName");
    GetConfigString(gsDemoURL, sizeof(gsDemoURL), "demoURL");
    if(StrContains(gsDemoURL, "://") == -1) {
        Format(gsDemoURL, sizeof(gsDemoURL), "http://%s", gsDemoURL);
    }
    GetConfigString(gsDemoExtension, sizeof(gsDemoExtension), "demoExtension");
    GetConfigString(gsPlayerURL, sizeof(gsPlayerURL), "url_player", "discord");
    GetConfigString(gsThumbsURL, sizeof(gsThumbsURL), "url_thumbs", "discord");
    GetConfigString(gsFooterText, sizeof(gsFooterText), "footer", "discord");
    GetConfigString(gsFlagCode, sizeof(gsFlagCode), "flagCode", "discord");
        
    char key[30];
    for(int i = 0; i < 99; i++)
    {
        Format(key, sizeof(key), "webhook%i", i + 1);
        if(!GetConfigString(gsWebhook[i], sizeof(gsWebhook[]), key, "discord")) {
            break;
        }
        if(StrContains(gsWebhook[i], "/slack", false) == -1) {
            StrCat(gsWebhook[i], sizeof(gsWebhook[]), "/slack");
        }
    }
}

public void OnMapStart()
{
    GetCurrentMap(gsMap, sizeof(gsMap));
    GetGamemode(gsMode, sizeof(gsMode));
    GetConfigString(gsModeName, sizeof(gsModeName), "name", "gamemodes", gsMode);
    gbTeamplay = FindConVar("mp_teamplay").BoolValue;
}

public void OnMatchStart()
{
    GetGameID(gsGameID, sizeof(gsGameID));
}

public void OnMatchEnd(bool success)
{
    if(success) {
        GenerateMatchReport();
    }
}

void GenerateMatchReport()
{
    int playercount, teamScore[2];
    char demolink[PLATFORM_MAX_PATH], thumblink[PLATFORM_MAX_PATH], playerScores[2][384], players[2][2096], player_json[10000], json[12000];
    bool sent;
   
    // Generate URLs
    if(strlen(gsDemoURL)) {
        Format(demolink, sizeof(demolink), "%s/%s%s", gsDemoURL, gsGameID, gsDemoExtension);
    }
    if(strlen(gsThumbsURL)) {
        Format(thumblink, sizeof(thumblink), "%s/%s.jpg", gsThumbsURL, gsMap);
    }
    
    // Fetch player data
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && !IsClientObserver(i))
        {
            char id[18], name[128];
            int team, index;
                    
            playercount++;
            GetClientAuthId(i, AuthId_Engine, id, sizeof(id));       
            GetClientName(i, name, sizeof(name));
            
            if(!IsFakeClient(i)) {
                Format(name, sizeof(name), "[%s](%s%s)", name, gsPlayerURL, id);
            }
                    
            if(gbTeamplay) {
                team = GetClientTeam(i);
                index = (team == TEAM_REBELS || team == TEAM_COMBINE) ? team - 2 : 0;
                teamScore[index] += GetClientFrags(i);
            }
    
            Format(players[index], sizeof(players[]), "%s%s\\n",     
                players[index], name
            );
                    
            Format(playerScores[index], sizeof(players[]), "%s%i Kills, %i Deaths\\n",
                playerScores[index], GetClientFrags(i), GetClientDeaths(i)
            );
                    
        }
    }
    
    #if !defined PLUGIN_DEBUG
    if(playercount < 2) {
        LogError("Discarding match report due to less than 2 active players");
        return;
    }
    #endif
   
    // Build player list
    if(gbTeamplay)
    {
        Format(player_json, sizeof(player_json),
            "{\
                \"value\": \"%s\",\
                \"short\": true,\
                \"title\": \"__The Combine__\"\
            },\
            {\
                \"value\": \"%s\",\
                \"short\": true,\
                \"title\": \"Team Score: ```%i```\"\
            },\
            {\
                \"value\": \"\",\
                \"short\": false,\
                \"title\": \"\"\
            },\
            {\
                \"value\": \"%s\",\
                \"short\": true,\
                \"title\": \"__Rebel Forces__\"\
            },\
            {\
                \"value\": \"%s\",\
                \"short\": true,\
                \"title\": \"Team Score: ```%i```\"\
            }",
            
            players[0],
            playerScores[0],
            teamScore[0],
            
            players[1],
            playerScores[1],
            teamScore[1]
        );
    }
    else {
        Format(player_json, sizeof(player_json),
            "{\
                \"value\": \"%s\",\
                \"short\": true,\
                \"title\": \"Player\"\
            },\
            {\
                \"value\": \"%s\",\
                \"short\": true,\
                \"title\": \"Score\"\
            }",
            players[0], playerScores[0]
        );
    }
    ReplaceString(player_json, sizeof(player_json), "  ", "");
    
    // Build final json
    Format(json, sizeof(json),
        "{\"attachments\":[{\
            \"color\": \"%s\",\
            \"title\": \":flag_%s:   %s\",\
            \"thumb_url\": \"%s\",\
            \"footer\": \"%s\",\
            \"fields\": [\
            {\       
                \"value\": \"**Map:**\\u2003%s\\n\
                    **Mode:**\\u2002%s\\n\
                    **Players:**\\u2002%i\",\
                \"short\": false,\
                \"title\": \"\"\
            },\
            {\
                \"value\": \"\",\
                \"short\": false,\
                \"title\": \"\"\
            },\
            %s, \
                {\"value\": \"\",\
                \"short\": false,\
                \"title\": \"\"\
            },\
            {\
                \"value\": \"**[%s](%s)**⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\",\
                \"short\": false,\
                \"title\": \"\"\
            }]\
        }]}",
        
        "#f79321",
        gsFlagCode,
        gsServerName,
        thumblink,
        gsFooterText,
        gsMap,
        strlen(gsModeName) ? gsModeName : gsMode,
        playercount,
        player_json,
        strlen(demolink) ? "Download match demo" : "",
        demolink
    );
    ReplaceString(json, sizeof(json), "  ", "");


    for(int i = 0; i < 99; i++) {
        if(strlen(gsWebhook[i])) {
            POST(gsWebhook[i], json);
            sent = true;
        }
        else break;
    }
    
    if(!sent) {
        LogError("No webhooks defined - check your config!");
    }
}

#if defined PLUGIN_DEBUG
public Action Command_Push(int argc)
{
    GenerateMatchReport();
}
#endif

void POST(const char[] url, const char[] json)
{
    Handle http = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url);
    
    #if defined PLUGIN_DEBUG
    SteamWorks_SetHTTPCallbacks(http, HTTPRequestCompleted);
    #endif
    
    SteamWorks_SetHTTPRequestRawPostBody(http, "application/json", json, strlen(json));
    SteamWorks_SetHTTPRequestNetworkActivityTimeout(http, 30);
    SteamWorks_SendHTTPRequest(http);
}

#if defined PLUGIN_DEBUG
stock int HTTPRequestCompleted(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, Handle data)
{
    int len = 0;
    SteamWorks_GetHTTPResponseBodySize(request, len);
    char[] response = new char[len];
    SteamWorks_GetHTTPResponseBodyData(request, response, len);
    PrintToServer("Response: %s", response);
}
#endif