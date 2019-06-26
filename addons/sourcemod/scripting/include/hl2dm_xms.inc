/*
**
*/
#if defined _hl2dm_xms_included
 #endinput
#endif
#define _hl2dm_xms_included

#define MAX_MAP_LENGTH		32
#define MAX_MODE_LENGTH		16
#define MAX_SAY_LENGTH		192

#define TEAM_UNASSIGNED		0
#define TEAM_SPECTATORS		1
#define TEAM_COMBINE		2
#define TEAM_REBELS			3

#define STATE_PAUSE			-1
#define STATE_DEFAULT		0
#define STATE_DEFAULTEX		1
#define STATE_MATCHWAIT		2
#define STATE_MATCH			3
#define STATE_MATCHEX		4
#define STATE_POST			5
#define STATE_CHANGE		6

#define CHAT_PREFIX			"# " // Prefix for client-only messages
#define CLR_MAIN			"{white}" // Most text
#define CLR_INFO			"{silver}" // Informational text (not too important)
#define CLR_HIGH			"{goldenrod}" // Highlights, eg name of the map we are changing to
#define CLR_FAIL			"{fullred}" // Error highlight

/**
 * Retrieve the value of the given string in the given (sub)keys
 *
 * @param buffer		Buffer to hold result
 * @param maxlen		Maximum length of buffer
 * @param key			Key to retrieve
 * @param ...			Variable number of key levels
 * @return				1 if the key has value, 0 if no value, -1 if key not found
 */
native int XMS_GetConfigString(char[] buffer, int maxlen, const char[] key, const char[] ...);

/**
 * Retrieve comma-seperated list of available subkeys
 *
 * @param buffer		Buffer to hold result
 * @param maxlen		Maximum length of buffer
 * @param ...			Variable number of optional higher key levels
 * @return				Number of subkeys or -1 if key not found
 */
native int XMS_GetConfigKeys(char[] buffer, int maxlen, const char[] ...);

// Get current Gamestate value
native int XMS_GetGamestate();

// Set Gamestate value
native int XMS_SetGamestate(int state);

// Retrieve current gamemode
native int XMS_GetGamemode(char[] buffer, int maxlen);

// Set gamemode
native int XMS_SetGamemode(const char[] mode);

// Retrieve Game ID
native int XMS_GetGameID(char[] buffer, int maxlen);

// Corrected time elapsed in seconds
native float XMS_GetTimeElapsed();

// Corrected time remaining in seconds
// @param chatTime - adds value of mp_chattime
native float XMS_GetTimeRemaining(bool chatTime);

// Whether teamplay is active - doesn't rely on mp_teamplay which can report incorrectly
native bool XMS_IsGameTeamplay();

// Called when the Gamestate value changes
forward void OnGamestateChanged(int new_state, int old_state);



// Useful extras
stock int ClientArgToTarget(int client, int arg)
{
	char	buffer[MAX_NAME_LENGTH];
	int		target;
	
	GetCmdArg(arg, buffer, sizeof(buffer));
	target = FindTarget(client, buffer, true, false);
	return target;
}
stock int GetCmdArgInt(int arg)
{
	char buffer[192];
	
	GetCmdArg(arg, buffer, sizeof(buffer));
	return (StringToInt(buffer));
}
stock bool IsClientAdmin(int client)
{ 
	return (CheckCommandAccess(client, "generic_admin", ADMFLAG_GENERIC, false));
}
stock void ClientCommandAll(const char[] command, any ...)
{
	char formatCmd[PLATFORM_MAX_PATH];
	
	VFormat(formatCmd, PLATFORM_MAX_PATH, command, 2);
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i)) continue;
		ClientCommand(i, formatCmd);
	}
}
stock void PlayGameSoundAll(const char[] path)
{
	ClientCommandAll("playgamesound %s", path);
}
stock int FReplaceString(char[] text, int maxlength, const char[] search, bool caseSensitive=false, const char[] replace, char[] ...)
{
	char buffer[MAX_BUFFER_LENGTH];
	
	VFormat(buffer, sizeof(buffer), replace, 6);
	return (ReplaceString(text, maxlength, search, buffer, caseSensitive));
}

// Morecolors extras
#if defined _colors_included
stock void CPrintToChatFrom(int client, int recipient, bool team, const char[] message, any ...)
{
	char fmessage[512];
	
	VFormat(fmessage, sizeof(fmessage), message, 5);
	CPrintToChatEx(recipient, client, "%s{teamcolor}%N{default} :  %s", IsClientObserver(client) ? "*SPEC* " : team ? IsClientObserver(client) ? "(Spectator)" : "(TEAM)" : NULL_STRING, client, fmessage);
}
stock void CPrintToChatAllFrom(int client, bool team, const char[] message, any ...)
{	
	char fmessage[512];
	
	VFormat(fmessage, sizeof(fmessage), message, 4);	
	for (int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientConnected(i) || !IsClientInGame(i)) continue;
		if(team && GetClientTeam(client) != GetClientTeam(i)) continue;
		CPrintToChatFrom(client, i, team, fmessage);
	}
}
#endif

// Plugin library
public SharedPlugin __pl_xms = 
{
	name = "xms",
	file = "xms.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};
 
#if !defined REQUIRE_PLUGIN
public void __pl_xms_SetNTVOptional()
{
	MarkNativeAsOptional("XMS_GetGamestate");
	MarkNativeAsOptional("XMS_SetGamestate");
	MarkNativeAsOptional("XMS_GetGamemode");
	MarkNativeAsOptional("XMS_SetGamemode");
	MarkNativeAsOptional("XMS_GetConfigString");
	MarkNativeAsOptional("XMS_GetConfigKeys");
	MarkNativeAsOptional("XMS_GetTimeRemaining");
	MarkNativeAsOptional("XMS_GetTimeElapsed");
	MarkNativeAsOptional("XMS_IsGameTeamplay");
	MarkNativeAsOptional("XMS_GetGameID");
}
#endif