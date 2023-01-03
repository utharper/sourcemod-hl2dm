#pragma semicolon 1

public Plugin myinfo = {
    name                 = "XMS - Name of Custom Gamemode",
    version              = "0.1",
    description          = "Description of your custom gamemode",
    author               = "you",
    url                  = "www.yourwebsite.com"
};

//

#include <sourcemod>
#include <xms>

//

bool gbEnabled;

//

public void OnMapStart()
{
    gbEnabled = IsGamemode("custom"); // tag of your gamemode in xms.cfg
}

void SomeOtherFunction()
{
    if(gbEnabled)
    {
        // Do Stuff
    }
}