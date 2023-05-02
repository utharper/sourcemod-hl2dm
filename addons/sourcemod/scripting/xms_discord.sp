#pragma dynamic 131072
#pragma semicolon 1
#pragma newdecls required
//#define PLUGIN_DEBUG

#define PLUGIN_VERSION  "1.3"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xms_discord.upd"

public Plugin myinfo = {
    name              = "XMS - Discord",
    version           = PLUGIN_VERSION,
    description       = "Broadcasts competitive match results to Discord server",
    author            = "harper",
    url               = PLUGIN_URL
};

/**************************************************************
 * INCLUDES
 *************************************************************/
#include <sourcemod>
#include <steamworks>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <updater>

#define REQUIRE_PLUGIN
#include <jhl2dm>
#include <xms>

/**************************************************************
 * GLOBAL VARS
 *************************************************************/
bool gbTeamplay;
char gsMatchHook [99][PLATFORM_MAX_PATH];
char gsReportHook[PLATFORM_MAX_PATH];
char gsServerName[32];
char gsDemoURL   [PLATFORM_MAX_PATH];
char gsDemoExt   [8];
char gsGameID    [128];
char gsMap       [MAX_MAP_LENGTH];
char gsMode      [MAX_MODE_LENGTH];
char gsModeName  [32];
char gsPlayerURL [PLATFORM_MAX_PATH];
char gsThumbsURL [PLATFORM_MAX_PATH];
char gsFooter    [256];
char gsFlagCode  [3];

/**************************************************************/

#if defined PLUGIN_DEBUG
public Action Command_Push(int argc)
{
    GenerateMatchReport();
}
#endif

public void OnPluginStart()
{
    CreateConVar("xms_discord_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);

    #if defined PLUGIN_DEBUG
    RegServerCmd("discord_push", Command_Push, "Manually push match report to Discord server");
    #endif

    if (LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnAllPluginsLoaded()
{
    GetConfigString(gsServerName, sizeof(gsServerName), "ServerName");
    GetConfigString(gsDemoExt,    sizeof(gsDemoExt),    "DemoExtension");
    GetConfigString(gsDemoURL,    sizeof(gsDemoURL),    "DemoURL");

    if (StrContains(gsDemoURL, "://") == -1) {
        Format(gsDemoURL, sizeof(gsDemoURL), "http://%s", gsDemoURL);
    }

    GetConfigString(gsPlayerURL,  sizeof(gsPlayerURL),  "PlayerURL",       "Discord");
    GetConfigString(gsThumbsURL,  sizeof(gsThumbsURL),  "ThumbsURL",       "Discord");
    GetConfigString(gsFooter,     sizeof(gsFooter),     "FooterText",      "Discord");
    GetConfigString(gsFlagCode,   sizeof(gsFlagCode),   "FlagCode",        "Discord");
    
    if (GetConfigString(gsReportHook, sizeof(gsReportHook), "FeedbackWebhook", "Discord")) {
        ReplaceString(gsReportHook, sizeof(gsReportHook), "://discord.com", "://discordapp.com", false);        
    }

    for (int i = 0; i < 99; i++)
    {
        char sKey[30];

        Format(sKey, sizeof(sKey), "MatchWebhook%i", i + 1);
        if (!GetConfigString(gsMatchHook[i], sizeof(gsMatchHook[]), sKey, "Discord")) {
            break;
        }

        ReplaceString(gsMatchHook[i], sizeof(gsMatchHook[]), "://discord.com", "://discordapp.com", false);

        if (StrContains(gsMatchHook[i], "/slack", false) == -1) {
            StrCat(gsMatchHook[i], sizeof(gsMatchHook[]), "/slack");
        }
    }
}

public void OnMapStart()
{
    GetCurrentMap(gsMap, sizeof(gsMap));
    GetGamemode(gsMode, sizeof(gsMode));
    GetConfigString(gsModeName, sizeof(gsModeName), "Name", "Gamemodes", gsMode);

    gbTeamplay = FindConVar("mp_teamplay").BoolValue;
}

public void OnClientFeedback(const char[] sFeedback, const char[] sName, const char[] sID, const char[] sGameID)
{
    if (strlen(gsReportHook))
    {
        char sJson[4096];

        Format(sJson, sizeof(sJson), "{\"content\": \"**[%s]** --- [%s](<%s%s>) reports feedback:\\n  %s\"}", sGameID, sName, gsPlayerURL, sID, sFeedback);
        POST(gsReportHook, sJson);
    }
}

public void OnMatchStart()
{
    GetGameID(gsGameID, sizeof(gsGameID));
}

public void OnMatchEnd(bool bSuccess)
{
    if (bSuccess) {
        GenerateMatchReport();
    }
}

void GenerateMatchReport()
{
    int  iPlayers;
    int  iTeamScore [2];
    bool bSent;
    char sDemoURL   [PLATFORM_MAX_PATH];
    char sThumbURL  [PLATFORM_MAX_PATH];
    char sPlayers   [2][2096];
    char sScores    [2][384];
    char sPlayerJson[10000];
    char sFullJson  [12000];

    // Generate URLs
    if (strlen(gsDemoURL)) {
        Format(sDemoURL, sizeof(sDemoURL), "%s/%s%s", gsDemoURL, gsGameID, gsDemoExt);
    }
    if (strlen(gsThumbsURL)) {
        Format(sThumbURL, sizeof(sThumbURL), "%s/%s.jpg", gsThumbsURL, gsMap);
    }

    // Fetch player data
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsClientObserver(i))
        {
            int iTeam;
            int iIndex;
            char sId    [32];
            char sPlayer[128];

            iPlayers++;
            GetClientAuthId(i, AuthId_Engine, sId, sizeof(sId));
            GetClientName(i, sPlayer, sizeof(sPlayer));

            if (!IsFakeClient(i)) {
                Format(sPlayer, sizeof(sPlayer), "[%s](%s%s)", sPlayer, gsPlayerURL, sId);
            }

            if (gbTeamplay)
            {
                iTeam = GetClientTeam(i);

                if (iTeam == TEAM_REBELS || iTeam == TEAM_COMBINE) {
                    iIndex = iTeam - 2;
                }

                iTeamScore[iIndex] += GetClientFrags(i);
            }

            Format(sPlayers[iIndex], sizeof(sPlayers[]), "%s%s\\n", sPlayers[iIndex], sPlayer);
            Format(sScores[iIndex], sizeof(sScores[]), "%s%i Kills, %i Deaths\\n", sScores[iIndex], GetClientFrags(i), GetClientDeaths(i));
        }
    }

    #if !defined PLUGIN_DEBUG
    if (iPlayers < 2) {
        LogError("Discarding match report due to less than 2 active players");
        return;
    }
    #endif

    // Build player list
    if (gbTeamplay)
    {
        Format(sPlayerJson, sizeof(sPlayerJson),
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

            sPlayers[0],
            sScores[0],
            iTeamScore[0],
            sPlayers[1],
            sScores[1],
            iTeamScore[1]
        );
    }
    else {
        Format(sPlayerJson, sizeof(sPlayerJson),
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
            sPlayers[0], sScores[0]
        );
    }
    ReplaceString(sPlayerJson, sizeof(sPlayerJson), "  ", "");

    // Build final json
    Format(sFullJson, sizeof(sFullJson),
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
        sThumbURL,
        gsFooter,
        gsMap,
        strlen(gsModeName) ? gsModeName : gsMode,
        iPlayers,
        sPlayerJson,
        strlen(sDemoURL) ? "Download match demo" : "",
        sDemoURL
    );
    ReplaceString(sFullJson, sizeof(sFullJson), "  ", "");

    // Send
    for (int i = 0; i < 99; i++)
    {
        if (!strlen(gsMatchHook[i])) {
            break;
        }

        POST(gsMatchHook[i], sFullJson);
        bSent = true;
    }

    if (!bSent) {
        LogError("No webhooks defined - check your config!");
    }
}

void POST(const char[] sUrl, const char[] sJson)
{
    Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sUrl);

    #if defined PLUGIN_DEBUG
    SteamWorks_SetHTTPCallbacks(hRequest, OnRequestCompleted);
    #endif

    SteamWorks_SetHTTPRequestRawPostBody(hRequest, "application/json", sJson, strlen(sJson));
    SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 30);
    SteamWorks_SendHTTPRequest(hRequest);
}

#if defined PLUGIN_DEBUG
int OnRequestCompleted(Handle hRequest, bool bFailure, bool bSuccessful, EHTTPStatusCode iStatusCode, Handle hData)
{
    int iLen;
    SteamWorks_GetHTTPResponseBodySize(hRequest, iLen);

    char[] sResponse = new char[iLen];
    SteamWorks_GetHTTPResponseBodyData(hRequest, sResponse, iLen);

    PrintToServer("Response: %s", sResponse);
}
#endif