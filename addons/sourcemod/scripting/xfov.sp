#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION  "2.1"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xfov.upd"

public Plugin myinfo = {
    name              = "xFov - eXtended Field Of View",
    version           = PLUGIN_VERSION,
    description       = "Enables support for custom player FOV values",
    author            = "harper",
    url               = PLUGIN_URL
};

/**************************************************************
 * INCLUDES
 *************************************************************/
#include <sourcemod>
#include <clientprefs>
#include <morecolors>
#include <sdkhooks>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <updater>

#define REQUIRE_PLUGIN
#include <jhl2dm>

/**************************************************************
 * GLOBAL VARS
 *************************************************************/
#define ZOOM_NONE 0
#define ZOOM_XBOW 1
#define ZOOM_SUIT 2
#define ZOOM_TOGL 3
#define FIRSTPERSON 4

enum struct _gConVar
{
    ConVar sv_tags;
    ConVar xfov_minfov;
    ConVar xfov_defaultfov;
    ConVar xfov_maxfov;
}
_gConVar gConVar;

int    giZoom[MAXPLAYERS + 1];
bool   gbModtags;
Handle gcFov;

/**************************************************************/

public void OnPluginStart()
{
    LoadTranslations("xfov.phrases.txt");

    gcFov = RegClientCookie("hl2dm_fov", "Field-of-view value", CookieAccess_Public);

    gConVar.xfov_minfov     = CreateConVar("xfov_minfov", "90", "Minimum FOV allowed on server");
    gConVar.xfov_defaultfov = CreateConVar("xfov_defaultfov", "90", "Default FOV of players on server");
    gConVar.xfov_maxfov     = CreateConVar("xfov_maxfov", "110", "Maximum FOV allowed on server");
    
    gConVar.sv_tags         = FindConVar("sv_tags");
    gConVar.sv_tags.AddChangeHook(OnTagsChanged);
    
    AutoExecConfig();

    RegConsoleCmd("sm_fov", Command_FOV, "Set your desired field-of-view value");
    AddCommandListener(OnClientChangeFOV, "fov");
    AddCommandListener(OnClientToggleZoom, "toggle_zoom");

    MC_AddJColors();

    if (LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }

    CreateConVar("xfov_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    AddPluginTag();
}

public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnTagsChanged(Handle hConvar, const char[] sOldValue, const char[] sNewValue)
{
    if (!gbModtags) {
        AddPluginTag();
    }
}

void AddPluginTag()
{
    char sTags[128];

    gConVar.sv_tags.GetString(sTags, sizeof(sTags));

    if (StrContains(sTags, "xFov") == -1)
    {
        StrCat(sTags, sizeof(sTags), sTags[0] != 0 ? ",xFov" : "xFov");
        gbModtags = true;
        gConVar.sv_tags.SetString(sTags);
        gbModtags = false;
    }
}

public void OnClientPutInServer(int iClient)
{
    SDKHook(iClient, SDKHook_WeaponSwitchPost, OnClientSwitchWeapon);
}

public Action Command_FOV(int iClient, int iArgs)
{
    RequestFOV(iClient, GetCmdArgInt(1));

    return Plugin_Handled;
}

public Action OnClientChangeFOV(int iClient, const char[] sCommand, int iArgs)
{
    RequestFOV(iClient, GetCmdArgInt(1));

    return Plugin_Handled;
}

void RequestFOV(int iClient, int iFov)
{
    if (iFov < GetConVarInt(gConVar.xfov_minfov) || iFov > GetConVarInt(gConVar.xfov_maxfov))
    {
        MC_ReplyToCommand(iClient, "%t", "xfov_fail", GetConVarInt(gConVar.xfov_minfov), GetConVarInt(gConVar.xfov_maxfov));
    }
    else
    {
        SetClientCookieInt(iClient, gcFov, iFov);
        MC_ReplyToCommand(iClient, "%t", "xfov_success", iFov);
    }
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAngles[3], int &iWeapon)
{
    if (AreClientCookiesCached(iClient))
    {
        static int iLastButtons[MAXPLAYERS + 1];

        int iFov = GetClientCookieInt(iClient, gcFov);

        if (iFov < GetConVarInt(gConVar.xfov_minfov) || iFov > GetConVarInt(gConVar.xfov_maxfov)) {
            // fov is out of bounds, reset
            iFov = GetConVarInt(gConVar.xfov_defaultfov);
        }

        if (!IsClientObserver(iClient) && IsPlayerAlive(iClient))
        {
            char sWeapon[32];

            GetClientWeapon(iClient, sWeapon, sizeof(sWeapon));

            if (giZoom[iClient] == ZOOM_XBOW || giZoom[iClient] == ZOOM_TOGL) {
                // block suit zoom while xbow/toggle-zoomed
                iButtons &= ~IN_ZOOM;
            }

            if (giZoom[iClient] == ZOOM_TOGL)
            {
                if (StrEqual(sWeapon, "weapon_crossbow")) {
                    // block xbow zoom while toggle zoomed
                    iButtons &= ~IN_ATTACK2;
                }

                SetEntProp(iClient, Prop_Send, "m_iDefaultFOV", 90);
                return Plugin_Continue;
            }

            if (iButtons & IN_ZOOM)
            {
                if (!(iLastButtons[iClient] & IN_ZOOM) && !giZoom[iClient]) {
                    // suit zooming
                    giZoom[iClient] = ZOOM_SUIT;
                }
            }
            else if (giZoom[iClient] == ZOOM_SUIT) {
                // no longer suit zooming
                giZoom[iClient] = ZOOM_NONE;
            }

            if ((StrEqual(sWeapon, "weapon_crossbow") && (iButtons & IN_ATTACK2) && !(iLastButtons[iClient] & IN_ATTACK2)) || (!StrEqual(sWeapon, "weapon_crossbow") && giZoom[iClient] == ZOOM_XBOW))
            {
                // xbow zoom cycle
                giZoom[iClient] = (giZoom[iClient] == ZOOM_XBOW ? ZOOM_NONE : ZOOM_XBOW);
            }
        }
        else {
            giZoom[iClient] = ZOOM_NONE;
        }

        // set values
        if (giZoom[iClient] || (IsClientObserver(iClient) && GetEntProp(iClient, Prop_Send, "m_iObserverMode") == FIRSTPERSON)) {
            SetEntProp(iClient, Prop_Send, "m_iDefaultFOV", 90);
        }
        else if (giZoom[iClient] == ZOOM_NONE) {
            SetEntProp(iClient, Prop_Send, "m_iFOV", iFov);
            SetEntProp(iClient, Prop_Send, "m_iDefaultFOV", iFov);
        }

        iLastButtons[iClient] = iButtons;
    }

    return Plugin_Continue;
}

public Action OnClientToggleZoom(int iClient, const char[] sCommand, int iArgs)
{
    if (giZoom[iClient] != ZOOM_NONE)
    {
        if (giZoom[iClient] == ZOOM_TOGL || giZoom[iClient] == ZOOM_SUIT) {
            giZoom[iClient] = ZOOM_NONE;
        }
    }
    else {
        giZoom[iClient] = ZOOM_TOGL;
    }

    return Plugin_Continue;
}

public Action OnClientSwitchWeapon(int iClient, int iWeapon)
{
    if (giZoom[iClient] == ZOOM_TOGL) {
        giZoom[iClient] = ZOOM_NONE;
    }

    return Plugin_Continue;
}