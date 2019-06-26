#define PLUGIN_NAME			"XMS - SourceTV"
#define PLUGIN_VERSION		"1.12"
#define PLUGIN_DESCRIPTION	"SourceTV controller for eXtended Match System"
#define PLUGIN_AUTHOR		"harper"
#define PLUGIN_URL			"hl2dm.pro"

#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <morecolors>

#pragma newdecls required
#include <hl2dm_xms>

char	TvName[MAX_NAME_LENGTH],
		DemoName[256],
		DemoPath[PLATFORM_MAX_PATH];
	
bool 	IsRecording;

/******************************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnAllPluginsLoaded()
{
	XMS_GetConfigString(TvName, sizeof(TvName), "ScoresName", "SourceTV");
	XMS_GetConfigString(DemoPath, sizeof(DemoPath), "DemoPath", "SourceTV");
}

public void OnGamestateChanged(int new_state, int old_state)
{
	if(new_state == STATE_MATCHWAIT && !IsRecording) StartRecord();
	else if((new_state == STATE_POST || new_state == STATE_CHANGE) && IsRecording) StopRecord(false);
	else if(new_state == STATE_DEFAULT && IsRecording) StopRecord(true);
}

void StartRecord()
{
	char timedate[22],
		map[MAX_MAP_LENGTH],
		mode[MAX_MODE_LENGTH];
	
	FormatTime(timedate, sizeof(timedate), "%Y%m%d-%Hh%Mm");
	GetCurrentMap(map, sizeof(map));
	XMS_GetGamemode(mode, sizeof(mode));
	XMS_GetGameID(DemoName, sizeof(DemoName));
	ServerCommand("tv_record %s/%s", DemoPath, DemoName);
	
	IsRecording = true;
}

void StopRecord(bool early)
{
	if(early)
	{
		char demofile[PLATFORM_MAX_PATH];
		
		BuildPath(Path_SM, demofile, PLATFORM_MAX_PATH, "../../%s/%s.dem", DemoPath, DemoName);
		DeleteFile(demofile);
		
		CPrintToChatAll("%sMatch ended early - SourceTV demo not saved.", CLR_INFO);
	}
	else CPrintToChatAll("%sMatch saved to %s%s.dem", CLR_MAIN, CLR_HIGH, DemoName);
	
	ServerCommand("tv_stoprecord");
	IsRecording = false;
}
