#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <morecolors>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>

// ====[ CONSTANTS ]===================================================
#define PLUGIN_NAME         "SOAP Tournament"
#define PLUGIN_AUTHOR       "Lange - maintained by sappho.io"
#define PLUGIN_VERSION      "3.8.5"
#define PLUGIN_CONTACT      "https://sappho.io"
#define RED                 0
#define BLU                 1
#define TEAM_OFFSET         2

// ====[ PLUGIN ]======================================================
public Plugin myinfo =
{
    name                    = PLUGIN_NAME,
    author                  = PLUGIN_AUTHOR,
    description             = "Automatically loads and unloads plugins when a mp_tournament match goes live or ends.",
    version                 = PLUGIN_VERSION,
    url                     = PLUGIN_CONTACT
};

// ====[ VARIABLES ]===================================================

// for morecolors lol
#define SOAP_TAG "{lime}[{cyan}SOAP{lime}]{white} "

bool teamReadyState[2];
bool dming;
Handle redPlayersReady;
Handle bluePlayersReady;
Handle g_readymode_min;
// global forward handle;
Handle g_StopDeathMatching;
Handle g_StartDeathMatching;
// ConVars
ConVar g_cvReadyModeCountdown;
ConVar g_cvEnforceReadyModeCountdown;

// ====[ FUNCTIONS ]===================================================

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    RegPluginLibrary("soap_tournament");

    return APLRes_Success;
}

/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------- */

public void OnPluginStart()
{
    LoadTranslations("soap_tf2dm.phrases");

    // Win conditions met (maxrounds, timelimit)
    HookEvent("teamplay_game_over", Event_GameOver);

    // Win conditions met (windifference)
    HookEvent("tf_game_over", Event_GameOver);

    HookEvent("tournament_stateupdate", Event_TournamentStateupdate);

    // Hook for events when player changes their team.
    HookEvent("player_team", Event_PlayerTeam);

    // Hook into mp_tournament_restart
    RegServerCmd("mp_tournament_restart", TournamentRestartHook);

    // Listen for player readying or unreadying.
    AddCommandListener(Listener_TournamentPlayerReadystate, "tournament_player_readystate");

    // maybe todo: force teamreadymode to 0 and remove the old logic as that cvar appears to be broken in tf2,
    // causing issues where soap works perfectly fine but the announcer never starts the countdown nor does the game ever start
    // i don't know. needs more testing.
    // see: https://github.com/sapphonie/tf2-halftime/pull/1

    g_cvEnforceReadyModeCountdown = CreateConVar("soap_enforce_readymode_countdown", "1", "Set as 1 to keep mp_tournament_readymode_countdown 5 so P-Rec works properly", _, true, 0.0, true, 1.0);
    g_cvReadyModeCountdown = FindConVar("mp_tournament_readymode_countdown");
    g_readymode_min = FindConVar("mp_tournament_readymode_min");

    SetConVarInt(g_cvReadyModeCountdown, 5, true, true);
    HookConVarChange(g_cvEnforceReadyModeCountdown, handler_ConVarChange);
    HookConVarChange(g_cvReadyModeCountdown, handler_ConVarChange);

    redPlayersReady = CreateArray();
    bluePlayersReady = CreateArray();

    // add a global forward for other plugins to use
    g_StopDeathMatching  = CreateGlobalForward("SOAP_StopDeathMatching", ET_Event);
    g_StartDeathMatching = CreateGlobalForward("SOAP_StartDeathMatching", ET_Event);

    // i don't think any of this is needed as OnPluginStart calls OnMapStart and most of it gets set there?
    //dming = false;
    //
    //// start!
    //StartDeathmatching();
    //
    //// forcibly unreadies teams on late load
    //ServerCommand("mp_tournament_restart");
}

/* OnMapStart()
 *
 * When the map starts - also run on plugin start
 * -------------------------------------------------------------------------- */
public void OnMapStart()
{
    teamReadyState[RED] = false;
    teamReadyState[BLU] = false;

    dming = false;
    ServerCommand("mp_tournament_restart");
    StartDeathmatching();
}

/* StopDeathmatching()
 *
 * Executes soap_live.cfg if it hasn't already been executed..
 * -------------------------------------------------------------------------- */
void StopDeathmatching()
{
    Call_StartForward(g_StopDeathMatching);
    Call_Finish();
    ServerCommand("exec sourcemod/soap_live.cfg");
    MC_PrintToChatAll(SOAP_TAG ... "{green}%t", "Plugins unloaded");
    ClearArray(redPlayersReady);
    ClearArray(bluePlayersReady);
    dming = false;
}

/* StartDeathmatching()
 *
 * Executes soap_notlive.cfg if it hasn't already been executed..
 * -------------------------------------------------------------------------- */
void StartDeathmatching()
{
    Call_StartForward(g_StartDeathMatching);
    Call_Finish();
    ServerCommand("exec sourcemod/soap_notlive.cfg");
    MC_PrintToChatAll(SOAP_TAG ... "{red}%t", "Plugins reloaded");
    ClearArray(redPlayersReady);
    ClearArray(bluePlayersReady);
    dming = true;
}

// ====[ CALLBACKS ]===================================================

public void Event_TournamentStateupdate(Handle event, const char[] name, bool dontBroadcast)
{
    // significantly more robust way of getting team ready status
    // the != 0 converts the result to a bool
    teamReadyState[RED] = GameRules_GetProp("m_bTeamReady", 1, 2) != 0;
    teamReadyState[BLU] = GameRules_GetProp("m_bTeamReady", 1, 3) != 0;

    // If both teams are ready, StopDeathmatching.
    if (teamReadyState[RED] && teamReadyState[BLU])
    {
        StopDeathmatching();
    }
    // don't start deathmatching again if we're already dming!
    else if (!dming)
    {
        // One or more of the teams isn't ready, StartDeathmatching.
        StartDeathmatching();
    }
}

public Action Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast)
{
    int clientid = GetEventInt(event, "userid");

    // players switching teams unreadies teams without triggering tournament_stateupdate. Crutch!
    teamReadyState[RED] = GameRules_GetProp("m_bTeamReady", 1, 2) != 0;
    teamReadyState[BLU] = GameRules_GetProp("m_bTeamReady", 1, 3) != 0;

    if (FindValueInArray(redPlayersReady, clientid) != -1)
    {
        RemoveFromArray(redPlayersReady, FindValueInArray(redPlayersReady, clientid));
    }
    else if (FindValueInArray(bluePlayersReady, clientid) != -1)
    {
        RemoveFromArray(bluePlayersReady, FindValueInArray(bluePlayersReady, clientid));
    }

    return Plugin_Continue;
}

public Action Event_GameOver(Handle event, const char[] name, bool dontBroadcast)
{
    teamReadyState[RED] = false;
    teamReadyState[BLU] = false;
    StartDeathmatching();

    return Plugin_Continue;
}

public Action TournamentRestartHook(int args)
{
    teamReadyState[RED] = false;
    teamReadyState[BLU] = false;
    StartDeathmatching();

    return Plugin_Continue;
}

public void handler_ConVarChange(Handle convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_cvReadyModeCountdown && GetConVarBool(g_cvEnforceReadyModeCountdown))
    {
        SetConVarInt(g_cvReadyModeCountdown, 5, true, true);
    }
    if (convar == g_cvEnforceReadyModeCountdown && StringToInt(newValue) == 1)
    {
        SetConVarInt(g_cvReadyModeCountdown, 5, true, true);
    }
}

public Action Listener_TournamentPlayerReadystate(int client, const char[] command, int args)
{
    char arg[4];
    int min = GetConVarInt(g_readymode_min);
    int clientid = GetClientUserId(client);
    int clientTeam = GetClientTeam(client);

    GetCmdArg(1, arg, sizeof(arg));
    if (StrEqual(arg, "1"))
    {
        if (clientTeam - TEAM_OFFSET == 0)
        {
            PushArrayCell(redPlayersReady, clientid);
        }
        else if (clientTeam - TEAM_OFFSET == 1)
        {
            PushArrayCell(bluePlayersReady, clientid);
        }
    }
    else if (StrEqual(arg, "0"))
    {
        if (clientTeam - TEAM_OFFSET == 0)
        {
            RemoveFromArray(redPlayersReady, FindValueInArray(redPlayersReady, clientid));
        }
        else if (clientTeam - TEAM_OFFSET == 1)
        {
            RemoveFromArray(bluePlayersReady, FindValueInArray(bluePlayersReady, clientid));
        }
    }
    if (GetArraySize(redPlayersReady) == min && GetArraySize(bluePlayersReady) == min)
    {
        StopDeathmatching();
    }

    return Plugin_Continue;
}
