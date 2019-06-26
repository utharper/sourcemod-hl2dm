#define PLUGIN_NAME			"XMS - HUD"
#define PLUGIN_VERSION		"1.12"
#define PLUGIN_DESCRIPTION	"Timeleft and spectator HUD for eXtended Match System"
#define PLUGIN_AUTHOR		"harper, Adrianilloo"
#define PLUGIN_URL			"hl2dm.pro"

#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required
#include <hl2dm_xms>

Handle	Hud_Spectator,
		Hud_Time;
		
/******************************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{	
	Hud_Spectator = CreateHudSynchronizer();
	Hud_Time = CreateHudSynchronizer();
}

public void OnAllPluginsLoaded()
{
	CreateTimer(0.1, T_TimeHud, _, TIMER_REPEAT);
	CreateTimer(0.1, T_SpecHud, _, TIMER_REPEAT);
}

public Action T_TimeHud(Handle timer)
{	
	char 	buffer[24];
	bool 	red;
	int		gamestate = XMS_GetGamestate();
	
	if(gamestate == STATE_MATCHWAIT || gamestate == STATE_CHANGE || gamestate == STATE_PAUSE)
	{
		static int count;
		
		Format(buffer, sizeof(buffer), ". . %s%s%s", count >= 20 ? ". " : NULL_STRING, count >= 15 ? ". " : NULL_STRING, count >= 10 ? "." : NULL_STRING);
		count++;
		if(count == 25) count = 0;
	}
	else
	{
		if(gamestate == STATE_POST)
		{
			red = true;
			Format(buffer, sizeof(buffer), "— Game Over —");
		}
		else if(gamestate == STATE_MATCHEX || gamestate == STATE_DEFAULTEX)
		{
			red = true;
			Format(buffer, sizeof(buffer), "— Overtime —");
		}
		
		if(GetConVarBool(FindConVar("mp_timelimit")))
		{
			float tl = XMS_GetTimeRemaining(false);
			
			if(tl < 0) tl = 0.0;
			int h = RoundToNearest(tl) / 3600,
				s = RoundToNearest(tl) % 60,
				m;
					
			if(h)
			{
				m = RoundToNearest(tl) / 60 - (h * 60);
				Format(buffer, sizeof(buffer), "%dh %d:%02d\n%s", h, m, s, buffer);
			}
			else
			{
				m = RoundToNearest(tl) / 60;
					
				if(tl >= 60) Format(buffer, sizeof(buffer), "%d:%02d\n%s", m, s, buffer);
				else
				{
					red = true;
						
					if(tl >= 10)	Format(buffer, sizeof(buffer), "%i\n%s", RoundToNearest(tl), buffer);
					else			Format(buffer, sizeof(buffer), "%.1f\n%s", tl, buffer);
				}
			}
		}
	}
	
	if(red) SetHudTextParams(-1.0, 0.01, 0.2, 220, 10, 10, 255, 0, 0.0, 0.0, 0.0);
	else	SetHudTextParams(-1.0, 0.01, 0.2, 220, 177, 0, 255, 0, 0.0, 0.0, 0.0);
	
	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientConnected(client) || !IsClientInGame(client)) continue;
		ShowSyncHudText(client, Hud_Time, "%s", buffer);
	}
}

public Action T_SpecHud(Handle timer)
{
	int gamestate = XMS_GetGamestate();
	
	if(gamestate != STATE_POST && gamestate != STATE_PAUSE) 
	{
		for(int client = 1; client <= MaxClients; client++)
		{			
			if(!IsClientConnected(client) || !IsClientInGame(client) || !IsClientObserver(client) || IsClientSourceTV(client) || GetClientButtons(client) & IN_SCORE) continue;
			
			int		target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
			char	hudout[1024];
						
			// format hud text
			if(GetEntProp(client, Prop_Send, "m_iObserverMode") != 7 && target > 0 && IsClientConnected(target) && IsClientInGame(target))
			{
				int buttons = GetClientButtons(target);
				
				Format
				(
					hudout, 
					sizeof(hudout), 
					"health: %d   suit: %d\nvel: %03d  %s    %0.1fº\n%s         %s          %s\n%s     %s     %s",
					GetClientHealth(target),
					GetClientArmor(target),
					GetClientVelocity(target),
					(buttons & IN_FORWARD) ? "↑" : "  ", 
					GetClientHorizAngle(target),
					(buttons & IN_MOVELEFT) ? "←" : "  ", 
					(buttons & IN_SPEED) ? "+SPEED" : "       ", 
					(buttons & IN_MOVERIGHT) ? "→" : "  ",
					(buttons & IN_DUCK) ? "+DUCK" : "    ",
					(buttons & IN_BACK) ? "↓" : "  ",
					(buttons & IN_JUMP) ? "+JUMP" : "    "
				);
			}
			else Format(hudout, sizeof(hudout), "\n[Free-look]");

			SetHudTextParams(-1.0, 0.75, 0.2, 220, 177, 0, 255, 0, 0.0, 0.0, 0.0);
			ShowSyncHudText(client, Hud_Spectator, hudout);
		}
	}
}

int GetClientVelocity(int client)
{
	float	x = GetEntDataFloat(client, FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]")),
			y = GetEntDataFloat(client, FindSendPropInfo("CBasePlayer", "m_vecVelocity[1]")),
			z = GetEntDataFloat(client, FindSendPropInfo("CBasePlayer", "m_vecVelocity[2]"));
	
	return RoundToNearest(SquareRoot(x * x + y * y + z * z));
}

float GetClientHorizAngle(int client)
{
	float angles[3]; 

	GetClientAbsAngles(client, angles);
	return angles[1];
}
