#pragma semicolon 1 // Force strict semicolon mode.
#pragma newdecls required // use new syntax

// ====[ INCLUDES ]====================================================
#include <sourcemod>
#include <sdktools>
#include <regex>
#include <tf2_stocks>
#include <morecolors>
#include <sdkhooks>
#include <dhooks>
// Needed for downloading spawns
#include <SteamWorks>

#undef REQUIRE_PLUGIN
#include <afk>
#include <updater>


#pragma newdecls required // use new syntax


// ====[ CONSTANTS ]===================================================
#define PLUGIN_NAME         "SOAP TF2 Deathmatch"
#define PLUGIN_AUTHOR       "Icewind, MikeJS, Lange, Tondark - maintained by sappho.io"
#define PLUGIN_VERSION      "4.5.0"
#define PLUGIN_CONTACT      "https://github.com/sapphonie/SOAP-TF2DM"
#define UPDATE_URL          "https://raw.githubusercontent.com/sapphonie/SOAP-TF2DM/master/updatefile.txt"

// ====[ VARIABLES ]===================================================

// for morecolors lol
#define SOAP_TAG "{lime}[{cyan}SOAP{lime}]{white} "

#define TFMAXPLAYERS 33

bool FirstLoad;

// Regen-over-time
bool g_bRegen[TFMAXPLAYERS+1];

Handle g_hRegenTimer[TFMAXPLAYERS+1];

bool g_bSpawnMap;
ArrayList g_hRedSpawns;
ArrayList g_hBluSpawns;
Handle g_hKv;

// Kill Regens (hp+ammo)
int g_iMaxClips1[TFMAXPLAYERS+1];
int g_iMaxClips2[TFMAXPLAYERS+1];
int g_iMaxHealth[TFMAXPLAYERS+1];

// Time limit enforcement
Handle g_tCheckTimeLeft;



// stuff for debug show spwns
Handle Timer_ShowSpawns;
int te_modelidx;

// mp_tourney convar
Handle mp_tournament;

// Regen damage given on kill
#define RECENT_DAMAGE_SECONDS 15
int g_iRecentDamage[TFMAXPLAYERS+1][TFMAXPLAYERS+1][RECENT_DAMAGE_SECONDS];
Handle g_hRecentDamageTimer;

// AFK
int g_bAFKSupported;


// Load config from other map version
Regex g_normalizeMapRegex;

char spawnSound[24] = "items/spawn_item.wav";

Handle soap_gamedata;
Handle SDKCall_GetBaseEntity;


// for determining if we should let a client spawn or not
bool dontSpawnClient[TFMAXPLAYERS+1];

ConVar soap_regenhp           ;
ConVar soap_regentick         ;
ConVar soap_regendelay        ;
ConVar soap_kill_start_regen  ;
ConVar soap_spawn_delay       ;
ConVar soap_spawnrandom       ;
ConVar soap_teamspawnrandom   ;
ConVar soap_kill_heal_ratio   ;
ConVar soap_dmg_heal_ratio    ;
ConVar soap_kill_heal_static  ;
ConVar soap_kill_ammo         ;
ConVar soap_opendoors         ;
ConVar soap_disablecabinet    ;
ConVar soap_showhp            ;
ConVar soap_forcetimelimit    ;
ConVar soap_disablehealthpacks;
ConVar soap_disableammopacks  ;
ConVar soap_novelocityonspawn ;
ConVar soap_debugspawns       ;
ConVar soap_fallback_config   ;
ConVar soap_autoupdate_spawns ;

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
    "tf_logic_arena",                   // DELETE*      - need to delete these, otherwise fight / spectate bullshit shows up on arena maps
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
    "item_ammopack_small",              // DELETE       - ^
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
    // g_bCanDownload  = GetExtensionFileStatus("SteamWorks.ext") == 1 ? true : false;

    if (LibraryExists("updater")) {
        Updater_AddPlugin(UPDATE_URL);
    }

    LoadTranslations("soap_tf2dm.phrases");

    // Create convars
    // make soap version cvar unchageable to work around older autogen'd configs resetting it back to 3.8
    CreateConVar("soap", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_CHEAT);
    soap_regenhp                = CreateConVar("soap_regenhp",              "1", "Health added per regeneration tick. Set to 0 to disable.", FCVAR_NOTIFY);
    soap_regentick              = CreateConVar("soap_regentick",            "0.1", "Delay between regeration ticks.", FCVAR_NOTIFY);
    soap_regendelay             = CreateConVar("soap_regendelay",           "5.0", "Seconds after damage before regeneration.", FCVAR_NOTIFY);
    soap_kill_start_regen       = CreateConVar("soap_kill_start_regen",     "1", "Start the heal-over-time regen immediately after a kill.", FCVAR_NOTIFY);
    soap_spawn_delay            = CreateConVar("soap_spawn_delay",          "1.5", "Spawn timer.", FCVAR_NOTIFY);
    soap_spawnrandom            = CreateConVar("soap_spawnrandom",          "1", "Enable random spawns.", FCVAR_NOTIFY);
    soap_teamspawnrandom        = CreateConVar("soap_teamspawnrandom",      "0", "Enable random spawns independent of team", FCVAR_NOTIFY);
    soap_kill_heal_ratio        = CreateConVar("soap_kill_heal_ratio",      "0.5", "Percentage of HP to restore on kills. .5 = 50%. Should not be used with soap_kill_heal_static.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    soap_dmg_heal_ratio         = CreateConVar("soap_dmg_heal_ratio",       "0.0", "Percentage of HP to restore based on amount of damage given. .5 = 50%. Should not be used with soap_kill_heal_static.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    soap_kill_heal_static       = CreateConVar("soap_kill_heal_static",     "0", "Amount of HP to restore on kills. Exact value applied the same to all classes. Should not be used with soap_kill_heal_ratio.", FCVAR_NOTIFY);
    soap_kill_ammo              = CreateConVar("soap_kill_ammo",            "1", "Enable ammo restoration on kills.", FCVAR_NOTIFY);
    soap_opendoors              = CreateConVar("soap_opendoors",            "1", "Force all doors to open. Required on maps like cp_well.", FCVAR_NOTIFY);
    soap_disablecabinet         = CreateConVar("soap_disablecabinet",       "1", "Disables the resupply cabinets on map load", FCVAR_NOTIFY);
    soap_showhp                 = CreateConVar("soap_showhp",               "1", "Print killer's health to victim on death.", FCVAR_NOTIFY);
    soap_forcetimelimit         = CreateConVar("soap_forcetimelimit",       "1", "Time limit enforcement, used to fix a never-ending round issue on gravelpit.", _, true, 0.0, true, 1.0);
    soap_disablehealthpacks     = CreateConVar("soap_disablehealthpacks",   "0", "Disables the health packs on map load.", FCVAR_NOTIFY);
    soap_disableammopacks       = CreateConVar("soap_disableammopacks",     "0", "Disables the ammo packs on map load.", FCVAR_NOTIFY);
    soap_novelocityonspawn      = CreateConVar("soap_novelocityonspawn",    "1", "Prevents players from inheriting their velocity from previous lives when spawning thru SOAP.", FCVAR_NOTIFY);
    soap_debugspawns            = CreateConVar("soap_debugspawns",          "0", "Set to 1 to draw boxes around spawn points when players spawn. Set to 2 to draw ALL spawn points constantly. For debugging.", FCVAR_NOTIFY, true, 0.0, true, 2.0);
    soap_fallback_config        = CreateConVar("soap_fallback_config", "1", "Enable falling back to spawns from other versions of the map if no spawns are configured for the current map.", FCVAR_NOTIFY);
    soap_autoupdate_spawns      = CreateConVar("soap_autoupdate_spawns", "1", "Always download the newest version of spawns for every map loaded.", FCVAR_NOTIFY);


    // for determining whether to delete arena entities or not
    mp_tournament           = FindConVar("mp_tournament");

    // Hook convar changes and events
    HookConVarChange(soap_debugspawns,      handler_ConVarChange);
    HookConVarChange(soap_fallback_config,  handler_ConVarChange);
    HookConVarChange(soap_opendoors,      handler_ConVarChange);
    HookConVarChange(soap_disablecabinet,  handler_ConVarChange);
    HookConVarChange(soap_disablehealthpacks,  handler_ConVarChange);
    HookConVarChange(soap_disableammopacks,  handler_ConVarChange);

    HookEvent("player_death",           Event_player_death, EventHookMode_Pre);
    HookEvent("player_hurt",            Event_player_hurt);
    HookEvent("player_spawn",           Event_player_spawn, EventHookMode_Pre);
    HookEvent("player_team",            Event_player_team,  EventHookMode_Pre);
    HookEvent("player_changeclass",     Event_player_class, EventHookMode_Pre);
    HookEvent("teamplay_round_start",   Event_round_start);
    HookEvent("teamplay_restart_round", Event_round_start);

    // Create arrays for the spawning system
    g_hRedSpawns = CreateArray(6);
    g_hBluSpawns = CreateArray(6);

    // Crutch to fix some issues that appear when the plugin is loaded mid-round.
    FirstLoad = true;

    // Lock control points and intel on map. Also respawn all players into DM spawns. This instance of LockMap() is needed for mid-round loads of DM. (See: Volt's DM/Pub hybrid server.)
    LockMap();

    // Create configuration file in cfg/sourcemod folder
    AutoExecConfig(true, "soap_tf2dm", "sourcemod");

    g_normalizeMapRegex = new Regex("(_(a|b|beta|u|r|v|rc|f|final|comptf|ugc)?[0-9]*[a-z]?$)|([0-9]+[a-z]?$)", 0);

    GetRealClientCount();

    OnConfigsExecuted();

    te_modelidx = PrecacheModel("effects/beam_generic_2.vmt", true);

    // SetConVarBool(FindConVar("mp_disable_respawn_times"), false);


    // GAMEDATA
    soap_gamedata = LoadGameConfigFile("soap");
    if (!soap_gamedata)
    {
        SetFailState("Couldn't load SOAP DM gamedata!");
    }

    // For preventing clients from respawning when they're not supposed to
    Handle CTFPlayer__ForceRespawn = DHookCreateFromConf(soap_gamedata, "CTFPlayer::ForceRespawn");
    if (!CTFPlayer__ForceRespawn)
    {
        SetFailState("Failed to setup detour for CTFPlayer::ForceRespawn");
    }

    if (!DHookEnableDetour(CTFPlayer__ForceRespawn, false, Detour_CTFPlayer__ForceRespawn))
    {
        SetFailState("Failed to detour CTFPlayer::ForceRespawn");
    }
    PrintToServer("-> Detoured CTFPlayer::ForceRespawn");

    // For getting the entity index of a client from a pointer
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(soap_gamedata, SDKConf_Virtual, "CBaseEntity::GetBaseEntity");
    PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
    SDKCall_GetBaseEntity = EndPrepSDKCall();
    if (!SDKCall_GetBaseEntity)
    {
        SetFailState("Couldn't set up CBaseEntity::GetBaseEntity SDKCall");
    }
    PrintToServer("-> Detoured CTFPlayer::ForceRespawn");
}

// This is run on map start since the gamerules ent will get wiped and respawned on map changes
void doGameRulesDetour()
{
    // For forcing the round state to be "running" and not preround or anything else dumb
    Handle CTFGameRules__Think = DHookCreateFromConf(soap_gamedata, "CTFGameRules::Think");
    if (!CTFGameRules__Think)
    {
        SetFailState("Failed to setup detour for CTFGameRules::Think");
    }

    if (!DHookEnableDetour(CTFGameRules__Think, false, Detour_CTFGameRules__Think))
    {
        SetFailState("Failed to detour CTFGameRules::Think.");
    }

    PrintToServer("-> Detoured CTFGameRules::Think");
}

MRESReturn Detour_CTFGameRules__Think(int pThis)
{
    // RoundState rs = GameRules_GetRoundState();
    // LogMessage("-> !!!!!Detour_CTFGameRules__Think!!!!!!!! %i", rs);

    // don't interfere with after round bullshit
    RoundState roundstate = view_as<RoundState>( GameRules_GetProp("m_iRoundState") );
    if (roundstate >= RoundState_Bonus)
    {
        return MRES_Ignored;
    }
    GameRules_SetProp("m_iRoundState", RoundState_RoundRunning);
    return MRES_Ignored;
}

public MRESReturn Detour_CTFPlayer__ForceRespawn(Address pThis)
{
    // I don't know why this would ever happen but just in case
    if (!pThis)
    {
        LogMessage("no this");
        return MRES_Ignored;
    }

    // LogMessage("-> !!!!!Detour_CTFPlayer__ForceRespawn!!!!!!!!");
    // LogMessage("ent = %x", pThis);

    // Don't inhibit spawns on maps without actual spawns
    if (!g_bSpawnMap)
    {
        // LogMessage("no g_bSpawnMap");
        return MRES_Ignored;
    }

    int client = SDKCall(SDKCall_GetBaseEntity, pThis);
    //LogMessage("client = %N", client);

    if (IsClientSourceTV(client) || IsClientReplay(client))
    {
        return MRES_Ignored;
    }

    if (dontSpawnClient[client])
    {
        //LogMessage("dontSpawnClient = %N", dontSpawnClient[client]);
        return MRES_Supercede;
    }

    return MRES_Ignored;
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

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "afk"))
    {
        g_bAFKSupported = false;
    }
}

/* OnMapStart()
 *
 * When the map starts.
 * -------------------------------------------------------------------------- */
public void OnMapStart()
{
    // Kill everything, because fuck memory leaks.
    delete g_tCheckTimeLeft;

    for (int i = 1; i <= MaxClients; i++)
    {
        delete g_hRegenTimer[i];
    }

    // DON'T load on MGE
    char map[128];
    GetCurrentMapLowercase(map, sizeof(map));

    if (StrContains(map, "mge", false) != -1)
    {
        SetFailState("Cowardly refusing to load SOAP DM on an MGE map.");
    }

    // init our spawn system
    InitSpawnSys();

    // Load the sound file played when a player is spawned.
    PrecacheSound(spawnSound, true);

    // Begin the time check that prevents infinite rounds on A/D and KOTH maps.
    CreateTimeCheck();

    doGameRulesDetour();
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

    delete g_hKv;
    g_hKv = CreateKeyValues("Spawns");

    char map[64];
    GetCurrentMapLowercase(map, sizeof(map));

    char path[256];
    BuildPath(Path_SM, path, sizeof(path), "configs/soap/%s.cfg", map);

    if (GetConVarBool(soap_autoupdate_spawns))
    {
        LogMessage("Updating map spawns for map: %s. Trying to download...", map);
        DownloadConfig();
    }
    else
    {
        LogMessage("Not autodownloading spawns, soap_autoupdate_spawns == 0!");
        // Try to load a fallback
        if (GetConfigPath(map, path, sizeof(path)))
        {
            LoadMapConfig(map, path);
        }
    }
    // we got a local copy
    // if (FileExists(path))
    // {
    //     LoadMapConfig(map, path);
    // }
    // we don't have a local copy
    // else
    // {
    //     // we can try to download one
    //     //if (g_bCanDownload)
    //     //{
    //     //    LogMessage("Map spawns missing. Map: %s. Trying to download...", map);
    //     //    DownloadConfig();
    //     //}
    //     // // we can't try to download one
    //     // else
    //     // {
    //     //     LogMessage("Map spawns missing. Map: %s. SteamWorks is not installed, we can't try to download them!", map);
    //     //     // Try to load a fallback
    //     //     if (GetConfigPath(map, path, sizeof(path)))
    //     //     {
    //     //         LoadMapConfig(map, path);
    //     //     }
    //     // }
    // }
    // End spawn system.
}

// initalCheck being true means we're checking only if the spawn
int  entityHit = -1;
bool IsPointValidForPlayer(float point[3], bool initalCheck = false, int spawningClient = -1)
{
    if (initalCheck)
    {
        // test if this spawn is even remotely sane
        if (TR_PointOutsideWorld(point))
        {
            MC_PrintToChatAll(SOAP_TAG ... "Spawn at %.2f %.2f %.2f is COMPLETELY outside the world!", point[0], point[1], point[2]);
            LogError("Spawn at %.2f %.2f %.2f is outside the world! Aborting...", point[0], point[1], point[2]);
            return false;
        }
    }


    // player box and then cube ( sizeOfBox x sizeOfBox x sizeOfBox )
    if (!initalCheck)
    {
        float mins[3] = { -24.0, -24.0, 0.0  };
        float maxs[3] = {  24.0,  24.0, 82.0 };

        // Check if player is at this point
        TR_TraceHullFilter
        (
            point,
            point,
            mins,
            maxs,
            MASK_PLAYERSOLID, // only hit solid entities
            PlayerFilter
        );

        // debug, for visualizing
        if (GetConVarInt(soap_debugspawns) > 0)
        {
            // This makes mins/maxes actually exist in the world at our chosen point instead of at origin
            AddVectors(point, mins, mins);
            AddVectors(point, maxs, maxs);

            float life = 2.5;
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


        // The (trace) box hit a gamer
        if (TR_DidHit())
        {
            // LogMessage("Spawn at %.2f %.2f %.2f %i hit a player! Trying another spawn...", point[0], point[1], point[2]);
            return false;
        }

        // Check if enemy player or enemy projectile is within sizeOfBox units cubed of this point
        const float sizeOfBox = 256.0;
        mins = { -sizeOfBox, -sizeOfBox, -sizeOfBox };
        maxs = {  sizeOfBox,  sizeOfBox,  sizeOfBox };

        // This makes mins/maxes actually exist in the world at our chosen point instead of at origin
        AddVectors(point, mins, mins);
        AddVectors(point, maxs, maxs);

        // I know it looks sus here passing a global variable to this function, but this is all run single threaded
        // so it will always match with the ProjectileEnumerator function for that client
        entityHit = -1;
        TR_EnumerateEntitiesBox(mins, maxs, 0 /* don't mask any ents out */, ProjectileEnumerator, spawningClient);

        // debug, for visualizing
        if (GetConVarInt(soap_debugspawns) > 0)
        {
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

        if (entityHit > 0)
        {
            // LogMessage("Spawn at %.2f %.2f %.2f hit... something?!?! ent = %i - Aborting...", point[0], point[1], point[2], entityHit);
            return false;
        }
    }
    // size of a player
    else
    {
        float mins[3] = { -24.0, -24.0, 0.0  };
        float maxs[3] = {  24.0,  24.0, 82.0 };

        TR_TraceHullFilter
        (
            point,
            point,
            mins,
            maxs,
            MASK_PLAYERSOLID, // solid ents only
            WorldFilter
        );

        // The (trace) box hit the world
        if (TR_DidHit())
        {
            // The trace hit the world! Uh oh.
            LogError("Spawn at %.2f %.2f %.2f clips into the world - needs more space! Aborting...", point[0], point[1], point[2]);
            return false;
        }
    }

    return true;
}

#include <sdkhooks>

// True to continue enumerating, otherwise false.
public bool ProjectileEnumerator(int entity, int spawningClient)
{
    // World (yes, we are allowed to clip into the world) or invalid, keep looking
    if (entity == 0 || !IsValidEntity(entity))
    {
        return true;
    }

    char classname[128];
    if (!GetEntityClassname(entity, classname, sizeof(classname)))
    {
        // Should never happen?!?
        LogError("No classname set for entity %i!?", entity);
        return true;
    }

    // This checks if the player or projectile within this box is on the same team
    // as the player we are trying to spawn here or not
    if (StrEqual(classname, "player") || StrContains(classname, "proj_") != -1)
    {
        int foundEntityTeam;
        // player
        if (entity <= MaxClients)
        {
            foundEntityTeam = GetClientTeam(entity);
        }
        // projectile
        else
        {
            foundEntityTeam = GetEntProp(entity, Prop_Send, "m_iTeamNum");
        }

        int spawningClientTeam;
        spawningClientTeam = GetClientTeam(spawningClient);

        // Same team, keep looking for more entities
        if (foundEntityTeam == spawningClientTeam)
        {
            return true;
        }

        // NOT the same team, stop looking, we can't spawn here
        entityHit = entity;
        return false;
    }

    // Keep looking...
    return true;
}

// True to allow ent to be hit, false otherwise
public bool WorldFilter(int entity, int contentsMask)
{
    // world
    if (entity == 0)
    {
        return true;
    }
    // not world
    return false;
}

// True to allow ent to be hit, false otherwise
public bool PlayerFilter(int entity, int contentsMask)
{
    // not a player
    if (entity > MaxClients)
    {
        return false;
    }
    // player
    else
    {
        return true;
    }
}

// Some day I will rewrite this
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
                if (!IsPointValidForPlayer(origin, true))
                {
                    continue;
                }

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
                if (!IsPointValidForPlayer(origin, true))
                {
                    continue;
                }

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
    while (KvGotoNextKey(g_hKv));
}

/* OnMapEnd()
 *
 * When the map ends.
 * -------------------------------------------------------------------------- */
public void OnMapEnd()
{
    // Memory leaks: fuck 'em.
    delete g_tCheckTimeLeft;
    delete Timer_ShowSpawns;

    for (int i = 0; i <= MaxClients; i++)
    {
        delete g_hRegenTimer[i];
    }
}

/* OnConfigsExecuted()
 *
 * When game configurations (e.g., map-specific configs) are executed.
 * -------------------------------------------------------------------------- */
public void OnConfigsExecuted()
{
    if (GetConVarInt(soap_debugspawns) >= 2)
    {
        LogMessage("doing debug spawns");
        delete Timer_ShowSpawns;
        Timer_ShowSpawns = CreateTimer(0.1, DebugShowSpawns, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }

    // reexec map config after grabbing cvars - for dm servers, to customize cvars per map etc.
    char map[64];
    GetCurrentMapLowercase(map, sizeof(map));

    ServerCommand("exec %s", map);
}


/* OnClientConnected()
 *
 * When a client connects to the server.
 * -------------------------------------------------------------------------- */
public void OnClientConnected(int client)
{
    // Set the client's slot regen timer handle to null.
    delete g_hRegenTimer[client];

    // Reset the player's damage given/received to 0.
    ResetPlayerDmgBasedRegen(client, true);

    // Kills the annoying 30 second "waiting for players" at the start of a map.
    //ServerCommand("mp_waitingforplayers_cancel 1");
    SetConVarInt(FindConVar("mp_waitingforplayers_time"), 0);

    dontSpawnClient[client] = false;
}

/* OnClientDisconnect()
 *
 * When a client disconnects from the server.
 * -------------------------------------------------------------------------- */
public void OnClientDisconnect(int client)
{
    // Set the client's slot regen timer handle to null.
    delete g_hRegenTimer[client];

    // Reset the player's damage given/received to 0.
    ResetPlayerDmgBasedRegen(client, true);

    dontSpawnClient[client] = false;
}

/* handler_ConVarChange()
 *
 * Called when a convar's value is changed..
 * -------------------------------------------------------------------------- */
public void handler_ConVarChange(Handle convar, const char[] oldValue, const char[] newValue)
{

    if (convar == soap_opendoors)
    {
        if (!!StringToInt(newValue))
        {
            OpenDoors();
        }
        else
        {
            ResetMap();
        }
        return;
    }

    if (convar == soap_disablecabinet || soap_disablehealthpacks || soap_disableammopacks)
    {
        if (!!StringToInt(newValue))
        {
            DoAllEnts();
        }
        else
        {
            ResetMap();
        }
        return;
    }

    if (convar == soap_kill_heal_ratio)
    {
        StartStopRecentDamagePushbackTimer();
        return;
    }

    if (convar == soap_debugspawns)
    {
        if (StringToInt(newValue) <= 0)
        {
            // gets whacked in the timer
        }
        else if (StringToInt(newValue) == 1)
        {
            InitSpawnSys();

            LogMessage("doing debug spawns [1]");
        }
        else if (StringToInt(newValue) >= 2)
        {
            InitSpawnSys();

            LogMessage("doing debug spawns [2]");
            delete Timer_ShowSpawns;
            Timer_ShowSpawns = CreateTimer(0.1, DebugShowSpawns, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        }
        return;
    }
    if (convar == soap_fallback_config)
    {
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
 * Check map time left every 1 seconds.
 * -------------------------------------------------------------------------- */
public Action CheckTime(Handle timer)
{
    int iTimeLeft;
    int iTimeLimit;
    GetMapTimeLeft(iTimeLeft);
    GetMapTimeLimit(iTimeLimit);

    // LogMessage("timeleft = %i, timelimit = %i", iTimeLeft, iTimeLimit);

    // If soap_forcetimelimit = 1, mp_timelimit != 0, and the timeleft is < 0, change the map to sm_nextmap in 15 seconds.
    if (GetConVarBool(soap_forcetimelimit) && iTimeLeft < -5 && iTimeLimit > 0)
    {
        // TODO: Is this really still needed?
        // Prevents a constant map change issue present on a small number of servers.
        if (GetRealClientCount() > 0)
        {
            ChangeMap();
        }
    }

    return Plugin_Continue;
}

/* ChangeMap()
 *
 * Changes the map to whatever sm_nextmap is.
 * -------------------------------------------------------------------------- */
void ChangeMap()
{
    // If sm_nextmap isn't set or isn't registered, abort because there is nothing to change to.
    if (FindConVar("sm_nextmap") == null)
    {
        LogError("[SOAP] FATAL: Could not find sm_nextmap cvar. Cannot force a map change!");
        return;
    }

    char newmap[64];
    GetNextMap(newmap, sizeof(newmap));
    ForceChangeLevel(newmap, "Enforced Map Timelimit");
}

/* CreateTimeCheck()
 *
 * Used to create the timer that checks if the round is over.
 * -------------------------------------------------------------------------- */
void CreateTimeCheck()
{
    delete g_tCheckTimeLeft;

    g_tCheckTimeLeft = CreateTimer(0.1, CheckTime, _, TIMER_REPEAT);
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
void RandomSpawn_ReqFrame(int userid)
{
    RandomSpawn(null, userid);
}

public Action RandomSpawn(Handle timer, int userid)
{
    // UserIDs are passed through timers instead of client indexes because it ensures that no mismatches can happen as UserIDs are unique.
    int client = GetClientOfUserId(userid);

    // Client wasn't valid
    if (!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    // get client team
    int team = GetClientTeam(client);

    // if random team spawn is enabled...
    if (GetConVarBool(soap_teamspawnrandom))
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

    if (IsPointValidForPlayer(origin, false /* use 256x256 box */, client))
    {
        ActuallySpawnPlayer(client, origin, angles);
    }
    else
    {
        // Try again...
        RequestFrame(RandomSpawn_ReqFrame, userid);
    }

    return Plugin_Continue;
}

void ActuallySpawnPlayer(int client, float origin[3], float angles[3])
{
    dontSpawnClient[client] = false;
    // Respawn them, they will get teleported ASAP
    TF2_RespawnPlayer(client);

    // and actually teleport the player!
    // null their velocity so ppl don't go flying when they respawn
    if (GetConVarBool(soap_novelocityonspawn))
    {
        TeleportEntity(client, origin, angles, {0.0, 0.0, 0.0});
    }
    // Teleport the player to their spawn point [ old logic ]
    else
    {
        TeleportEntity(client, origin, angles, NULL_VECTOR);
    }

    // Make a sound at the spawn point.
    EmitAmbientSound(spawnSound, origin);
}

int currentlyshowingcolor = 2;
Action DebugShowSpawns(Handle timer)
{
    if (GetConVarInt(soap_debugspawns) < 2)
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
    // no roll etc
    angles[2] = 0.0;

    // bottom left
    float mins[3] = { -24.0, -24.0, 0.0  };
    // top right
    float maxs[3] = {  24.0,  24.0, 82.0 };

    // This is so we can draw a yellow line that indicates where the client will face when they spawn
    float newpos[3];
    float angvec[3];
    GetAngleVectors(angles, angvec, NULL_VECTOR, NULL_VECTOR);

    // scale the angles 64 units in front of us
    ScaleVector(angvec, 64.0);

    // add em
    AddVectors(origin, angvec, newpos);

    // draw it
    TE_DrawLazer(origin, newpos, {255,255,1,255});

    // draw spawn in the world instead of around the origin
    AddVectors(origin, mins, mins);
    AddVectors(origin, maxs, maxs);

    // send the damn box
    TE_SendBeamBoxToAll
    (
        mins,                                       // upper corner
        maxs,                                       // lower corner
        te_modelidx,                                // model index
        te_modelidx,                                // halo index
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
public Action Respawn(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidClient(client))
    {
        return Plugin_Continue;
    }

    TFTeam team = TF2_GetClientTeam(client);
    if (team != TFTeam_Blue && team != TFTeam_Red)
    {
        return Plugin_Continue;
    }

    // Are random spawns on and does this map have spawns?
    if
    (
        GetConVarBool(soap_spawnrandom) && g_bSpawnMap
        &&
        // Is player not afk?
        (
            !g_bAFKSupported || !IsPlayerAFK(client)
        )
    )
    {
        RandomSpawn(null, userid);
    }
    else
    {
        // Play a sound anyway, because sounds are cool.
        // Don't play a sound if the player is AFK.
        if (!g_bAFKSupported || !IsPlayerAFK(client))
        {
            TF2_RespawnPlayer(client);
            float origin[3];
            GetClientEyePosition(client, origin);
            EmitAmbientSound(spawnSound, origin);
        }
    }

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
public Action StartRegen(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    // delete g_hRegenTimer[client];

    if (!IsValidClient(client))
    {
        return Plugin_Continue;
    }

    g_bRegen[client] = true;

    g_hRegenTimer[client] = CreateTimer(GetConVarFloat(soap_regentick), Regen, userid, TIMER_REPEAT);

    // Regen(null, userid);

    return Plugin_Continue;
}

/* Regen()
 *
 * Heals a player for X amount of health every Y seconds.
 * -------------------------------------------------------------------------- */
public Action Regen(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidClient(client))
    {
        return Plugin_Continue;
    }

    if (g_bRegen[client] && IsPlayerAlive(client))
    {
        int health = GetClientHealth(client) + GetConVarInt(soap_regenhp);

        // If the regen would give the client more than their max hp, just set it to max.
        if (health > g_iMaxHealth[client])
        {
            health = g_iMaxHealth[client];
        }

        if (GetClientHealth(client) <= g_iMaxHealth[client])
        {
            SetEntProp(client, Prop_Send, "m_iHealth", health, 1);
            SetEntProp(client, Prop_Data, "m_iHealth", health, 1);
        }

        // Call this function again in g_fRegenTick seconds.
        // g_hRegenTimer[client] = CreateTimer(GetConVarFloat(soap_regentick), Regen, userid);
    }

    return Plugin_Continue;
}

/* Timer_RecentDamagePushback()
 *
 * Every second push back all recent damage by 1 index.
 * This ensures we only remember the last <x> seconds of recent damage.
 * -------------------------------------------------------------------------- */
public Action Timer_RecentDamagePushback(Handle timer, int userid)
{
    // This is dumb and ugly
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i))
        {
            continue;
        }

        for (int j = 1; j <= MaxClients; j++)
        {
            if (!IsValidClient(j))
            {
                continue;
            }

            for (int k = RECENT_DAMAGE_SECONDS - 2; k >= 0; k--)
            {
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
    if (GetConVarFloat(soap_dmg_heal_ratio) > 0.0)
    {
        if (!g_hRecentDamageTimer)
        {
            g_hRecentDamageTimer = CreateTimer(1.0, Timer_RecentDamagePushback, _, TIMER_REPEAT);
        }
    }
    else
    {
        delete g_hRecentDamageTimer;
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
    int userid = GetClientUserId(client);

    int isDeadRinger = GetEventInt(event,"death_flags") & 32;
    if (!IsValidClient(client) || isDeadRinger)
    {
        return Plugin_Continue;
    }

    CreateTimer(GetConVarFloat(soap_spawn_delay), Respawn, userid, TIMER_FLAG_NO_MAPCHANGE);

    int attacker    = GetClientOfUserId(GetEventInt(event, "attacker"));
    // LogMessage("attacker = %i", attacker);
    // int assister = GetClientOfUserId(GetEventInt(event, "assister"));


    if (!IsValidClient(attacker))
    {
        return Plugin_Continue;
    }

    int weapon1 = -1;
    int weapon2 = -1;

    int weaponID1 = -1;
    int weaponID2 = -1;

    if (attacker != 0)
    {
        if (IsValidEntity(GetPlayerWeaponSlot(attacker, 0)))
        {
            weapon1 = GetPlayerWeaponSlot(attacker, 0);
            if (weapon1 > MaxClients)
            {
                weaponID1 = GetEntProp(weapon1, Prop_Send, "m_iItemDefinitionIndex");
            }
        }
        if (IsValidEntity(GetPlayerWeaponSlot(attacker, 1)))
        {
            weapon2 = GetPlayerWeaponSlot(attacker, 1);
            if (weapon2 > MaxClients)
            {
                weaponID2 = GetEntProp(weapon2, Prop_Send, "m_iItemDefinitionIndex");
            }
        }
    }

    if (attacker != 0 && client != attacker)
    {
        if (GetConVarBool(soap_showhp))
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
        if (GetConVarFloat(soap_kill_heal_ratio) > 0.0)
        {
            if ((GetClientHealth(attacker) + RoundFloat(GetConVarFloat(soap_kill_heal_ratio) * g_iMaxHealth[attacker])) > g_iMaxHealth[attacker])
            {
                targetHealth = g_iMaxHealth[attacker];
            }
            else
            {
                targetHealth = GetClientHealth(attacker) + RoundFloat(GetConVarFloat(soap_kill_heal_ratio) * g_iMaxHealth[attacker]);
            }
        }

        // Heals a flat value, regardless of class.
        else if (GetConVarInt(soap_kill_heal_static) > 0)
        {
            if ((GetClientHealth(attacker) + GetConVarInt(soap_kill_heal_static)) > g_iMaxHealth[attacker])
            {
                targetHealth = g_iMaxHealth[attacker];
            }
            else
            {
                targetHealth = GetClientHealth(attacker) + GetConVarInt(soap_kill_heal_static);
            }
        }

        if (targetHealth > GetClientHealth(attacker))
        {
            SetEntProp(attacker, Prop_Data, "m_iHealth", targetHealth);
        }

        // Gives full ammo for primary and secondary weapon to the player who got the kill.
        // This is not compatable with unlockreplacer, because as far as i can tell, it doesn't even work anymore.
        if (GetConVarBool(soap_kill_ammo) && !FindConVar("sm_unlock_version"))
        {
            // Check the primary weapon, and set its ammo.
            // make sure the weapon is actually a real one!
            if (weapon1 == -1 || weaponID1 == -1)
            {
                return Plugin_Continue;
            }
            // Widowmaker can not be reliably resupped, and the point of the weapon is literally infinite ammo for aiming anyway. Skip it!
            else if (weaponID1 == 527)
            {
                return Plugin_Continue;
            }
            // this fixes the cow mangler and pomson
            else if (weaponID1 == 441 || weaponID1 == 588)
            {
                SetEntPropFloat(GetPlayerWeaponSlot(attacker, 0), Prop_Send, "m_flEnergy", 20.0);
            }
            else if (g_iMaxClips1[attacker] > 0)
            {
                SetEntProp(GetPlayerWeaponSlot(attacker, 0), Prop_Send, "m_iClip1", g_iMaxClips1[attacker]);
            }
            // Check the secondary weapon, and set its ammo.
            // make sure the weapon is actually a real one!
            if (weapon2 == -1 || weaponID2 == -1)
            {
                return Plugin_Continue;
            }
            // this fixes the bison
            else if (weaponID2 == 442)
            {
                SetEntPropFloat(GetPlayerWeaponSlot(attacker, 1), Prop_Send, "m_flEnergy", 20.0);
            }
            else if (g_iMaxClips2[attacker] > 0)
            {
                SetEntProp(GetPlayerWeaponSlot(attacker, 1), Prop_Send, "m_iClip1", g_iMaxClips2[attacker]);
            }
        }

        // Give the killer regen-over-time if so configured.
        if (soap_kill_start_regen && !g_bRegen[attacker])
        {
            int attackeruserid = GetClientUserId(attacker);
            StartRegen(null, attackeruserid);
        }
    }

    // Heal the people that damaged the victim (also if the victim died without there being an attacker).
    if (GetConVarFloat(soap_dmg_heal_ratio) > 0.0)
    {
        char clientname[32];
        GetClientName(client, clientname, sizeof(clientname));
        for (int player = 1; player <= MaxClients; player++)
        {
            if (!IsValidClient(player))
            {
                continue;
            }

            int dmg = 0;
            for (int i = 0; i < RECENT_DAMAGE_SECONDS; i++)
            {
                dmg += g_iRecentDamage[client][player][i];
                g_iRecentDamage[client][player][i] = 0;
            }

            dmg = RoundFloat(dmg * GetConVarFloat(soap_dmg_heal_ratio));

            if (dmg > 0 && IsPlayerAlive(player))
            {
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
    if (GetConVarFloat(soap_dmg_heal_ratio) > 0.0)
    {
        ResetPlayerDmgBasedRegen(client);
    }

    return Plugin_Continue;
}

/* Event_player_hurt()
 *
 * Called when a player is hurt.
 * -------------------------------------------------------------------------- */
public Action Event_player_hurt(Handle event, const char[] name, bool dontBroadcast)
{
    int userid      = GetEventInt(event, "userid");
    int client      = GetClientOfUserId(GetEventInt(event, "userid"));
    int attacker    = GetClientOfUserId(GetEventInt(event, "attacker"));
    int damage      = GetEventInt(event, "damageamount");

    if (!IsValidClient(attacker) || client == attacker || !attacker)
    {
        return Plugin_Continue;
    }
    g_bRegen[client] = false;

    delete g_hRegenTimer[client];

    g_hRegenTimer[client] = CreateTimer(GetConVarFloat(soap_regendelay), StartRegen, userid);
    g_iRecentDamage[client][attacker][0] += damage;

    return Plugin_Continue;
}

bool isSpawnProtected[TFMAXPLAYERS+1] = false;

void SpawnProtect(int client)
{
    isSpawnProtected[client] = true;
    SetEntityCollisionGroup(client, 2 /* what is 2 */ );
    EntityCollisionRulesChanged(client);
    SetEntityRenderMode(client, RENDER_TRANSCOLOR);
    SetEntityRenderColor(client, 255, 255, 255, 128);

    int weapon;
    for (int i = 0; i <= view_as<int>(TFWeaponSlot_Item2); i++)
    {
        weapon = GetPlayerWeaponSlot(client, i);
        if (IsValidEntity(weapon))
        {
            SetEntityRenderMode(weapon, RENDER_TRANSCOLOR);
            SetEntityRenderColor(weapon, 255, 255, 255, 128);
        }
    }
    TF2_AddCondition(client, TFCond_UberchargedHidden, TFCondDuration_Infinite, 0);
}

void SpawnUnprotect(int client)
{
    SetEntityCollisionGroup(client, 0 /* what is 0 */ );
    EntityCollisionRulesChanged(client);
    SetEntityRenderMode(client, RENDER_NORMAL);
    SetEntityRenderColor(client, 255, 255, 255, 255);

    int weapon;
    for (int i = 0; i <= view_as<int>(TFWeaponSlot_Item2); i++)
    {
        weapon = GetPlayerWeaponSlot(client, i);
        if (IsValidEntity(weapon))
        {
            SetEntityRenderMode(weapon, RENDER_NORMAL);
            SetEntityRenderColor(weapon, 255, 255, 255, 255);
        }
    }
    int userid = GetClientUserId(client);
    TF2_RemoveCondition(client, TFCond_UberchargedHidden);
    isSpawnProtected[client] = false;
}


public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if ( isSpawnProtected[client] && ( buttons || weapon || mouse[0] || mouse[1] ) )
    {
        SpawnUnprotect(client);
    }
    return;
}

/* Event_player_spawn()
 *
 * Called when a player spawns.
 * -------------------------------------------------------------------------- */
public Action Event_player_spawn(Handle event, const char[] name, bool dontBroadcast)
{
    int client  = GetClientOfUserId(GetEventInt(event, "userid"));
    int userid  = GetClientUserId(client);

    if (!IsValidClient(client))
    {
        return Plugin_Continue;
    }
    SpawnProtect(client);
    ResetPlayerDmgBasedRegen(client);
    // No sentries!
    int flags   = GetEntityFlags(client);
    flags      |= FL_NOTARGET;
    SetEntityFlags(client, flags);

    delete g_hRegenTimer[client];
    g_hRegenTimer[client] = CreateTimer(GetConVarFloat(soap_regendelay), StartRegen, userid);

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
public Action Event_round_start(Handle event, const char[] name, bool dontBroadcast)
{
    LockMap();

    return Plugin_Continue;
}

/* Event_player_team()
 *
 * Called when a player joins a team.
 * -------------------------------------------------------------------------- */
public Action Event_player_team(Handle event, const char[] name, bool dontBroadcast)
{
    int userid      = GetEventInt(event, "userid");
    int client      = GetClientOfUserId(userid);

    int team        = GetEventInt(event, "team");
    int oldteam     = GetEventInt(event, "oldteam");

    dontSpawnClient[client] = true;

    if ( team != oldteam )
    {
        // LogMessage("player team ->");
        ResetPlayerDmgBasedRegen(client, true);
        // spec / unassigned
        if (oldteam == 0 || oldteam == 1)
        {
            // dontSpawnClient[client] = false;
            CreateTimer(GetConVarFloat(soap_spawn_delay), Respawn, userid);
        }
    }

    return Plugin_Continue;
}


/* Event_player_class()
 *
 * Called when a player requests to change their class.
 * -------------------------------------------------------------------------- */
public Action Event_player_class(Handle event, const char[] name, bool dontBroadcast)
{

    int userid  = GetEventInt(event, "userid");
    int client  = GetClientOfUserId(userid);

    dontSpawnClient[client] = true;

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
        SpawnProtect(client);
    }
    else
    {
        // Move to battlefield
        RandomSpawn_ReqFrame(GetClientUserId(client));
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

    FirstLoad = true;
    ResetPlayers();

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
                //int entref = EntIndexToEntRef(ent);
                DoEnt(i, ent);
            }
        }
    }
}

// act on the ents: requires iterator # and entref
void DoEnt(int i, int entity)
{
    //if (!IsValidEntity(entref))
    //{
    //    return;
    //}

    if (!IsValidEntity(entity))
    {
        return;
    }
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
        if (GetConVarBool(soap_disablecabinet))
        {
            RemoveEntity(entity);
        }
    }
    // if ent is a respawn room (allows for resupping!) AND cabinets are off, remove it. otherwise skip
    else if (StrContains(g_entIter[i], "func_respawnroom", false) != -1)
    {
        if (GetConVarBool(soap_disablecabinet))
        {
            RemoveEntity(entity);
        }
    }
    // if ent is a healthpack AND healthpacks are off, remove it. otherwise skip
    else if (StrContains(g_entIter[i], "item_healthkit", false) != -1)
    {
        if (GetConVarBool(soap_disablehealthpacks))
        {
            RemoveEntity(entity);
        }
    }
    // if ent is a ammo pack AND ammo kits are off, remove it. otherwise skip
    else if (StrContains(g_entIter[i], "item_ammopack", false) != -1)
    {
        if (GetConVarBool(soap_disableammopacks))
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

// catch ents that spawn after map start / plugin load
public void OnEntityCreated(int entity, const char[] className)
{
    // iterate thru list of entities to act on
    for (int i = 0; i < sizeof(g_entIter); i++)
    {
        // does it match any of the ents?
        if (StrEqual(className, g_entIter[i]))
        {
            // Need to requestframe here...
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
    if (!GetConVarBool(soap_opendoors))
    {
        return;
    }
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
void ResetPlayers()
{
    int userid;
    if (FirstLoad)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClient(i))
            {
                userid = GetClientUserId(i);
                CreateTimer(GetConVarFloat(soap_spawn_delay), Respawn, userid, TIMER_FLAG_NO_MAPCHANGE);
                ResetPlayerDmgBasedRegen(i);
            }
        }

        FirstLoad = false;
    }
    else
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClient(i))
            {
                userid = GetClientUserId(i);
                dontSpawnClient[i] = true;
                CreateTimer(0.1, StartRegen, userid, TIMER_FLAG_NO_MAPCHANGE);
                ResetPlayerDmgBasedRegen(i);
            }
        }
    }
}

/* ResetPlayerDmgBasedRegen()
 *
 * Resets the client's recent damage output to 0.
 * -------------------------------------------------------------------------- */
void ResetPlayerDmgBasedRegen(int client, bool alsoResetTaken = false)
{
    for (int player = 1; player <= MaxClients; player++)
    {
        for (int i = 0; i < RECENT_DAMAGE_SECONDS; i++)
        {
            g_iRecentDamage[player][client][i] = 0;
            if (alsoResetTaken)
            {
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
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i))
        {
            SpawnUnprotect(i);
            SDKHooks_TakeDamage(i, 0, 0, 9999.9, DMG_CRIT, 0, {10000.0, 10000.0, 10000.0}, NULL_VECTOR, true);
        }
    }

    MC_PrintToChatAll(SOAP_TAG ... "Soap DM unloaded.");
}

public bool GetConfigPath(const char[] map, char[] path, int maxlength)
{
    if (!GetConVarBool(soap_fallback_config))
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
        if (StrContains(file, cleanMap, false) == 0)
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
