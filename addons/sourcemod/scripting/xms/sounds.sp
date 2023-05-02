// Game sounds:
#define SOUND_CONNECT        "friends/friend_online.wav"
#define SOUND_DISCONNECT     "friends/friend_join.wav"
#define SOUND_ACTIONPENDING  "buttons/blip1.wav"
#define SOUND_ACTIONCOMPLETE "hl1/fvox/beep.wav"
#define SOUND_COMMANDFAIL    "resource/warning.wav"
#define SOUND_ACTIVATED      "hl1/fvox/activated.wav"
#define SOUND_DEACTIVATED    "hl1/fvox/deactivated.wav"
#define SOUND_MENUACTION     "weapons/slam/buttonclick.wav"
#define SOUND_REPLENISH      "items/medshot4.wav"
char gsMusicPath[6][PLATFORM_MAX_PATH] =
{
    "music/hl2_song14.mp3",
    "music/hl2_song20_submix0.mp3",
    "music/hl2_song15.mp3",
    "music/hl1_song25_remix3.mp3",
    "music/hl1_song10.mp3",
    "music/hl2_song12_long.mp3"
};

// Custom sounds:
#define SOUND_VOTECALLED     "xms/votecall.wav"
#define SOUND_VOTEFAILED     "xms/votefail.wav"
#define SOUND_VOTESUCCESS    "xms/voteaccept.wav"
#define SOUND_GG             "xms/gg.mp3"

/**************************************************************
 * END OF ROUND MUSIC
 *************************************************************/
void PlayRoundEndMusic()
{
    static int iRan;

    float fTime = gConVar.mp_chattime.IntValue - 4.5;
    int   i;

    do {
        i = Math_GetRandomInt(0, 5);
    } while (i == iRan);

    iRan = i;

    for (int iClient = 1; iClient <= MaxClients; iClient++) {
        if (GetClientCookieBool(gSounds.cMusic, iClient)) {
            QueryClientConVar(iClient, "snd_musicvolume", PlayMusicAtClientVolume, iRan);
        }
    }
    CreateTimer(fTime < 5 ? 0.1 : fTime, T_SoundFadeTrigger, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void PlayMusicAtClientVolume(QueryCookie cookie, int iClient, ConVarQueryResult result, const char[] sName, const char[] sValue, int iPos)
{
    float fVolume = StringToFloat(sValue);

    if (fVolume < 0 || fVolume > 1) {
        fVolume = 0.5;
    }

    EmitSoundToClient(iClient, gsMusicPath[iPos], _, _, _, _, fVolume);
}

public Action T_SoundFadeTrigger(Handle hTimer)
{
    ClientCommandAll("soundfade 100 1 0 5");
    SetGamestate(GAME_CHANGING);

    return Plugin_Handled;
}

/**************************************************************
 * MISC SOUNDS
 *************************************************************/
void PrepareSound(const char[] sName)
{
    char sPath[PLATFORM_MAX_PATH];

    Format(sPath, sizeof(sPath), "sound/%s", sName);
    PrecacheSound(sName);
    AddFileToDownloadsTable(sPath);
}

void IfCookiePlaySound(Handle hCookie, int iClient, const char[] sFile, bool bUnset=true)
{
    if (GetClientCookieBool(hCookie, iClient, bUnset)) {
        ClientCommand(iClient, "playgamesound %s", sFile);
    }
}

void IfCookiePlaySoundAll(Handle hCookie, const char[] sFile, bool bUnset=true)
{
    for (int iClient = 1; iClient <= MaxClients; iClient++) {
        IfCookiePlaySound(hCookie, iClient, sFile, bUnset);
    }
}