#define PLUGIN_VERSION  "2.0"
#define PLUGIN_URL      "www.hl2dm.community"
#define PLUGIN_UPDATE   "http://raw.githubusercontent.com/utharper/sourcemod-hl2dm/master/addons/sourcemod/extended_fov.upd"

public Plugin myinfo = {
    name              = "xfov (eXtended Field Of View)",
    version           = PLUGIN_VERSION,
    description       = "Enables support for custom player FOV values",
    author            = "harper",
    url               = PLUGIN_URL
};

/**************************************************************************************************/

#pragma semicolon 1
#pragma newdecls optional
#include <sourcemod>
#include <clientprefs>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <updater>

#pragma newdecls required
#include <jhl2dm>

/**************************************************************************************************/

ConVar ghConVarMin;
ConVar ghConVarDefault;
ConVar ghConVarMax;
Handle ghCookie;

int giClientZoom[MAXPLAYERS + 1];
enum(+=1) { ZOOM_NONE, ZOOM_XBOW, ZOOM_SUIT, ZOOM_TOGL, FIRSTPERSON }

/**************************************************************************************************/

public void OnPluginStart()
{
    LoadTranslations("xfov.phrases.txt");
    
    ghCookie = RegClientCookie("hl2dm_fov", "Field-of-view value", CookieAccess_Public);
    ghConVarMin = CreateConVar("xfov_minfov", "90", "Minimum FOV allowed on server");
    ghConVarDefault = CreateConVar("xfov_defaultfov", "90", "Default FOV of players on server");
    ghConVarMax = CreateConVar("xfov_maxfov", "110", "Maximum FOV allowed on server");
    CreateConVar("xfov_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    
    AutoExecConfig();
    
    RegConsoleCmd("sm_fov", Command_FOV, "Set your desired field-of-view value");
    AddCommandListener(OnClientChangeFOV, "fov");
    AddCommandListener(OnClientToggleZoom, "toggle_zoom");
    
    MC_AddColor("N", COLOR_NORMAL);
    MC_AddColor("I", COLOR_INFORMATION);
    MC_AddColor("H", COLOR_HIGHLIGHT);
    MC_AddColor("E", COLOR_ERROR);
    
    if(LibraryExists("updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) {
        Updater_AddPlugin(PLUGIN_UPDATE);
    }
}

public Action Command_FOV(int client, int args)
{
    RequestFOV(client, GetCmdArgInt(1));
}

public Action OnClientChangeFOV(int client, const char[] command, int args)
{
    RequestFOV(client, GetCmdArgInt(1));
}

void RequestFOV(int client, int fov)
{
    if(fov < GetConVarInt(ghConVarMin) || fov > GetConVarInt(ghConVarMax)) {
        MC_ReplyToCommand(client, "%t", "xfov_fail", GetConVarInt(ghConVarMin), GetConVarInt(ghConVarMax));
    }
    else {
        char sFov[4];
        IntToString(fov, sFov, sizeof(sFov));
        SetClientCookie(client, ghCookie, sFov);
        MC_ReplyToCommand(client, "%t", "xfov_success", fov);
    }
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(AreClientCookiesCached(client))
    {
        static int lastbuttons[MAXPLAYERS + 1];
        
        int fov = GetClientCookieInt(client, ghCookie);
        
        if(fov < GetConVarInt(ghConVarMin) || fov > GetConVarInt(ghConVarMax)) {
            // fov is out of bounds, reset
            fov = GetConVarInt(ghConVarDefault);
        }
        
        if(!IsClientObserver(client) && IsPlayerAlive(client))
        {
            char sWeapon[32];
            
            GetClientWeapon(client, sWeapon, sizeof(sWeapon));
            
            if(giClientZoom[client] == ZOOM_XBOW || giClientZoom[client] == ZOOM_TOGL) {
                // block suit zoom while xbow/toggle-zoomed
                buttons &= ~IN_ZOOM;
            }
            
            if(giClientZoom[client] == ZOOM_TOGL)
            {
                if(StrEqual(sWeapon, "weapon_crossbow")) {
                    // block xbow zoom while toggle zoomed
                    buttons &= ~IN_ATTACK2;
                }
                
                SetEntProp(client, Prop_Send, "m_iDefaultFOV", 90);
                return Plugin_Continue;
            }
            
            if(buttons & IN_ZOOM)
            {
                if(!(lastbuttons[client] & IN_ZOOM) && !giClientZoom[client]) {
                    // suit zooming
                    giClientZoom[client] = ZOOM_SUIT;
                }
            }
            else if(giClientZoom[client] == ZOOM_SUIT) {
                // no longer suit zooming
                giClientZoom[client] = ZOOM_NONE;
            }
            
            if((StrEqual(sWeapon, "weapon_crossbow") && (buttons & IN_ATTACK2) && !(lastbuttons[client] & IN_ATTACK2)) || (!StrEqual(sWeapon, "weapon_crossbow") && giClientZoom[client] == ZOOM_XBOW))
            {
                // xbow zoom cycle
                giClientZoom[client] = (giClientZoom[client] == ZOOM_XBOW ? ZOOM_NONE : ZOOM_XBOW);
            }
        }
        else {
            giClientZoom[client] = ZOOM_NONE;
        }
        
        // set values
        if(giClientZoom[client] || (IsClientObserver(client) && GetEntProp(client, Prop_Send, "m_iObserverMode") == FIRSTPERSON)) {
            SetEntProp(client, Prop_Send, "m_iDefaultFOV", 90);
        }
        else if(giClientZoom[client] == ZOOM_NONE) {
            SetEntProp(client, Prop_Send, "m_iFOV", fov);
            SetEntProp(client, Prop_Send, "m_iDefaultFOV", fov);
        }
        
        lastbuttons[client] = buttons;
    }
    
    return Plugin_Continue;
}

public Action OnClientToggleZoom(int client, const char[] command, int args)
{
    if(giClientZoom[client] != ZOOM_NONE) {
        if(giClientZoom[client] == ZOOM_TOGL || giClientZoom[client] == ZOOM_SUIT) {
            giClientZoom[client] = ZOOM_NONE;
        }
    }
    else {
        giClientZoom[client] = ZOOM_TOGL;
    }
}