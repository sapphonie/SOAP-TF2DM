#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <color_literals>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>

// ====[ CONSTANTS ]===================================================
#define PLUGIN_NAME         "SOAP Tournament"
#define PLUGIN_AUTHOR       "Lange - maintained by sappho.io"
#define PLUGIN_VERSION      "3.8.1"
#define PLUGIN_CONTACT      "https://steamcommunity.com/id/langeh/"
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

bool teamReadyState[2];
ArrayList redPlayersReady;
ArrayList bluePlayersReady;
ConVar g_readymode_min;
// global forward handle;
GlobalForward g_fwStopDeathMatching;
GlobalForward g_fwStartDeathMatching;
// ConVars
ConVar g_cvReadyModeCountdown;
ConVar g_cvEnforceReadyModeCountdown;

// ====[ FUNCTIONS ]===================================================

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    RegPluginLibrary("soap_tournament");
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

    //HookEvent("teamplay_round_restart_seconds", Event_TeamplayRestartSeconds);
    HookEvent("tournament_stateupdate", Event_TournamentStateupdate);

    // Hook for events when player changes their team.
    HookEvent("player_team", Event_PlayerTeam);

    // Hook into mp_tournament_restart
    RegServerCmd("mp_tournament_restart", TournamentRestartHook);

    // Listen for player readying or unreadying.
    AddCommandListener(Listener_TournamentPlayerReadystate, "tournament_player_readystate");

    g_cvEnforceReadyModeCountdown = CreateConVar("soap_enforce_readymode_countdown", "1", "Set as 1 to keep mp_tournament_readymode_countdown 5 so P-Rec works properly", _, true, 0.0, true, 1.0);
    g_cvReadyModeCountdown = FindConVar("mp_tournament_readymode_countdown");
    g_readymode_min = FindConVar("mp_tournament_readymode_min");

    g_cvReadyModeCountdown.SetInt(5, true, true);
    
    g_cvEnforceReadyModeCountdown.AddChangeHook(handler_ConVarChange);
    g_cvReadyModeCountdown.AddChangeHook(handler_ConVarChange);

    redPlayersReady = new ArrayList();
    bluePlayersReady = new ArrayList();

    // add a global forward for other plugins to use
    g_fwStopDeathMatching = new GlobalForward("SOAP_StopDeathMatching", ET_Event);
    g_fwStartDeathMatching = new GlobalForward("SOAP_StartDeathMatching", ET_Event);

    StartDeathmatching();

    // forcibly unreadies teams on late load
    ServerCommand("mp_tournament_restart");
}

/* OnMapStart()
 *
 * When the map starts.
 * -------------------------------------------------------------------------- */
public void OnMapStart()
{
    teamReadyState[RED] = false;
    teamReadyState[BLU] = false;

    StartDeathmatching();
}

/* StopDeathmatching()
 *
 * Executes soap_live.cfg if it hasn't already been executed..
 * -------------------------------------------------------------------------- */
void StopDeathmatching()
{
    Call_StartForward(g_fwStopDeathMatching);
    Call_Finish();
    ServerCommand("exec sourcemod/soap_live.cfg");
    PrintColoredChatAll(COLOR_LIME ... "[" ... "\x0700FFBF" ... "SOAP" ... COLOR_LIME ... "]" ... COLOR_WHITE ... " " ... COLOR_GREEN ... "%t", "Plugins unloaded");
    redPlayersReady.Clear();
    bluePlayersReady.Clear();
}

/* StartDeathmatching()
 *
 * Executes soap_notlive.cfg if it hasn't already been executed..
 * -------------------------------------------------------------------------- */
void StartDeathmatching()
{
    Call_StartForward(g_fwStartDeathMatching);
    Call_Finish();
    ServerCommand("exec sourcemod/soap_notlive.cfg");
    PrintColoredChatAll(COLOR_LIME ... "[" ... "\x0700FFBF" ... "SOAP" ... COLOR_LIME ... "]" ... COLOR_WHITE ... " " ... COLOR_RED ... "%t", "Plugins reloaded");
    redPlayersReady.Clear();
    bluePlayersReady.Clear();
}
// ====[ CALLBACKS ]===================================================

public void Event_TournamentStateupdate(Event event, const char[] name, bool dontBroadcast)
{
    // significantly more robust way of getting team ready status
    teamReadyState[RED] = GameRules_GetProp("m_bTeamReady", 1, .element=2) != 0;
    teamReadyState[BLU] = GameRules_GetProp("m_bTeamReady", 1, .element=3) != 0;

    // If both teams are ready, StopDeathmatching.
    if (teamReadyState[RED] && teamReadyState[BLU])
    {
        StopDeathmatching();
    }
    else
    {
        // One or more of the teams isn't ready, StartDeathmatching.
        StartDeathmatching();
    }
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int clientid = event.GetInt("userid");

    // players switching teams unreadies teams without triggering tournament_stateupdate. Crutch!
    teamReadyState[RED] = GameRules_GetProp("m_bTeamReady", 1, .element=2) != 0;
    teamReadyState[BLU] = GameRules_GetProp("m_bTeamReady", 1, .element=3) != 0;

    if (redPlayersReady.FindValue(clientid) != -1)
    {
        redPlayersReady.Erase(redPlayersReady.FindValue(clientid));
    }
    else if (bluePlayersReady.FindValue(clientid) != -1)
    {
        bluePlayersReady.Erase(bluePlayersReady.FindValue(clientid));
    }
}

public Action Event_GameOver(Event event, const char[] name, bool dontBroadcast)
{
    teamReadyState[RED] = false;
    teamReadyState[BLU] = false;
    StartDeathmatching();
}

public Action TournamentRestartHook(int args)
{
    teamReadyState[RED] = false;
    teamReadyState[BLU] = false;
    StartDeathmatching();
}

public void handler_ConVarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_cvReadyModeCountdown && g_cvEnforceReadyModeCountdown.BoolValue)
    {
        g_cvReadyModeCountdown.SetInt(5, true, true);
    }
    if (convar == g_cvEnforceReadyModeCountdown && StringToInt(newValue) == 1)
    {
        g_cvReadyModeCountdown.SetInt(5, true, true);
    }
}

public Action Listener_TournamentPlayerReadystate(int client, const char[] command, int args)
{
    char arg[4];
    int min = g_readymode_min.IntValue;
    int clientid = GetClientUserId(client);
    int clientTeam = GetClientTeam(client);

    GetCmdArg(1, arg, sizeof(arg));
    if (StrEqual(arg, "1"))
    {
        if (clientTeam - TEAM_OFFSET == 0)
        {
            redPlayersReady.Push(clientid);
        }
        else if (clientTeam - TEAM_OFFSET == 1)
        {
            bluePlayersReady.Push(clientid);
        }
    }
    else if (StrEqual(arg, "0"))
    {
        if (clientTeam - TEAM_OFFSET == 0)
        {
            redPlayersReady.Erase(redPlayersReady.FindValue(clientid));
        }
        else if (clientTeam - TEAM_OFFSET == 1)
        {
            bluePlayersReady.Erase(bluePlayersReady.FindValue(clientid));
        }
    }
    if (redPlayersReady.Length == min && bluePlayersReady.Length == min)
    {
        StopDeathmatching();
    }
}
