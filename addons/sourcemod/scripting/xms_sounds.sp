#define PLUGIN_NAME         "XMS - Sounds"
#define PLUGIN_VERSION      "1.13"
#define PLUGIN_DESCRIPTION  "Game sounds for eXtended Match System"
#define PLUGIN_AUTHOR       "harper"
#define PLUGIN_URL          "HL2DM.PRO"
#define UPDATE_URL          "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_sounds.upd"

#define SOUND_CONNECT       "friends/friend_online.wav"
#define SOUND_DISCONNECT    "friends/friend_join.wav"
#define SOUND_MUSIC_0       "music/hl2_song14.mp3"
#define SOUND_MUSIC_1       "music/hl2_song20_submix4.mp3"
#define SOUND_MUSIC_2       "music/hl2_song15.mp3"
#define SOUND_MUSIC_3       "music/hl1_song25_remix3.mp3"
#define SOUND_MUSIC_4       "music/hl1_song10.mp3"
#define SOUND_MUSIC_5       "music/hl2_song23_suitsong3.mp3" // Rare (1/10 chance)

#pragma semicolon 1
#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <updater>

#define REQUIRE_PLUGIN
#pragma newdecls required
#include <hl2dm-xms>

bool IsSoundFading;

/****************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnMapStart()
{
    IsSoundFading = false;
    
    if(LibraryExists("updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnGamestateChanged(int new_state, int old_state)
{
    if(new_state == STATE_POST) PlayRoundEndMusic();
    else if(new_state == STATE_CHANGE && old_state == STATE_POST)
    {
        CreateTimer(0.1, T_SoundFadeTrigger, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnClientPutInServer(int client)
{
    int state = XMS_GetGamestate();
    
    if(state != STATE_MATCH && state != STATE_MATCHEX && state != STATE_MATCHWAIT) PlayGameSoundAll(SOUND_CONNECT); 
    ClientCommand(client, "soundfade 0 0 0 0"); // cancel fade in case of early map change
}

public void PlayRoundEndMusic()
{
    static int  last_rand = -1;
    int         rand;
    float       fadetime;
    
    do rand = GetRandomInt(0, 5);
    while(last_rand == rand || rand == 5 && GetRandomInt(0, 1) != 1);
    
    last_rand = rand;
    fadetime = GetConVarInt(FindConVar("mp_chattime")) - 4.5;
    if(fadetime < 5) fadetime = 0.1;
    
    PlayGameSoundAll(rand == 0 ? SOUND_MUSIC_0 : rand == 1 ? SOUND_MUSIC_1 : rand == 2 ? SOUND_MUSIC_2 : rand == 3 ? SOUND_MUSIC_3 : rand == 4 ? SOUND_MUSIC_4 : SOUND_MUSIC_5);
    CreateTimer(fadetime, T_SoundFadeTrigger, _, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.1, T_SoundFadeAction, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    int state = XMS_GetGamestate();
    
    if(state != STATE_MATCH && state != STATE_MATCHEX && state != STATE_MATCHWAIT) PlayGameSoundAll(SOUND_DISCONNECT);
}

public Action T_SoundFadeTrigger(Handle timer)
{
    IsSoundFading = true;
}

public Action T_SoundFadeAction(Handle timer)
{
    if(IsSoundFading)
    {
        ClientCommandAll("soundfade 100 1 0 5");
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}
