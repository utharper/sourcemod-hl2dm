#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION  "1.0"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xfootsteps.upd"

public Plugin myinfo = {
    name              = "xFootsteps",
    version           = PLUGIN_VERSION,
    description       = "Custom settings for HL2DM footsteps",
    author            = "harper, sidezz",
    url               = PLUGIN_URL
};

/**************************************************************
 * INCLUDES
 *************************************************************/
#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#undef REQUIRE_PLUGIN
#include <updater>
#include <jhl2dm>

/**************************************************************
 * GLOBAL VARS
 *************************************************************/
int    giSelf     = 1;
float  gfVolume   = 1.0;
bool   gbCookie   = true;
bool   gbTeam     = true;
bool   gbEnemy    = true;
bool   gbHardboot = false;
bool   gbTeamplay;
bool   gbLate;
ConVar gCvar;
Cookie gCookie;

/**************************************************************/

public APLRes AskPluginLoad2(Handle hPlugin, bool bLate, char[] sError, int iLen)
{
    gbLate = bLate;
    return APLRes_Success;
}

public void OnPluginStart()
{
    gCvar = FindConVar("sv_footsteps");
    gCookie = RegClientCookie("cl_footsteps", "Enable hearing your own footsteps", CookieAccess_Public);
    RegConsoleCmd("cl_footsteps", Cmd_Footsteps, "Enable/disable hearing your own footsteps (if allowed by server)");

    CreateConVar("xfootsteps_self", "1", "Players hear their own footsteps by default").AddChangeHook(SetVar_Self);
    CreateConVar("xfootsteps_self_setting", "1", "Allow players to set cl_footsteps").AddChangeHook(SetVar_Cookie);
    CreateConVar("xfootsteps_team", "1", "Players hear their team's footsteps?").AddChangeHook(SetVar_Team);
    CreateConVar("xfootsteps_enemy", "1", "Players hear enemy footsteps?").AddChangeHook(SetVar_Enemy);
    CreateConVar("xfootsteps_volume", "1.0", "Volume of footsteps", _, true, 0.1, true, 1.0).AddChangeHook(SetVar_Volume);
    CreateConVar("xfootsteps_hardboot", "0", "Force players to emit rebel \"hardboot\" sound, regardless of playermodel").AddChangeHook(SetVar_Hardboot);
    AutoExecConfig();

    if (LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }

    if (gbLate) {
        ReplicateToAll("0");
    }

    AddNormalSoundHook(OnSound);
    CreateConVar("xfootsteps_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
}

public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnClientCookiesCached(int iClient)
{
    // Set default cookie value.
    if (gbCookie && !ClientCookieHasValue(iClient, gCookie)) {
        SetClientCookieInt(iClient, gCookie, giSelf ? 1 : 0);
    }
}

public void OnMapStart()
{
    gbTeamplay = FindConVar("mp_teamplay").BoolValue;
}

public void OnClientPutInServer(int iClient)
{
    ReplicateTo(iClient, "0");
}

public Action Cmd_Footsteps(int iClient, int iArgs)
{
    if (!iArgs)
    {
        if (gbCookie) {
            ReplyToCommand(iClient, "\"cl_footsteps\" = \"%i\"", GetClientCookieInt(iClient, gCookie));
            ReplyToCommand(iClient, " - Enable hearing your own footsteps");
        }
        else {
            ReplyToCommand(iClient, "This feature is disabled by the server.");
        }
    }
    else {
        SetClientCookieInt(iClient, gCookie, GetCmdArgInt(1));
    }

    return Plugin_Handled;
}

public Action OnSound(int iClients[MAXPLAYERS], int &iNumClients, char sSample[PLATFORM_MAX_PATH], int &iEntity, int &iChannel, float &fVolume, int &iLevel, int &iPitch, int &iFlags, char sEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (iEntity < 1 || iEntity > MaxClients || !IsClientInGame(iEntity)) {
        return Plugin_Continue;
    }

    if (StrContains(sSample, "npc/metropolice/gear", false) != -1 || StrContains(sSample, "npc/combine_soldier/gear", false) != -1)
    {
        if (gbHardboot) {
            // Force rebel sound.
            Format(sSample, sizeof(sSample), "npc/footsteps/hardboot_generic%i.wav", StringToInt(sSample[StrContains(sSample, ".wav", false) - 1]));
        }
    }
    else if (StrContains(sSample, "npc/footsteps/hardboot_generic", false) == -1) {
        // Not a footstep sound.
        return Plugin_Continue;
    }

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientConnected(iClient) || !IsClientInGame(iClient)) {
            continue;
        }

        if (iEntity == iClient || (IsClientObserver(iClient) && GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget") == iEntity) )
        {
            // Footstep originates from the player, or who he is spectating
            if (giSelf == 0 || (gbCookie && GetClientCookieInt(iClient, gCookie) == 0) ) {
                continue;
            }
        }
        else if (GetClientTeam(iEntity) == GetClientTeam(iClient))
        {
            if (gbTeamplay && !gbTeam) {
                continue;
            }
            else if (!gbTeamplay && !gbEnemy) {
                continue;
            }
        }
        else if (!gbEnemy) {
            continue;
        }

        EmitSoundToClient(iClient, sSample, iEntity, iChannel, iLevel, iFlags, fVolume * gfVolume, iPitch);
    }

    return Plugin_Handled;
}

void ReplicateTo(int iClient, const char[] sValue)
{
    if (IsClientInGame(iClient) && !IsFakeClient(iClient)) {
        gCvar.ReplicateToClient(iClient, sValue);
    }
}

void ReplicateToAll(const char[] sValue)
{
    for (int iClient = 1; iClient <= MaxClients; iClient++) {
        ReplicateTo(iClient, sValue);
    }
}

void SetVar_Self(ConVar cVar, const char[] sOld, const char[] sNew) {
    giSelf = StringToInt(sNew);
}
void SetVar_Team(ConVar cVar, const char[] sOld, const char[] sNew) {
    gbTeam = view_as<bool>(StringToInt(sNew));
}
void SetVar_Enemy(ConVar cVar, const char[] sOld, const char[] sNew) {
    gbEnemy = view_as<bool>(StringToInt(sNew));
}
void SetVar_Volume(ConVar cVar, const char[] sOld, const char[] sNew) {
    gfVolume = StringToFloat(sNew);
}
void SetVar_Hardboot(ConVar cVar, const char[] sOld, const char[] sNew) {
    gbHardboot = view_as<bool>(StringToInt(sNew));
}
void SetVar_Cookie(ConVar cVar, const char[] sOld, const char[] sNew) {
    gbCookie = view_as<bool>(StringToInt(sNew));
}

public void OnPluginEnd()
{
    ReplicateToAll("1");
}