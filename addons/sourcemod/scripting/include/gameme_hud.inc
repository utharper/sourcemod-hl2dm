#if defined _gameme_hud_included
    #endinput
#endif
#define _gameme_hud_included

#define GM_RANK 0     // Player rank
#define GM_PRE_RANK 1 // Player rank as of when the current round started

#define GM_POINTS 2
#define GM_PRE_POINTS 3

#define GM_KILLS 4
#define GM_PRE_KILLS 5

#define GM_DEATHS 6
#define GM_PRE_DEATHS 7

#define GM_SUICIDES 8
#define GM_PRE_SUICIDES 9

#define GM_HEADSHOTS 10
#define GM_PRE_HEADSHOTS 11

#define GM_HPK 12
#define GM_PRE_HPK 13

#define GM_ACCURACY 14
#define GM_PRE_ACCURACY 15

#define GM_KILLSPREE 16
#define GM_PRE_KILLSPREE 17

#define GM_DEATHSPREE 18
#define GM_PRE_DEATHSPREE 19

#define GM_KPD 20
#define GM_PRE_KPD 21

#define GM_PLAYTIME 22 // Total player time
#define GM_PRETIME 23  // Playtime provided by gameME (updated on map change)
#define GM_MAPTIME 24  // Playtime in the current map session

// Change in total values during current round (can be negative):
#define GM_ROUNDPOINTS 25
#define GM_ROUNDKILLS 26
#define GM_ROUNDDEATHS 27
#define GM_ROUNDSUICIDES 28
#define GM_ROUNDHEADSHOTS 29

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

stock char[] gameME_FetchPlayerChar(int iClient, int iField, bool bRoundFloat=false)
{
    char sValue[64];

    gameME_FetchPlayerData(sValue, sizeof(sValue), iClient, iField, bRoundFloat);

    return sValue;
}

stock int gameME_FetchPlayerInt(int iClient, int iField)
{
    char sValue[64];

    if(gameME_FetchPlayerData(sValue, sizeof(sValue), iClient, iField)) {
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