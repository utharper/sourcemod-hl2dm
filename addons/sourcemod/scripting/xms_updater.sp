#define PLUGIN_NAME			"XMS - Updater"
#define PLUGIN_VERSION		"1.12"
#define PLUGIN_DESCRIPTION	"Updater plugin for eXtended Match System"
#define PLUGIN_AUTHOR		"harper"
#define PLUGIN_URL			"hl2dm.pro"

#define UPDATE_URL			"https://hl2dm.pro/update.upd"

#pragma semicolon 1
#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <updater>

#pragma newdecls required

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{
	if(LibraryExists("updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "updater")) Updater_AddPlugin(UPDATE_URL);
}
