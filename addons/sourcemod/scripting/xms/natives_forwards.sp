/**************************************************************
 * NATIVES
 *************************************************************/
public int Native_GetGamestate(Handle hPlugin, int iParams)
{
    return gRound.iState;
}

public int Native_GetGamemode(Handle hPlugin, int iParams)
{
    int iBytes;

    SetNativeString(1, gRound.sMode, GetNativeCell(2), true, iBytes);
    return iBytes;
}

public int Native_GetGameID(Handle hPlugin, int iParams)
{
    int iBytes;

    SetNativeString(1, gRound.sUID, GetNativeCell(2), true, iBytes);
    return iBytes;
}

public int Native_GetTimeRemaining(Handle hPlugin, int iParams)
{
    float fTime = (gConVar.mp_timelimit.FloatValue * 60 - GetGameTime() + gRound.fStartTime);

    if (GetNativeCell(1))
    {
        if (gRound.iState == GAME_OVER) {
            return view_as<int>(gConVar.mp_chattime.FloatValue - (GetGameTime() - gRound.fEndTime));
        }
        return view_as<int>(fTime + gConVar.mp_chattime.FloatValue);
    }

    return view_as<int>(fTime);
}

public int Native_GetTimeElapsed(Handle hPlugin, int iParams)
{
    return view_as<int>(GetGameTime() - gRound.fStartTime);
}

/**************************************************************
 * FORWARDS
 *************************************************************/
void Forward_OnGamestateChanged(int iState)
{
    Call_StartForward(gForward.hGamestateChanged);
    Call_PushCell(iState);
    Call_PushCell(gRound.iState);
    Call_Finish();
}

void Forward_OnMatchStart()
{
    Call_StartForward(gForward.hMatchStarted);
    Call_Finish();
}

void Forward_OnMatchEnd(bool bCompleted)
{
    Call_StartForward(gForward.hMatchEnded);
    Call_PushCell(view_as<int>(bCompleted));
    Call_Finish();
}

void Forward_OnClientFeedback(const char[] sFeedback, const char[] sName, const char[] sID, const char[] sGameID)
{
    Call_StartForward(gForward.hFeedback);
    Call_PushString(sFeedback);
    Call_PushString(sName);
    Call_PushString(sID);
    Call_PushString(sGameID);
    Call_Finish();
}