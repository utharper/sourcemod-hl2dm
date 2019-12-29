#define PLUGIN_VERSION "1.0"
#define UPDATE_URL     "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_exfov.upd"

public Plugin myinfo=
{
    name        = "XMS - Extended FOV (standalone)",
    version     = PLUGIN_VERSION,
    description = "Adds support for increased FOV on HL2DM servers",
    author      = "harper <www.hl2dm.pro>",
    url         = "www.hl2dm.pro"
};

/******************************************************************/

#pragma semicolon 1
#include <sourcemod>
#include <clientprefs>
#include <morecolors>

#undef REQUIRE_PLUGIN
 #include <updater>
 
 #pragma newdecls required
  #include <hl2dm-xms>
#define REQUIRE_PLUGIN
 
/******************************************************************/

#define MIN_FOV 90
#define MAX_FOV 120
#define DEFAULT 90

Handle Cookie_FOV;
int    ClientZoom[MAXPLAYERS + 1]; // 0=nozoom, 1=xbow, 2=suitzoom, 3=togglezoom

/******************************************************************/

public void OnPluginStart()
{
    CreateConVar("hl2dm-xms_exfov_version", PLUGIN_VERSION, _, FCVAR_NOTIFY);
    
    Cookie_FOV = RegClientCookie("xms_fov", "Field-of-view value", CookieAccess_Public);
    RegConsoleCmd("sm_fov", Command_FOV, "Set your desired field-of-view value");
    
    AddCommandListener(LCommand_ToggleZoom, "toggle_zoom");
    AddCommandListener(LCommand_FOV       , "fov");
    
    if(LibraryExists("updater"))  Updater_AddPlugin(UPDATE_URL);
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) Updater_AddPlugin(UPDATE_URL);
}

public Action Command_FOV(int client, int args)
{
    RequestFOV(client, GetCmdArgInt(1));
}

public Action LCommand_FOV(int client, const char[] command, int args)
{
    RequestFOV(client, GetCmdArgInt(1));
}

public Action LCommand_ToggleZoom(int client, const char[] command, int args)
{ 
    ClientZoom[client] = (ClientZoom[client] == 3) ? 0 : 3;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(AreClientCookiesCached(client))
    {
        static int lastbuttons[MAXPLAYERS + 1];
        
        int fov = GetClientCookieInt(client, Cookie_FOV);

        if(fov < MIN_FOV || fov > MAX_FOV)
        {
            fov = DEFAULT;
        }
        
        if(!IsClientObserver(client))
        {
            char sWeapon[32];
            
            GetClientWeapon(client, sWeapon, sizeof(sWeapon));
            
            if(ClientZoom[client] == 1 || ClientZoom[client] == 3)
            {
                // block suit zoom while xbow/toggle-zoomed
                buttons &= ~IN_ZOOM;
            }
        
            if(ClientZoom[client] == 3)
            {
                if(StrEqual(sWeapon, "weapon_crossbow"))
                {
                    // block xbow zoom while toggle zoomed
                    buttons &= ~IN_ATTACK2;
                }
                
                //SetEntProp(client, Prop_Send, "m_iFOV", 18);
                SetEntProp(client, Prop_Send, "m_iDefaultFOV", 90);
                return Plugin_Continue;
            }
            
            if(buttons & IN_ZOOM)
            {
                if(!(lastbuttons[client] & IN_ZOOM) && !ClientZoom[client])
                {
                    // suit zooming
                    ClientZoom[client] = 2;
                }
            } 
            else if(ClientZoom[client] == 2)
            {
                // no longer suit zooming
                ClientZoom[client] = 0;
            }
            
            if(ClientZoom[client] < 2
               && ( (StrEqual(sWeapon, "weapon_crossbow") && buttons & IN_ATTACK2 && !(lastbuttons[client] & IN_ATTACK2))
                || (!StrEqual(sWeapon, "weapon_crossbow") && ClientZoom[client]) )
            ){
                // xbow zoom cycled
                ClientZoom[client] = ClientZoom[client] ? 0 : 1;
            }
        }
     
        // set values
        if(ClientZoom[client] || IsClientObserver(client) && GetEntProp(client, Prop_Send, "m_iObserverMode") == SPECMODE_FIRSTPERSON)
        {
            SetEntProp(client, Prop_Send, "m_iDefaultFOV", 90);  
        }
        else if(ClientZoom[client] == 0)
        {
            SetEntProp(client, Prop_Send, "m_iFOV", fov);
            SetEntProp(client, Prop_Send, "m_iDefaultFOV", fov);          
        }
        
        lastbuttons[client] = buttons;
    }
    
    return Plugin_Continue;
}

void RequestFOV(int client, int fov)
{
    if(fov < MIN_FOV || fov > MAX_FOV)
    {
        CReplyToCommand(client, "%s%sError: %sFOV must be a value between %s%i %sand %s%i%s.",
            CHAT_FAIL, CHAT_PM, CHAT_MAIN, CHAT_HIGH, MIN_FOV, CHAT_MAIN, CHAT_HIGH, MAX_FOV, CHAT_MAIN
        );
    }
    else
    {
        CReplyToCommand(client, "%s%sChanged your FOV to %s%i%s.",
            CHAT_MAIN, CHAT_PM, CHAT_HIGH, fov, CHAT_MAIN
        );
        
        SetClientCookieInt(client, Cookie_FOV, fov);
    }
}