#if !defined _jhl2dm_included
    #error "jhl2dm required"
    #endinput
#endif

#if defined _xms_included
    #endinput
#endif

#define _xms_included

/**************************************************************************************************/

enum( += 1)
{
    GAME_PAUSED = -1,  // Game is paused
    GAME_DEFAULT,      // Standard state
    GAME_OVERTIME,     // Non-match overtime
    GAME_MATCHWAIT,    // Match countdown
    GAME_MATCH,        // Match in progress
    GAME_MATCHEX,      // Match overtime
    GAME_OVER,         // Map has ended
    GAME_CHANGING,     // Map is changing/reloading
}

#define MAX_MODE_LENGTH 16

/**************************************************************************************************/

/**
 * Retrieve comma-seperated list of available subkeys
 *
 * @param buffer        Buffer to hold result
 * @param maxlen        Maximum length of buffer
 * @param ...           Variable number of key levels from which to search
 * @return              Number of subkeys or -1 if key not found
 */
native int GetConfigKeys(char[] buffer, int maxlen, const char[]...);

/**
 * Retrieve the string value of this key
 *
 * @param buffer        Buffer to hold result
 * @param maxlen        Maximum length of buffer
 * @param key           Key to retrieve
 * @param ...           Variable number of optional higher key levels, starting from the highest level
 * @return              1 if the key has value, 0 if no value, -1 if key not found
 */
native int GetConfigString(char[] buffer, int maxlen, const char[] key, const char[]...);

/**
 * Retrieve the integer value of this key
 *
 * @param key           Key to retrieve
 * @param ...           Variable number of optional higher key levels, starting from the highest level
 * @return              Value, or -1 if not found
 */
native int GetConfigInt(const char[] key, const char[]...);

/**
 * Retrieve current XMS Gamestate
 *
 * @return              Value of current Gamestate
 */
native int GetGamestate();

/**
 * Check whether the current gamestate is one of these
 * @param ...           Gamestate value(s) to check
 * @return              1 if one of the gamestates is current, 0 otherwise 
 */
native bool IsGamestate(int ...);

/**
 * Retrieve currently loaded Gamemode
 *
 * @param buffer        Buffer to hold result
 * @param maxlen        Maximum length of buffer
 * @return              Number of bytes written
 */
native int GetGamemode(char[] buffer, int maxlen);

/**
 * Retrieve the XMS Game ID
 *
 * @param buffer        Buffer to hold result
 * @param maxlen        Maximum length of buffer
 * @return              Number of bytes written
 */
native int GetGameID(char[] buffer, int maxlen);

/**
 * Retrieve corrected game-time elapsed
 *
 * @return              Seconds elapsed
 */
native float GetTimeElapsed();

/**
 * Retrieve corrected game-time remaining
 *
 * @param chatTime      Add remaining mp_chattime to return
 * @return              Seconds remaining
 */
native float GetTimeRemaining(bool chatTime);

/**
 * Called when the Gamestate value changes
 *
 * @param new_state      New Gamestate value
 * @param old_state      Previous Gamestate value
 */
forward void OnGamestateChanged(int new_state, int old_state);

/**
 * Called when a match is started
 */
forward void OnMatchStart();

/**
 * Called when a match ends
 *
 * @param success      True if the match came to a natural end, false if ended early/cancelled
 */
forward void OnMatchEnd(bool success);

stock bool IsGameMatch() {
    return IsGamestate(GAME_MATCH, GAME_MATCHEX, GAME_MATCHWAIT, GAME_PAUSED);
}

stock bool IsGameOver() {
    return IsGamestate(GAME_OVER, GAME_CHANGING);
}

stock bool IsGamemode(const char[] mode)
{
    char gamemode[MAX_MODE_LENGTH];
    GetGamemode(gamemode, sizeof(gamemode));
    return StrEqual(gamemode, mode, false);
}

stock bool IsValidGamemode(const char[] mode)
{
    char list[512];
    if(GetConfigKeys(list, sizeof(list), "gamemodes")) {
        return IsItemDistinctInList(mode, list);
    }
    return false;
}

stock bool IsModeMatchable(const char[] mode)
{
    return view_as<bool>(GetConfigInt("matchable", "gamemodes", mode));
}

/**************************************************************************************************/

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
public void __pl_SetNTVOptional()
{
    MarkNativeAsOptional("GetConfigKeys");
    MarkNativeAsOptional("GetConfigString");
    MarkNativeAsOptional("GetConfigInt");
    MarkNativeAsOptional("GetGamestate");
    MarkNativeAsOptional("IsGamestate");
    MarkNativeAsOptional("GetGamemode");
    MarkNativeAsOptional("GetGameID");
    MarkNativeAsOptional("GetTimeElapsed");
    MarkNativeAsOptional("GetTimeRemaining");
}
#endif