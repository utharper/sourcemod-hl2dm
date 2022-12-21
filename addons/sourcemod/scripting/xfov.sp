#pragma semicolon 1

#define PLUGIN_VERSION  "2.0"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/xfov.upd"

public Plugin myinfo = {
    name              = "xfov (eXtended Field Of View)",
    version           = PLUGIN_VERSION,
    description       = "Enables support for custom player FOV values",
    author            = "harper",
    url               = PLUGIN_URL
};

/**************************************************************/

#include <sourcemod>
#include <clientprefs>
#include <morecolors>
#include <sdkhooks>
#include <smlib>

#undef REQUIRE_PLUGIN
#include <updater>

#define REQUIRE_PLUGIN
#pragma newdecls required
#include <jhl2dm>

/**************************************************************/

#define ZOOM_NONE 0
#define ZOOM_XBOW 1
#define ZOOM_SUIT 2
#define ZOOM_TOGL 3
#define FIRSTPERSON 4

/**************************************************************/

int    giClientZoom[MAXPLAYERS + 1];

Handle ghCookie;

ConVar ghConVarMin,
       ghConVarDefault,
       ghConVarMax;

/**************************************************************/

public void OnPluginStart()
{
    LoadTranslations("xfov.phrases.txt");

    ghCookie = RegClientCookie("hl2dm_fov", "Field-of-view value", CookieAccess_Public);

    ghConVarMin     = CreateConVar("xfov_minfov", "90", "Minimum FOV allowed on server");
    ghConVarDefault = CreateConVar("xfov_defaultfov", "90", "Default FOV of players on server");
    ghConVarMax     = CreateConVar("xfov_maxfov", "110", "Maximum FOV allowed on server");
    AutoExecConfig();

    CreateConVar("xfov_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);

    RegConsoleCmd("sm_fov", Command_FOV, "Set your desired field-of-view value");
    AddCommandListener(OnClientChangeFOV, "fov");
    AddCommandListener(OnClientToggleZoom, "toggle_zoom");

    RegisterColors();

    if (LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
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
    if (iFov < GetConVarInt(ghConVarMin) || iFov > GetConVarInt(ghConVarMax)) {
        MC_ReplyToCommand(iClient, "%t", "xfov_fail", GetConVarInt(ghConVarMin), GetConVarInt(ghConVarMax));
    }
    else
    {
        char sFov[4];

        IntToString(iFov, sFov, sizeof(sFov));
        SetClientCookie(iClient, ghCookie, sFov);
        MC_ReplyToCommand(iClient, "%t", "xfov_success", iFov);
    }
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAngles[3], int &iWeapon)
{
    if (AreClientCookiesCached(iClient))
    {
        static int iLastButtons[MAXPLAYERS + 1];

        int iFov = GetClientCookieInt(iClient, ghCookie);

        if (iFov < GetConVarInt(ghConVarMin) || iFov > GetConVarInt(ghConVarMax)) {
            // fov is out of bounds, reset
            iFov = GetConVarInt(ghConVarDefault);
        }

        if (!IsClientObserver(iClient) && IsPlayerAlive(iClient))
        {
            char sWeapon[32];

            GetClientWeapon(iClient, sWeapon, sizeof(sWeapon));

            if (giClientZoom[iClient] == ZOOM_XBOW || giClientZoom[iClient] == ZOOM_TOGL) {
                // block suit zoom while xbow/toggle-zoomed
                iButtons &= ~IN_ZOOM;
            }

            if (giClientZoom[iClient] == ZOOM_TOGL)
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
                if (!(iLastButtons[iClient] & IN_ZOOM) && !giClientZoom[iClient]) {
                    // suit zooming
                    giClientZoom[iClient] = ZOOM_SUIT;
                }
            }
            else if (giClientZoom[iClient] == ZOOM_SUIT) {
                // no longer suit zooming
                giClientZoom[iClient] = ZOOM_NONE;
            }

            if ((StrEqual(sWeapon, "weapon_crossbow") && (iButtons & IN_ATTACK2) && !(iLastButtons[iClient] & IN_ATTACK2)) || (!StrEqual(sWeapon, "weapon_crossbow") && giClientZoom[iClient] == ZOOM_XBOW))
            {
                // xbow zoom cycle
                giClientZoom[iClient] = (giClientZoom[iClient] == ZOOM_XBOW ? ZOOM_NONE : ZOOM_XBOW);
            }
        }
        else {
            giClientZoom[iClient] = ZOOM_NONE;
        }

        // set values
        if (giClientZoom[iClient] || (IsClientObserver(iClient) && GetEntProp(iClient, Prop_Send, "m_iObserverMode") == FIRSTPERSON)) {
            SetEntProp(iClient, Prop_Send, "m_iDefaultFOV", 90);
        }
        else if (giClientZoom[iClient] == ZOOM_NONE) {
            SetEntProp(iClient, Prop_Send, "m_iFOV", iFov);
            SetEntProp(iClient, Prop_Send, "m_iDefaultFOV", iFov);
        }

        iLastButtons[iClient] = iButtons;
    }

    return Plugin_Continue;
}

public Action OnClientToggleZoom(int iClient, const char[] sCommand, int iArgs)
{
    if (giClientZoom[iClient] != ZOOM_NONE)
    {
        if (giClientZoom[iClient] == ZOOM_TOGL || giClientZoom[iClient] == ZOOM_SUIT) {
            giClientZoom[iClient] = ZOOM_NONE;
        }
    }
    else {
        giClientZoom[iClient] = ZOOM_TOGL;
    }

    return Plugin_Continue;
}

public Action OnClientSwitchWeapon(int iClient, int iWeapon)
{
    if (giClientZoom[iClient] == ZOOM_TOGL) {
        giClientZoom[iClient] = ZOOM_NONE;
    }

    return Plugin_Continue;
}