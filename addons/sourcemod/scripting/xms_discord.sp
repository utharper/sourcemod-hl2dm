#define PLUGIN_NAME			"XMS - Discord Match Report"
#define PLUGIN_VERSION		"1.12"
#define PLUGIN_DESCRIPTION	"Posts match results to a Discord server"
#define PLUGIN_AUTHOR		"harper"
#define PLUGIN_URL			"hl2dm.pro"

#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <discord>
#include <morecolors>

#pragma newdecls required
#include <hl2dm_xms>

char	ServerName[64],
		WebHookURL[PLATFORM_MAX_PATH],
		DiscordURL[PLATFORM_MAX_PATH],
		DemoURL[PLATFORM_MAX_PATH],
		DemoExt[10];

/****************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnAllPluginsLoaded()
{
	XMS_GetConfigString(ServerName, sizeof(ServerName), "ServerName");
	XMS_GetConfigString(WebHookURL, sizeof(WebHookURL), "WebHookURL", "Discord");
	XMS_GetConfigString(DiscordURL, sizeof(DiscordURL), "DiscordURL", "Discord");
	XMS_GetConfigString(DemoURL, sizeof(DemoURL), "DemoURL", "Discord");
	XMS_GetConfigString(DemoExt, sizeof(DemoExt), "DemoExtension", "Discord");
}

public void OnGamestateChanged(int new_state, int old_state)
{
	if(new_state == STATE_POST && (old_state == STATE_MATCH || old_state == STATE_MATCHEX))
	{
		DiscordPush();
		CreateTimer(0.1, T_DiscordAnn, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void DiscordPush()
{
	if(strlen(WebHookURL))
	{
		int		playercount;
		
		char	gameID[1024],
				gameURL[PLATFORM_MAX_PATH],
				players[4096],
				playerScores[4096],
				teamScores[1024],
				mode[MAX_MODE_LENGTH],
				modeName[1024],
				map[MAX_MAP_LENGTH],
				gameInfo[4096];
			
		DiscordWebHook hook = new DiscordWebHook(WebHookURL);
		hook.SlackMode = true;
		
		XMS_GetGameID(gameID, sizeof(gameID));
		Format(gameURL, sizeof(gameURL), "Demo: %s/%s.%s", DemoURL, gameID, DemoExt);
		
		XMS_GetGamemode(mode, sizeof(mode));
		XMS_GetConfigString(modeName, sizeof(modeName), "Name", "GameModes", mode);
		GetCurrentMap(map, sizeof(map));
	
		if(XMS_IsGameTeamplay()) Format(teamScores, sizeof(teamScores), "%i\n%i", Team_GetScore(TEAM_REBELS), Team_GetScore(TEAM_COMBINE));
		
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsClientObserver(i))
			{
				playercount++;
				int team = GetClientTeam(i);
				char id[32];
				GetClientAuthId(i, AuthId_Engine, id, sizeof(id));
				
				Format(players, sizeof(players), "%s\%s\'%N' *%s*\n", players, XMS_IsGameTeamplay() ? (team == TEAM_REBELS ? "(R) ": team == TEAM_COMBINE ? "(C) " : "(?) ") : NULL_STRING, i, id);
				Format(playerScores, sizeof(playerScores), "%s%i kills and %i deaths\n", playerScores, GetClientFrags(i), GetClientDeaths(i));
			}
		}
		
		Format(gameInfo, sizeof(gameInfo), "**Server:** %s\n**Map:** %s\n**Mode:** %s (*%s*)\n**Players:** %i", ServerName, map, mode, modeName, playercount);
		
		MessageEmbed Embed = new MessageEmbed();
		
		Embed.SetColor("#f79321");
		Embed.SetTitle(gameID);
		Embed.AddField(NULL_STRING, gameInfo, false);
		Embed.AddField(NULL_STRING, NULL_STRING, false);
		Embed.AddField("Player *[SteamID]*", players, true);
		Embed.AddField("Score", playerScores, true);
		Embed.AddField(NULL_STRING, NULL_STRING, false);
		
		if(XMS_IsGameTeamplay())
		{
			Embed.AddField("Team", "Rebels (R)\nCombine (C)", true);
			Embed.AddField("Team Score", teamScores, true);
		}
		
		if(strlen(DemoURL))
		{
			Embed.AddField(NULL_STRING, NULL_STRING, false);
			Embed.AddField(NULL_STRING, gameURL, false);
		}
		
		hook.Embed(Embed);
		hook.Send();
		
		delete hook;
	}
}

public Action T_DiscordAnn(Handle timer)
{
	if(strlen(DiscordURL))
	{
		CPrintToChatAll("%sMatch info saved on Discord: %s", CLR_INFO, DiscordURL);
	}
}
