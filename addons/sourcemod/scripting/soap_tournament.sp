#pragma semicolon 1
#include <sourcemod>

// ====[ CONSTANTS ]===================================================
#define PLUGIN_NAME		"SOAP Tournament"
#define PLUGIN_AUTHOR		"Lange"
#define PLUGIN_VERSION		"3.4"
#define PLUGIN_CONTACT		"http://steamcommunity.com/id/langeh/"
#define RED 0
#define BLU 1
#define TEAM_OFFSET 2

// ====[ PLUGIN ]======================================================
public Plugin:myinfo =
{
	name			= PLUGIN_NAME,
	author			= PLUGIN_AUTHOR,
	description	= "Automatically loads and unloads plugins when a mp_tournament match goes live or ends.",
	version		= PLUGIN_VERSION,
	url				= PLUGIN_CONTACT
};

// ====[ VARIABLES ]===================================================

new bool:teamReadyState[2] = { false, false },
	bool:g_dm = false,
	Handle:redPlayersReady,
	Handle:bluePlayersReady,
	Handle:g_readymode_min;

ConVar g_cvReadyModeCountdown;
ConVar g_cvEnforceReadyModeCountdown;


// ====[ FUNCTIONS ]===================================================

/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------- */

public OnPluginStart()
{
	LoadTranslations("soap_tf2dm.phrases");
	// Game restart
	//HookEvent("teamplay_restart_round", GameRestartEvent);

	// Win conditions met (maxrounds, timelimit)
	HookEvent("teamplay_game_over", GameOverEvent);

	// Win conditions met (windifference)
	HookEvent("tf_game_over", GameOverEvent);

	// Hook into mp_tournament_restart
	RegServerCmd("mp_tournament_restart", TournamentRestartHook);
	
	//HookEvent("teamplay_round_restart_seconds", Event_TeamplayRestartSeconds);
	HookEvent("tournament_stateupdate", Event_TournamentStateupdate); 

	// Hook for events when player changes their team.
	HookEvent("player_team", Event_PlayerTeam);

	// Listen for player readying or unreadying.
	AddCommandListener(Listener_TournamentPlayerReadystate, "tournament_player_readystate");

	g_cvEnforceReadyModeCountdown = CreateConVar("soap_enforce_readymode_countdown", "1", "Set as 1 to keep mp_tournament_readymode_countdown 5 so P-Rec works properly", _, true, 0.0, true, 1.0);
	g_cvReadyModeCountdown = FindConVar("mp_tournament_readymode_countdown");
	g_readymode_min = FindConVar("mp_tournament_readymode_min");
	SetConVarInt(g_cvReadyModeCountdown, 5, true, true);
	HookConVarChange(g_cvEnforceReadyModeCountdown, handler_ConVarChange);
	HookConVarChange(g_cvReadyModeCountdown, handler_ConVarChange);
	
	redPlayersReady = CreateArray();
	bluePlayersReady = CreateArray();

	StartDeathmatching();
}

/* OnMapStart()
 *
 * When the map starts.
 * -------------------------------------------------------------------------- */
public OnMapStart()
{
	teamReadyState[0] = false;
	teamReadyState[1] = false;
	StartDeathmatching();
}

/* StopDeathmatching()
 *
 * Executes soap_live.cfg if it hasn't already been executed..
 * -------------------------------------------------------------------------- */
StopDeathmatching()
{
	if(g_dm == true)
	{
		ServerCommand("exec sourcemod/soap_live.cfg");
		PrintToChatAll("[SOAP] %t", "Plugins unloaded");
		ClearArray(redPlayersReady);
		ClearArray(bluePlayersReady);
		g_dm = false;
	}
}

/* StartDeathmatching()
 *
 * Executes soap_notlive.cfg if it hasn't already been executed..
 * -------------------------------------------------------------------------- */
StartDeathmatching()
{
	if(g_dm == false)
	{
		ServerCommand("exec sourcemod/soap_notlive.cfg");
		PrintToChatAll("[SOAP] %t", "Plugins reloaded");
		ClearArray(redPlayersReady);
		ClearArray(bluePlayersReady);
		g_dm = true;
	}
}

// ====[ CALLBACKS ]===================================================

public Event_TournamentStateupdate(Handle:event, const String:name[], bool:dontBroadcast)
{
	
	new team = GetClientTeam(GetEventInt(event, "userid")) - TEAM_OFFSET;
	new bool:nameChange = GetEventBool(event, "namechange");
	new bool:readyState = GetEventBool(event, "readystate");

	if (!nameChange)
	{
		teamReadyState[team] = readyState;

		// If both teams are ready, StopDeathmatching.
		if (teamReadyState[RED] && teamReadyState[BLU])
		{
			StopDeathmatching();
		} else { // One or more of the teams isn't ready, StartDeathmatching.
			StartDeathmatching();
		}
	}
}

public Event_PlayerTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	new clientid = GetEventInt(event, "userid");
	RemoveFromArray(redPlayersReady, FindValueInArray(redPlayersReady, clientid));
}

public GameOverEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	teamReadyState[0] = false;
	teamReadyState[1] = false;
	StartDeathmatching();
}

public Action:TournamentRestartHook(args)
{
	teamReadyState[0] = false;
	teamReadyState[1] = false;
	StartDeathmatching();
	return Plugin_Continue;
}

public handler_ConVarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(convar == g_cvReadyModeCountdown && GetConVarBool(g_cvEnforceReadyModeCountdown))
	{
		SetConVarInt(g_cvReadyModeCountdown, 5, true, true);
	}
	if(convar == g_cvEnforceReadyModeCountdown && StringToInt(newValue) == 1)
	{
		SetConVarInt(g_cvReadyModeCountdown, 5, true, true);
	}
}

public Action:Listener_TournamentPlayerReadystate(client, const String:command[], args)
{
	decl String:arg[4];
	new min = GetConVarInt(g_readymode_min), clientid = GetClientUserId(client);
	GetCmdArg(1, arg, sizeof(arg));
	if (StrEqual(arg, "1"))
	{
		if (GetClientTeam(client) - TEAM_OFFSET == 0)
		{
			PushArrayCell(redPlayersReady, clientid);
		} else if (GetClientTeam(client) - TEAM_OFFSET == 1)
		{
			PushArrayCell(bluePlayersReady, clientid);
		}
	} else if (StrEqual(arg, "0"))
	{
		if (GetClientTeam(client) - TEAM_OFFSET == 0)
		{
			RemoveFromArray(redPlayersReady, FindValueInArray(redPlayersReady, clientid));
		} else if (GetClientTeam(client) - TEAM_OFFSET == 1)
		{
			RemoveFromArray(bluePlayersReady, FindValueInArray(bluePlayersReady, clientid));
		}
	}
	if (GetArraySize(redPlayersReady) == min && GetArraySize(bluePlayersReady) == min)
	{
		StopDeathmatching();
	}
}
