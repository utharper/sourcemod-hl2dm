#define PLUGIN_VERSION "1.14"
#define UPDATE_URL     "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_menu.upd"

public Plugin myinfo=
{
    name        = "XMS - Client Menu",
    version     = PLUGIN_VERSION,
    description = "Commands menu for XMS (requires cl_showpluginmessages 1)",
    author      = "harper",
    url         = "www.hl2dm.pro"
};

/******************************************************************/

#pragma semicolon 1
#include <sourcemod>
#include <morecolors>

#undef REQUIRE_PLUGIN
 #include <updater>
#define REQUIRE_PLUGIN

#pragma newdecls required
 #include <hl2dm-xms>

/******************************************************************/

Menu BaseMenu,
     MapchangeMenu,
     ModeMenu,
     TeamMenu,
     ProfileMenu;
     
char Gamemodes[512],
     Currentmode[MAX_MODE_LENGTH];
     
int Announced[MAXPLAYERS + 1];

/******************************************************************/

public void OnPluginStart()
{
    RegConsoleCmd("sm_menu", Command_Menu, "Open the XMS menu");
    
    if(LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnAllPluginsLoaded()
{
    XMS_GetConfigKeys(Gamemodes, sizeof(Gamemodes), "GameModes");
    
    if(!CommandExists("sm_run"))
    {
        LogError("xms_commands not running or is incompatible");
    }
}

public void OnMapStart()
{
    XMS_GetGamemode(Currentmode, sizeof(Currentmode));
    
    BaseMenu =      BuildBaseMenu(),
    MapchangeMenu = BuildMapMenu(),
    ModeMenu =      BuildModeMenu(),
    TeamMenu =      BuildTeamMenu(),
    ProfileMenu =   BuildProfileMenu();
}

public void OnClientPostAdminCheck(int client)
{
    Announced[client] = false;
    CreateTimer(1.0, T_RebuildProfiles, client, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(1.1, T_InitMenu, client, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    Announced[client] = false;
    ProfileMenu = BuildProfileMenu();
}

public Action T_RebuildProfiles(Handle timer, int client)
{
    if(IsClientInGame(client))
    {
        ProfileMenu = BuildProfileMenu();
    }
}

public Action T_InitMenu(Handle timer, int client)
{
    if(IsClientInGame(client))
    {
        QueryClientConVar(client, "cl_showpluginmessages", ShowMenuIfVisible, client);
    }
}

public Action Command_Menu(int client, int args)
{
    QueryClientConVar(client, "cl_showpluginmessages", ShowMenuIfVisible, client);
}

public void ShowMenuIfVisible(QueryCookie cookie, int client, ConVarQueryResult result, char[] cvarName, char[] cvarValue)
{   
    if(!StrEqual(cvarValue, "1"))
    {
        if(!Announced[client])
        {
            CPrintToChat(client, "%s%sWarning: Couldn't display XMS menu.\n%s%s%s%sSet %scl_ShowPluginMessages 1%s in your console!",
                CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_FAIL, CHAT_PREFIX, CLR_MAIN, CLR_HIGH, CLR_MAIN
            );
            // keep trying silently
            CreateTimer(5.0, T_InitMenu, client, TIMER_FLAG_NO_MAPCHANGE);
            Announced[client] = true;
        }
    }
    else
    {
        CPrintToChat(client, "%s%sPress ESC to open server menu", CLR_MAIN, CHAT_PREFIX);
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
}

public int Menu_Base(Menu menu, MenuAction action, int client, int param)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        
        menu.GetItem(param, info, sizeof(info));
        
        if(StrEqual(info, "map"))               MapchangeMenu.Display(client, MENU_TIME_FOREVER);
        else if(StrEqual(info, "mode"))         ModeMenu.Display(client, MENU_TIME_FOREVER);
        else if(StrEqual(info, "team"))         TeamMenu.Display(client, MENU_TIME_FOREVER);
        else if(StrEqual(info, "profile"))      ProfileMenu.Display(client, MENU_TIME_FOREVER);
        
        else if(StrEqual(info, "admin") &&
            IsClientAdmin(client))              FakeClientCommand(client, "sm_admin");
            
        else
        {
            if(StrEqual(info, "start"))         FakeClientCommand(client, "say !start");
            else if(StrEqual(info, "stop"))     FakeClientCommand(client, "say !stop");
            else if(StrEqual(info, "coinflip")) FakeClientCommand(client, "say !coinflip");
            
            BaseMenu.Display(client, MENU_TIME_FOREVER);
        }
    }
    
    else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack))
    {
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
}

public int Menu_Team(Menu menu, MenuAction action, int client, int param)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        
        menu.GetItem(param, info, sizeof(info));
        
        FakeClientCommand(client, "jointeam %i",
            StrEqual(info, "Rebels") ? TEAM_REBELS
            : StrEqual(info, "Combine") ? TEAM_COMBINE
            : TEAM_SPECTATORS
        );
        
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
    
    else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack))
    {
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
}

public int Menu_Run(Menu menu, MenuAction action, int client, int param)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        
        menu.GetItem(param, info, sizeof(info));
        
        FakeClientCommand(client, "say !run %s", info);
        
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
    
    else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack))
    {
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
}

public int Menu_Profile(Menu menu, MenuAction action, int client, int param)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        
        menu.GetItem(param, info, sizeof(info));
        
        FakeClientCommand(client, "say /profile %s", info);
        
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
    
    else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack))
    {
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
}

Menu BuildModeMenu()
{
    char list[512],
         modes[512][MAX_MODE_LENGTH];
    int  count = XMS_GetConfigKeys(list, sizeof(list), "GameModes");
    Menu menu  = new Menu(Menu_Run);
    
    ExplodeString(list, ",", modes, count, MAX_MODE_LENGTH);
    
    for(int i = 0; i < count; i++)
    {
        if(!StrEqual(modes[i], Currentmode))
        {
            menu.AddItem(modes[i], modes[i]);
        }
    }
    
    menu.SetTitle("Current mode: %s", Currentmode);
    menu.ExitBackButton = true;
    menu.ExitButton = false;
    
    return menu;
}

Menu BuildBaseMenu()
{
    char servername[64],
         currentmap[MAX_MAP_LENGTH];
    Menu menu = new Menu(Menu_Base);
         
    XMS_GetConfigString(servername, sizeof(servername), "ServerName");
    
    GetCurrentMap(currentmap, sizeof(currentmap));
    StripMapPrefix(currentmap, currentmap, sizeof(currentmap));

    menu.SetTitle("Select an option to see more info.\n\n(Say !menu to reopen this page\n if you close it accidentally.)\n\nServer: %s\nMap:    %s\nMode:   %s\n\n- GameVersion: %i\n- eXtended Match System [XMS]\n   v%s | www.hl2dm.pro",
        servername, currentmap, Currentmode, GetGameVersion(), PLUGIN_VERSION
    );
   
    menu.AddItem("team"     , "Join team");
    menu.AddItem("map"      , "Change map");
    menu.AddItem("mode"     , "Change mode");
    menu.AddItem("start"    , "Start match");
    menu.AddItem("stop"     , "Stop match");
    menu.AddItem("profile"  , "View profile");
    menu.AddItem("coinflip" , "Flip a coin");
    
    menu.AddItem("admin"    , "Admin menu");
    
    return menu;
}

Menu BuildTeamMenu()
{
    Menu menu = new Menu(Menu_Team);
    
    menu.SetTitle("Select a team to join\n(teams are locked during match)");
    menu.ExitBackButton = true;
    menu.ExitButton = false;    
    
    menu.AddItem("Rebels", "Rebels");
    
    if(XMS_IsGameTeamplay()) menu.AddItem("Combine", "Combine");
    
    menu.AddItem("Spectators", "Spectators");
    
    return menu;
}

Menu BuildMapMenu()
{
    char mapcycle[PLATFORM_MAX_PATH];
    File file;
    
    if(!XMS_GetConfigString(mapcycle, sizeof(mapcycle), "Mapcycle", "GameModes", Currentmode))
    {
         Format(mapcycle, sizeof(mapcycle), "cfg/mapcycle_default.txt");
    }
    else Format(mapcycle, sizeof(mapcycle), "cfg/%s", mapcycle);
    
    file = OpenFile(mapcycle, "rt");
    if(file != null)
    {
        char mapname[MAX_MAP_LENGTH];
        Menu menu = new Menu(Menu_Run);
        
        menu.SetTitle("(maps available in this mode)");
        menu.ExitBackButton = true;
        menu.ExitButton = false;
            
        while(!file.EndOfFile() && file.ReadLine(mapname, sizeof(mapname)))
        {
            int len = strlen(mapname);
        
            if(mapname[0] == ';' || !IsCharAlpha(mapname[0])) continue;
            for(int i = 0; i < len; i++)
            {
                if(IsCharSpace(mapname[i]))
                {
                    mapname[i] = '\0';
                    break;
                }
            }
        
            if(!IsMapValid(mapname)) continue;
            
            StripMapPrefix(mapname, mapname, sizeof(mapname));
            menu.AddItem(mapname, mapname);
        }
        file.Close();
            
        return menu;
    }
    
    LogError("Couldn't read mapcyclefile: cfg/%s", mapcycle);
    return null;
}

Menu BuildProfileMenu()
{
    Menu menu = new Menu(Menu_Profile);
    
    menu.SetTitle("Open player's steam profile\n (press ESC after selecting)");
    menu.ExitBackButton = true;
    menu.ExitButton = false;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        char name[MAX_NAME_LENGTH],
             si[8];
       
        if(!IsClientInGame(i) || IsFakeClient(i)) continue;
        IntToString(GetClientUserId(i), si, sizeof(si));
        Format(name, sizeof(name), "%N", i);
        
        menu.AddItem(si, name);
    }
    
    return menu;
}