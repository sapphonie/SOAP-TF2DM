#pragma semicolon 1 // Force strict semicolon mode.

// ====[ INCLUDES ]====================================================
#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#undef REQUIRE_PLUGIN
#include <afk>
#include <updater>

#undef REQUIRE_EXTENSIONS
#include <cURL>

// ====[ CONSTANTS ]===================================================
#define PLUGIN_NAME		"SOAP TF2 Deathmatch"
#define PLUGIN_AUTHOR	"Icewind, MikeJS, Lange, & Tondark"
#define PLUGIN_VERSION	"3.8"
#define PLUGIN_CONTACT	"http://steamcommunity.com/id/icewind1991, http://www.mikejsavage.com/, http://steamcommunity.com/id/langeh/"
#define UPDATE_URL		"http://lange.github.io/SOAP-TF2DM/updatefile.txt"

// ====[ VARIABLES ]===================================================
new bool:FirstLoad;

// Regen-over-time
new bool:g_bRegen[MAXPLAYERS+1],
	Handle:g_hRegenTimer[MAXPLAYERS+1] = INVALID_HANDLE,
	Handle:g_hRegenHP = INVALID_HANDLE,
	g_iRegenHP,
	Handle:g_hRegenTick = INVALID_HANDLE,
	Float:g_fRegenTick,
	Handle:g_hRegenDelay = INVALID_HANDLE,
	Float:g_fRegenDelay,
	Handle:g_hKillStartRegen = INVALID_HANDLE,
	bool:g_bKillStartRegen;

// Spawning
new Handle:g_hSpawn = INVALID_HANDLE,
	Float:g_fSpawn,
	Handle:g_hSpawnRandom = INVALID_HANDLE,
	bool:g_bSpawnRandom,
	bool:g_bSpawnMap,
	Handle:g_hRedSpawns = INVALID_HANDLE,
	Handle:g_hBluSpawns = INVALID_HANDLE,
	Handle:g_hKv = INVALID_HANDLE;

// Kill Regens (hp+ammo)
new g_iMaxClips1[MAXPLAYERS+1],
	g_iMaxClips2[MAXPLAYERS+1],
	g_iMaxHealth[MAXPLAYERS+1],
	Handle:g_hKillHealRatio = INVALID_HANDLE,
	Float:g_fKillHealRatio,
	Handle:g_hDamageHealRatio = INVALID_HANDLE,
	Float:g_fDamageHealRatio,
	Handle:g_hKillHealStatic = INVALID_HANDLE,
	g_iKillHealStatic,
	Handle:g_hKillAmmo = INVALID_HANDLE,
	bool:g_bKillAmmo,
	Handle:g_hShowHP = INVALID_HANDLE,
	bool:g_bShowHP;

// Time limit enforcement
new Handle:g_hForceTimeLimit = INVALID_HANDLE,
	bool:g_bForceTimeLimit,
	Handle:g_tCheckTimeLeft = INVALID_HANDLE;

// Doors and cabinets
new Handle:g_hOpenDoors = INVALID_HANDLE, Handle:g_hDisableCabinet = INVALID_HANDLE,
	bool:g_bOpenDoors, bool:g_bDisableCabinet;

// Health packs and ammo
new Handle:g_hDisableHealthPacks = INVALID_HANDLE, Handle:g_hDisableAmmoPacks = INVALID_HANDLE,
	bool:g_bDisableHealthPacks, bool:g_bDisableAmmoPacks;

// Regen damage given on kill
#define RECENT_DAMAGE_SECONDS 10
new g_iRecentDamage[MAXPLAYERS+1][MAXPLAYERS+1][RECENT_DAMAGE_SECONDS],
	Handle:g_hRecentDamageTimer;

//AFK
new g_bAFKSupported;

//cURL
new g_bcURLSupported;

new CURL_Default_opt[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,1},
	{_:CURLOPT_TIMEOUT,300},
	{_:CURLOPT_CONNECTTIMEOUT,120},
	{_:CURLOPT_USE_SSL,CURLUSESSL_TRY},
	{_:CURLOPT_SSL_VERIFYPEER,0},
	{_:CURLOPT_SSL_VERIFYHOST,0},
	{_:CURLOPT_VERBOSE,0}
};

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

// ====[ PLUGIN ]======================================================
public Plugin:myinfo = {
	name		= PLUGIN_NAME,
	author		= PLUGIN_AUTHOR,
	description	= "Team deathmatch gameplay for TF2.",
	version		= PLUGIN_VERSION,
	url			= PLUGIN_CONTACT
};

// ====[ FUNCTIONS ]===================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	MarkNativeAsOptional("curl_easy_init");
	MarkNativeAsOptional("curl_easy_setopt_int_array");
	MarkNativeAsOptional("curl_OpenFile");
	MarkNativeAsOptional("curl_easy_setopt_handle");
	MarkNativeAsOptional("curl_easy_setopt_string");
	MarkNativeAsOptional("curl_easy_perform_thread");
	return APLRes_Success;
}

/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------- */
public OnPluginStart() {
	g_bAFKSupported = LibraryExists("afk");
	g_bcURLSupported = GetExtensionFileStatus("curl.ext") == 1 ? true : false;

	if (LibraryExists("updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}

	LoadTranslations("soap_tf2dm.phrases");

	// Create convars
	CreateConVar("soap", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_REPLICATED);
	g_hRegenHP = CreateConVar("soap_regenhp", "1", "Health added per regeneration tick. Set to 0 to disable.", FCVAR_NOTIFY);
	g_hRegenTick = CreateConVar("soap_regentick", "0.1", "Delay between regeration ticks.", FCVAR_NOTIFY);
	g_hRegenDelay = CreateConVar("soap_regendelay", "5.0", "Seconds after damage before regeneration.", FCVAR_NOTIFY);
	g_hKillStartRegen = CreateConVar("soap_kill_start_regen", "1", "Start the heal-over-time regen immediately after a kill.", FCVAR_NOTIFY);
	g_hSpawn = CreateConVar("soap_spawn_delay", "1.5", "Spawn timer.", FCVAR_NOTIFY);
	g_hSpawnRandom = CreateConVar("soap_spawnrandom", "1", "Enable random spawns.", FCVAR_NOTIFY);
	g_hKillHealRatio = CreateConVar("soap_kill_heal_ratio", "0.5", "Percentage of HP to restore on kills. .5 = 50%. Should not be used with soap_kill_heal_static.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hDamageHealRatio = CreateConVar("soap_dmg_heal_ratio", "0.0", "Percentage of HP to restore based on amount of damage given. .5 = 50%. Should not be used with soap_kill_heal_static.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hKillHealStatic = CreateConVar("soap_kill_heal_static", "0", "Amount of HP to restore on kills. Exact value applied the same to all classes. Should not be used with soap_kill_heal_ratio.", FCVAR_NOTIFY);
	g_hKillAmmo = CreateConVar("soap_kill_ammo", "1", "Enable ammo restoration on kills.", FCVAR_NOTIFY);
	g_hOpenDoors = CreateConVar("soap_opendoors", "1", "Force all doors to open. Required on maps like cp_well.", FCVAR_NOTIFY);
	g_hDisableCabinet = CreateConVar("soap_disablecabinet", "1", "Disables the resupply cabinets on map load", FCVAR_NOTIFY);
	g_hShowHP = CreateConVar("soap_showhp", "1", "Print killer's health to victim on death.", FCVAR_NOTIFY);
	g_hForceTimeLimit  = CreateConVar("soap_forcetimelimit", "1", "Time limit enforcement, used to fix a never-ending round issue on gravelpit.", _, true, 0.0, true, 1.0);
	g_hDisableHealthPacks = CreateConVar("soap_disablehealthpacks", "0", "Disables the health packs on map load.", FCVAR_NOTIFY);
	g_hDisableAmmoPacks = CreateConVar("soap_disableammopacks", "0", "Disables the ammo packs on map load.", FCVAR_NOTIFY);

	// Hook convar changes and events
	HookConVarChange(g_hRegenHP, handler_ConVarChange);
	HookConVarChange(g_hRegenTick, handler_ConVarChange);
	HookConVarChange(g_hRegenDelay, handler_ConVarChange);
	HookConVarChange(g_hKillStartRegen, handler_ConVarChange);
	HookConVarChange(g_hSpawn, handler_ConVarChange);
	HookConVarChange(g_hSpawnRandom, handler_ConVarChange);
	HookConVarChange(g_hKillHealRatio, handler_ConVarChange);
	HookConVarChange(g_hDamageHealRatio, handler_ConVarChange);
	HookConVarChange(g_hKillHealStatic, handler_ConVarChange);
	HookConVarChange(g_hKillAmmo, handler_ConVarChange);
	HookConVarChange(g_hOpenDoors, handler_ConVarChange);
	HookConVarChange(g_hDisableCabinet, handler_ConVarChange);
	HookConVarChange(g_hShowHP, handler_ConVarChange);
	HookConVarChange(g_hForceTimeLimit, handler_ConVarChange);
	HookConVarChange(g_hDisableHealthPacks, handler_ConVarChange);
	HookConVarChange(g_hDisableAmmoPacks, handler_ConVarChange);
	HookEvent("player_death", Event_player_death);
	HookEvent("player_hurt", Event_player_hurt);
	HookEvent("player_spawn", Event_player_spawn);
	HookEvent("player_team", Event_player_team);
	HookEvent("teamplay_round_start", Event_round_start);
	HookEvent("teamplay_restart_round", Event_round_start);

	// Create arrays for the spawning system
	g_hRedSpawns = CreateArray();
	g_hBluSpawns = CreateArray();

	// Crutch to fix some issues that appear when the plugin is loaded mid-round.
	FirstLoad = true;

	// Begin the time check that prevents infinite rounds on A/D and KOTH maps. It is run here as well as in OnMapStart() so that it will still work even if the plugin is loaded mid-round.
	CreateTimeCheck();

	// Lock control points and intel on map. Also respawn all players into DM spawns. This instance of LockMap() is needed for mid-round loads of DM. (See: Volt's DM/Pub hybrid server.)
	LockMap();

	// Reset all player's regens. Used here for mid-round loading compatability.
	ResetPlayers();

	// Create configuration file in cfg/sourcemod folder
	AutoExecConfig(true, "soap_tf2dm", "sourcemod");
}

public OnLibraryAdded(const String:name[]) {
	// Set up auto updater
	if (StrEqual(name, "afk")) {
		g_bAFKSupported = true;
	}

	if (StrEqual(name, "cURL")) {
		g_bcURLSupported = true;
	}

	if (StrEqual(name, "updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public OnLibraryRemoved(const String:name[]) {
	if (StrEqual(name, "afk")) {
		g_bAFKSupported = false;
	}

	if (StrEqual(name, "cURL")) {
		g_bcURLSupported = false;
	}
}

/* OnGetGameDescription()
 *
 * When the game description is polled.
 * -------------------------------------------------------------------------- */
public Action:OnGetGameDescription(String:gameDesc[64]) {
	// Changes the game description from "Team Fortress 2" to "SOAP TF2DM vx.x")
	Format(gameDesc, sizeof(gameDesc), "SOAP TF2DM v%s",PLUGIN_VERSION);
	return Plugin_Changed;
}

/* OnMapStart()
 *
 * When the map starts.
 * -------------------------------------------------------------------------- */
public OnMapStart() {
	// Kill everything, because fuck memory leaks.
	if (g_tCheckTimeLeft != INVALID_HANDLE) {
		KillTimer(g_tCheckTimeLeft);
		g_tCheckTimeLeft = INVALID_HANDLE;
	}

	for (new i = 0; i < MaxClients+1; i++) {
		if (g_hRegenTimer[i]!=INVALID_HANDLE) {
			KillTimer(g_hRegenTimer[i]);
			g_hRegenTimer[i] = INVALID_HANDLE;
		}
	}

	// Spawn system written by MikeJS.
	ClearArray(g_hRedSpawns);
	ClearArray(g_hBluSpawns);

	for (new i = 0; i < MAXPLAYERS; i++) {
		PushArrayCell(g_hRedSpawns, CreateArray(6));
		PushArrayCell(g_hBluSpawns, CreateArray(6));
	}

	g_bSpawnMap = false;

	if (g_hKv!=INVALID_HANDLE) {
		CloseHandle(g_hKv);
	}

	g_hKv = CreateKeyValues("Spawns");

	decl String:map[64];
	GetCurrentMap(map, sizeof(map));

	decl String:path[256];
	BuildPath(Path_SM, path, sizeof(path), "configs/soap/%s.cfg", map);

	if (FileExists(path)) {
		LoadMapConfig(map, path);
	} else {
		if (g_bcURLSupported) {
			DownloadConfig(map, path);
		} else {
			SetFailState("Map spawns missing. Map: %s, no cURL support", map);
			LogError("File Not Found: %s, no cURL support", path);
		}
	}
	// End spawn system.

	// Load the sound file played when a player is spawned.
	PrecacheSound("items/spawn_item.wav", true);

	// Begin the time check that prevents infinite rounds on A/D and KOTH maps.
	CreateTimeCheck();
}

public LoadMapConfig(const String:map[], const String:path[]) {
	g_bSpawnMap = true;
	FileToKeyValues(g_hKv, path);

	decl String:players[4], Float:vectors[6], Float:origin[3], Float:angles[3];
	new iplayers;

	do {
		KvGetSectionName(g_hKv, players, sizeof(players));
		iplayers = StringToInt(players);

		if (KvJumpToKey(g_hKv, "red")) {
			KvGotoFirstSubKey(g_hKv);
			do {
				KvGetVector(g_hKv, "origin", origin);
				KvGetVector(g_hKv, "angles", angles);

				vectors[0] = origin[0];
				vectors[1] = origin[1];
				vectors[2] = origin[2];
				vectors[3] = angles[0];
				vectors[4] = angles[1];
				vectors[5] = angles[2];

				for (new i = iplayers; i < MAXPLAYERS; i++) {
					PushArrayArray(GetArrayCell(g_hRedSpawns, i), vectors);
				}
			} while (KvGotoNextKey(g_hKv));

			KvGoBack(g_hKv);
			KvGoBack(g_hKv);
		} else {
			SetFailState("Red spawns missing. Map: %s  Players: %i", map, iplayers);
		}

		if (KvJumpToKey(g_hKv, "blue")) {
			KvGotoFirstSubKey(g_hKv);
			do {
				KvGetVector(g_hKv, "origin", origin);
				KvGetVector(g_hKv, "angles", angles);

				vectors[0] = origin[0];
				vectors[1] = origin[1];
				vectors[2] = origin[2];
				vectors[3] = angles[0];
				vectors[4] = angles[1];
				vectors[5] = angles[2];

				for (new i = iplayers; i < MAXPLAYERS; i++) {
					PushArrayArray(GetArrayCell(g_hBluSpawns, i), vectors);
				}
			} while (KvGotoNextKey(g_hKv));
		} else {
			SetFailState("Blue spawns missing. Map: %s  Players: %i", map, iplayers);
		}
	} while (KvGotoNextKey(g_hKv));
}

/* OnMapEnd()
 *
 * When the map ends.
 * -------------------------------------------------------------------------- */
public OnMapEnd() {
	// Memory leaks: fuck 'em.

	if (g_tCheckTimeLeft!=INVALID_HANDLE) {
		KillTimer(g_tCheckTimeLeft);
		g_tCheckTimeLeft = INVALID_HANDLE;
	}

	for (new i = 0; i < MAXPLAYERS + 1; i++) {
		if (g_hRegenTimer[i] != INVALID_HANDLE) {
			KillTimer(g_hRegenTimer[i]);
			g_hRegenTimer[i] = INVALID_HANDLE;
		}
	}
}

/* OnConfigsExecuted()
 *
 * When game configurations (e.g., map-specific configs) are executed.
 * -------------------------------------------------------------------------- */
public OnConfigsExecuted() {
	// Get the values for internal global variables.
	g_iRegenHP = GetConVarInt(g_hRegenHP);
	g_fRegenTick = GetConVarFloat(g_hRegenTick);
	g_fRegenDelay = GetConVarFloat(g_hRegenDelay);
	g_bKillStartRegen = GetConVarBool(g_hKillStartRegen);
	g_fSpawn = GetConVarFloat(g_hSpawn);
	g_bSpawnRandom = GetConVarBool(g_hSpawnRandom);
	g_fKillHealRatio = GetConVarFloat(g_hKillHealRatio);
	g_fDamageHealRatio = GetConVarFloat(g_hDamageHealRatio);
	StartStopRecentDamagePushbackTimer();
	g_iKillHealStatic = GetConVarInt(g_hKillHealStatic);
	g_bKillAmmo = GetConVarBool(g_hKillAmmo);
	g_bOpenDoors = GetConVarBool(g_hOpenDoors);
	g_bDisableCabinet = GetConVarBool(g_hDisableCabinet);
	g_bShowHP = GetConVarBool(g_hShowHP);
	g_bForceTimeLimit = GetConVarBool(g_hForceTimeLimit);
	g_bDisableHealthPacks = GetConVarBool(g_hDisableHealthPacks);
	g_bDisableAmmoPacks = GetConVarBool(g_hDisableAmmoPacks);
}


/* OnClientConnected()
 *
 * When a client connects to the server.
 * -------------------------------------------------------------------------- */
public OnClientConnected(client) {
	// Set the client's slot regen timer handle to INVALID_HANDLE.
	if (g_hRegenTimer[client] != INVALID_HANDLE) {
		KillTimer(g_hRegenTimer[client]);
		g_hRegenTimer[client] = INVALID_HANDLE;
	}

	// Reset the player's damage given/received to 0.
	ResetPlayerDmgBasedRegen(client, true);

	// Kills the annoying 30 second "waiting for players" at the start of a map.
	ServerCommand("mp_waitingforplayers_cancel 1");
}

/* OnClientDisconnect()
 *
 * When a client disconnects from the server.
 * -------------------------------------------------------------------------- */
public OnClientDisconnect(client) {
	// Set the client's slot regen timer handle to INVALID_HANDLE again because I really don't want to take any chances.
	if (g_hRegenTimer[client] != INVALID_HANDLE) {
		KillTimer(g_hRegenTimer[client]);
		g_hRegenTimer[client] = INVALID_HANDLE;
	}
}

/* handler_ConVarChange()
 *
 * Called when a convar's value is changed..
 * -------------------------------------------------------------------------- */
public handler_ConVarChange(Handle:convar, const String:oldValue[], const String:newValue[]) {
	// When a cvar is changed during runtime, this is called and the corresponding internal variable is updated to reflect this change.
	// SourcePawn can't `switch` with Strings, so this huge if/else chain is our only option.
	if (convar == g_hRegenHP) {
		g_iRegenHP = StringToInt(newValue);
	} else if (convar == g_hRegenTick) {
		g_fRegenTick = StringToFloat(newValue);
	} else if (convar == g_hRegenDelay) {
		g_fRegenDelay = StringToFloat(newValue);
	} else if (convar == g_hKillStartRegen) {
		if (StringToInt(newValue) >= 1) {
			g_bKillStartRegen = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bKillStartRegen = false;
		}
	} else if (convar == g_hSpawn) {
		g_fSpawn = StringToFloat(newValue);
	} else if (convar == g_hSpawnRandom) {
		if (StringToInt(newValue) >= 1) {
			g_bSpawnRandom = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bSpawnRandom = false;
		}
	} else if (convar == g_hKillHealRatio) {
		g_fKillHealRatio = StringToFloat(newValue);
	} else if (convar == g_hDamageHealRatio) {
		g_fDamageHealRatio = StringToFloat(newValue);
		StartStopRecentDamagePushbackTimer();
	} else if (convar == g_hKillHealStatic) {
		g_iKillHealStatic = StringToInt(newValue);
	} else if (convar == g_hKillAmmo) {
		if (StringToInt(newValue) >= 1) {
			g_bKillAmmo = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bKillAmmo = false;
		}
	} else if (convar == g_hForceTimeLimit) {
		if (StringToInt(newValue) >= 1) {
			g_bForceTimeLimit = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bForceTimeLimit = false;
		}
	} else if (convar == g_hOpenDoors) {
		if (StringToInt(newValue) >= 1) {
			g_bOpenDoors = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bOpenDoors = false;
		}
	} else if (convar == g_hDisableCabinet) {
		if (StringToInt(newValue) >= 1) {
			g_bDisableCabinet = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bDisableCabinet = false;
		}
	} else if (convar == g_hShowHP) {
		if (StringToInt(newValue) >= 1) {
			g_bShowHP = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bShowHP = false;
		}
	} else if (convar == g_hDisableHealthPacks) {
		if (StringToInt(newValue) >= 1) {
			g_bDisableHealthPacks = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bDisableHealthPacks = false;
		}
	} else if (convar == g_hDisableAmmoPacks) {
		if (StringToInt(newValue) >= 1) {
			g_bDisableAmmoPacks = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bDisableAmmoPacks = false;
		}
	}
}

/*
 * ------------------------------------------------------------------
 *	  _______                 ___            _ __
 *	 /_  __(_)____ ___  ___  / (_)____ ___  (_) /_
 *	  / / / // __ `__ \/ _ \/ / // __ `__ \/ / __/
 *	 / / / // / / / / /  __/ / // / / / / / / /_
 *	/_/ /_//_/ /_/ /_/\___/_/_//_/ /_/ /_/_/\__/
 * ------------------------------------------------------------------
 */

/* CheckTime()
 *
 * Check map time left every 15 seconds.
 * -------------------------------------------------------------------------- */
public Action:CheckTime(Handle:timer) {
	new iTimeLeft;
	new iTimeLimit;
	GetMapTimeLeft(iTimeLeft);
	GetMapTimeLimit(iTimeLimit);

	// If soap_forcetimelimit = 1, mp_timelimit != 0, and the timeleft is < 0, change the map to sm_nextmap in 15 seconds.
	if (g_bForceTimeLimit && iTimeLeft <= 0 && iTimeLimit > 0) {
		if (GetRealClientCount() > 0) { // Prevents a constant map change issue present on a small number of servers.
			CreateTimer(15.0, ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
			if (g_tCheckTimeLeft != INVALID_HANDLE) {
				KillTimer(g_tCheckTimeLeft);
				g_tCheckTimeLeft = INVALID_HANDLE;
			}
		}
	}
}

/* ChangeMap()
 *
 * Changes the map whatever sm_nextmap is.
 * -------------------------------------------------------------------------- */
public Action:ChangeMap(Handle:timer) {
	// If sm_nextmap isn't set or isn't registered, abort because there is nothing to change to.
	if (FindConVar("sm_nextmap") == INVALID_HANDLE) {
		LogError("[SOAP] FATAL: Could not find sm_nextmap cvar. Cannot force a map change!");
		return;
	}

	new iTimeLeft;
	new iTimeLimit;
	GetMapTimeLeft(iTimeLeft);
	GetMapTimeLimit(iTimeLimit);

	// Check that soap_forcetimelimit = 1, mp_timelimit != 0, and timeleft < 0 again, because something could have changed in the last 15 seconds.
	if (g_bForceTimeLimit && iTimeLeft <= 0 &&  iTimeLimit > 0) {
		new String:newmap[65];
		GetNextMap(newmap, sizeof(newmap));
		ForceChangeLevel(newmap, "Enforced Map Timelimit");
	} else {  // Turns out something did change.
		LogMessage("[SOAP] Aborting forced map change due to soap_forcetimelimit 1 or timelimit > 0.");

		if (iTimeLeft > 0) {
			CreateTimeCheck();
		}
	}
}

/* CreateTimeCheck()
 *
 * Used to create the timer that checks if the round is over.
 * -------------------------------------------------------------------------- */
CreateTimeCheck() {
	if (g_tCheckTimeLeft != INVALID_HANDLE) {
		KillTimer(g_tCheckTimeLeft);
		g_tCheckTimeLeft = INVALID_HANDLE;
	}

	g_tCheckTimeLeft = CreateTimer(15.0, CheckTime, _, TIMER_REPEAT);
}

/*
 * ------------------------------------------------------------------
 *	   _____                            _
 *	  / ___/____  ____ __      ______  (_)____  ____ _
 *	  \__ \/ __ \/ __ `/ | /| / / __ \/ // __ \/ __ `/
 *	 ___/ / /_/ / /_/ /| |/ |/ / / / / // / / / /_/ /
 *	/____/ .___/\__,_/ |__/|__/_/ /_/_//_/ /_/\__, /
 *		/_/                                  /____/
 * ------------------------------------------------------------------
 */

/* RandomSpawn()
 *
 * Picks a spawn point at random from the %map%.cfg, and teleports the player to it.
 * -------------------------------------------------------------------------- */
public Action:RandomSpawn(Handle:timer, any:clientid) {
	new client = GetClientOfUserId(clientid); // UserIDs are passed through timers instead of client indexes because it ensures that no mismatches can happen as UserIDs are unique.

	if (!IsValidClient(client)) {
		return Plugin_Handled; // Client wasn't valid, so there's no point in trying to spawn it!
	}

	if (IsPlayerAlive(client)) { // Can't teleport a dead player.
		new team = GetClientTeam(client), Handle:array, size, Handle:spawns = CreateArray(), count = GetClientCount();
		decl Float:vectors[6], Float:origin[3], Float:angles[3];

		if (team == 2) { // Is player on RED?
			for (new i = 0; i <= count; i++) {
				// Yep, get the RED spawns for this map.
				array = GetArrayCell(g_hRedSpawns, i);

				if (GetArraySize(array) != 0) {
					size = PushArrayCell(spawns, array);
				}
			}
		} else { // Nope, he's on BLU.
			for (new i = 0; i <= count; i++) {
				// Get the BLU spawns.
				array = GetArrayCell(g_hBluSpawns, i);

				if (GetArraySize(array) != 0) {
					size = PushArrayCell(spawns, array);
				}
			}
		}

		array = GetArrayCell(spawns, GetRandomInt(0, GetArraySize(spawns) - 1));
		size = GetArraySize(array);
		GetArrayArray(array, GetRandomInt(0, size - 1), vectors); // Put the values from a random spawn in the config into a variable so it can be used.
		CloseHandle(spawns); // Close the handle so there are no memory leaks.

		// Put the spawn location (origin) and POV (angles) into something a bit easier to keep track of.
		origin[0] = vectors[0];
		origin[1] = vectors[1];
		origin[2] = vectors[2];
		angles[0] = vectors[3];
		angles[1] = vectors[4];
		angles[2] = vectors[5];

		/* Below is how players are prevented from spawning within one another. */

		new Handle:trace = TR_TraceHullFilterEx(origin, origin, Float:{-24.0, -24.0, 0.0}, Float:{24.0, 24.0, 82.0}, MASK_PLAYERSOLID, TraceEntityFilterPlayers);
		// The above line creates a 'box' at the spawn point to be used. This box is roughly the size of a player.

		if (TR_DidHit(trace) && IsValidClient(TR_GetEntityIndex(trace))) {
			// The 'box' hit a player!
			CloseHandle(trace);
			CreateTimer(0.01, RandomSpawn, clientid, TIMER_FLAG_NO_MAPCHANGE); // Get a new spawn, because this one is occupied.
			return Plugin_Handled;
		} else {
			// All clear.
			TeleportEntity(client, origin, angles, NULL_VECTOR); // Teleport the player to their spawn point.
			EmitAmbientSound("items/spawn_item.wav", origin); // Make a sound at the spawn point.
		}

		CloseHandle(trace); // Stops leaks dead.
	}

	return Plugin_Continue;
}

public bool:TraceEntityFilterPlayers(entity, contentsMask) {
	// Used by the 'box' method to filter out everything that isn't a player.
	return IsValidClient(entity);
}

/* Respawn()
 *
 * Respawns a player on a delay.
 * -------------------------------------------------------------------------- */
public Action:Respawn(Handle:timer, any:clientid) {
	new client = GetClientOfUserId(clientid);

	if (!IsValidClient(client)) {
		return;
	}

	TF2_RespawnPlayer(client);
}

/*
 * ------------------------------------------------------------------
 *		____
 *	   / __ \___  ____ ____  ____
 *	  / /_/ / _ \/ __ `/ _ \/ __ \
 *	 / _, _/  __/ /_/ /  __/ / / /
 *	/_/ |_|\___/\__, /\___/_/ /_/
 *			   /____/
 * ------------------------------------------------------------------
 */

/* StartRegen()
 *
 * Starts regen-over-time on a player.
 * -------------------------------------------------------------------------- */
public Action:StartRegen(Handle:timer, any:clientid) {
	new client = GetClientOfUserId(clientid);

	if (g_hRegenTimer[client]!=INVALID_HANDLE) {
		KillTimer(g_hRegenTimer[client]);
		g_hRegenTimer[client] = INVALID_HANDLE;
	}

	if (!IsValidClient(client)) {
		return;
	}

	g_bRegen[client] = true;
	Regen(INVALID_HANDLE, clientid);
}

/* Regen()
 *
 * Heals a player for X amount of health every Y seconds.
 * -------------------------------------------------------------------------- */
public Action:Regen(Handle:timer, any:clientid) {
	new client = GetClientOfUserId(clientid);

	if (g_hRegenTimer[client]!=INVALID_HANDLE) {
		KillTimer(g_hRegenTimer[client]);
		g_hRegenTimer[client] = INVALID_HANDLE;
	}

	if (!IsValidClient(client)) {
		return;
	}

	if (g_bRegen[client] && IsPlayerAlive(client)) {
		new health = GetClientHealth(client)+g_iRegenHP;

		 // If the regen would give the client more than their max hp, just set it to max.
		if (health > g_iMaxHealth[client]) {
			health = g_iMaxHealth[client];
		}

		if (GetClientHealth(client) <= g_iMaxHealth[client]) {
			SetEntProp(client, Prop_Send, "m_iHealth", health, 1);
			SetEntProp(client, Prop_Data, "m_iHealth", health, 1);
		}

		// Call this function again in g_fRegenTick seconds.
		g_hRegenTimer[client] = CreateTimer(g_fRegenTick, Regen, clientid);
	}
}

/* GetWeaponAmmo()
 *
 * Part of a crutch used when unlockreplacer.smx is loaded.
 * -------------------------------------------------------------------------- */
GetWeaponAmmo(String:w[32]) {
	/* This is needed because when unlockreplacer.smx replaces a weapon, the weapon it replaced is still what gets read when certain functions are run.
	 * Example: The buff banner is replaced with a shotgun. It works fine in-game, but the server will still report an invalid clip size, because the buff banner doesn't use ammo.
	 * So the name of the weapon that's really equipped is passed to this function, where it is paired with a static value that is it's known clip size. */

	if (StrEqual("tf_weapon_shotgun_soldier", w) || StrEqual("tf_weapon_shotgun_pyro", w) || StrEqual("tf_weapon_shotgun_hwg", w)) {
		return 6;
	} else if (StrEqual("tf_weapon_pipebomblauncher", w)) {
		return 8;
	} else if (StrEqual("tf_weapon_pistol_scout", w) || StrEqual("tf_weapon_pistol", w)) {
		return 12;
	} else if (StrEqual("tf_weapon_smg", w)) {
		return 25;
	} else {
		// Haven't the foggiest idea what weapon they're holding, just give it 1 bullet and be done with it.
		return 1;
	}
}

/* Timer_RecentDamagePushback()
 *
 * Every second push back all recent damage by 1 index.
 * This ensures we only remember the last 9-10 seconds of recent damage.
 * -------------------------------------------------------------------------- */
public Action:Timer_RecentDamagePushback(Handle:timer, any:clientid) {
	for (new i = 1; i <= MaxClients; i++) {
		if (!IsValidClient(i)) {
			continue;
		}

		for (new j = 1; j <= MaxClients; j++) {
			if (!IsValidClient(j)) {
				continue;
			}

			for (new k = RECENT_DAMAGE_SECONDS - 2; k >= 0; k--) {
				g_iRecentDamage[i][j][k+1] = g_iRecentDamage[i][j][k];
			}

			g_iRecentDamage[i][j][0] = 0;
		}
	}
}

/* StartStopRecentDamagePushbackTimer()
 *
 * Starts or stops the recent damage pushback timer, based on the current value
 * of the corresponding ConVar.
 * -------------------------------------------------------------------------- */
StartStopRecentDamagePushbackTimer() {
	if (g_fDamageHealRatio > 0.0) {
		if (g_hRecentDamageTimer == INVALID_HANDLE) {
			g_hRecentDamageTimer = CreateTimer(1.0, Timer_RecentDamagePushback, _, TIMER_REPEAT);
		}
	} else {
		if (g_hRecentDamageTimer != INVALID_HANDLE) {
			KillTimer(g_hRecentDamageTimer);
			g_hRecentDamageTimer = INVALID_HANDLE;
		}
	}
}


/*
 * ------------------------------------------------------------------
 *		______                  __
 *	   / ____/_   _____  ____  / /______
 *	  / __/  | | / / _ \/ __ \/ __/ ___/
 *	 / /___  | |/ /  __/ / / / /_(__  )
 *	/_____/  |___/\___/_/ /_/\__/____/
 *
 * ------------------------------------------------------------------
 */

/* Event_player_death()
 *
 * Called when a player dies.
 * -------------------------------------------------------------------------- */
public Action:Event_player_death(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new clientid = GetClientUserId(client);

	new isDeadRinger = GetEventInt(event,"death_flags") & 32;
	if (!IsValidClient(client) || isDeadRinger) {
		return;
	}

	CreateTimer(g_fSpawn, Respawn, clientid, TIMER_FLAG_NO_MAPCHANGE);

	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	decl String:sWeapon[32];
	new iWeapon;

	if (IsValidEntity(attacker) && attacker > 0) {
		GetClientWeapon(attacker, sWeapon, sizeof(sWeapon));
	}

	if (IsValidClient(attacker) && client != attacker) {
		if (g_bShowHP) {
			if (IsPlayerAlive(attacker)) {
				PrintToChat(client, "[SOAP] %t", "Health Remaining", GetClientHealth(attacker));
			} else {
				PrintToChat(client, "[SOAP] %t", "Attacker is dead");
			}
		}

		new targetHealth = 0;

		// Heals a percentage of the killer's class' max health.
		if (g_fKillHealRatio > 0.0) {
			if ((GetClientHealth(attacker) + RoundFloat(g_fKillHealRatio * g_iMaxHealth[attacker])) > g_iMaxHealth[attacker]) {
				targetHealth = g_iMaxHealth[attacker];
			} else {
				targetHealth = GetClientHealth(attacker) + RoundFloat(g_fKillHealRatio * g_iMaxHealth[attacker]);
			}
		}

		// Heals a flat value, regardless of class.
		if (g_iKillHealStatic > 0) {
			if ((GetClientHealth(attacker) + g_iKillHealStatic) > g_iMaxHealth[attacker]) {
				targetHealth = g_iMaxHealth[attacker];
			} else {
				targetHealth =  GetClientHealth(attacker) + g_iKillHealStatic;
			}
		}

		if (targetHealth > GetClientHealth(attacker)) {
			SetEntProp(attacker, Prop_Data, "m_iHealth", targetHealth);
		}

		// Gives full ammo for primary and secondary weapon to the player who got the kill.
		if (g_bKillAmmo) {
			// Check the primary weapon, and set its ammo.
			if (g_iMaxClips1[attacker] > 0 && TF2_GetPlayerClass(attacker) != TFClassType:2) {
				SetEntProp(GetPlayerWeaponSlot(attacker, 0), Prop_Send, "m_iClip1", g_iMaxClips1[attacker]);
			} else if (StrEqual(sWeapon, "tf_weapon_compound_bow") || StrEqual(sWeapon, "tf_weapon_grenadelauncher") || StrEqual(sWeapon, "tf_weapon_revolver") || StrEqual(sWeapon, "tf_weapon_rocketlauncher") || StrEqual(sWeapon, "tf_weapon_rocketlauncher_directhit") || StrEqual(sWeapon, "tf_weapon_scattergun") || StrEqual(sWeapon, "tf_weapon_shotgun_primary") || StrEqual(sWeapon, "tf_weapon_syringegun_medic")) {
				GetClientWeapon(attacker, sWeapon, sizeof(sWeapon));
				iWeapon = GetEntDataEnt2(attacker, FindSendPropInfo("CTFPlayer", "m_hActiveWeapon"));
				SetEntProp(iWeapon, Prop_Send, "m_iClip1", GetWeaponAmmo(sWeapon));
			}

			// Check the secondary weapon, and set its ammo.
			if (g_iMaxClips2[attacker] > 0) {
				SetEntProp(GetPlayerWeaponSlot(attacker, 1), Prop_Send, "m_iClip1", g_iMaxClips2[attacker]);
			} else if (StrEqual(sWeapon, "tf_weapon_buff_item") || StrEqual(sWeapon, "tf_weapon_pipebomblauncher") || StrEqual(sWeapon, "tf_weapon_pistol") || StrEqual(sWeapon, "tf_weapon_pistol_scout") || StrEqual(sWeapon, "tf_weapon_shotgun_hwg") || StrEqual(sWeapon, "tf_weapon_shotgun_pyro") || StrEqual(sWeapon, "tf_weapon_shotgun_soldier") || StrEqual(sWeapon, "tf_weapon_smg")) {
				GetClientWeapon(attacker, sWeapon, sizeof(sWeapon));
				iWeapon = GetEntDataEnt2(attacker, FindSendPropInfo("CTFPlayer", "m_hActiveWeapon"));
				SetEntProp(iWeapon, Prop_Send, "m_iClip1", GetWeaponAmmo(sWeapon));
			}
		}

		// Give the killer regen-over-time if so configured.
		if (g_bKillStartRegen && !g_bRegen[attacker]) {
			StartRegen(INVALID_HANDLE, attacker);
		}
	}

	// Heal the people that damaged the victim (also if the victim died without there being an attacker).
	if (g_fDamageHealRatio > 0.0) {
		decl String:clientname[32];
		GetClientName(client, clientname, sizeof(clientname));
		for (new player = 1; player <= MaxClients; player++) {
			if (!IsValidClient(player)) {
				continue;
			}

			new dmg = 0;
			for (new i = 0; i < RECENT_DAMAGE_SECONDS; i++) {
				dmg += g_iRecentDamage[client][player][i];
				g_iRecentDamage[client][player][i] = 0;
			}

			dmg = RoundFloat(dmg * g_fDamageHealRatio);

			if (dmg > 0 && IsPlayerAlive(player)) {
				if ((GetClientHealth(player) + dmg) > g_iMaxHealth[player]) {
					SetEntProp(player, Prop_Data, "m_iHealth", g_iMaxHealth[player]);
				} else {
					SetEntProp(player, Prop_Data, "m_iHealth", GetClientHealth(player) + dmg);
				}

				PrintToChat(player, "[SOAP] %t", attacker == player ? "Kill HP Received" : "Damage HP Received", dmg, clientname);
			}
		}
	}

	// Reset the player's recent damage
	if (g_fDamageHealRatio > 0.0) {
		ResetPlayerDmgBasedRegen(client);
	}
}

/* Event_player_hurt()
 *
 * Called when a player is hurt.
 * -------------------------------------------------------------------------- */
public Action:Event_player_hurt(Handle:event, const String:name[], bool:dontBroadcast) {
	new clientid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new damage = GetEventInt(event, "damageamount");

	if (IsValidClient(attacker) && client!=attacker) {
		g_bRegen[client] = false;

		if (g_hRegenTimer[client]!=INVALID_HANDLE) {
			KillTimer(g_hRegenTimer[client]);
			g_hRegenTimer[client] = INVALID_HANDLE;
		}

		g_hRegenTimer[client] = CreateTimer(g_fRegenDelay, StartRegen, clientid);
		g_iRecentDamage[client][attacker][0] += damage;
	}
}

/* Event_player_spawn()
 *
 * Called when a player spawns.
 * -------------------------------------------------------------------------- */
public Action:Event_player_spawn(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new clientid = GetClientUserId(client);

	if (g_hRegenTimer[client]!=INVALID_HANDLE) {
		KillTimer(g_hRegenTimer[client]);
		g_hRegenTimer[client] = INVALID_HANDLE;
	}

	g_hRegenTimer[client] = CreateTimer(0.01, StartRegen, clientid);

	if (!IsValidClient(client)) {
		return;
	}

	// Are random spawns on and does this map have spawns?
	if (g_bSpawnRandom && g_bSpawnMap && (!g_bAFKSupported || !IsPlayerAFK(client))) {
		CreateTimer(0.01, RandomSpawn, clientid, TIMER_FLAG_NO_MAPCHANGE);
	} else {
		// Play a sound anyway, because sounds are cool.
		// Don't play a sound if the player is AFK.
		if (!g_bAFKSupported || !IsPlayerAFK(client)) {
			decl Float:vecOrigin[3];
			GetClientEyePosition(client, vecOrigin);
			EmitAmbientSound("items/spawn_item.wav", vecOrigin);
		}
	}

	// Get the player's max health and store it in a global variable. Doing it this way is handy for things like the Gunslinger and Eyelander, which change max health.
	g_iMaxHealth[client] = GetClientHealth(client);

	// Crutch used when unlockreplacer.smx is running and it replaces a weapon that isn't equippable or has no ammo.
	g_iMaxClips1[client] = -1;
	g_iMaxClips2[client] = -1;

	// Check how much ammo each gun can hold in its clip and store it in a global variable so it can be regenerated to that amount later.
	if (IsValidEntity(GetPlayerWeaponSlot(client, 0))) {
		g_iMaxClips1[client] = GetEntProp(GetPlayerWeaponSlot(client, 0), Prop_Data, "m_iClip1");
	}

	if (IsValidEntity(GetPlayerWeaponSlot(client, 1))) {
		g_iMaxClips2[client] = GetEntProp(GetPlayerWeaponSlot(client, 1), Prop_Data, "m_iClip1");
	}
}

/* Event_round_start()
 *
 * Called when a round starts.
 * -------------------------------------------------------------------------- */
public Action:Event_round_start(Handle:event, const String:name[], bool:dontBroadcast) {
	LockMap();
}

/* Event_player_team()
 *
 * Called when a player joins a team.
 * -------------------------------------------------------------------------- */
public Action:Event_player_team(Handle:event, const String:name[], bool:dontBroadcast) {
	new clientid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(clientid);

	new team = GetEventInt(event, "team");
	new oldteam = GetEventInt(event, "oldteam");

	if (team != oldteam) {
		ResetPlayerDmgBasedRegen(client, true);
	}

	return Plugin_Continue;
}

/* OnAfkStateChanged()
 *
 * Called when the AFK state of a player has changed.
 * It is the AFK plugin that calls this method.
 * -------------------------------------------------------------------------- */
public OnAfkStateChanged(client, bool:afk) {
	new TFTeam:team = TFTeam:GetClientTeam(client);
	if (team != TFTeam_Blue && team != TFTeam_Red) {
		return;
	}

	if (afk) {
		// Move back to spawn
		TF2_RespawnPlayer(client);
	} else {
		// Move to battlefield
		CreateTimer(0.01, RandomSpawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

/*
 * ------------------------------------------------------------------
 *		__  ____
 *	   /  |/  (_)__________
 *	  / /|_/ / // ___/ ___/
 *	 / /  / / /(__  ) /__
 *	/_/  /_/_//____/\___/
 *
 * ------------------------------------------------------------------
 */

/* LockMap()
 *
 * Locks all objectives on the map and gets it ready for DM.
 * -------------------------------------------------------------------------- */

LockMap() {
	// List of entities to remove. This should remove all objectives on a map, but koth_viaduct seems to be partially unaffected by this.
	new String:saRemove[][] = {
		"team_round_timer",
		"func_regenerate",
		"team_control_point_master",
		"team_control_point",
		"trigger_capture_area",
		"tf_logic_koth",
		"logic_auto",
		"logic_relay",
		"item_teamflag",
		"item_healthkit_full",
		"item_healthkit_medium",
		"item_healthkit_small",
		"item_ammopack_full",
		"item_ammopack_medium",
		"item_ammopack_small"
	};

	for (new i = 0; i < sizeof(saRemove); i++) {
		new ent = MAXPLAYERS+1;
		while ((ent = FindEntityByClassname2(ent, saRemove[i])) != -1 && (!StrEqual(saRemove[i], "func_regenerate", false) || g_bDisableCabinet) && (StrContains(saRemove[i], "item_healthkit", false) == -1 || g_bDisableHealthPacks) && (StrContains(saRemove[i], "item_ammopack", false) == -1 || g_bDisableAmmoPacks)) {
			if (IsValidEdict(ent)) {
				AcceptEntityInput(ent, "Disable");
			}
		}
	}

	OpenDoors();
	ResetPlayers();
}



/* OpenDoors()
 *
 * Initially forces all doors open and keeps them unlocked even when they close.
 * -------------------------------------------------------------------------- */
OpenDoors() {
	if (g_bOpenDoors) {
		new ent = MAXPLAYERS+1;
		while ((ent = FindEntityByClassname(ent, "func_door"))!=-1) {
			if (IsValidEdict(ent)) {
				AcceptEntityInput(ent, "unlock", -1);
				AcceptEntityInput(ent, "open", -1);
			}
		}

		ent = MAXPLAYERS+1;
		while ((ent = FindEntityByClassname(ent, "prop_dynamic"))!=-1) {
			if (IsValidEdict(ent)) {
				new String:tName[64];
				GetEntPropString(ent, Prop_Data, "m_iName", tName, sizeof(tName));
				if ((StrContains(tName,"door",false)!=-1) || (StrContains(tName,"gate",false)!=-1)) {
					AcceptEntityInput(ent, "unlock", -1);
					AcceptEntityInput(ent, "open", -1);
				}
			}
		}
	}
}

/* ResetPlayers()
 *
 * Can respawn or reset regen-over-time on all players.
 * -------------------------------------------------------------------------- */
ResetPlayers() {
	new id;
	if (FirstLoad == true) {
		for (new i = 0; i < MaxClients; i++) {
			if (IsValidClient(i)) {
				id = GetClientUserId(i);
				CreateTimer(g_fSpawn, Respawn, id, TIMER_FLAG_NO_MAPCHANGE);
			}
		}

		FirstLoad = false;
	} else {
		for (new i = 0; i < MaxClients; i++) {
			if (IsValidClient(i)) {
				id = GetClientUserId(i);
				CreateTimer(0.1, StartRegen, id, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}

	for (new i = 1; i <= MaxClients; i++) {
		ResetPlayerDmgBasedRegen(i);
	}
}

/* ResetPlayerDmgBasedRegen()
 *
 * Resets the client's recent damage output to 0.
 * -------------------------------------------------------------------------- */
ResetPlayerDmgBasedRegen(client, bool:alsoResetTaken = false) {
	for (new player = 1; player <= MaxClients; player++) {
		for (new i = 0; i < RECENT_DAMAGE_SECONDS; i++) {
			g_iRecentDamage[player][client][i] = 0;
		}
	}

	if (alsoResetTaken) {
		for (new player = 1; player <= MaxClients; player++) {
			for (new i = 0; i < RECENT_DAMAGE_SECONDS; i++) {
				g_iRecentDamage[client][player][i] = 0;
			}
		}
	}
}

/* IsValidClient()
 *
 * Checks if a client is valid.
 * -------------------------------------------------------------------------- */
bool:IsValidClient(iClient) {
	if (iClient < 1 || iClient > MaxClients) {
		return false;
	} if (!IsClientConnected(iClient)) {
		return false;
	}

	return IsClientInGame(iClient);
}

/* FindEntityByClassname2()
 *
 * Finds entites, and won't error out when searching invalid entities.
 * -------------------------------------------------------------------------- */
stock FindEntityByClassname2(startEnt, const String:classname[]) {
	/* If startEnt isn't valid, shift it back to the nearest valid one */
	while (startEnt > -1 && !IsValidEntity(startEnt)) {
		startEnt--;
	}

	return FindEntityByClassname(startEnt, classname);
}

/* GetRealClientCount()
 *
 * Gets the number of clients connected to the game..
 * -------------------------------------------------------------------------- */
stock GetRealClientCount() {
	new clients = 0;

	for (new i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) {
			clients++;
		}
	}

	return clients;
}

DownloadConfig(const String:map[], const String:targetPath[]) {
	decl String:url[256];
	Format(url, sizeof(url), "https://raw.githubusercontent.com/Lange/SOAP-TF2DM/master/addons/sourcemod/configs/soap/%s.cfg", map);

	new Handle:curl = curl_easy_init();
	new Handle:output_file = curl_OpenFile(targetPath, "wb");
	CURL_DEFAULT_OPT(curl);

	new Handle:hDLPack = CreateDataPack();
	WritePackCell(hDLPack, _:output_file);
	WritePackString(hDLPack, map);
	WritePackString(hDLPack, targetPath);

	curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, output_file);
	curl_easy_setopt_string(curl, CURLOPT_URL, url);
	curl_easy_perform_thread(curl, OnDownloadComplete, hDLPack);
}

OnDownloadComplete(Handle:hndl, CURLcode:code, any hDLPack) {
	decl String:map[128];
	decl String:targetPath[128];

	ResetPack(hDLPack);
	CloseHandle(Handle:ReadPackCell(hDLPack)); // output_file
	ReadPackString(hDLPack, map, sizeof(map));
	ReadPackString(hDLPack, targetPath, sizeof(targetPath));
	CloseHandle(hDLPack);
	CloseHandle(hndl);

	if (code != CURLE_OK) {
		DeleteFile(targetPath);
		SetFailState("Map spawns missing. Map: %s, failed to download config", map);
		LogError("Failed to download config for: %s", map);
	} else {
		if (FileSize(targetPath) < 1024) {
			DeleteFile(targetPath);
			SetFailState("Map spawns missing. Map: %s, failed to download config", map);
			LogError("Failed to download config for: %s", map);
			return;
		} else {
			PrintToChatAll("Successfully downloaded config %s", map);
			LoadMapConfig(map, targetPath);
		}
	}
}
