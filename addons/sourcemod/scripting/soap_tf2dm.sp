#pragma semicolon 1 // Force strict semicolon mode.

// ====[ INCLUDES ]====================================================

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <color_literals>
#undef REQUIRE_PLUGIN
#include <afk>
#include <updater>

#undef REQUIRE_EXTENSIONS
#include <cURL>

// ====[ NEWDECLS REQUIRED ]====================================================

#pragma newdecls required

// ====[ CONSTANTS ]===================================================

#define PLUGIN_NAME         "SOAP TF2 Deathmatch"
#define PLUGIN_AUTHOR       "Icewind, MikeJS, Lange, Tondark - maintained by sappho.io"
#define PLUGIN_VERSION      "4.1.1"
#define PLUGIN_CONTACT      "https://steamcommunity.com/id/icewind1991, https://steamcommunity.com/id/langeh/, https://sappho.io"
#define UPDATE_URL          "https://raw.githubusercontent.com/sapphonie/SOAP-TF2DM/master/updatefile.txt"

// ====[ VARIABLES ]===================================================

bool
	g_bFirstLoad;

// Regen-over-time
bool
	g_bRegen[MAXPLAYERS + 1],
	g_bKillStartRegen;

int 
	g_iRegenHP;
	
Handle
	g_tmRegenTimer[MAXPLAYERS + 1];
	
ConVar 
	g_cvRegenHP, 
	g_cvRegenTick, 
	g_cvRegenDelay, 
	g_cvKillStartRegen;
	
float 
	g_fRegenTick, 
	g_fRegenDelay;

// Spawning
ConVar 
	g_cvSpawnRandom, 
	g_cvTeamSpawnRandom, 
	g_cvSpawn;
	
float 
	g_fSpawn;
	
bool 
	g_bSpawnRandom,
	g_bTeamSpawnRandom, 
	g_bSpawnMap;
	
ArrayList 
	g_alRedSpawns,
	g_alBluSpawns;

KeyValues 
	g_kvGlobalKV;

// Kill Regens (hp+ammo)

int 
	g_iMaxClips1[MAXPLAYERS + 1], 
	g_iMaxClips2[MAXPLAYERS + 1], 
	g_iMaxHealth[MAXPLAYERS + 1];

ConVar
	g_cvKillHealRatio,
	g_cvDamageHealRatio,
	g_cvKillHealStatic,
	g_cvKillAmmo,
	g_cvShowHP;

float 
	g_fKillHealRatio,
	g_fDamageHealRatio;

int 
	g_iKillHealStatic;

bool 
	g_bKillAmmo,
	g_bShowHP;

// Time limit enforcement

ConVar 
	g_hForceTimeLimit;

Handle
	g_tCheckTimeLeft;

bool
	g_bForceTimeLimit; 

// Doors and cabinets

ConVar 
	g_cvOpenDoors,
	g_cvDisableCabinet;

bool
	g_bOpenDoors,
	g_bDisableCabinet;

// Health packs and ammo

ConVar 
	g_cvDisableHealthPacks,
	g_cvDisableAmmoPacks;
	
bool
	g_bDisableHealthPacks,
	g_bDisableAmmoPacks;

// Regen damage given on kill

#define RECENT_DAMAGE_SECONDS 10

int
	g_iRecentDamage[MAXPLAYERS + 1][MAXPLAYERS + 1][RECENT_DAMAGE_SECONDS];
	
Handle
	g_tRecentDamageTimer;

// AFK

bool 
	g_bAFKSupported;

// cURL

bool g_bcURLSupported;

int CURL_Default_opt[][2] =  {
	
	{ view_as<int>(CURLOPT_NOSIGNAL), 1 }, 
	{ view_as<int>(CURLOPT_NOPROGRESS), 1 }, 
	{ view_as<int>(CURLOPT_TIMEOUT), 300 }, 
	{ view_as<int>(CURLOPT_CONNECTTIMEOUT), 120 }, 
	{ view_as<int>(CURLOPT_USE_SSL), CURLUSESSL_TRY }, 
	{ view_as<int>(CURLOPT_SSL_VERIFYPEER), 0 }, 
	{ view_as<int>(CURLOPT_SSL_VERIFYHOST), 0 }, 
	{ view_as<int>(CURLOPT_VERBOSE), 0 }
	
};

// Entities to remove

char g_entIter[][] =  {
	
	"team_round_timer",  // DISABLE      - Don't delete this ent, it WILL crash servers otherwise: https://crash.limetech.org/om2df7575vq3
	"team_control_point_master",  // DISABLE      - this ent causes weird behavior in DM servers if deleted. just disable
	"team_control_point",  // DISABLE      - No need to remove this, disabling works fine
	"tf_logic_koth",  // DISABLE      - ^
	"tf_logic_arena",  // DELETE       - need to delete these, otherwise fight / spectate bullshit shows up on arena maps
	"logic_auto",  // DISABLE      - ^
	"logic_relay",  // DISABLE      - ^
	"item_teamflag",  // DISABLE      - ^
	"trigger_capture_area",  // TELEPORT     - we tele these ents out of the players reach (under the map by 5000 units) to disable them because theres issues with huds sometimes bugging out otherwise if theyre deleted
	"func_regenerate",  // DELETE       - deleting this ent is the only way to reliably prevent it from working in DM otherwise, and it gets reloaded on match start anyway
	"func_respawnroom",  // DELETE       - ^
	"func_respawnroomvisualizer",  // DELETE       - ^
	"item_healthkit_full",  // DELETE       - ^
	"item_healthkit_medium",  // DELETE       - ^
	"item_healthkit_small",  // DELETE       - ^
	"item_ammopack_full",  // DELETE       - ^
	"item_ammopack_medium",  // DELETE       - ^
	"item_ammopack_small" // DELETE       - ^
	
};

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

// ====[ PLUGIN ]======================================================

public Plugin myinfo = {
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "Team deathmatch gameplay for TF2.", 
	version = PLUGIN_VERSION, 
	url = PLUGIN_CONTACT
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
 
public void OnPluginStart() {
	
	PrintColoredChatAll(COLOR_LIME..."["..."\x0700FFBF"..."SOAP"...COLOR_LIME..."]"...COLOR_WHITE..." Soap DM loaded.");
	
	g_bAFKSupported = LibraryExists("afk");
	g_bcURLSupported = GetExtensionFileStatus("curl.ext") == 1 ? true : false;
	
	if (LibraryExists("updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
	
	LoadTranslations("soap_tf2dm.phrases");
	
	// Create convars
	// make soap version cvar unchageable to work around older autogen'd configs resetting it back to 3.8
	
	CreateConVar("soap", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_CHEAT);
	g_cvRegenHP = CreateConVar("soap_regenhp", "1", "Health added per regeneration tick. Set to 0 to disable.", FCVAR_NOTIFY);
	g_cvRegenTick = CreateConVar("soap_regentick", "0.1", "Delay between regeration ticks.", FCVAR_NOTIFY);
	g_cvRegenDelay = CreateConVar("soap_regendelay", "5.0", "Seconds after damage before regeneration.", FCVAR_NOTIFY);
	g_cvKillStartRegen = CreateConVar("soap_kill_start_regen", "1", "Start the heal-over-time regen immediately after a kill.", FCVAR_NOTIFY);
	g_cvSpawn = CreateConVar("soap_spawn_delay", "1.5", "Spawn timer.", FCVAR_NOTIFY);
	g_cvSpawnRandom = CreateConVar("soap_spawnrandom", "1", "Enable random spawns.", FCVAR_NOTIFY);
	g_cvTeamSpawnRandom = CreateConVar("soap_teamspawnrandom", "0", "Enable random spawns independent of team", FCVAR_NOTIFY);
	g_cvKillHealRatio = CreateConVar("soap_kill_heal_ratio", "0.5", "Percentage of HP to restore on kills. .5 = 50%. Should not be used with soap_kill_heal_static.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDamageHealRatio = CreateConVar("soap_dmg_heal_ratio", "0.0", "Percentage of HP to restore based on amount of damage given. .5 = 50%. Should not be used with soap_kill_heal_static.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvKillHealStatic = CreateConVar("soap_kill_heal_static", "0", "Amount of HP to restore on kills. Exact value applied the same to all classes. Should not be used with soap_kill_heal_ratio.", FCVAR_NOTIFY);
	g_cvKillAmmo = CreateConVar("soap_kill_ammo", "1", "Enable ammo restoration on kills.", FCVAR_NOTIFY);
	g_cvOpenDoors = CreateConVar("soap_opendoors", "1", "Force all doors to open. Required on maps like cp_well.", FCVAR_NOTIFY);
	g_cvDisableCabinet = CreateConVar("soap_disablecabinet", "1", "Disables the resupply cabinets on map load", FCVAR_NOTIFY);
	g_cvShowHP = CreateConVar("soap_showhp", "1", "Print killer's health to victim on death.", FCVAR_NOTIFY);
	g_hForceTimeLimit = CreateConVar("soap_forcetimelimit", "1", "Time limit enforcement, used to fix a never-ending round issue on gravelpit.", _, true, 0.0, true, 1.0);
	g_cvDisableHealthPacks = CreateConVar("soap_disablehealthpacks", "0", "Disables the health packs on map load.", FCVAR_NOTIFY);
	g_cvDisableAmmoPacks = CreateConVar("soap_disableammopacks", "0", "Disables the ammo packs on map load.", FCVAR_NOTIFY);
	
	// Hook convar changes and events
	g_cvRegenHP.AddChangeHook(handler_ConVarChange);
	g_cvRegenTick.AddChangeHook(handler_ConVarChange);
	g_cvRegenDelay.AddChangeHook(handler_ConVarChange);
	g_cvKillStartRegen.AddChangeHook(handler_ConVarChange);
	g_cvSpawn.AddChangeHook(handler_ConVarChange);
	g_cvSpawnRandom.AddChangeHook(handler_ConVarChange);
	g_cvTeamSpawnRandom.AddChangeHook(handler_ConVarChange);
	g_cvKillHealRatio.AddChangeHook(handler_ConVarChange);
	g_cvDamageHealRatio.AddChangeHook(handler_ConVarChange);
	g_cvKillHealStatic.AddChangeHook(handler_ConVarChange);
	g_cvKillAmmo.AddChangeHook(handler_ConVarChange);
	g_cvOpenDoors.AddChangeHook(handler_ConVarChange);
	g_cvDisableCabinet.AddChangeHook(handler_ConVarChange);
	g_cvShowHP.AddChangeHook(handler_ConVarChange);
	g_hForceTimeLimit.AddChangeHook(handler_ConVarChange);
	g_cvDisableHealthPacks.AddChangeHook(handler_ConVarChange);
	g_cvDisableAmmoPacks.AddChangeHook(handler_ConVarChange);
	
	HookEvent("player_death", Event_player_death);
	HookEvent("player_hurt", Event_player_hurt);
	HookEvent("player_spawn", Event_player_spawn);
	HookEvent("player_team", Event_player_team);
	HookEvent("teamplay_round_start", Event_round_start);
	HookEvent("teamplay_restart_round", Event_round_start);
	
	// Create arrays for the spawning system
	g_alBluSpawns = new ArrayList();
	g_alRedSpawns = new ArrayList();
	
	// Crutch to fix some issues that appear when the plugin is loaded mid-round.
	g_bFirstLoad = true;
	
	// Begin the time check that prevents infinite rounds on A/D and KOTH maps. It is run here as well as in OnMapStart() so that it will still work even if the plugin is loaded mid-round.
	CreateTimeCheck();
	
	// Lock control points and intel on map. Also respawn all players into DM spawns. This instance of LockMap() is needed for mid-round loads of DM. (See: Volt's DM/Pub hybrid server.)
	LockMap();
	// Reset all player's regens. Used here for mid-round loading compatability.
	ResetPlayers();
	
	// Create configuration file in cfg/sourcemod folder
	AutoExecConfig(true, "soap_tf2dm", "sourcemod");
	
}

public void OnLibraryAdded(const char[] name) {
	
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

public void OnLibraryRemoved(const char[] name) {
	
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
 
public Action OnGetGameDescription(char gameDesc[64]) {
	
	// Changes the game description from "Team Fortress 2" to "SOAP TF2DM vx.x")
	
	Format(gameDesc, sizeof(gameDesc), "SOAP TF2DM v%s", PLUGIN_VERSION);
	return Plugin_Changed;
	
}

/* OnMapStart()
 *
 * When the map starts.
 * -------------------------------------------------------------------------- */
public void OnMapStart() {
	
	// Kill everything, because fuck memory leaks.
	
	delete g_tCheckTimeLeft;
	
	for (int i = 0; i < MaxClients + 1; i++) {
		delete g_tmRegenTimer[i];
	}
	
	// Spawn system written by MikeJS.
	g_alRedSpawns.Clear();
	g_alBluSpawns.Clear();
	
	for (int i = 0; i < MAXPLAYERS; i++) {
		g_alRedSpawns.Push(CreateArray(6));
		g_alBluSpawns.Push(CreateArray(6));
	}
	
	g_bSpawnMap = false;
	
	delete g_kvGlobalKV;
	g_kvGlobalKV = new KeyValues("Spawns");
	
	char map[64];
	GetCurrentMap(map, sizeof(map));
	
	char path[256];
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

public void LoadMapConfig(const char[] map, const char[] path) {
	
	g_bSpawnMap = true;
	g_kvGlobalKV.ImportFromFile(path);
	
	char players[4];
	float vectors[6];
	float origin[3];
	float angles[3];
	int iplayers;
	
	do {
		g_kvGlobalKV.GetSectionName(players, sizeof(players));
		iplayers = StringToInt(players);
		
		if (g_kvGlobalKV.JumpToKey("red")) {
			g_kvGlobalKV.GotoFirstSubKey();
			do {
				g_kvGlobalKV.GetVector("origin", origin);
				g_kvGlobalKV.GetVector("angles", angles);
				
				vectors[0] = origin[0];
				vectors[1] = origin[1];
				vectors[2] = origin[2];
				vectors[3] = angles[0];
				vectors[4] = angles[1];
				vectors[5] = angles[2];
				
				for (int i = iplayers; i < MAXPLAYERS; i++) {
					PushArrayArray(GetArrayCell(g_alRedSpawns, i), vectors);
				}
			} while (g_kvGlobalKV.GotoNextKey());
			
			g_kvGlobalKV.GoBack();
			g_kvGlobalKV.GoBack();
		} else {
			SetFailState("Red spawns missing. Map: %s  Players: %i", map, iplayers);
		}
		
		if (g_kvGlobalKV.JumpToKey("blue")) {
			g_kvGlobalKV.GotoFirstSubKey();
			do {
				g_kvGlobalKV.GetVector("origin", origin);
				g_kvGlobalKV.GetVector("angles", angles);
				
				vectors[0] = origin[0];
				vectors[1] = origin[1];
				vectors[2] = origin[2];
				vectors[3] = angles[0];
				vectors[4] = angles[1];
				vectors[5] = angles[2];
				
				for (int i = iplayers; i < MAXPLAYERS; i++) {
					PushArrayArray(GetArrayCell(g_alBluSpawns, i), vectors);
				}
			} while (g_kvGlobalKV.GotoNextKey());
		} else {
			SetFailState("Blue spawns missing. Map: %s  Players: %i", map, iplayers);
		}
	} while (g_kvGlobalKV.GotoNextKey());
	
}

/* OnMapEnd()
 *
 * When the map ends.
 * -------------------------------------------------------------------------- */
 
public void OnMapEnd() {
	
	// Memory leaks: fuck 'em.
	
	delete g_tCheckTimeLeft;
	
	for (int i = 0; i < MAXPLAYERS + 1; i++) {
		delete g_tmRegenTimer[i];
	}
	
}

/* OnConfigsExecuted()
 *
 * When game configurations (e.g., map-specific configs) are executed.
 * -------------------------------------------------------------------------- */
 
public void OnConfigsExecuted() {
	
	// Get the values for internal global variables.
	
	g_iRegenHP = g_cvRegenHP.IntValue;
	g_iKillHealStatic = g_cvKillHealStatic.IntValue;
	
	g_fRegenTick = g_cvRegenTick.FloatValue;
	g_fRegenDelay = g_cvRegenDelay.FloatValue;
	g_fSpawn = g_cvSpawn.FloatValue;
	g_fKillHealRatio = g_cvKillHealRatio.FloatValue;
	g_fDamageHealRatio = g_cvDamageHealRatio.FloatValue;
	
	g_bKillStartRegen = g_cvKillStartRegen.BoolValue;
	g_bSpawnRandom = g_cvSpawnRandom.BoolValue;
	g_bKillAmmo = g_cvKillAmmo.BoolValue;
	g_bOpenDoors = g_cvOpenDoors.BoolValue;
	g_bDisableCabinet = g_cvDisableCabinet.BoolValue;
	g_bShowHP = g_cvShowHP.BoolValue;
	g_bForceTimeLimit = g_hForceTimeLimit.BoolValue;
	g_bDisableHealthPacks = g_cvDisableHealthPacks.BoolValue;
	g_bDisableAmmoPacks = g_cvDisableAmmoPacks.BoolValue;
	
	StartStopRecentDamagePushbackTimer();
	
}


/* OnClientConnected()
 *
 * When a client connects to the server.
 * -------------------------------------------------------------------------- */
 
public void OnClientConnected(int client) {
	
	// Set the client's slot regen timer handle to null.
	
	delete g_tmRegenTimer[client];
	
	// Reset the player's damage given/received to 0.
	
	ResetPlayerDmgBasedRegen(client, true);
	
	// Kills the annoying 30 second "waiting for players" at the start of a map.
	
	ServerCommand("mp_waitingforplayers_cancel 1");
	
}

/* OnClientDisconnect()
 *
 * When a client disconnects from the server.
 * -------------------------------------------------------------------------- */
 
public void OnClientDisconnect(int client) {
	
	// Set the client's slot regen timer handle to null again because I really don't want to take any chances.
	
	delete g_tmRegenTimer[client];
	
}

/* handler_ConVarChange()
 *
 * Called when a convar's value is changed..
 * -------------------------------------------------------------------------- */
 
public void handler_ConVarChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	
	// When a cvar is changed during runtime, this is called and the corresponding internal variable is updated to reflect this change.
	// SourcePawn can't `switch` with Strings, so this huge if/else chain is our only option.
	
	if (convar == g_cvRegenHP) {
		g_iRegenHP = StringToInt(newValue);
	} else if (convar == g_cvRegenTick) {
		g_fRegenTick = StringToFloat(newValue);
	} else if (convar == g_cvRegenDelay) {
		g_fRegenDelay = StringToFloat(newValue);
	} else if (convar == g_cvKillStartRegen) {
		if (StringToInt(newValue) >= 1) {
			g_bKillStartRegen = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bKillStartRegen = false;
		}
	} else if (convar == g_cvSpawn) {
		g_fSpawn = StringToFloat(newValue);
	} else if (convar == g_cvSpawnRandom) {
		if (StringToInt(newValue) >= 1) {
			g_bSpawnRandom = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bSpawnRandom = false;
		}
	} else if (convar == g_cvTeamSpawnRandom) {
		if (StringToInt(newValue) >= 1) {
			g_bTeamSpawnRandom = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bTeamSpawnRandom = false;
		}
	} else if (convar == g_cvKillHealRatio) {
		g_fKillHealRatio = StringToFloat(newValue);
	} else if (convar == g_cvDamageHealRatio) {
		g_fDamageHealRatio = StringToFloat(newValue);
		StartStopRecentDamagePushbackTimer();
	} else if (convar == g_cvKillHealStatic) {
		g_iKillHealStatic = StringToInt(newValue);
	} else if (convar == g_cvKillAmmo) {
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
	} else if (convar == g_cvOpenDoors) {
		if (StringToInt(newValue) >= 1) {
			g_bOpenDoors = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bOpenDoors = false;
		}
	} else if (convar == g_cvDisableCabinet) {
		if (StringToInt(newValue) >= 1) {
			g_bDisableCabinet = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bDisableCabinet = false;
		}
	} else if (convar == g_cvShowHP) {
		if (StringToInt(newValue) >= 1) {
			g_bShowHP = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bShowHP = false;
		}
	} else if (convar == g_cvDisableHealthPacks) {
		if (StringToInt(newValue) >= 1) {
			g_bDisableHealthPacks = true;
		} else if (StringToInt(newValue) <= 0) {
			g_bDisableHealthPacks = false;
		}
	} else if (convar == g_cvDisableAmmoPacks) {
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
 
public Action CheckTime(Handle timer) {
	
	int iTimeLeft;
	int iTimeLimit;
	GetMapTimeLeft(iTimeLeft);
	GetMapTimeLimit(iTimeLimit);
	
	// If soap_forcetimelimit = 1, mp_timelimit != 0, and the timeleft is < 0, change the map to sm_nextmap in 15 seconds.
	
	if (g_bForceTimeLimit && iTimeLeft <= 0 && iTimeLimit > 0) {
		if (GetRealClientCount() > 0) {  // Prevents a constant map change issue present on a small number of servers.
			CreateTimer(15.0, ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
			if (g_tCheckTimeLeft != null) {
				KillTimer(g_tCheckTimeLeft);
				g_tCheckTimeLeft = null;
			}
		}
	}
	
}

/* ChangeMap()
 *
 * Changes the map whatever sm_nextmap is.
 * -------------------------------------------------------------------------- */
 
public Action ChangeMap(Handle timer) {
	
	// If sm_nextmap isn't set or isn't registered, abort because there is nothing to change to.
	
	if (FindConVar("sm_nextmap") == null) {
		LogError("[SOAP] FATAL: Could not find sm_nextmap cvar. Cannot force a map change!");
		return;
	}
	
	int iTimeLeft;
	int iTimeLimit;
	GetMapTimeLeft(iTimeLeft);
	GetMapTimeLimit(iTimeLimit);
	
	// Check that soap_forcetimelimit = 1, mp_timelimit != 0, and timeleft < 0 again, because something could have changed in the last 15 seconds.
	if (g_bForceTimeLimit && iTimeLeft <= 0 && iTimeLimit > 0) {
		char newmap[65];
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
 
void CreateTimeCheck() {
	
	delete g_tCheckTimeLeft;
	
	g_tCheckTimeLeft = CreateTimer(15.0, CheckTime, _, TIMER_REPEAT);
	
}

/*
 * ------------------------------------------------------------------
 *	   _____                            _
 *	  / ___/____  ____ __      ______  (_)____  ____ _
 *	  \__ \/ __ \/ __ `/ | /| / / __ \/ // __ \/ __ `/
 *	 ___/ / /_/ / /_/ /| |/ |/ / / / / // / / / /_/ /
 *	/____/ .___/\__,_/ |__/|__/_/ /_/_//_/ /_/\__, /
 *	    /_/                                  /____/
 * ------------------------------------------------------------------
 */

/* RandomSpawn()
 *
 * Picks a spawn point at random from the %map%.cfg, and teleports the player to it.
 * -------------------------------------------------------------------------- */
 
public Action RandomSpawn(Handle timer, any clientid) {
	
	// UserIDs are passed through timers instead of client indexes because it ensures that no mismatches can happen as UserIDs are unique.
	
	int client = GetClientOfUserId(clientid); 
	
	if (!IsValidClient(client)) {
		return Plugin_Handled; // Client wasn't valid, so there's no point in trying to spawn it!
	}
	
	if (IsPlayerAlive(client)) {  // Can't teleport a dead player.
	
		int team = GetClientTeam(client), 
			count = GetClientCount(),
			size;
			
		ArrayList array,
				  spawns = new ArrayList(); 
		
		float vectors[6],
			  origin[3],
			  angles[3];
		
		// if random team spawn is enabled...
		if (g_bTeamSpawnRandom)
		{
			// ...pick a random team!
			team = GetRandomInt(2, 3);
		}
		
		if (team == 2) {  // Is player on RED?
			for (int i = 0; i <= count; i++) {
				// Yep, get the RED spawns for this map.
				array = g_alRedSpawns.Get(i);
				
				if (array.Length != 0) {
					size = spawns.Push(array);
				}
			}
		}
		else {  // Nope, they're on BLU.
			for (int i = 0; i <= count; i++) {
				// Get the BLU spawns.
				array = g_alBluSpawns.Get(i);
				
				if (array.Length != 0) {
					size = spawns.Push(array);
				}
			}
		}
				
		array = spawns.Get(GetRandomInt(0, spawns.Length - 1));
		size = array.Length;
		array.GetArray(GetRandomInt(0, size - 1), vectors); // Put the values from a random spawn in the config into a variable so it can be used.
		delete spawns; // Close the handle so there are no memory leaks.
		
		// Put the spawn location (origin) and POV (angles) into something a bit easier to keep track of.
		
		origin[0] = vectors[0];
		origin[1] = vectors[1];
		origin[2] = vectors[2];
		angles[0] = vectors[3];
		angles[1] = vectors[4];
		angles[2] = vectors[5];
		
		/* Below is how players are prevented from spawning within one another. */
		
		Handle trace = TR_TraceHullFilterEx(origin, origin, view_as<float>({ -24.0, -24.0, 0.0 }), view_as<float>({ 24.0, 24.0, 82.0 }), MASK_PLAYERSOLID, TraceEntityFilterPlayers);
		// The above line creates a 'box' at the spawn point to be used. This box is roughly the size of a player.
		
		if (TR_DidHit(trace) && IsValidClient(TR_GetEntityIndex(trace))) {
			// The 'box' hit a player!
			delete trace;
			CreateTimer(0.01, RandomSpawn, clientid, TIMER_FLAG_NO_MAPCHANGE); // Get a new spawn, because this one is occupied.
			return Plugin_Handled;
		} else {
			// All clear.
			TF2_RemoveCondition(client, TFCond_UberchargedHidden);
			TeleportEntity(client, origin, angles, NULL_VECTOR); // Teleport the player to their spawn point.
			EmitAmbientSound("items/spawn_item.wav", origin); // Make a sound at the spawn point.
		}
		
		delete trace; // Stops leaks dead.
	}
	
	return Plugin_Continue;
	
}

public bool TraceEntityFilterPlayers(int entity, int contentsMask) {
	
	// Used by the 'box' method to filter out everything that isn't a player.
	
	return IsValidClient(entity);
	
}

/* Respawn()
 *
 * Respawns a player on a delay.
 * -------------------------------------------------------------------------- */
 
public Action Respawn(Handle timer, any clientid) {
	
	int client = GetClientOfUserId(clientid);
	
	if (!IsValidClient(client)) {
		return;
	}
	
	TF2_RespawnPlayer(client);
	
}

/*
 * ------------------------------------------------------------------
 *	    ____
 *	   / __ \___  ____ ____  ____
 *	  / /_/ / _ \/ __ `/ _ \/ __ \
 *	 / _, _/  __/ /_/ /  __/ / / /
 *	/_/ |_|\___/\__, /\___/_/ /_/
 *	           /____/
 * ------------------------------------------------------------------
 */

/* StartRegen()
 *
 * Starts regen-over-time on a player.
 * -------------------------------------------------------------------------- */
 
public Action StartRegen(Handle timer, any clientid) {
	
	int client = GetClientOfUserId(clientid);
	
	delete g_tmRegenTimer[client];
	
	if (!IsValidClient(client)) {
		return;
	}
	
	g_bRegen[client] = true;
	Regen(null, clientid);
	
}

/* Regen()
 *
 * Heals a player for X amount of health every Y seconds.
 * -------------------------------------------------------------------------- */
 
public Action Regen(Handle timer, any clientid) {
	
	int client = GetClientOfUserId(clientid);
	
	delete g_tmRegenTimer[client];
	
	if (!IsValidClient(client)) {
		return;
	}
	
	if (g_bRegen[client] && IsPlayerAlive(client)) {
		
		int health = GetClientHealth(client) + g_iRegenHP;
		
		// If the regen would give the client more than their max hp, just set it to max.
		
		if (health > g_iMaxHealth[client]) {
			health = g_iMaxHealth[client];
		}
		
		if (GetClientHealth(client) <= g_iMaxHealth[client]) {
			SetEntProp(client, Prop_Send, "m_iHealth", health, 1);
			SetEntProp(client, Prop_Data, "m_iHealth", health, 1);
		}
		
		// Call this function again in g_fRegenTick seconds.
		
		g_tmRegenTimer[client] = CreateTimer(g_fRegenTick, Regen, clientid);
	}
	
}

/* Timer_RecentDamagePushback()
 *
 * Every second push back all recent damage by 1 index.
 * This ensures we only remember the last 9-10 seconds of recent damage.
 * -------------------------------------------------------------------------- */
 
public Action Timer_RecentDamagePushback(Handle timer, any clientid) {
	
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsValidClient(i)) {
			continue;
		}
		
		for (int j = 1; j <= MaxClients; j++) {
			if (!IsValidClient(j)) {
				continue;
			}
			
			for (int k = RECENT_DAMAGE_SECONDS - 2; k >= 0; k--) {
				g_iRecentDamage[i][j][k + 1] = g_iRecentDamage[i][j][k];
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
 
void StartStopRecentDamagePushbackTimer() {

	if (g_fDamageHealRatio > 0.0) {
		if (g_tRecentDamageTimer == null) {
			g_tRecentDamageTimer = CreateTimer(1.0, Timer_RecentDamagePushback, _, TIMER_REPEAT);
		}
	} else {
		delete g_tRecentDamageTimer;
	}
	
}


/*
 * ------------------------------------------------------------------
 *	    ______                  __
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
 
public Action Event_player_death(Event event, const char[] name, bool dontBroadcast) {
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	int clientid = GetClientUserId(client);
	
	int isDeadRinger = event.GetInt("death_flags") & 32;
	if (!IsValidClient(client) || isDeadRinger) {
		return;
	}
	
	CreateTimer(g_fSpawn, Respawn, clientid, TIMER_FLAG_NO_MAPCHANGE);
	
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	int weapon1 = -1,
		weapon2 = -1,
		weaponID1 = -1,
		weaponID2 = -1;
	
	
	if (IsValidClient(attacker) && attacker != 0)
	{
		if (IsValidEntity(GetPlayerWeaponSlot(attacker, 0))) {
			weapon1 = GetPlayerWeaponSlot(attacker, 0);
			if (weapon1 > MaxClients) {
				weaponID1 = GetEntProp(weapon1, Prop_Send, "m_iItemDefinitionIndex");
			}
		}
		if (IsValidEntity(GetPlayerWeaponSlot(attacker, 1))) {
			weapon2 = GetPlayerWeaponSlot(attacker, 1);
			if (weapon2 > MaxClients) {
				weaponID2 = GetEntProp(weapon2, Prop_Send, "m_iItemDefinitionIndex");
			}
		}
	}
	
	if (IsValidClient(attacker) && client != attacker) {
		if (g_bShowHP) {
			if (IsPlayerAlive(attacker)) {
				PrintColoredChat(client, COLOR_LIME..."["..."\x0700FFBF"..."SOAP"...COLOR_LIME..."]"...COLOR_WHITE..." %t", "Health Remaining", GetClientHealth(attacker));
			} else {
				PrintColoredChat(client, COLOR_LIME..."["..."\x0700FFBF"..."SOAP"...COLOR_LIME..."]"...COLOR_WHITE..." %t", "Attacker is dead");
			}
		}
		
		int targetHealth;
		
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
				targetHealth = GetClientHealth(attacker) + g_iKillHealStatic;
			}
		}
		
		if (targetHealth > GetClientHealth(attacker)) {
			SetEntProp(attacker, Prop_Data, "m_iHealth", targetHealth);
		}
		
		// Gives full ammo for primary and secondary weapon to the player who got the kill.
		// This is not compatable with unlockreplacer, because as far as i can tell, it doesn't even work anymore.
		if (g_bKillAmmo) {
			// if you somehow get it to work, it's still not compatible, sorry!
			if (FindConVar("sm_unlock_version") == null) {
				// Check the primary weapon, and set its ammo.
				// make sure the weapon is actually a real one!
				if (weapon1 == -1 || weaponID1 == -1) {
					return;
				}
				// Widowmaker can not be reliably resupped, and the point of the weapon is literally infinite ammo for aiming anyway. Skip it!
				else if (weaponID1 == 527) {
					return;
				}
				// this fixes the cow mangler and pomson
				else if (weaponID1 == 441 || weaponID1 == 588) {
					SetEntPropFloat(GetPlayerWeaponSlot(attacker, 0), Prop_Send, "m_flEnergy", 20.0);
				}
				else if (g_iMaxClips1[attacker] > 0) {
					SetEntProp(GetPlayerWeaponSlot(attacker, 0), Prop_Send, "m_iClip1", g_iMaxClips1[attacker]);
					
				}
				// Check the secondary weapon, and set its ammo.
				// make sure the weapon is actually a real one!
				if (weapon2 == -1 || weaponID2 == -1) {
					return;
				}
				// this fixes the bison
				else if (weaponID2 == 442) {
					SetEntPropFloat(GetPlayerWeaponSlot(attacker, 1), Prop_Send, "m_flEnergy", 20.0);
				}
				else if (g_iMaxClips2[attacker] > 0) {
					SetEntProp(GetPlayerWeaponSlot(attacker, 1), Prop_Send, "m_iClip1", g_iMaxClips2[attacker]);
				}
			}
		}
		
		// Give the killer regen-over-time if so configured.
		if (g_bKillStartRegen && !g_bRegen[attacker]) {
			StartRegen(null, attacker);
		}
	}
	
	// Heal the people that damaged the victim (also if the victim died without there being an attacker).
	if (g_fDamageHealRatio > 0.0) {
		char clientname[32];
		GetClientName(client, clientname, sizeof(clientname));
		for (int player = 1; player <= MaxClients; player++) {
			if (!IsValidClient(player)) {
				continue;
			}
			
			int dmg = 0;
			for (int i = 0; i < RECENT_DAMAGE_SECONDS; i++) {
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
				PrintColoredChat(player, COLOR_LIME..."["..."\x0700FFBF"..."SOAP"...COLOR_LIME..."]"...COLOR_WHITE..." %t", attacker == player ? "Kill HP Received" : "Damage HP Received", dmg, clientname);
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
 
public Action Event_player_hurt(Event event, const char[] name, bool dontBroadcast) {
	
	int clientid = event.GetInt("userid"),
		client = GetClientOfUserId(event.GetInt("userid")),
		attacker = GetClientOfUserId(event.GetInt("attacker")),
		damage = event.GetInt("damageamount");
	
	if (IsValidClient(attacker) && client != attacker) {
		g_bRegen[client] = false;
		
		delete g_tmRegenTimer[client];
		
		g_tmRegenTimer[client] = CreateTimer(g_fRegenDelay, StartRegen, clientid);
		g_iRecentDamage[client][attacker][0] += damage;
	}
	
}

/* Event_player_spawn()
 *
 * Called when a player spawns.
 * -------------------------------------------------------------------------- */
public Action Event_player_spawn(Event event, const char[] name, bool dontBroadcast) {
	
	int client = GetClientOfUserId(event.GetInt("userid")),
		clientid = GetClientUserId(client);
	
	delete g_tmRegenTimer[client];
	
	g_tmRegenTimer[client] = CreateTimer(0.01, StartRegen, clientid);
	
	if (!IsValidClient(client)) {
		return;
	}
	
	TF2_AddCondition(client, TFCond_UberchargedHidden, TFCondDuration_Infinite, 0);
	
	// Are random spawns on and does this map have spawns?
	if (g_bSpawnRandom && g_bSpawnMap && (!g_bAFKSupported || !IsPlayerAFK(client))) {
		CreateTimer(0.01, RandomSpawn, clientid, TIMER_FLAG_NO_MAPCHANGE);
	} else {
		// Play a sound anyway, because sounds are cool.
		// Don't play a sound if the player is AFK.
		if (!g_bAFKSupported || !IsPlayerAFK(client)) {
			float vecOrigin[3];
			GetClientEyePosition(client, vecOrigin);
			EmitAmbientSound("items/spawn_item.wav", vecOrigin);
		}
	}
	
	// Get the player's max health and store it in a global variable. Doing it this way is handy for things like the Gunslinger and Eyelander, which change max health.
	g_iMaxHealth[client] = GetClientHealth(client);
	
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
 
public Action Event_round_start(Event event, const char[] name, bool dontBroadcast) {
	
	LockMap();
	
}

/* Event_player_team()
 *
 * Called when a player joins a team.
 * -------------------------------------------------------------------------- */
 
public Action Event_player_team(Event event, const char[] name, bool dontBroadcast) {
	int clientid = event.GetInt("userid");
	int client = GetClientOfUserId(clientid);
	
	int team = event.GetInt("team");
	int oldteam = event.GetInt("oldteam");
	
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
 
public int OnAfkStateChanged(int client, bool afk) {
	
	TFTeam team = TF2_GetClientTeam(client);
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
 *	    __  ____
 *	   /  |/  (_)__________
 *	  / /|_/ / // ___/ ___/
 *	 / /  / / /(__  ) /__
 *	/_/  /_/_//____/\___/
 *
 * ------------------------------------------------------------------
 */

/* LockMap() and other Entity Removal shennanigans
 *
 * Locks all objectives on the map and gets it ready for DM.
 * OnEntityCreated is required to reliably delete entities that get loaded after LockMap() is called
 * Note that this DOES NOT fix needing to reload the map after changing the disable cabinet / health pack / ammo pack cvars
 * -------------------------------------------------------------------------- */

void LockMap() {
	for (int i = 0; i < sizeof(g_entIter); i++) {
		int entity = MAXPLAYERS + 1;
		while ((entity = FindEntityByClassname2(entity, g_entIter[i])) != -1) {
			RemoveAllEnts(i, entity);
		}
	}
	OpenDoors();
	ResetPlayers();
	
}

public void OnEntityCreated(int entity, const char[] className) {
	
	for (int i = 0; i < sizeof(g_entIter); i++) {
		if (StrEqual(className, g_entIter[i])) {
			RemoveAllEnts(i, entity);
			break;
		}
	}
	
}

void RemoveAllEnts(int i, int entity) {
	
	if (IsValidEntity(entity)) {
		
		// remove arena logic (disabling doesn't properly disable the fight / spectate bullshit)
		if (StrContains(g_entIter[i], "tf_logic_arena", false) != -1) {
			RemoveEntity(entity);
		}
		// if ent is a func regen AND cabinets are off, remove it. otherwise skip
		else if (StrContains(g_entIter[i], "func_regenerate", false) != -1) {
			if (g_bDisableCabinet) {
				RemoveEntity(entity);
			}
		}
		else if (StrContains(g_entIter[i], "func_respawnroom", false) != -1) {
			if (g_bDisableCabinet) {
				RemoveEntity(entity);
			}
		}
		// if ent is a healthpack AND healthpacks are off, remove it. otherwise skip
		else if (StrContains(g_entIter[i], "item_healthkit", false) != -1) {
			if (g_bDisableHealthPacks) {
				RemoveEntity(entity);
			}
		}
		// if ent is a ammo pack AND ammo kits are off, remove it. otherwise skip
		else if (StrContains(g_entIter[i], "item_ammopack", false) != -1) {
			if (g_bDisableAmmoPacks) {
				RemoveEntity(entity);
			}
		}
		// move trigger zones out of player reach because otherwise the point gets capped in dm servers and it's annoying
		// we don't remove / disable because both cause issues/bugs otherwise
		else if (StrContains(g_entIter[i], "trigger_capture", false) != -1) {
			TeleportEntity(entity, view_as<float>( { 0.0, 0.0, -5000.0 } ), NULL_VECTOR, NULL_VECTOR);
		}
		// disable every other found matching ent instead of deleting, deleting certain logic/team timer ents is unneeded and can crash servers
		else {
			AcceptEntityInput(entity, "Disable");
		}
	}
	
}

/* OpenDoors() - rewritten by nanochip and stephanie
 *
 * Initially forces all doors open and keeps them unlocked even when they close.
 * -------------------------------------------------------------------------- */

void OpenDoors()
{
	if (g_bOpenDoors) {
		
		int ent = -1;
		// search for all func doors
		while ((ent = FindEntityByClassname(ent, "func_door")) != -1) {
			if (IsValidEntity(ent)) {
				AcceptEntityInput(ent, "unlock", -1);
				AcceptEntityInput(ent, "open", -1);
				//RemoveEntity(ent);
				FixNearbyDoorRelatedThings(ent);
			}
		}
		// reset ent
		ent = -1;
		// search for all other possible doors
		while ((ent = FindEntityByClassname(ent, "prop_dynamic")) != -1) {
			if (IsValidEntity(ent)) {
				char tName[64];
				char modelName[64];
				GetEntPropString(ent, Prop_Data, "m_iName", tName, sizeof(tName));
				GetEntPropString(ent, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
				if (StrContains(tName, "door", false) != -1 
				 || StrContains(tName, "gate", false) != -1 
				 || StrContains(modelName, "door", false) != -1
				 || StrContains(modelName, "gate", false) != -1) {
					AcceptEntityInput(ent, "unlock", -1);
					AcceptEntityInput(ent, "open", -1);
					//RemoveEntity(ent);
					FixNearbyDoorRelatedThings(ent);
				}
			}
		}
	}
	
}

// remove any func_brushes that could be blockbullets and open area portals near those func_brushes
void FixNearbyDoorRelatedThings(int ent) {
	
	float doorLocation[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", doorLocation);
	char brushName[32];
	float brushLocation[3];
	int iterEnt = -1;
	while ((iterEnt = FindEntityByClassname(iterEnt, "func_brush")) != -1) {
		if (IsValidEntity(iterEnt)) {
			GetEntPropVector(iterEnt, Prop_Send, "m_vecOrigin", brushLocation);
			if (GetVectorDistance(doorLocation, brushLocation) < 50.0) {
				GetEntPropString(iterEnt, Prop_Data, "m_iName", brushName, sizeof(brushName));
				if ((StrContains(brushName, "bullet", false) != -1) || (StrContains(brushName, "door", false) != -1)) {
					//RemoveEntity(iterEnt);
					AcceptEntityInput(iterEnt, "kill");
				}
			}
		}
	}
	
	// iterate thru all area portals on the map and open them
	// don't worry - the client immediately closes ones that aren't necessary to be open. probably.
	iterEnt = -1;
	while ((iterEnt = FindEntityByClassname(iterEnt, "func_areaportal")) != -1) {
		if (IsValidEntity(iterEnt)) {
			AcceptEntityInput(iterEnt, "Open");
		}
	}
	
}

/* ResetPlayers()
 *
 * Can respawn or reset regen-over-time on all players.
 * -------------------------------------------------------------------------- */
 
void ResetPlayers() {
	
	int id;
	if (g_bFirstLoad == true) {
		for (int i = 0; i < MaxClients; i++) {
			if (IsValidClient(i)) {
				id = GetClientUserId(i);
				CreateTimer(g_fSpawn, Respawn, id, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
		
		g_bFirstLoad = false;
	} else {
		for (int i = 0; i < MaxClients; i++) {
			if (IsValidClient(i)) {
				id = GetClientUserId(i);
				CreateTimer(0.1, StartRegen, id, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		ResetPlayerDmgBasedRegen(i);
	}
	
}

/* ResetPlayerDmgBasedRegen()
 *
 * Resets the client's recent damage output to 0.
 * -------------------------------------------------------------------------- */
 
void ResetPlayerDmgBasedRegen(int client, bool alsoResetTaken = false) {
	
	for (int player = 1; player <= MaxClients; player++) {
		for (int i = 0; i < RECENT_DAMAGE_SECONDS; i++) {
			g_iRecentDamage[player][client][i] = 0;
		}
	}
	
	if (alsoResetTaken) {
		for (int player = 1; player <= MaxClients; player++) {
			for (int i = 0; i < RECENT_DAMAGE_SECONDS; i++) {
				g_iRecentDamage[client][player][i] = 0;
			}
		}
	}
	
}

/* IsValidClient()
 *
 * Checks if a client is valid.
 * -------------------------------------------------------------------------- */
 
bool IsValidClient(int iClient) {
	
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
stock int FindEntityByClassname2(int startEnt, const char[] classname) {
	
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
stock int GetRealClientCount() {
	
	int clients;
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) {
			clients++;
		}
	}
	
	return clients;
}

void DownloadConfig(const char[] map, const char[] targetPath) {
	
	char url[256];
	Format(url, sizeof(url), "https://raw.githubusercontent.com/sapphonie/SOAP-TF2DM/master/addons/sourcemod/configs/soap/%s.cfg", map);
	
	Handle curl = curl_easy_init();
	Handle output_file = curl_OpenFile(targetPath, "wb");
	CURL_DEFAULT_OPT(curl);
	
	DataPack hDLPack = new DataPack();
	hDLPack.WriteCell(view_as<int>(output_file));
	hDLPack.WriteString(map);
	hDLPack.WriteString(targetPath);
	
	curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, output_file);
	curl_easy_setopt_string(curl, CURLOPT_URL, url);
	curl_easy_perform_thread(curl, OnDownloadComplete, hDLPack);
	
}

void OnDownloadComplete(Handle hndl, CURLcode code, DataPack hDLPack) {
	
	char map[128];
	char targetPath[128];
	
	hDLPack.Reset();
	delete view_as<Handle>(hDLPack.ReadCell()); // output_file
	hDLPack.ReadString(map, sizeof(map));
	hDLPack.ReadString(targetPath, sizeof(targetPath));
	delete hDLPack;
	delete hndl;
	
	if (code != CURLE_OK) {
		DeleteFile(targetPath);
		SetFailState("Map spawns missing. Map: %s, failed to download config", map);
		LogError("Failed to download config for: %s", map);
	} else {
		if (FileSize(targetPath) < 256) {
			DeleteFile(targetPath);
			SetFailState("Map spawns missing. Map: %s, failed to download config", map);
			LogError("Failed to download config for: %s", map);
			return;
		} else {
			PrintColoredChatAll(COLOR_LIME..."["..."\x0700FFBF"..."SOAP"...COLOR_LIME..."]"...COLOR_WHITE..." Successfully downloaded config %s.", map);
			LoadMapConfig(map, targetPath);
		}
	}
}

/* OnPluginEnd()
 *
 * When the plugin shuts down.
 * -------------------------------------------------------------------------- */
 
public void OnPluginEnd() {
	
	PrintColoredChatAll(COLOR_LIME..."["..."\x0700FFBF"..."SOAP"...COLOR_LIME..."]"...COLOR_WHITE..." Soap DM unloaded.");
	
}
