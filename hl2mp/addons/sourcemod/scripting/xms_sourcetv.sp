#define PLUGIN_NAME         "XMS - SourceTV"
#define PLUGIN_VERSION      "1.13"
#define PLUGIN_DESCRIPTION  "SourceTV controller and demo uploader for eXtended Match System"
#define PLUGIN_AUTHOR       "harper"
#define PLUGIN_URL          "HL2DM.PRO"
#define UPDATE_URL          "https://raw.githubusercontent.com/jackharpr/hl2dm-xms/master/addons/sourcemod/xms_sourcetv.upd"

#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <updater>
#include <system2>

#define REQUIRE_PLUGIN
#pragma newdecls required
#include <hl2dm-xms>

char    DemoName[256],
        DemoFolder[PLATFORM_MAX_PATH],
        UploadPath[PLATFORM_MAX_PATH],
        DemoWeb[PLATFORM_MAX_PATH],
        FTP_Username[256],
        FTP_Password[256],
        FTP_Hostname[256],
        FTP_Path[1024];
        
int     FTP_Port;
    
bool    IsRecording,
        ZipDemos,
        Zip32bit,
        UploadDemos,
        PurgeDemos;

/******************************************************************/

public Plugin myinfo={name=PLUGIN_NAME,version=PLUGIN_VERSION,description=PLUGIN_DESCRIPTION,author=PLUGIN_AUTHOR,url=PLUGIN_URL};

public void OnPluginStart()
{
    if(LibraryExists("updater")) Updater_AddPlugin(UPDATE_URL);
    
    if(LibraryExists("system2"))
    {
        char bindir[PLATFORM_MAX_PATH],
             bindir32[PLATFORM_MAX_PATH];
             
        if(!System2_Check7ZIP(bindir, sizeof(bindir)))
        {
            if(!System2_Check7ZIP(bindir32, sizeof(bindir32), true))
            {
                if(StrEqual(bindir, bindir32)) LogError("ERROR: 7-ZIP was not found or is not executable at '%s'", bindir);
                else LogError("ERROR: 7-ZIP was not found or is not executable at '%s' or '%s'", bindir, bindir32);
            }
            else Zip32bit = true;
        }  
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "updater")) Updater_AddPlugin(UPDATE_URL);
}

public void OnAllPluginsLoaded()
{
    char buffer[1024];
    
    XMS_GetConfigString(buffer, sizeof(buffer), "ZipDemos", "SourceTV");
    ZipDemos = StrEqual(buffer, "1");
    
    XMS_GetConfigString(buffer, sizeof(buffer), "Enable", "SourceTV", "UploadDemos");
    if(StrEqual(buffer, "1"))
    {
        UploadDemos = true;

        XMS_GetConfigString(FTP_Hostname, sizeof(FTP_Hostname), "Host", "SourceTV", "UploadDemos");
        XMS_GetConfigString(FTP_Username, sizeof(FTP_Username), "Username", "SourceTV", "UploadDemos");
        XMS_GetConfigString(FTP_Password, sizeof(FTP_Password), "Password", "SourceTV", "UploadDemos");
        XMS_GetConfigString(FTP_Path, sizeof(FTP_Path), "Path", "SourceTV", "UploadDemos");
        XMS_GetConfigString(DemoWeb, sizeof(DemoWeb), "URL", "SourceTV", "UploadDemos");
        
        XMS_GetConfigString(buffer, sizeof(buffer), "Port", "SourceTV", "UploadDemos");
        FTP_Port = StringToInt(buffer);
        
        XMS_GetConfigString(buffer, sizeof(buffer), "PurgeLocal", "SourceTV", "UploadDemos");
        PurgeDemos = StrEqual(buffer, "1");
    }
    
    XMS_GetConfigString(DemoFolder, sizeof(DemoFolder), "DemoFolder", "SourceTV");
    
    if(!DirExists(DemoFolder)) CreateDirectory(DemoFolder, 509);
    Format(buffer, sizeof(buffer), "%s/incomplete", DemoFolder);
    if(!DirExists(buffer)) CreateDirectory(buffer, 509);
}

public void OnGamestateChanged(int new_state, int old_state)
{
    if(new_state == STATE_MATCHWAIT && !IsRecording) StartRecord();
    else if(new_state == STATE_POST && IsRecording) CreateTimer(5.0, T_StopRecord, false);
    else if((new_state == STATE_DEFAULT || new_state == STATE_CHANGE) && IsRecording) StopRecord(true);
}

public Action T_StopRecord(Handle timer, bool early)
{
    StopRecord(early);
}

void StartRecord()
{
    XMS_GetGameID(DemoName, sizeof(DemoName));
    ServerCommand("tv_record %s/incomplete/%s", DemoFolder, DemoName);
    
    IsRecording = true;
}

void StopRecord(bool early)
{
    char path_incomplete[PLATFORM_MAX_PATH],
         path_complete[PLATFORM_MAX_PATH];
         
    BuildPath(Path_SM, path_incomplete, PLATFORM_MAX_PATH, "../../%s/incomplete/%s.dem", DemoFolder, DemoName);
    BuildPath(Path_SM, path_complete, PLATFORM_MAX_PATH, "../../%s/%s.dem", DemoFolder, DemoName);
    
    if(early)
    {
        DeleteFile(path_incomplete);
        CPrintToChatAll("%s(Match ended early - SourceTV demo not saved)", CLR_INFO);
    }
    else
    {
        RenameFile(path_complete, path_incomplete);
        
        if(ZipDemos) CompressDemo(path_complete);
        else if(UploadDemos)
        {
            strcopy(UploadPath, PLATFORM_MAX_PATH, path_complete);
            UploadDemo();
        }
    }
    
    ServerCommand("tv_stoprecord");
    IsRecording = false;
}

void CompressDemo(const char[] path)
{   
    BuildPath(Path_SM, UploadPath, PLATFORM_MAX_PATH, "../../%s/%s.zip", DemoFolder, DemoName);
    System2_Compress(OnCompressed, path, UploadPath, ARCHIVE_ZIP, LEVEL_9, _, Zip32bit);     
}

void UploadDemo()
{
    System2FTPRequest ftpRequest = new System2FTPRequest(FtpResponseCallback, "ftp://%s/%s/%s.%s", FTP_Hostname, FTP_Path, DemoName, ZipDemos ? "zip" : "dem");
    ftpRequest.CreateMissingDirs = true;
    ftpRequest.SetPort(FTP_Port);
    ftpRequest.SetAuthentication(FTP_Username, FTP_Password);
    ftpRequest.SetInputFile(UploadPath);
    ftpRequest.StartRequest();     
}

stock void OnCompressed(bool success, const char[] command, System2ExecuteOutput output, any data)
{
    if(success)
    {
        char oldfile[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, oldfile, PLATFORM_MAX_PATH, "../../%s/%s.dem", DemoFolder, DemoName);
        DeleteFile(oldfile);
        
        if(UploadDemos)
        {
            UploadDemo();
        }
    }
    else LogError("ERROR: Demo compress function failed");
}

stock void FtpResponseCallback(bool success, const char[] error, System2FTPRequest request, System2FTPResponse response)
{
    CPrintToChatAll("%sSourceTV demo uploaded: %s%s/%s.%s", CLR_MAIN, CLR_HIGH, DemoWeb, DemoName, ZipDemos ? "zip" : "dem");
    if(PurgeDemos)
    {
        DeleteFile(UploadPath);
    }
}