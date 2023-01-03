#if defined _xms_included
  #endinput
#endif
#define _xms_included

#define MAX_MODE_LENGTH 16

// Gamestates:
#define GAME_PAUSED    -1 // Game is paused
#define GAME_DEFAULT    0 // Standard state
#define GAME_OVERTIME   1 // Non-match overtime
#define GAME_MATCHWAIT  2 // Match countdown
#define GAME_MATCH      3 // Match in progress
#define GAME_MATCHEX    4 // Match overtime
#define GAME_OVER       5 // Map has ended
#define GAME_CHANGING   6 // Map is changing/reloading

/**************************************************************
 * NATIVES
 *************************************************************/

/**
 * Retrieve comma-seperated list of available subkeys
 *
 * @param sBuffer       Buffer to hold result
 * @param iLen          Maximum length of buffer
 * @param ...           Variable number of key levels from which to search
 * @return              Number of subkeys or -1 if key not found
 */
native int GetConfigKeys(char[] sBuffer, int iLen, const char[]...);

/**
 * Retrieve the string value of this key
 *
 * @param sBuffer       Buffer to hold result
 * @param iLen          Maximum length of buffer
 * @param sKey          Key to retrieve
 * @param ...           Variable number of optional higher key levels, starting from the highest level
 * @return              1 if the key has value, 0 if no value, -1 if key not found
 */
native int GetConfigString(char[] sBuffer, int iLen, const char[] sKey, const char[]...);

/**
 * Retrieve the integer value of this key
 *
 * @param sKey          Key to retrieve
 * @param ...           Variable number of optional higher key levels, starting from the highest level
 * @return              Value, or -1 if not found
 */
native int GetConfigInt(const char[] sKey, const char[]...);

/**
 * Retrieve current XMS Gamestate
 *
 * @return              Value of current Gamestate
 */
native int GetGamestate();

/**
 * Retrieve currently loaded Gamemode
 *
 * @param sBuffer       Buffer to hold result
 * @param iLen          Maximum length of buffer
 * @return              Number of bytes written
 */
native int GetGamemode(char[] sBuffer, int iLen);

/**
 * Retrieve the XMS Game ID
 *
 * @param sBuffer       Buffer to hold result
 * @param iLen          Maximum length of buffer
 * @return              Number of bytes written
 */
native int GetGameID(char[] sBuffer, int iLen);

/**
 * Retrieve corrected game-time elapsed
 *
 * @return              Seconds elapsed
 */
native float GetTimeElapsed();

/**
 * Retrieve corrected game-time remaining
 *
 * @param bChatTime     Add remaining mp_chattime to return?
 * @return              Seconds remaining
 */
native float GetTimeRemaining(bool bChatTime);

/**************************************************************
 * FORWARDS
 *************************************************************/

/**
 * Called when the Gamestate value changes
 *
 * @param iNew           New Gamestate value
 * @param iOld           Previous Gamestate value
 */
forward void OnGamestateChanged(int iNew, int iOld);

/**
 * Called when a match is started
 */
forward void OnMatchStart();

/**
 * Called when a match ends
 *
 * @param bSuccess       True if the match came to a natural end, false if ended early/cancelled
 */
forward void OnMatchEnd(bool bSuccess);

/**
 * Called when client submits feedback through XMS menu
 *
 * @param sFeedback      Feedback string
 * @param sName          Client name
 * @param sID            Client SteamID
 * @param sGameID        XMS Game ID
 */
forward void OnClientFeedback(const char[] sFeedback, const char[] sName, const char[] sID, const char[] sGameID);


/**************************************************************
 * USEFUL SHORTCUTS
 *************************************************************/

// Is a match in progress?
stock bool IsGameMatch()
{
    int iState = GetGamestate();

    if (iState == GAME_MATCH || iState == GAME_MATCHEX || iState == GAME_MATCHWAIT || iState == GAME_PAUSED) {
        return true;
    }

    return false;
}

// Has the round ended?
stock bool IsGameOver()
{
    int iState = GetGamestate();

    if (iState == GAME_OVER || iState == GAME_CHANGING) {
        return true;
    }

    return false;
}

// Is the current gamemode sMode?
stock bool IsGamemode(const char[] sMode)
{
    char sCurrent[MAX_MODE_LENGTH];
    
    GetGamemode(sCurrent, sizeof(sCurrent));
    
    return StrEqual(sCurrent, sMode, false);
}

// Does sMode support competitive matches?
stock bool IsModeMatchable(const char[] sMode = NULL_STRING)
{
    char sMode2[MAX_MODE_LENGTH];

    if (!strlen(sMode)) {
        GetGamemode(sMode2, sizeof(sMode2));
    }
    else {
        strcopy(sMode2, sizeof(sMode2), sMode);
    }

    return view_as<bool>(GetConfigInt("Matchable", "Gamemodes", sMode2));
}


/**************************************************************
 * XMENU NATIVES
 *************************************************************/

/**
 * (Internal use) Create menu from datapack
 *
 * @param iClient       Client index for translation
 * @param bBackButton   Show back button on non-paginated menu?
 * @param bNumbered     Show option numbers?
 * @param sCommandBase  Command base for menu options
 * @param sTitle        Title of menu
 * @param sMessage      Message of menu
 * @param dPack         Datapack
 * @return              StringMap containing KeyValues for each page
 */
native StringMap XMenu(int iClient, bool bBackButton, bool bNumbered, const char[] sCommandBase, const char[] sTitle, const char[] sMessage, Handle dPack);

/**
 * (Internal use) Create menu from translation strings
 *
 * @param iClient       Client index for translation language
 * @param iTranslate    Translation type
 * @param bBackButton   Show back button on non-paginated menu?
 * @param bNumbered     Show option numbers?
 * @param sCommandBase  Command base for menu options
 * @param sTitle        Title of menu
 * @param sMessage      Message of menu
 * @param ...           Menu options
 * @return              StringMap containing KeyValues for each page
 */
native StringMap XMenuQuick(int iClient, int iTranslate, bool bBackButton, bool bNumbered, const char[] sCommandBase, const char[] sTitle, const char[] sMessage, any ...);
#define XMENU_TRANSLATE_NONE                    0
#define XMENU_TRANSLATE_TITLE                   1
#define XMENU_TRANSLATE_TITLE_MESSAGE           2
#define XMENU_TRANSLATE_TITLE_MESSAGE_OPTIONS   3
#define XMENU_TRANSLATE_TITLE_OPTIONS           4
#define XMENU_TRANSLATE_MESSAGE_OPTIONS         5
#define XMENU_TRANSLATE_MESSAGE                 6
#define XMENU_TRANSLATE_OPTIONS                 7

/**
 * (Internal use) Create menu box without options
 *
 * @param sCommandBase  Command base for menu
 * @param sTitle        Title of menu
 * @param sMessage      Message of menu
 * @param iType         DialogType_Entry or DialogType_Text
 * @return              StringMap containing KeyValues for menu
 */
native StringMap XMenuBox(const char[] sCommandBase, const char[] sTitle, const char[] sMessage, DialogType iType=DialogType_Entry);


/**************************************************************
 * PLUGIN LIBRARY
 *************************************************************/

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
    MarkNativeAsOptional("GetConfigKeys");
    MarkNativeAsOptional("GetConfigString");
    MarkNativeAsOptional("GetConfigInt");
    MarkNativeAsOptional("GetGamestate");
    MarkNativeAsOptional("GetGamemode");
    MarkNativeAsOptional("GetGameID");
    MarkNativeAsOptional("GetTimeElapsed");
    MarkNativeAsOptional("GetTimeRemaining");
    MarkNativeAsOptional("XMenu");
    MarkNativeAsOptional("XMenuQuick");
    MarkNativeAsOptional("XMenuBox");
}
#endif