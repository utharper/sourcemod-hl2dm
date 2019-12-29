#define PLUGIN_VERSION "1.15"
#define UPDATE_URL     "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_menu.upd"

public Plugin myinfo=
{
    name        = "XMS - Client Menu",
    version     = PLUGIN_VERSION,
    description = "Commands menu for XMS (requires cl_showpluginmessages 1)",
    author      = "harper <www.hl2dm.pro>",
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
     ProfileMenu,
     FovMenu,
     DynamicMenu  [MAXPLAYERS + 1];
     
char MasterVersion[5],
     Gamemodes    [512],
     Currentmode  [MAX_MODE_LENGTH],
     Currentmap   [MAX_MAP_LENGTH];
     
int  MenuDisplay  [MAXPLAYERS + 1];

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
    GetConVarString(FindConVar("hl2dm-xms_version"), MasterVersion, sizeof(MasterVersion));
    
    XMS_GetConfigKeys(Gamemodes, sizeof(Gamemodes), "GameModes");
    
    if(!CommandExists("sm_run"))
    {
        LogError("xms_commands not running or is incompatible");
    }
}

public void OnMapStart()
{
    GetCurrentMap(Currentmap, sizeof(Currentmap));
    XMS_GetGamemode(Currentmode, sizeof(Currentmode));
    
    BaseMenu      = BuildBaseMenu(),
    MapchangeMenu = BuildMapMenu(Currentmode),
    ModeMenu      = BuildModeMenu(),
    TeamMenu      = BuildTeamMenu(),
    FovMenu       = BuildFovMenu();
}

public void OnClientPostAdminCheck(int client)
{
    MenuDisplay[client] = 0;
    CreateTimer(1.0, T_RebuildProfiles, client, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(1.1, T_InitMenu, client, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    MenuDisplay[client] = 0;
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
    if(MenuDisplay[client] == 2)
    {
        return Plugin_Stop;
    }
    
    if(IsClientInGame(client) && !IsFakeClient(client))
    {
        QueryClientConVar(client, "cl_showpluginmessages", ShowMenuIfVisible, client);
    }
    
    return Plugin_Continue;
}

public Action Command_Menu(int client, int args)
{
    MenuDisplay[client] = 0;
    QueryClientConVar(client, "cl_showpluginmessages", ShowMenuIfVisible, client);
}

public void ShowMenuIfVisible(QueryCookie cookie, int client, ConVarQueryResult result, char[] cvarName, char[] cvarValue)
{   
    if(!StrEqual(cvarValue, "1"))
    {
        if(MenuDisplay[client] == 0)
        {
            CPrintToChat(client, "%s%sWarning: %sCan't display XMS menu. Set %scl_ShowPluginMessages 1%s in your console!",
                CHAT_FAIL, CHAT_PM, CHAT_MAIN, CHAT_HIGH, CHAT_MAIN
            );
            // keep trying silently
            CreateTimer(2.0, T_InitMenu, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
            MenuDisplay[client] = 1;
        }
    }
    else
    {
        MenuDisplay[client] = 2;
        CPrintToChat(client, "%s%sPress ESC to open server menu", CHAT_MAIN, CHAT_PM);
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
}

public int Menu_Base(Menu menu, MenuAction action, int client, int param)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        
        menu.GetItem(param, info, sizeof(info));
        
        if     (StrEqual(info, "map"))          MapchangeMenu.Display(client, MENU_TIME_FOREVER);
        else if(StrEqual(info, "mode"))         ModeMenu.Display(client, MENU_TIME_FOREVER);
        else if(StrEqual(info, "team"))         TeamMenu.Display(client, MENU_TIME_FOREVER);
        else if(StrEqual(info, "profile"))      ProfileMenu.Display(client, MENU_TIME_FOREVER);
        else if(StrEqual(info, "fov"))          FovMenu.Display(client, MENU_TIME_FOREVER);
            
        else
        {
            if     (StrEqual(info, "start"))    FakeClientCommand(client, "sm_start");
            else if(StrEqual(info, "pause"))    FakeClientCommand(client, "sm_pause");
            else if(StrEqual(info, "stop"))     FakeClientCommand(client, "sm_stop");
            else if(StrEqual(info, "coinflip")) FakeClientCommand(client, "sm_coinflip");
            
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

public int Menu_Mode(Menu menu, MenuAction action, int client, int param)
{
    if(action == MenuAction_Select)
    {
        char info[MAX_MAP_LENGTH];

        menu.GetItem(param, info, sizeof(info));
        DynamicMenu[client] = BuildMapMenu(info);
        
        DynamicMenu[client].Display(client, MENU_TIME_FOREVER);
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
        
        FakeClientCommand(client, "sm_run %s", info);
        
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
        FakeClientCommand(client, "sm_profile %s", info);
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
    
    else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack))
    {
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
}

public int Menu_Fov(Menu menu, MenuAction action, int client, int param)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        
        menu.GetItem(param, info, sizeof(info));
        FakeClientCommand(client, "sm_fov %s", info);
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }
    
    else if(action == MenuAction_Cancel && (param == MenuCancel_Exit || param == MenuCancel_ExitBack))
    {
        BaseMenu.Display(client, MENU_TIME_FOREVER);
    }   
}

Menu BuildFovMenu()
{
    Menu menu  = new Menu(Menu_Fov);
    
    for(int i = 90; i <= 120; i += 5)
    {
        char si[4];
        IntToString(i, si, sizeof(si));
        menu.AddItem(si, si);
    }
    
    menu.SetTitle("Change your FOV");
    menu.ExitBackButton = true;
    menu.ExitButton = false;
    
    return menu;
}

Menu BuildModeMenu()
{
    char list[512],
         modes[512][MAX_MODE_LENGTH];
    int  count = XMS_GetConfigKeys(list, sizeof(list), "GameModes");
    Menu menu  = new Menu(Menu_Mode);
    
    ExplodeString(list, ",", modes, count, MAX_MODE_LENGTH);
    
    for(int i = 0; i < count; i++)
    {
        if(!StrEqual(modes[i], Currentmode))
        {
            menu.AddItem(modes[i], modes[i]);
        }
    }
    
    menu.SetTitle("1/2 - Select mode to change to \n\nCurrent mode is: %s", Currentmode);
    menu.ExitBackButton = true;
    menu.ExitButton = false;
    
    return menu;
}

Menu BuildBaseMenu()
{
    char currentmapx[MAX_MAP_LENGTH];
    char servername[64];
    char modedesc[32];
    Menu menu = new Menu(Menu_Base);
         
    XMS_GetConfigString(servername, sizeof(servername), "ServerName");
    XMS_GetConfigString(modedesc, sizeof(modedesc), "Name", "Gamemodes", Currentmode);
    
    StripMapPrefix(Currentmap, currentmapx, sizeof(currentmapx));

    menu.SetTitle("Select an option to see more info.\n\n(Say !menu to reopen this page\n if you close it accidentally.)\n\nServer: %s\nMap:    %s\nMode:   %s (%s)\n\n- GameVersion: %i\n- eXtended Match System [XMS]\n   v%s | www.hl2dm.pro",
        servername, currentmapx, Currentmode, modedesc, GetGameVersion(), MasterVersion
    );
   
    menu.AddItem("team"     , "Join team");
    menu.AddItem("map"      , "Change map");
    menu.AddItem("mode"     , "Change mode");
    menu.AddItem("start"    , "Start match");
    menu.AddItem("stop"     , "Stop match");
    
    if(CommandExists("sm_pause"))
    {
        menu.AddItem("pause", "Pause match");
    }
    
    menu.AddItem("profile"  , "View profile");
    menu.AddItem("coinflip" , "Flip a coin");
    
    if(CommandExists("sm_fov"))
    {
        menu.AddItem("fov"  , "Change FOV");
    }
    
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

Menu BuildMapMenu(const char[] gamemode)
{
    char mapcycle[PLATFORM_MAX_PATH];
    File file;
    
    if(!XMS_GetConfigString(mapcycle, sizeof(mapcycle), "Mapcycle", "GameModes", gamemode))
    {
         Format(mapcycle, sizeof(mapcycle), "cfg/mapcycle_default.txt");
    }
    else Format(mapcycle, sizeof(mapcycle), "cfg/%s", mapcycle);
    
    file = OpenFile(mapcycle, "rt");
    if(file != null)
    {
        char mapname[MAX_MAP_LENGTH],
             runcommand[MAX_MAP_LENGTH + MAX_MODE_LENGTH + 1],
             retainmodes[256];
        Menu menu = new Menu(Menu_Run);
        
        menu.ExitBackButton = true;
        menu.ExitButton = false;
        
        if(!StrEqual(gamemode, Currentmode))
        {
            menu.SetTitle("2/2 - Choose map for new mode: %s", gamemode);
            Format(runcommand, sizeof(runcommand), "%s %s", gamemode, mapname);
            
            // Add the current map as first option if applicable
            if(XMS_GetConfigString(retainmodes, sizeof(retainmodes), "$retain", "MapModes"))
            {
                if(IsItemDistinctInList(Currentmode, retainmodes) && IsItemDistinctInList(gamemode, retainmodes))
                {
                    StripMapPrefix(Currentmap, mapname, sizeof(mapname));
                    StrCat(mapname, sizeof(mapname), " (current)");
                    menu.AddItem(runcommand, mapname);
                }
            }
        }
        else menu.SetTitle("Available maps for current mode");
       
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
            
            if(!StrEqual(mapname, Currentmap))
            {
                Format(runcommand, sizeof(runcommand), "%s %s", gamemode, mapname);
                StripMapPrefix(mapname, mapname, sizeof(mapname));
                menu.AddItem(runcommand, mapname);
            }
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
    
    menu.SetTitle("Open player steam profile in MOTD\n(press ESC after selecting player)\n\nIf it does not load, try again.");
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