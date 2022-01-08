#if defined _gameme_hud_included
    #endinput
#endif
#define _gameme_hud_included

enum(+=1)
{
    // Player rank      // Player rank as of when the current round started
    GM_RANK,            GM_PRE_RANK,
    
    GM_POINTS,          GM_PRE_POINTS,
    GM_KILLS,           GM_PRE_KILLS,
    GM_DEATHS,          GM_PRE_DEATHS,
    GM_SUICIDES,        GM_PRE_SUICIDES,
    GM_HEADSHOTS,       GM_PRE_HEADSHOTS,
    GM_HPK,             GM_PRE_HPK,
    GM_ACCURACY,        GM_PRE_ACCURACY,
    GM_KILLSPREE,       GM_PRE_KILLSPREE,
    GM_DEATHSPREE,      GM_PRE_DEATHSPREE,
    GM_KPD,             GM_PRE_KPD,
    
    GM_PLAYTIME,    // Total player time
    GM_PRETIME,     // Playtime provided by gameME (updated on map change)
    GM_MAPTIME,     // Playtime in the current map session
    
    // Change in total values during current round (can be negative):
    GM_ROUNDPOINTS, GM_ROUNDKILLS, GM_ROUNDDEATHS, GM_ROUNDSUICIDES, GM_ROUNDHEADSHOTS
}

/**************************************************************/

/**
 * Check whether stats are available to fetch.
 *
 * @return              True if available, false if not
 */
native bool gameME_StatsInitialised();

/**
 * Check whether a player is ranked and we can fetch their stats
 *
 * @param iClient       Client index
 * @return              True if available, false if not
 */
native bool gameME_IsPlayerRanked(int iClient);

/**
 * Retrieve the given stats field for client
 *
 * @param sBuffer       Buffer to hold result
 * @param iLen          Maximum length of buffer
 * @param iClient       Client index
 * @param iField        Stats field index
 * @param bRoundFloat   Round floating point values to nearest whole
 * @return              Number of bytes written
 */
native int gameME_FetchPlayerData(char[] sBuffer, int iLen, int iClient, int iField, bool bRoundFloat=false);

/**
 * Retrieve the <iRank> player from the top 10 list.
 *
 * @param iRank         Rank to fetch, from 1-10
 * @param sName         String to hold player name
 * @param iLen          Maximum length of name
 * @return              Player's number of points, or -1 on failure.
 */
native int gameME_FetchTop10PlayerData(int iRank, char[] sName, int iLen);

/**************************************************************/

stock char gameME_FetchPlayerChar(int iClient, int iField, bool bRoundFloat=false)
{
    char sValue[64];
    
    gameME_FetchPlayerData(sValue, sizeof(sValue), iClient, iField, bRoundFloat);
    
    return sValue;
}

stock int gameME_FetchPlayerInt(int iClient, int iField)
{
    char sValue[64];
    
    if (gameME_FetchPlayerData(sValue, sizeof(sValue), iClient, iField)) {
        return StringToInt(sValue);
    }
    
    return -1;
}

stock float gameME_FetchPlayerFloat(int iClient, int iField, bool bRoundFloat=false)
{
    char  sValue[64];
    float fValue = -1.0;
    
    if (gameME_FetchPlayerData(sValue, sizeof(sValue), iClient, iField, bRoundFloat)) {
        fValue = StringToFloat(sValue);
    }
    
    return fValue;
}

/**************************************************************/

public SharedPlugin __pl_gameme_hud =
{
    name = "gameme_hud",
    file = "gameme_hud.smx", 
    #if defined REQUIRE_PLUGIN
        required = 1, 
    #else
        required = 0, 
    #endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_gameme_hud_SetNTVOptional()
{
    MarkNativeAsOptional("gameME_StatsInitialised");
    MarkNativeAsOptional("gameME_IsPlayerRanked");
    MarkNativeAsOptional("gameME_FetchPlayerData");
    MarkNativeAsOptional("gameME_FetchTop10PlayerData");
}
#endif