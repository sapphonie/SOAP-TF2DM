#pragma semicolon 1 // Force strict semicolon mode.
#pragma newdecls required // use new syntax

// ====[ INCLUDES ]====================================================
#include <sourcemod>
#include <sdktools>
#include <regex>
#include <tf2_stocks>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <afk>
#include <updater>

#undef REQUIRE_EXTENSIONS
#include <SteamWorks>

#pragma newdecls required // use new syntax


// ====[ CONSTANTS ]===================================================
#define PLUGIN_NAME         "SOAP TF2 Deathmatch"
#define PLUGIN_AUTHOR       "Icewind, MikeJS, Lange, Tondark - maintained by sappho.io"
#define PLUGIN_VERSION      "4.4.6"
#define PLUGIN_CONTACT      "https://steamcommunity.com/id/icewind1991, https://sappho.io"
#define UPDATE_URL          "https://raw.githubusercontent.com/sapphonie/SOAP-TF2DM/master/updatefile.txt"

// ====[ VARIABLES ]===================================================

// for morecolors lol
#define SOAP_TAG "{lime}[{cyan}SOAP{lime}]{white} "

bool FirstLoad;

// Regen-over-time
int g_iRegenHP;
bool g_bRegen[MAXPLAYERS+1];
bool g_bKillStartRegen;
float g_fRegenTick;
float g_fRegenDelay;
Handle g_hRegenTimer[MAXPLAYERS+1];
Handle g_hRegenHP;
Handle g_hRegenTick;
Handle g_hRegenDelay;
Handle g_hKillStartRegen;

// Spawning
bool g_bSpawnRandom;
bool g_bTeamSpawnRandom;
bool g_bSpawnMap;
float g_fSpawn;
Handle g_hSpawn;
Handle g_hTeamSpawnRandom;
Handle g_hSpawnRandom;
ArrayList g_hRedSpawns;
ArrayList g_hBluSpawns;
Handle g_hKv;

// Kill Regens (hp+ammo)
int g_iMaxClips1[MAXPLAYERS+1];
int g_iMaxClips2[MAXPLAYERS+1];
int g_iMaxHealth[MAXPLAYERS+1];
int g_iKillHealStatic;
bool g_bKillAmmo;
bool g_bShowHP;
float g_fKillHealRatio;
float g_fDamageHealRatio;
Handle g_hKillHealRatio;
Handle g_hDamageHealRatio;
Handle g_hKillHealStatic;
Handle g_hKillAmmo;
Handle g_hShowHP;

// Time limit enforcement
bool g_bForceTimeLimit;
Handle g_hForceTimeLimit;
Handle g_tCheckTimeLeft;

// Doors and cabinets
bool g_bOpenDoors;
bool g_bDisableCabinet;
Handle g_hOpenDoors;
Handle g_hDisableCabinet;

// Health packs and ammo
bool g_bDisableHealthPacks;
bool g_bDisableAmmoPacks;
Handle g_hDisableHealthPacks;
Handle g_hDisableAmmoPacks;

// velocity on spawn
Handle g_hNoVelocityOnSpawn;
bool g_bNoVelocityOnSpawn;

// debug spawns
Handle g_hDebugSpawns;
int g_iDebugSpawns;

// stuff for debug show spwns
Handle Timer_ShowSpawns;
int te_modelidx;

// mp_tourney convar
Handle mp_tournament;

// Regen damage given on kill
#define RECENT_DAMAGE_SECONDS 10
int g_iRecentDamage[MAXPLAYERS+1][MAXPLAYERS+1][RECENT_DAMAGE_SECONDS];
Handle g_hRecentDamageTimer;

// AFK
int g_bAFKSupported;

// cURL
int g_bCanDownload;

// Load config from other map version
Regex g_normalizeMapRegex;
bool g_bEnableFallbackConfig;
Handle g_hEnableFallbackConfig;


// Entities to remove - don't worry! these all get reloaded on round start!
char g_entIter[][] =
{
    "team_round_timer",                 // DISABLE*     - Don't delete this ent, it will crash servers otherwise. Don't disable on passtime maps either, for the same reason.
    "team_control_point_master",        // DISABLE      - this ent causes weird behavior in DM servers if deleted. just disable
    "team_control_point",               // DISABLE      - No need to remove this, disabling works fine
    "tf_logic_koth",                    // DISABLE      - ^
    "logic_auto",                       // DISABLE      - ^
    "logic_relay",                      // DISABLE      - ^
    "item_teamflag",                    // DISABLE      - ^
    "trigger_capture_area",             // TELEPORT     - we tele these ents under the map by 5000 units to disable them - otherwise, huds bug out occasionally
    "tf_logic_arena",                   // DELETE*      - need to delete these, otherwise fight / spectate bullshit shows up on arena maps.
                                        //                set mp_tournament to 1 to prevent this, since nuking the ents permanently breaks arena mode, for some dumb tf2 reason
                                        //                if this is not acceptable for your use case, please open a github issue and i will address it, thank you!
    "func_regenerate",                  // DELETE       - deleting this ent is the only way to reliably prevent it from working in DM otherwise
    "func_respawnroom",                 // DELETE       - ^
    "func_respawnroomvisualizer",       // DELETE       - ^
    "item_healthkit_full",              // DELETE       - ^
    "item_healthkit_medium",            // DELETE       - ^
    "item_healthkit_small",             // DELETE       - ^
    "item_ammopack_full",               // DELETE       - ^
    "item_ammopack_medium",             // DELETE       - ^
    "item_ammopack_small"               // DELETE       - ^
};


// ====[ PLUGIN ]======================================================
public Plugin myinfo = {
    name           = PLUGIN_NAME,
    author         = PLUGIN_AUTHOR,
    description    = "Team deathmatch gameplay for TF2.",
    version        = PLUGIN_VERSION,
    url            = PLUGIN_CONTACT
};


/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------- */
public void OnPluginStart()
{
    MC_PrintToChatAll(SOAP_TAG ... "Soap DM loaded.");
    g_bAFKSupported = LibraryExists("afk");
    g_bCanDownload  = GetExtensionFileStatus("SteamWorks.ext") == 1 ? true : false;

    if (LibraryExists("updater")) {
        Updater_AddPlugin(UPDATE_URL);
    }

    LoadTranslations("soap_tf2dm.phrases");

    // Create convars
    // make soap version cvar unchageable to work around older autogen'd configs resetting it back to 3.8
    CreateConVar("soap", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_CHEAT);
    g_hRegenHP              = CreateConVar("soap_regenhp", "1", "Health added per regeneration tick. Set to 0 to disable.", FCVAR_NOTIFY);
    g_hRegenTick            = CreateConVar("soap_regentick", "0.1", "Delay between regeration ticks.", FCVAR_NOTIFY);
    g_hRegenDelay           = CreateConVar("soap_regendelay", "5.0", "Seconds after damage before regeneration.", FCVAR_NOTIFY);
    g_hKillStartRegen       = CreateConVar("soap_kill_start_regen", "1", "Start the heal-over-time regen immediately after a kill.", FCVAR_NOTIFY);
    g_hSpawn                = CreateConVar("soap_spawn_delay", "1.5", "Spawn timer.", FCVAR_NOTIFY);
    g_hSpawnRandom          = CreateConVar("soap_spawnrandom", "1", "Enable random spawns.", FCVAR_NOTIFY);
    g_hTeamSpawnRandom      = CreateConVar("soap_teamspawnrandom", "0", "Enable random spawns independent of team", FCVAR_NOTIFY);
    g_hKillHealRatio        = CreateConVar("soap_kill_heal_ratio", "0.5", "Percentage of HP to restore on kills. .5 = 50%. Should not be used with soap_kill_heal_static.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hDamageHealRatio      = CreateConVar("soap_dmg_heal_ratio", "0.0", "Percentage of HP to restore based on amount of damage given. .5 = 50%. Should not be used with soap_kill_heal_static.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hKillHealStatic       = CreateConVar("soap_kill_heal_static", "0", "Amount of HP to restore on kills. Exact value applied the same to all classes. Should not be used with soap_kill_heal_ratio.", FCVAR_NOTIFY);
    g_hKillAmmo             = CreateConVar("soap_kill_ammo", "1", "Enable ammo restoration on kills.", FCVAR_NOTIFY);
    g_hOpenDoors            = CreateConVar("soap_opendoors", "1", "Force all doors to open. Required on maps like cp_well.", FCVAR_NOTIFY);
    g_hDisableCabinet       = CreateConVar("soap_disablecabinet", "1", "Disables the resupply cabinets on map load", FCVAR_NOTIFY);
    g_hShowHP               = CreateConVar("soap_showhp", "1", "Print killer's health to victim on death.", FCVAR_NOTIFY);
    g_hForceTimeLimit       = CreateConVar("soap_forcetimelimit", "1", "Time limit enforcement, used to fix a never-ending round issue on gravelpit.", _, true, 0.0, true, 1.0);
    g_hDisableHealthPacks   = CreateConVar("soap_disablehealthpacks", "0", "Disables the health packs on map load.", FCVAR_NOTIFY);
    g_hDisableAmmoPacks     = CreateConVar("soap_disableammopacks", "0", "Disables the ammo packs on map load.", FCVAR_NOTIFY);
    g_hNoVelocityOnSpawn    = CreateConVar("soap_novelocityonspawn", "1", "Prevents players from inheriting their velocity from previous lives when spawning thru SOAP.", FCVAR_NOTIFY);
    g_hDebugSpawns          = CreateConVar("soap_debugspawns", "0", "Set to 1 to draw boxes around spawn points when players spawn. Set to 2 to draw ALL spawn points constantly. For debugging.", FCVAR_NOTIFY, true, 0.0, true, 2.0);
    g_hEnableFallbackConfig = CreateConVar("soap_fallback_config", "1", "Enable falling back to spawns from other versions of the map if no spawns are configured for the current map.", FCVAR_NOTIFY);

    // for determining whether to delete arena entities or not
    mp_tournament           = FindConVar("mp_tournament");

    // Hook convar changes and events
    HookConVarChange(g_hRegenHP,              handler_ConVarChange);
    HookConVarChange(g_hRegenTick,            handler_ConVarChange);
    HookConVarChange(g_hRegenDelay,           handler_ConVarChange);
    HookConVarChange(g_hKillStartRegen,       handler_ConVarChange);
    HookConVarChange(g_hSpawn,                handler_ConVarChange);
    HookConVarChange(g_hSpawnRandom,          handler_ConVarChange);
    HookConVarChange(g_hTeamSpawnRandom,      handler_ConVarChange);
    HookConVarChange(g_hKillHealRatio,        handler_ConVarChange);
    HookConVarChange(g_hDamageHealRatio,      handler_ConVarChange);
    HookConVarChange(g_hKillHealStatic,       handler_ConVarChange);
    HookConVarChange(g_hKillAmmo,             handler_ConVarChange);
    HookConVarChange(g_hOpenDoors,            handler_ConVarChange);
    HookConVarChange(g_hDisableCabinet,       handler_ConVarChange);
    HookConVarChange(g_hShowHP,               handler_ConVarChange);
    HookConVarChange(g_hForceTimeLimit,       handler_ConVarChange);
    HookConVarChange(g_hDisableHealthPacks,   handler_ConVarChange);
    HookConVarChange(g_hDisableAmmoPacks,     handler_ConVarChange);
    HookConVarChange(g_hNoVelocityOnSpawn,    handler_ConVarChange);
    HookConVarChange(g_hDebugSpawns,          handler_ConVarChange);
    HookConVarChange(g_hEnableFallbackConfig, handler_ConVarChange);

    HookEvent("player_death", Event_player_death);
    HookEvent("player_hurt", Event_player_hurt);
    HookEvent("player_spawn", Event_player_spawn, EventHookMode_Pre );
    HookEvent("player_team", Event_player_team);
    HookEvent("teamplay_round_start", Event_round_start);
    HookEvent("teamplay_restart_round", Event_round_start);

    // Create arrays for the spawning system
    g_hRedSpawns = CreateArray(6);
    g_hBluSpawns = CreateArray(6);

    // Crutch to fix some issues that appear when the plugin is loaded mid-round.
    FirstLoad = true;

    // Begin the time check that prevents infinite rounds on A/D and KOTH maps. It is run here as well as in OnMapStart() so that it will still work even if the plugin is loaded mid-round.
    CreateTimeCheck();

    // Lock control points and intel on map. Also respawn all players into DM spawns. This instance of LockMap() is needed for mid-round loads of DM. (See: Volt's DM/Pub hybrid server.)
    LockMap();

    // Create configuration file in cfg/sourcemod folder
    AutoExecConfig(true, "soap_tf2dm", "sourcemod");

    g_normalizeMapRegex = new Regex("(_(a|b|beta|u|r|v|rc|f|final|comptf|ugc)?[0-9]*[a-z]?$)|([0-9]+[a-z]?$)", 0);

    GetRealClientCount();

    OnConfigsExecuted();

    te_modelidx = PrecacheModel("effects/beam_generic_2.vmt", true);
}

public void OnLibraryAdded(const char[] name)
{
    // Set up auto updater
    if (StrEqual(name, "afk"))
    {
        g_bAFKSupported = true;
    }

    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnLibraryRemoved(const char[] name) {
    if (StrEqual(name, "afk")) {
        g_bAFKSupported = false;
    }
}

/* OnMapStart()
 *
 * When the map starts.
 * -------------------------------------------------------------------------- */
public void OnMapStart() {
    // Kill everything, because fuck memory leaks.
    if (g_tCheckTimeLeft != null)
    {
        KillTimer(g_tCheckTimeLeft);
        g_tCheckTimeLeft = null;
    }

    for (int i = 0; i < MaxClients+1; i++) {
        if (g_hRegenTimer[i]!=null) {
            KillTimer(g_hRegenTimer[i]);
            g_hRegenTimer[i] = null;
        }
    }

    // DON'T load on MGE
    char map[64];
    GetCurrentMapLowercase(map, sizeof(map));

    if (StrContains(map, "mge", false) != -1)
    {
        SetFailState("Cowardly refusing to load SOAP DM on an MGE map.");
    }

    // init our spawn system
    InitSpawnSys();

    // Load the sound file played when a player is spawned.
    PrecacheSound("items/spawn_item.wav", true);

    // Begin the time check that prevents infinite rounds on A/D and KOTH maps.
    CreateTimeCheck();
}


void InitSpawnSys()
{
    // Spawn system written by MikeJS && wholly refactored by sappho.io

    // get rid of any spawns we might have
    ClearArray(g_hRedSpawns);
    ClearArray(g_hBluSpawns);
    // make new ones. size of 6 because origin * 3 + angles * 3
    g_hRedSpawns = CreateArray(6);
    g_hBluSpawns = CreateArray(6);

    g_bSpawnMap = false;

    if (g_hKv != null)
    {
        CloseHandle(g_hKv);
    }

    g_hKv = CreateKeyValues("Spawns");

    char map[64];
    GetCurrentMapLowercase(map, sizeof(map));

    char path[256];
    BuildPath(Path_SM, path, sizeof(path), "configs/soap/%s.cfg", map);

    // we got a local copy
    if (FileExists(path))
    {
        LoadMapConfig(map, path);
    }
    // we don't have a local copy
    else
    {
        // we can try to download one
        if (g_bCanDownload)
        {
            LogMessage("Map spawns missing. Map: %s. Trying to download...", map);
            DownloadConfig();
        }
        // we can't try to download one
        else
        {
            LogMessage("Map spawns missing. Map: %s. SteamWorks is not installed, we can't try to download them!", map);
            // Try to load a fallback
            if (GetConfigPath(map, path, sizeof(path)))
            {
                LoadMapConfig(map, path);
            }
        }
    }
    // End spawn system.
}


void LoadMapConfig(const char[] map, const char[] path)
{
    FileToKeyValues(g_hKv, path);

    float vectors[6];
    float origin[3];
    float angles[3];

    do
    {
        if (KvJumpToKey(g_hKv, "red"))
        {

            KvGotoFirstSubKey(g_hKv);
            do
            {
                KvGetVector(g_hKv, "origin", origin);
                KvGetVector(g_hKv, "angles", angles);

                vectors[0] = origin[0];
                vectors[1] = origin[1];
                vectors[2] = origin[2];
                vectors[3] = angles[0];
                vectors[4] = angles[1];
                vectors[5] = angles[2];

                PushArrayArray(g_hRedSpawns, vectors);
                g_bSpawnMap = true;

            }
            while (KvGotoNextKey(g_hKv));

            KvGoBack(g_hKv);
            KvGoBack(g_hKv);
        }
        else
        {
            LogMessage("Red spawns missing. Map: %s", map);
            g_bSpawnMap = false;
        }

        if (KvJumpToKey(g_hKv, "blue"))
        {
            KvGotoFirstSubKey(g_hKv);
            do
            {
                KvGetVector(g_hKv, "origin", origin);
                KvGetVector(g_hKv, "angles", angles);

                vectors[0] = origin[0];
                vectors[1] = origin[1];
                vectors[2] = origin[2];
                vectors[3] = angles[0];
                vectors[4] = angles[1];
                vectors[5] = angles[2];

                PushArrayArray(g_hBluSpawns, vectors);
                g_bSpawnMap = true;

            }
            while (KvGotoNextKey(g_hKv));
        }
        else
        {
            LogMessage("Blue spawns missing. Map: %s", map);
            g_bSpawnMap = false;
        }
    }
    // ?
    while (KvGotoNextKey(g_hKv));
}

/* OnMapEnd()
 *
 * When the map ends.
 * -------------------------------------------------------------------------- */
public void OnMapEnd()
{
    // Memory leaks: fuck 'em.


    // TODO : deletify all of these, this is old syntax
    if (g_tCheckTimeLeft!=null) {
        KillTimer(g_tCheckTimeLeft);
        g_tCheckTimeLeft = null;
    }

    delete Timer_ShowSpawns;

    for (int i = 0; i < MAXPLAYERS + 1; i++) {
        if (g_hRegenTimer[i] != null) {
            KillTimer(g_hRegenTimer[i]);
            g_hRegenTimer[i] = null;
        }
    }
}

/* OnConfigsExecuted()
 *
 * When game configurations (e.g., map-specific configs) are executed.
 * -------------------------------------------------------------------------- */
public void OnConfigsExecuted()
{
    // Get the values for internal global variables.
    g_iRegenHP                  = GetConVarInt(g_hRegenHP);
    g_fRegenTick                = GetConVarFloat(g_hRegenTick);
    g_fRegenDelay               = GetConVarFloat(g_hRegenDelay);
    g_bKillStartRegen           = GetConVarBool(g_hKillStartRegen);
    g_fSpawn                    = GetConVarFloat(g_hSpawn);
    g_bSpawnRandom              = GetConVarBool(g_hSpawnRandom);
    g_fKillHealRatio            = GetConVarFloat(g_hKillHealRatio);
    g_fDamageHealRatio          = GetConVarFloat(g_hDamageHealRatio);
    StartStopRecentDamagePushbackTimer();
    g_iKillHealStatic           = GetConVarInt(g_hKillHealStatic);
    g_bKillAmmo                 = GetConVarBool(g_hKillAmmo);
    g_bOpenDoors                = GetConVarBool(g_hOpenDoors);
    g_bDisableCabinet           = GetConVarBool(g_hDisableCabinet);
    g_bShowHP                   = GetConVarBool(g_hShowHP);
    g_bForceTimeLimit           = GetConVarBool(g_hForceTimeLimit);
    g_bDisableHealthPacks       = GetConVarBool(g_hDisableHealthPacks);
    g_bDisableAmmoPacks         = GetConVarBool(g_hDisableAmmoPacks);

    g_bNoVelocityOnSpawn        = GetConVarBool(g_hNoVelocityOnSpawn);
    g_iDebugSpawns              = GetConVarInt(g_hDebugSpawns);
    if (g_iDebugSpawns >= 2)
    {
        LogMessage("doing debug spawns");
        delete Timer_ShowSpawns;
        Timer_ShowSpawns = CreateTimer(0.1, DebugShowSpawns, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
    g_bEnableFallbackConfig = GetConVarBool(g_hEnableFallbackConfig);

    // reexec map config after grabbing cvars - for dm servers, to customize cvars per map etc.
    char map[64];
    GetCurrentMapLowercase(map, sizeof(map));

    ServerCommand("exec %s", map);
}


/* OnClientConnected()
 *
 * When a client connects to the server.
 * -------------------------------------------------------------------------- */
public void OnClientConnected(int client) {
    // Set the client's slot regen timer handle to null.
    if (g_hRegenTimer[client] != null) {
        KillTimer(g_hRegenTimer[client]);
        g_hRegenTimer[client] = null;
    }

    // Reset the player's damage given/received to 0.
    ResetPlayerDmgBasedRegen(client, true);

    // Kills the annoying 30 second "waiting for players" at the start of a map.
    //ServerCommand("mp_waitingforplayers_cancel 1");
    SetConVarInt(FindConVar("mp_waitingforplayers_time"), 0);
}

/* OnClientDisconnect()
 *
 * When a client disconnects from the server.
 * -------------------------------------------------------------------------- */
public void OnClientDisconnect(int client) {
    // Set the client's slot regen timer handle to null again because I really don't want to take any chances.
    if (g_hRegenTimer[client] != null) {
        KillTimer(g_hRegenTimer[client]);
        g_hRegenTimer[client] = null;
    }
}

/* handler_ConVarChange()
 *
 * Called when a convar's value is changed..
 * -------------------------------------------------------------------------- */
public void handler_ConVarChange(Handle convar, const char[] oldValue, const char[] newValue) {
    // When a cvar is changed during runtime, this is called and the corresponding internal variable is updated to reflect this change.
    // SourcePawn can't `switch` with Strings, so this huge if/else chain is our only option.
    if (convar == g_hRegenHP)
    {
        g_iRegenHP = StringToInt(newValue);
    }
    else if (convar == g_hRegenTick)
    {
        g_fRegenTick = StringToFloat(newValue);
    }
    else if (convar == g_hRegenDelay)
    {
        g_fRegenDelay = StringToFloat(newValue);
    }
    else if (convar == g_hKillStartRegen)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bKillStartRegen = true;
        }
        else
        {
            g_bKillStartRegen = false;
        }
    }
    else if (convar == g_hSpawn)
    {
        g_fSpawn = StringToFloat(newValue);
    }
    else if (convar == g_hSpawnRandom)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bSpawnRandom = true;
        }
        else
        {
            g_bSpawnRandom = false;
        }
    }
    else if (convar == g_hTeamSpawnRandom)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bTeamSpawnRandom = true;
        }
        else
        {
            g_bTeamSpawnRandom = false;
        }
    }
    else if (convar == g_hKillHealRatio)
    {
        g_fKillHealRatio = StringToFloat(newValue);
    }
    else if (convar == g_hDamageHealRatio)
    {
        g_fDamageHealRatio = StringToFloat(newValue);
        StartStopRecentDamagePushbackTimer();
    }
    else if (convar == g_hKillHealStatic)
    {
        g_iKillHealStatic = StringToInt(newValue);
    }
    else if (convar == g_hKillAmmo)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bKillAmmo = true;
        }
        else
        {
            g_bKillAmmo = false;
        }
    }
    else if (convar == g_hForceTimeLimit)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bForceTimeLimit = true;
        }
        else
        {
            g_bForceTimeLimit = false;
        }
    }
    else if (convar == g_hOpenDoors)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bOpenDoors = true;
            OpenDoors();
        }
        else
        {
            g_bOpenDoors = false;
            ResetMap();
        }
    }
    else if (convar == g_hShowHP)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bShowHP = true;
        }
        else
        {
            g_bShowHP = false;
        }
    }
    else if (convar == g_hDisableCabinet)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bDisableCabinet = true;
            DoAllEnts();
        }
        else
        {
            g_bDisableCabinet = false;
            ResetMap();
        }
    }
    else if (convar == g_hDisableHealthPacks)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bDisableHealthPacks = true;
            DoAllEnts();
        }
        else
        {
            g_bDisableHealthPacks = false;
            ResetMap();
        }
    }
    else if (convar == g_hDisableAmmoPacks)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bDisableAmmoPacks = true;
            DoAllEnts();
        }
        else
        {
            g_bDisableAmmoPacks = false;
            ResetMap();
        }
    }
    else if (convar == g_hNoVelocityOnSpawn)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bNoVelocityOnSpawn = true;
        }
        else
        {
            g_bNoVelocityOnSpawn = false;
        }
    }
    else if (convar == g_hDebugSpawns)
    {
        if (StringToInt(newValue) <= 0)
        {
            g_iDebugSpawns = 0;
        }
        else if (StringToInt(newValue) == 1)
        {
            LogMessage("doing debug spawns [1]");
            g_iDebugSpawns = 1;
        }
        else if (StringToInt(newValue) >= 2)
        {
            g_iDebugSpawns = 2;
            LogMessage("doing debug spawns [2]");
            delete Timer_ShowSpawns;
            Timer_ShowSpawns = CreateTimer(0.1, DebugShowSpawns, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        }
        InitSpawnSys();
    }
    else if (convar == g_hEnableFallbackConfig)
    {
        if (StringToInt(newValue) >= 1)
        {
            g_bEnableFallbackConfig = true;
        }
        else
        {
            g_bEnableFallbackConfig = false;
        }
        LogMessage("Reloading spawns.");
        InitSpawnSys();
    }
}

/*
 * ------------------------------------------------------------------
 *    _______                 ___            _ __
 *   /_  __(_)____ ___  ___  / (_)____ ___  (_) /_
 *    / / / // __ `__ \/ _ \/ / // __ `__ \/ / __/
 *   / / / // / / / / /  __/ / // / / / / / / /_
 *  /_/ /_//_/ /_/ /_/\___/_/_//_/ /_/ /_/_/\__/
 * ------------------------------------------------------------------
 */

/* CheckTime()
 *
 * Check map time left every 5 seconds.
 * -------------------------------------------------------------------------- */
public Action CheckTime(Handle timer) {
    int iTimeLeft;
    int iTimeLimit;
    GetMapTimeLeft(iTimeLeft);
    GetMapTimeLimit(iTimeLimit);

    // If soap_forcetimelimit = 1, mp_timelimit != 0, and the timeleft is < 0, change the map to sm_nextmap in 15 seconds.
    if (g_bForceTimeLimit && iTimeLeft <= 0 && iTimeLimit > 0) {
        if (GetRealClientCount() > 0) { // Prevents a constant map change issue present on a small number of servers.
            CreateTimer(5.0, ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
            if (g_tCheckTimeLeft != null) {
                KillTimer(g_tCheckTimeLeft);
                g_tCheckTimeLeft = null;
            }
        }
    }
    return Plugin_Continue;
}

/* ChangeMap()
 *
 * Changes the map whatever sm_nextmap is.
 * -------------------------------------------------------------------------- */
public Action ChangeMap(Handle timer) {
    // If sm_nextmap isn't set or isn't registered, abort because there is nothing to change to.
    if (FindConVar("sm_nextmap") == null)
    {
        LogError("[SOAP] FATAL: Could not find sm_nextmap cvar. Cannot force a map change!");
        return Plugin_Continue;
    }

    int iTimeLeft;
    int iTimeLimit;
    GetMapTimeLeft(iTimeLeft);
    GetMapTimeLimit(iTimeLimit);

    // Check that soap_forcetimelimit = 1, mp_timelimit != 0, and timeleft < 0 again, because something could have changed in the last 15 seconds.
    if (g_bForceTimeLimit && iTimeLeft <= 0 &&  iTimeLimit > 0) {
        char newmap[65];
        GetNextMap(newmap, sizeof(newmap));
        ForceChangeLevel(newmap, "Enforced Map Timelimit");
    } else {  // Turns out something did change.
        LogMessage("[SOAP] Aborting forced map change due to soap_forcetimelimit 1 or timelimit > 0.");

        if (iTimeLeft > 0) {
            CreateTimeCheck();
        }
    }
    return Plugin_Continue;
}

/* CreateTimeCheck()
 *
 * Used to create the timer that checks if the round is over.
 * -------------------------------------------------------------------------- */
void CreateTimeCheck() {
    if (g_tCheckTimeLeft != null) {
        KillTimer(g_tCheckTimeLeft);
        g_tCheckTimeLeft = null;
    }

    g_tCheckTimeLeft = CreateTimer(5.0, CheckTime, _, TIMER_REPEAT);
}

/*
 * ------------------------------------------------------------------
 *     _____                            _
 *    / ___/____  ____ __      ______  (_)____  ____ _
 *    \__ \/ __ \/ __ `/ | /| / / __ \/ // __ \/ __ `/
 *   ___/ / /_/ / /_/ /| |/ |/ / / / / // / / / /_/ /
 *  /____/ .___/\__,_/ |__/|__/_/ /_/_//_/ /_/\__, /
 *      /_/                                  /____/
 * ------------------------------------------------------------------
 */

/* RandomSpawn()
 *
 * Picks a spawn point at random from the %map%.cfg, and teleports the player to it.
 * -------------------------------------------------------------------------- */
public Action RandomSpawn(Handle timer, any clientid)
{
    // UserIDs are passed through timers instead of client indexes because it ensures that no mismatches can happen as UserIDs are unique.
    int client = GetClientOfUserId(clientid);

    // Client wasn't valid OR isn't alive
    if (!IsValidClient(client) || !IsPlayerAlive(client))
    {
        return Plugin_Handled;
    }

    // get client team
    int team = GetClientTeam(client);


    // if random team spawn is enabled...
    if (g_bTeamSpawnRandom)
    {
        // ...pick a random team!
        team = GetRandomInt(2, 3);
    }

    // we store actual spawn vectors in this array
    float vectors[6];

    // total number of spawns on team <x>
    int numofspawns;

    // random number that we generate later
    int rand;
    // Is player on RED?
    if (team == 2)
    {
        // Yep, get the amt of RED spawns for this map
        numofspawns = GetArraySize(g_hRedSpawns);
        // random number = random spawn to put player in
        rand = GetRandomInt(0, numofspawns - 1);
        // get the spawn vectors and put them in our vector var
        GetArrayArray(g_hRedSpawns, rand, vectors);
    }
    // Nope, they're on BLU.
    else
    {
        // get the amt of BLU spawns for this map
        numofspawns = GetArraySize(g_hBluSpawns);
        // random number = random spawn to put player in
        rand = GetRandomInt(0, numofspawns - 1);
        // get the spawn vectors and put them in our vector var
        GetArrayArray(g_hBluSpawns, rand, vectors);
    }
    // debug
    // LogMessage("spawning -> %f %f %f %i", vectors[0], vectors[1], vectors[2], numofspawns);

    // Put the spawn location (origin) and POV (angles) into something a bit easier to keep track of.
    float origin[3];
    float angles[3];

    origin[0] = vectors[0];
    origin[1] = vectors[1];
    origin[2] = vectors[2];
    angles[0] = vectors[3];
    angles[1] = vectors[4];
    // get rid of roll lol
    angles[2] = 0.0;

    // test if this spawn is even remotely sane
    if (TR_PointOutsideWorld(origin))
    {
        LogError("Spawn at %.2f %.2f %.2f is outside the world! Aborting...", origin[0], origin[1], origin[2]);
        // delete this spawn for this map
        DeleteCrazySpawnThisMap(origin, team, rand);
        // try again!
        CreateTimer(0.1, RandomSpawn, clientid, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Handled;
    }

    // here's how players are prevented from spawning within one another.

    // bottom left
    float mins[3] = {-24.0, -24.0, 0.0};
    // top right
    float maxs[3] = {24.0, 24.0, 82.0};

    // This creates a 'box' roughly the size of a player (^ where we set our mins / maxes!) at already chosen spawn point
    TR_TraceHullFilter
    (
        origin,
        origin,
        mins,
        maxs,
        MASK_PLAYERSOLID,
        PlayerFilter
    );
    // math shennanigans
    AddVectors(origin, mins, mins);
    AddVectors(origin, maxs, maxs);


    // for debug - visualize spawn box
    if (g_iDebugSpawns > 0)
    {
        // debug, for visualizing
        float life = 5.0;
        TE_SendBeamBoxToAll
        (
            mins,                                       // upper corner
            maxs,                                       // lower corner
            te_modelidx,                                // model index
            te_modelidx,                                // halo index
            0,                                          // startfame
            1,                                          // framerate
            life,                                       // lifetime
            5.0,                                        // Width
            5.0,                                        // endwidth
            5,                                          // fadelength
            1.0,                                        // amplitude
            {0, 255, 0, 255},                           // color ( green )
            1                                           // speed
        );
    }

    // The (trace) box hit something
    if (TR_DidHit())
    {
        // ent index that it hit
        int ent = TR_GetEntityIndex();

        // The 'box' hit a player!
        if (IsValidClient(ent))
        {
            // debug
            //LogMessage("box hit player %N", ent);

            // Get a new spawn - someone's in this one!
            CreateTimer(0.1, RandomSpawn, clientid, TIMER_FLAG_NO_MAPCHANGE);
            return Plugin_Handled;
        }
        // The trace hit the world! Uh oh.
        LogError("Spawn at %.2f %.2f %.2f clips into the world - needs more space! Aborting...", origin[0], origin[1], origin[2]);
        // delete this spawn for this map
        DeleteCrazySpawnThisMap(origin, team, rand);

        // try again!
        CreateTimer(0.1, RandomSpawn, clientid, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Handled;
    }
    else
    {
        // we didn't hit anything! let's remove that uber we set earlier...
        TF2_RemoveCondition(client, TFCond_UberchargedHidden);
        // and actually teleport the player!
        // null their velocity so ppl don't go flying when they respawn
        if (g_bNoVelocityOnSpawn)
        {
            TeleportEntity(client, origin, angles, view_as<float>({0.0, 0.0, 0.0}));
        }
        // Teleport the player to their spawn point [ old logic ]
        else
        {
            TeleportEntity(client, origin, angles, NULL_VECTOR);
        }
        // debug
        // LogMessage("teleing %N", client);

        // Make a sound at the spawn point.
        EmitAmbientSound("items/spawn_item.wav", origin);
    }

    return Plugin_Continue;
}

void DeleteCrazySpawnThisMap(float origin[3], int team, int rand)
{
    // don't delete this spawn if we're debugging spawns
    if (g_iDebugSpawns > 0)
    {
        MC_PrintToChatAll(SOAP_TAG ... "soap_debugspawns is > 0, not deleting bad spawn at index %i pos %.2f %.2f %.2f", rand, origin[0], origin[1], origin[2]);
        return;
    }

    // we don't want to spawn here again.
    if (team == 2)
    {
        RemoveFromArray(g_hRedSpawns, rand);
    }
    else
    {
        RemoveFromArray(g_hBluSpawns, rand);
    }
    LogMessage("Deleting bad spawn at index %i pos %.2f %.2f %.2f", rand, origin[0], origin[1], origin[2]);
}

public bool PlayerFilter(int entity, int contentsMask)
{
    if (IsValidClient(entity))
    {
        return true;
    }
    return false;
}

// blah blah
int currentlyshowingcolor = 2;
Action DebugShowSpawns(Handle timer)
{
    if (g_iDebugSpawns < 2)
    {
        LogMessage("cvar not set, cancelling");
        Timer_ShowSpawns = null;
        return Plugin_Stop;
    }
    // this alternates the team we draw every timer tick
    ShowSpawnFor(currentlyshowingcolor);
    return Plugin_Continue;
}

// just pretend this is a for loop - we have to do this on a timer because we hit the tempent limit otherwise
void ShowSpawnFor(int team)
{
    // lifetime for our box
    float life = 5.0;
    // color int array we set later
    int color[4];
    // vectors we set later
    float vectors[6];
    // number of spawns on this team that we set later
    int numspawns;

    // variables per team that we iterate in our makeshift for loop
    static int red_i;
    static int blu_i;

    // red team
    if (team == 2)
    {
        // amt of red spawns
        numspawns = GetArraySize(g_hRedSpawns);
        if (numspawns < 1)
        {
            return;
        }
        // color duh
        color = {255, 0, 0, 255};
        // reset our makeshift for loop back to 0 if we already hit the max
        if (red_i >= numspawns)
        {
            red_i = 0;
        }
        // get the actual vectors here
        GetArrayArray(g_hRedSpawns, red_i, vectors);
        // iterate our makeshift for loop
        red_i++;
        // flip our color, next we'll do blue
        currentlyshowingcolor++;
    }
    else
    {
        // amt of blue spawns
        numspawns = GetArraySize(g_hBluSpawns);
        if (numspawns < 1)
        {
            return;
        }
        // color duh
        color = {0, 0, 255, 255};
        // reset our makeshift for loop back to 0 if we already hit the max
        if (blu_i >= numspawns)
        {
            blu_i = 0;
        }
        // get the actual vectors here
        GetArrayArray(g_hBluSpawns, blu_i, vectors);
        // iterate our makeshift for loop
        blu_i++;
        // flip our color, back to red
        currentlyshowingcolor--;
    }

    // Put the spawn location into origin. we don't need angles. this is a box.
    float origin[3];
    float angles[3];

    origin[0] = vectors[0];
    origin[1] = vectors[1];
    origin[2] = vectors[2];
    angles[0] = vectors[3];
    angles[1] = vectors[4];
    angles[2] = vectors[5];

    // test if this spawn is even remotely sane
    if (TR_PointOutsideWorld(origin))
    {
        MC_PrintToChatAll(SOAP_TAG ... "Spawn at %.2f %.2f %.2f is COMPLETELY outside the world!", origin[0], origin[1], origin[2]);
    }

    // bottom left
    float mins[3] = {-24.0, -24.0, 0.0};
    // top right
    float maxs[3] = {24.0, 24.0, 82.0};


    // This creates a 'box' roughly the size of a player (^ where we set our mins / maxes!) at already chosen spawn point
    TR_TraceHullFilter
    (
        origin,
        origin,
        mins,
        maxs,
        MASK_PLAYERSOLID,
        PlayerFilter
    );

    float newpos[3];
    float angvec[3];

    GetAngleVectors(angles, angvec, NULL_VECTOR, NULL_VECTOR);

    // scale the angles 200 units
    ScaleVector(angvec, 64.0);

    // add em
    AddVectors(origin, angvec, newpos);

    TE_DrawLazer(origin, newpos, {255,255,1,255});

    // blah blah fucking math shit
    AddVectors(origin, mins, mins);
    AddVectors(origin, maxs, maxs);


    // The (trace) box hit something
    if (TR_DidHit())
    {
        // ent index that it hit
        int ent = TR_GetEntityIndex();

        // The 'box' hit a player!
        if (IsValidClient(ent))
        {
            //
        }
        // the trace hit the world!
        else
        {
            MC_PrintToChatAll(SOAP_TAG ... "Spawn at %.2f %.2f %.2f clips into the world - needs more space!", origin[0], origin[1], origin[2]);
        }
    }

    // send the damn box
    TE_SendBeamBoxToAll
    (
        mins,                                       // upper corner
        maxs,                                       // lower corner
        te_modelidx ,                               // model index
        te_modelidx ,                               // halo index
        0,                                          // startfame
        1,                                          // framerate
        life,                                       // lifetime
        2.5,                                        // Width
        2.5,                                        // endwidth
        5,                                          // fadelength
        0.0,                                        // amplitude
        color,                                      // color
        1                                           // speed
    );
}

// just a stupid "send beam box" stock, i didn't write this
stock void TE_SendBeamBoxToAll(float uppercorner[3], const float bottomcorner[3], int ModelIndex, int HaloIndex, int StartFrame, int FrameRate, float Life, float Width, float EndWidth, int FadeLength, float Amplitude, const int Color[4], int Speed) {
    // Create the additional corners of the box
    float tc1[3];
    AddVectors(tc1, uppercorner, tc1);
    tc1[0] = bottomcorner[0];

    float tc2[3];
    AddVectors(tc2, uppercorner, tc2);
    tc2[1] = bottomcorner[1];

    float tc3[3];
    AddVectors(tc3, uppercorner, tc3);
    tc3[2] = bottomcorner[2];

    float tc4[3];
    AddVectors(tc4, bottomcorner, tc4);
    tc4[0] = uppercorner[0];

    float tc5[3];
    AddVectors(tc5, bottomcorner, tc5);
    tc5[1] = uppercorner[1];

    float tc6[3];
    AddVectors(tc6, bottomcorner, tc6);
    tc6[2] = uppercorner[2];

    // Draw all the edges
    TE_SetupBeamPoints(uppercorner, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(uppercorner, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(uppercorner, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc6, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc6, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc6, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc4, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc5, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc5, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc5, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc4, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc4, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
}

// set up the laser sprite
void TE_DrawLazer(float start[3], float end[3], int color[4])
{
    TE_SetupBeamPoints
    (
        start,          // startpos
        end,            // endpos
        te_modelidx,    // model idx
        te_modelidx,    // halo idx
        0,              // startframe
        0,              // framerate
        5.0,            // lifetime
        2.5,            // starting width
        2.5,            // ending width
        0,              // fade time duration
        0.0,            // amplitude
        color,          // color
        0               // beam speed
    );
    TE_SendToAll();
}


/* Respawn()
 *
 * Respawns a player on a delay.
 * -------------------------------------------------------------------------- */
public Action Respawn(Handle timer, int clientid)
{
    int client = GetClientOfUserId(clientid);

    if (!IsValidClient(client))
    {
        return Plugin_Continue;
    }

    TF2_RespawnPlayer(client);

    return Plugin_Continue;
}

/*
 * ------------------------------------------------------------------
 *      ____
 *     / __ \___  ____ ____  ____
 *    / /_/ / _ \/ __ `/ _ \/ __ \
 *   / _, _/  __/ /_/ /  __/ / / /
 *  /_/ |_|\___/\__, /\___/_/ /_/
 *             /____/
 * ------------------------------------------------------------------
 */

/* StartRegen()
 *
 * Starts regen-over-time on a player.
 * -------------------------------------------------------------------------- */
public Action StartRegen(Handle timer, int clientid) {
    int client = GetClientOfUserId(clientid);

    if (g_hRegenTimer[client]!=null) {
        KillTimer(g_hRegenTimer[client]);
        g_hRegenTimer[client] = null;
    }

    if (!IsValidClient(client)) {
        return Plugin_Continue;
    }

    g_bRegen[client] = true;
    Regen(null, clientid);

    return Plugin_Continue;
}

/* Regen()
 *
 * Heals a player for X amount of health every Y seconds.
 * -------------------------------------------------------------------------- */
public Action Regen(Handle timer, int clientid) {
    int client = GetClientOfUserId(clientid);

    if (g_hRegenTimer[client]!=null) {
        KillTimer(g_hRegenTimer[client]);
        g_hRegenTimer[client] = null;
    }

    if (!IsValidClient(client)) {
        return Plugin_Continue;
    }

    if (g_bRegen[client] && IsPlayerAlive(client)) {
        int health = GetClientHealth(client)+g_iRegenHP;

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

    return Plugin_Continue;
}

/* Timer_RecentDamagePushback()
 *
 * Every second push back all recent damage by 1 index.
 * This ensures we only remember the last 9-10 seconds of recent damage.
 * -------------------------------------------------------------------------- */
public Action Timer_RecentDamagePushback(Handle timer, int clientid) {
    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidClient(i)) {
            continue;
        }

        for (int j = 1; j <= MaxClients; j++) {
            if (!IsValidClient(j)) {
                continue;
            }

            for (int k = RECENT_DAMAGE_SECONDS - 2; k >= 0; k--) {
                g_iRecentDamage[i][j][k+1] = g_iRecentDamage[i][j][k];
            }

            g_iRecentDamage[i][j][0] = 0;
        }
    }

    return Plugin_Continue;
}

/* StartStopRecentDamagePushbackTimer()
 *
 * Starts or stops the recent damage pushback timer, based on the current value
 * of the corresponding ConVar.
 * -------------------------------------------------------------------------- */
void StartStopRecentDamagePushbackTimer()
{
    if (g_fDamageHealRatio > 0.0)
    {
        if (g_hRecentDamageTimer == null)
        {
            g_hRecentDamageTimer = CreateTimer(1.0, Timer_RecentDamagePushback, _, TIMER_REPEAT);
        }
    }
    else
    {
        if (g_hRecentDamageTimer != null)
        {
            KillTimer(g_hRecentDamageTimer);
            g_hRecentDamageTimer = null;
        }
    }
}


/*
 * ------------------------------------------------------------------
 *      ______                  __
 *     / ____/_   _____  ____  / /______
 *    / __/  | | / / _ \/ __ \/ __/ ___/
 *   / /___  | |/ /  __/ / / / /_(__  )
 *  /_____/  |___/\___/_/ /_/\__/____/
 *
 * ------------------------------------------------------------------
 */

/* Event_player_death()
 *
 * Called when a player dies.
 * -------------------------------------------------------------------------- */
public Action Event_player_death(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    int clientid = GetClientUserId(client);

    int isDeadRinger = GetEventInt(event,"death_flags") & 32;
    if (!IsValidClient(client) || isDeadRinger)
    {
        return Plugin_Continue;
    }

    CreateTimer(g_fSpawn, Respawn, clientid, TIMER_FLAG_NO_MAPCHANGE);

    int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

    int weapon1 = -1;
    int weapon2 = -1;

    int weaponID1 = -1;
    int weaponID2 = -1;


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
        if (g_bShowHP)
        {
            if (IsPlayerAlive(attacker))
            {
                MC_PrintToChat(client, SOAP_TAG ... "%t", "Health Remaining", GetClientHealth(attacker));
            }
            else
            {
                MC_PrintToChat(client, SOAP_TAG ... "%t", "Attacker is dead");
            }
        }

        int targetHealth = 0;

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
        // This is not compatable with unlockreplacer, because as far as i can tell, it doesn't even work anymore.
        if (g_bKillAmmo) {
            // if you somehow get it to work, it's still not compatible, sorry!
            if (FindConVar("sm_unlock_version") == null) {
                // Check the primary weapon, and set its ammo.
                // make sure the weapon is actually a real one!
                if (weapon1 == -1 || weaponID1 == -1) {
                    return Plugin_Continue;
                }
                // Widowmaker can not be reliably resupped, and the point of the weapon is literally infinite ammo for aiming anyway. Skip it!
                else if (weaponID1 == 527) {
                    return Plugin_Continue;
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
                    return Plugin_Continue;
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
                }
                else
                {
                    SetEntProp(player, Prop_Data, "m_iHealth", GetClientHealth(player) + dmg);
                }
                MC_PrintToChat(player, SOAP_TAG ... "%t", attacker == player ? "Kill HP Received" : "Damage HP Received", dmg, clientname);
            }
        }
    }

    // Reset the player's recent damage
    if (g_fDamageHealRatio > 0.0) {
        ResetPlayerDmgBasedRegen(client);
    }

    return Plugin_Continue;
}

/* Event_player_hurt()
 *
 * Called when a player is hurt.
 * -------------------------------------------------------------------------- */
public Action Event_player_hurt(Handle event, const char[] name, bool dontBroadcast) {
    int clientid = GetEventInt(event, "userid");
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    int damage = GetEventInt(event, "damageamount");

    if (IsValidClient(attacker) && client!=attacker) {
        g_bRegen[client] = false;

        if (g_hRegenTimer[client]!=null) {
            KillTimer(g_hRegenTimer[client]);
            g_hRegenTimer[client] = null;
        }

        g_hRegenTimer[client] = CreateTimer(g_fRegenDelay, StartRegen, clientid);
        g_iRecentDamage[client][attacker][0] += damage;
    }

    return Plugin_Continue;
}

/* Event_player_spawn()
 *
 * Called when a player spawns.
 * -------------------------------------------------------------------------- */
public Action Event_player_spawn(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    int clientid = GetClientUserId(client);

    if (g_hRegenTimer[client] != null)
    {
        KillTimer(g_hRegenTimer[client]);
        g_hRegenTimer[client] = null;
    }

    g_hRegenTimer[client] = CreateTimer(0.1, StartRegen, clientid);

    if (!IsValidClient(client))
    {
        return Plugin_Continue;
    }

    // Are random spawns on and does this map have spawns?
    if
    (
        g_bSpawnRandom && g_bSpawnMap
        &&
        // Is player not afk?
        (
            !g_bAFKSupported || !IsPlayerAFK(client)
        )
    )
    {
        TF2_AddCondition(client, TFCond_UberchargedHidden, 1.0, 0);
        RandomSpawn(null, clientid);
    }
    else
    {
        // Play a sound anyway, because sounds are cool.
        // Don't play a sound if the player is AFK.
        if (!g_bAFKSupported || !IsPlayerAFK(client))
        {
            float vecOrigin[3];
            GetClientEyePosition(client, vecOrigin);
            EmitAmbientSound("items/spawn_item.wav", vecOrigin);
            TF2_RemoveCondition(client, TFCond_UberchargedHidden); // since RandomSpawn will never be hit, we need to remove cond here
        }
    }

    // Get the player's max health and store it in a global variable. Doing it this way is handy for things like the Gunslinger and Eyelander, which change max health.
    g_iMaxHealth[client] = GetClientHealth(client);

    // Check how much ammo each gun can hold in its clip and store it in a global variable so it can be regenerated to that amount later.
    if (IsValidEntity(GetPlayerWeaponSlot(client, 0)))
    {
        g_iMaxClips1[client] = GetEntProp(GetPlayerWeaponSlot(client, 0), Prop_Data, "m_iClip1");
    }

    if (IsValidEntity(GetPlayerWeaponSlot(client, 1)))
    {
        g_iMaxClips2[client] = GetEntProp(GetPlayerWeaponSlot(client, 1), Prop_Data, "m_iClip1");
    }
    return Plugin_Continue;
}

/* Event_round_start()
 *
 * Called when a round starts.
 * -------------------------------------------------------------------------- */
public Action Event_round_start(Handle event, const char[] name, bool dontBroadcast) {
    LockMap();

    return Plugin_Continue;
}

/* Event_player_team()
 *
 * Called when a player joins a team.
 * -------------------------------------------------------------------------- */
public Action Event_player_team(Handle event, const char[] name, bool dontBroadcast) {
    int clientid = GetEventInt(event, "userid");
    int client = GetClientOfUserId(clientid);

    int team = GetEventInt(event, "team");
    int oldteam = GetEventInt(event, "oldteam");

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
public void OnAfkStateChanged(int client, bool afk)
{
    TFTeam team = TF2_GetClientTeam(client);
    if (team != TFTeam_Blue && team != TFTeam_Red)
    {
        return;
    }

    if (afk)
    {
        // Move back to spawn
        TF2_RespawnPlayer(client);
        // make them ubered until they unafk
        TF2_AddCondition(client, TFCond_UberchargedHidden, TFCondDuration_Infinite, 0);
    }
    else
    {
        // Remove hidden ubercharge
        TF2_RemoveCondition(client, TFCond_UberchargedHidden);
        // Move to battlefield
        CreateTimer(0.1, RandomSpawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

/*
 * ------------------------------------------------------------------
 *      __  ____
 *     /  |/  (_)__________
 *    / /|_/ / // ___/ ___/
 *   / /  / / /(__  ) /__
 *  /_/  /_/_//____/\___/
 *
 * ------------------------------------------------------------------
 */

/* LockMap() and other Entity shennanigans
 *
 * Locks all objectives on the map and gets it ready for DM.
 * OnEntityCreated is required to reliably delete entities that get loaded after LockMap() is called
 * Note that this DOES NOT fix needing to reload the map after changing the disable cabinet / health pack / ammo pack cvars
 * -------------------------------------------------------------------------- */

void LockMap()
{
    DoAllEnts();
    OpenDoors();
    ResetPlayers();
}

// Reload map, deleting and recreating most entities
// written by nanochip, modified by me
void ResetMap()
{
    SetConVarInt(FindConVar("mp_restartgame_immediate"), 1);
    // remove waiting for players time
    SetConVarInt(FindConVar("mp_waitingforplayers_time"), 0);
    MC_PrintToChatAll(SOAP_TAG ... "Resetting map.");
}

// func to iterate thru all ents and act on them with DoEnt()
void DoAllEnts()
{
    // iterate thru list of entities to act on
    for (int i = 0; i < sizeof(g_entIter); i++)
    {
        // init variable
        int ent = -1;
        // does this entity exist?
        while ((ent = FindEntityByClassname(ent, g_entIter[i])) > 0)
        {
            if (IsValidEntity(ent) && ent > 0)
            {
                DoEnt(i, ent);
            }
        }
    }
}

// act on the ents: requires iterator #  and entityid
void DoEnt(int i, int entity)
{
    if (IsValidEntity(entity))
    {
        // remove arena logic (disabling doesn't properly disable the fight / spectate bullshit)
        if (StrContains(g_entIter[i], "tf_logic_arena", false) != -1)
        {
            // Why am I not following the rest of the style of the plugin and storing this in a plugin var?
            // Because GetConVar* is literally a pointer deref and it doesn't make any difference from a performance POV.
            // Therefore, I don't care.
            // -sappho
            if (!GetConVarBool(mp_tournament))
            {
                RemoveEntity(entity);
            }
        }
        // if ent is a func regen AND cabinets are off, remove it. otherwise skip
        else if (StrContains(g_entIter[i], "func_regenerate", false) != -1)
        {
            if (g_bDisableCabinet)
            {
                RemoveEntity(entity);
            }
        }
        // if ent is a respawn room (allows for resupping!) AND cabinets are off, remove it. otherwise skip
        else if (StrContains(g_entIter[i], "func_respawnroom", false) != -1)
        {
            if (g_bDisableCabinet)
            {
                RemoveEntity(entity);
            }
        }
        // if ent is a healthpack AND healthpacks are off, remove it. otherwise skip
        else if (StrContains(g_entIter[i], "item_healthkit", false) != -1)
        {
            if (g_bDisableHealthPacks)
            {
                RemoveEntity(entity);
            }
        }
        // if ent is a ammo pack AND ammo kits are off, remove it. otherwise skip
        else if (StrContains(g_entIter[i], "item_ammopack", false) != -1)
        {
            if (g_bDisableAmmoPacks)
            {
                RemoveEntity(entity);
            }
        }
        // move trigger zones out of player reach because otherwise the point gets capped in dm servers and it's annoying
        // we don't remove / disable because both cause issues/bugs otherwise
        else if (StrContains(g_entIter[i], "trigger_capture", false) != -1)
        {
            float hell[3] = {0.0, 0.0, -5000.0};
            TeleportEntity(entity, hell, NULL_VECTOR, NULL_VECTOR);
        }
        else if (StrContains(g_entIter[i], "team_round_timer", false) != -1)
        {
            char map[64];
            GetCurrentMapLowercase(map, sizeof(map));
            if (StrContains(map, "pass_", false) != -1)
            {
                LogMessage("Not disabling passtime team_round_timer to avoid crashes.");
            }
            else
            {
                AcceptEntityInput(entity, "Disable");
            }
        }
        /* kill the pass time ball - TODO: this does nothing. why. why is passtime.
        else if (StrContains(g_entIter[i], "info_passtime_ball_spawn", false) != -1)
        {
             // this doesn't stop the ball from spawning
             AcceptEntityInput(entity, "Disable");
             // this will crash the server
             RemoveEntity(entity);
        }
        */
        // disable every other found matching ent instead of deleting, deleting certain logic/team timer ents is unneeded and can crash servers
        else
        {
            AcceptEntityInput(entity, "Disable");
        }
    }
}

// catch ents that spawn after map start / plugin load
public void OnEntityCreated(int entity, const char[] className)
{
    // iterate thru list of entities to act on
    for (int i = 0; i < sizeof(g_entIter); i++)
    {
        // does it match any of the ents?
        if (StrEqual(className, g_entIter[i]))
        {
            // yes! run DoEnt
            DoEnt(i, entity);
            // break out of the loop
            break;
        }
    }
}

/* OpenDoors() - rewritten by nanochip and stephanie
 *
 * Initially forces all doors open and keeps them unlocked even when they close.
 * -------------------------------------------------------------------------- */
void OpenDoors()
{
    if (g_bOpenDoors)
    {
        int ent = -1;
        // search for all func doors
        while ((ent = FindEntityByClassname(ent, "func_door")) > 0)
        {
            if (IsValidEntity(ent))
            {
                AcceptEntityInput(ent, "unlock", -1);
                AcceptEntityInput(ent, "open", -1);
                FixNearbyDoorRelatedThings(ent);
            }
        }
        // reset ent
        ent = -1;
        // search for all other possible doors
        while ((ent = FindEntityByClassname(ent, "prop_dynamic")) > 0)
        {
            if (IsValidEntity(ent))
            {
                char iName[64];
                char modelName[64];
                GetEntPropString(ent, Prop_Data, "m_iName", iName, sizeof(iName));
                GetEntPropString(ent, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
                if
                (
                        StrContains(iName, "door", false)       != -1
                     || StrContains(iName, "gate", false)       != -1
                     || StrContains(iName, "exit", false)       != -1
                     || StrContains(iName, "grate", false)      != -1
                     || StrContains(modelName, "door", false)   != -1
                     || StrContains(modelName, "gate", false)   != -1
                     || StrContains(modelName, "exit", false)   != -1
                     || StrContains(modelName, "grate", false)  != -1
                )
                {
                    AcceptEntityInput(ent, "unlock", -1);
                    AcceptEntityInput(ent, "open", -1);
                    FixNearbyDoorRelatedThings(ent);
                }
            }
        }
        // reset ent
        ent = -1;
        // search for all other possible doors
        while ((ent = FindEntityByClassname(ent, "func_brush")) > 0)
        {
            if (IsValidEntity(ent))
            {
                char brushName[64];
                GetEntPropString(ent, Prop_Data, "m_iName", brushName, sizeof(brushName));
                if
                (
                        StrContains(brushName, "door", false)   != -1
                     || StrContains(brushName, "gate", false)   != -1
                     || StrContains(brushName, "exit", false)   != -1
                     || StrContains(brushName, "grate", false)  != -1
                )
                {
                    RemoveEntity(ent);
                    FixNearbyDoorRelatedThings(ent);
                }
            }
        }
    }
}

// remove any func_brushes that could be blockbullets and open area portals near those func_brushes
void FixNearbyDoorRelatedThings(int ent)
{
    float doorLocation[3];
    float brushLocation[3];

    GetEntPropVector(ent, Prop_Send, "m_vecOrigin", doorLocation);

    int iterEnt = -1;
    while ((iterEnt = FindEntityByClassname(iterEnt, "func_brush")) > 0)
    {
        if (IsValidEntity(iterEnt))
        {
            GetEntPropVector(iterEnt, Prop_Send, "m_vecOrigin", brushLocation);
            if (GetVectorDistance(doorLocation, brushLocation) < 50.0)
            {
                char brushName[32];
                GetEntPropString(iterEnt, Prop_Data, "m_iName", brushName, sizeof(brushName));
                if
                (
                        StrContains(brushName, "bullet", false) != -1
                     || StrContains(brushName, "door", false)   != -1
                )
                {
                    RemoveEntity(iterEnt);
                }
            }
        }
    }

    // iterate thru all area portals on the map and open them
    // don't worry - the client immediately closes ones that aren't neccecary to be open. probably.
    iterEnt = -1;
    while ((iterEnt = FindEntityByClassname(iterEnt, "func_areaportal")) > 0)
    {
        if (IsValidEntity(iterEnt))
        {
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
    if (FirstLoad == true) {
        for (int i = 0; i < MaxClients; i++) {
            if (IsValidClient(i)) {
                id = GetClientUserId(i);
                CreateTimer(g_fSpawn, Respawn, id, TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        FirstLoad = false;
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
 * Checks if a client is valid. Ignore replay and stv bots.
 * -------------------------------------------------------------------------- */
bool IsValidClient(int client)
{
    return ((0 < client <= MaxClients) && IsClientInGame(client) && !IsClientSourceTV(client) && !IsClientReplay(client));
}

/* GetRealClientCount()
 *
 * Gets the number of clients connected to the game..
 * -------------------------------------------------------------------------- */
int GetRealClientCount()
{
    int clients = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i))
        {
            clients++;
        }
    }

    return clients;
}

void DownloadConfig()
{
    char map[64];
    GetCurrentMapLowercase(map, sizeof(map));

    char url[256];
    Format(url, sizeof(url), "https://raw.githubusercontent.com/sapphonie/SOAP-TF2DM/master/addons/sourcemod/configs/soap/%s.cfg", map);

    LogMessage("GETing url %s", url);

    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);

    SteamWorks_SetHTTPCallbacks(request, OnSteamWorksHTTPComplete);

    SteamWorks_SendHTTPRequest(request);
}

public void OnSteamWorksHTTPComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
    char map[64];
    GetCurrentMapLowercase(map, sizeof(map));

    char path[256];
    BuildPath(Path_SM, path, sizeof(path), "configs/soap/%s.cfg", map);

    if (bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK)
    {
        LogMessage("Downloaded spawn for %s!", map);
        SteamWorks_WriteHTTPResponseBodyToFile(hRequest, path);
        // load our map cfg
        LoadMapConfig(map, path);
    }
    else
    {
        LogMessage("Failed to download spawns. StatusCode = %i, bFailure = %i, RequestSuccessful = %i.", eStatusCode, bFailure, bRequestSuccessful);
        if (GetConfigPath(map, path, sizeof(path)))
        {
            LoadMapConfig(map, path);
        }
    }

    CloseHandle(hRequest);
}

/* OnPluginEnd()
 *
 * When the plugin shuts down.
 * -------------------------------------------------------------------------- */
public void OnPluginEnd()
{
    MC_PrintToChatAll(SOAP_TAG ... "Soap DM unloaded.");
}

public bool GetConfigPath(const char[] map, char[] path, int maxlength)
{
    if (!g_bEnableFallbackConfig)
    {
        return false;
    }
    LogMessage("No config for: %s, searching for fallback...", map);

    char cleanMap[64];
    strcopy(cleanMap, sizeof(cleanMap), map);

    char match[64];
    int matchnum = g_normalizeMapRegex.Match(cleanMap);
    if (matchnum > 0 && g_normalizeMapRegex.GetSubString(0, match, sizeof(match), 0) )
    {
        ReplaceString(cleanMap, sizeof(cleanMap), match, "", true);
        LogMessage("Cleaned map %s.", cleanMap);
    }

    BuildPath(Path_SM, path, maxlength, "configs/soap");
    LogMessage("path %s", path);
    DirectoryListing dh = OpenDirectory(path);
    char file[128];
    char foundFile[128];
    bool foundMatch = false;
    while (dh.GetNext(file, sizeof(file)))
    {
        // match was found at the start of the string
        if  ( StrContains(file, cleanMap, false) == 0 )
        {
            LogMessage("Found near match %s.", file);
            strcopy(foundFile, sizeof(foundFile), file);
            BuildPath(Path_SM, path, maxlength, "configs/soap/%s", file);
            foundMatch = true;
        }
    }

    if (foundMatch)
    {
        LogMessage("No configuration found for %s, loading fallback configuration from %s.", map, foundFile);
        MC_PrintToChatAll(SOAP_TAG ... "No configuration found for %s, loading fallback configuration from %s.", map, foundFile);
        return true;
    }
    else
    {
        LogMessage("No configuration found for %s, no fallback map found. Using default spawns.", map);
        return false;
    }

}

void GetCurrentMapLowercase(char[] map, int sizeofMap)
{
    GetCurrentMap(map, sizeofMap);

    // TF2 is case-insensitive when dealing with map names
    for (int i = 0; i < sizeof(sizeofMap); ++i)
    {
        map[i] = CharToLower(map[i]);
    }

}
