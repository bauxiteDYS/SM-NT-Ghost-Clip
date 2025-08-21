#include <sourcemod>
#include <sdkhooks>
#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define DEBUG false
#define MAX_GHOST_AREAS 32

Handle g_findGhostTimer;

char g_tag[] = "[Ghost Clip]";
char g_teleSound[] = "gameplay/ghost_pickup.wav";
char g_mapName[32];

float g_freezeGhostPos[3];
float g_lastSound;
float g_oldGhostPos[3] = {76543.0, 76543.0, 76543.0}; //impossible coordinates
float g_lastTelePos[3];
float g_ghostSpawnPos[3];
float g_ghostLastSafePos[3];
float g_ghostClipAreasMins[MAX_GHOST_AREAS][3];
float g_ghostClipAreasMaxs[MAX_GHOST_AREAS][3];

int g_ghost = -1;
int g_ghostClipAreaCount;

bool g_freezeGhost;
bool g_ghostCarried;
bool g_recordedSafePos;
bool g_doneTeleOnce;
bool g_lateLoad;

public Plugin myinfo = {
	name = "NT Ghost Clip",
	description = "Provides the ability to setup rectangular axis-aligned volumes where the ghost cannot be dropped into",
	author = "bauxite",
	version = "0.2.3",
	url = "",
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_lateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	#if DEBUG
	RegConsoleCmd("sm_fghost", FindGhostCommand);
	#endif
	
	if(g_lateLoad)
	{
		OnMapInit(); // doesn't seem like you need to also call mapstart or cfgs, as they are called again on plugin load
	}
}

#if DEBUG
public Action FindGhostCommand(int client, int args)
{
	FindTheGhost();
	
	return Plugin_Handled;
}
#endif

public void OnGameFrame()
{
	#if DEBUG
	static float oldPos[3];
	static float lastPrint;
	
	if(g_ghost > 0 && IsValidEntity(g_ghost))
	{
		float ghostPos[3];

		GetEntPropVector(g_ghost, Prop_Data, "m_vecAbsOrigin", ghostPos);
		
		if(GetGameTime() < lastPrint + 3.0)
		{
			if(!(oldPos[0] == ghostPos[0] && oldPos[1] == ghostPos[1] && oldPos[2] == ghostPos[2]))
			{
				for(int i = 0; i < 3; i++)
				{
					oldPos[i] = ghostPos[i];
				}
			
				PrintToServer("%s GHOST HAS MOVED - %d", g_tag, GetGameTickCount());
			
				lastPrint = GetGameTime();
			}
		}
	}
	#endif
	
	if(g_ghostClipAreaCount == 0)
	{
		return;
	}
	
	if(g_ghost <= 0 || g_ghostCarried || !IsValidEntity(g_ghost))
	{
		return;
	}
	
	CheckGhostPos();
}

void CheckGhostPos()
{
	bool spawnTele;
	float ghostPos[3];

	GetEntPropVector(g_ghost, Prop_Data, "m_vecAbsOrigin", ghostPos);
			
	if((g_oldGhostPos[0] == ghostPos[0] && g_oldGhostPos[1] == ghostPos[1] && g_oldGhostPos[2] == ghostPos[2]))
	{
		//if the ghost hasn't moved from last check, no need to recheck all areas
		
		#if DEBUG
		static float lastPrint;
		if(GetGameTime() < lastPrint + 3.0)
		{
			return;
		}
		PrintToServer("%s Ghost Hasn't Moved - %d", g_tag, GetGameTickCount());
		lastPrint = GetGameTime();
		#endif
		
		return;
	}
	
	for(int i = 0; i < 3; i++)
	{
		g_oldGhostPos[i] = ghostPos[i];
	}
	
	#if DEBUG
	static float lastPrint;
	if(GetGameTime() < lastPrint + 3.0)
	{
		PrintToServer("%s Checking Ghost pos - %d", g_tag, GetGameTickCount());
		lastPrint = GetGameTime();
	}
	#endif
		
	if (IsInsideArea(ghostPos))
	{
		#if DEBUG
		PrintToServer("%d is inside an area - %d", g_ghost, GetGameTickCount());
		#endif

		if(g_recordedSafePos)
		{
			g_ghostCarried = false; // its not carried as we teleport it now - might be carried again upon teleport finish
			
			TeleportEntity(g_ghost, g_ghostLastSafePos, {0.0, 0.0, 0.0}, {0.0, 0.0, 0.0});
			
			for(int i = 0; i < 3; i++)
			{
				g_lastTelePos[i] = g_ghostLastSafePos[i];
			}
			
			//spawnTele = false; // dont need this as it's already false
			
		}
		else // we dont have a recorded valid pos, doesnt mean ghost spawned in a clip though
		{
			// if we teled the ghost to spawn before and have no valid last safe pos, 
			// and also it didn't move from spawn pos
			// just leave it, its probably stuck in a loop due to spawn being in a clip zone
			
			if(	g_doneTeleOnce 	&& 	g_lastTelePos[0] == g_ghostSpawnPos[0]
								&& 	g_lastTelePos[1] == g_ghostSpawnPos[1]
								&&	g_lastTelePos[2] == g_ghostSpawnPos[2]
								&& 	ghostPos[0] == g_ghostSpawnPos[0]
								&& 	ghostPos[1] == g_ghostSpawnPos[1]
								&& 	ghostPos[2] == g_ghostSpawnPos[2]
			)
			{
				return;
			}
			
			g_ghostCarried = false; // its not carried as we teleport it now - might be carried again upon teleport finish
			
			TeleportEntity(g_ghost, g_ghostSpawnPos, {0.0, 0.0, 0.0}, {0.0, 0.0, 0.0});
			
			#if DEBUG
			PrintToServer("%s Teleporting to Spawn %.3f %.3f %.3f", g_tag, g_ghostSpawnPos[0], g_ghostSpawnPos[1], g_ghostSpawnPos[2]);
			#endif
			
			for(int i = 0; i < 3; i++)
			{
				g_lastTelePos[i] = g_ghostSpawnPos[i];
			}
			
			spawnTele = true;
		}
		
		#if DEBUG
		PrintToServer("%s Teleporting", g_tag);
		#endif
		
		// we just teleported to either spawn or last safe pos
		// now we need to "freeze" it so it doesn't fall back of a ledge or something
		
		g_freezeGhost = true;
		
		if(spawnTele)
		{
			for(int i = 0; i < 3; i++)
			{
				g_freezeGhostPos[i] = g_ghostSpawnPos[i];
			}
		}
		else
		{
			for(int i = 0; i < 3; i++)
			{
				g_freezeGhostPos[i] = g_ghostLastSafePos[i];
			}
		}
		
		FreezeGhost();
		
		if(GetGameTime() > g_lastSound + 1.0)
		{
			// we can skip the first tele to spawntele sound, usually happens if ghost spawns in a clip
			// but it could happen if nobody picks ghost up and somehow it enters a clip also
			// explosions or shooting so idk if this is a good idea...
			
			if(g_doneTeleOnce || !spawnTele) 
			{
				g_lastSound = GetGameTime();
				EmitSoundToAll(g_teleSound, _, _, _, _, 0.6, 190);
			}
		}
		
		g_doneTeleOnce = true;
	}
}

void FreezeGhost()
{
	if(!g_freezeGhost || g_ghost <= 0)
	{
		return;
	}
	
	float none[3];
	
	TeleportEntity(g_ghost, g_freezeGhostPos, none, none);
	RequestFrame(FreezeGhost);
}

bool IsInsideArea(float pos[3])
{
	// return int of the area ent is inside?
	
	bool inside;
	
	for (int i = 0; i < g_ghostClipAreaCount; i++)
	{
		if(	pos[0] >= g_ghostClipAreasMins[i][0] && pos[0] <= g_ghostClipAreasMaxs[i][0] 
		&& 	pos[1] >= g_ghostClipAreasMins[i][1] && pos[1] <= g_ghostClipAreasMaxs[i][1] 
		&& 	pos[2] >= g_ghostClipAreasMins[i][2] && pos[2] <= g_ghostClipAreasMaxs[i][2])
		{
			inside = true;
		}
	}
	
	return inside;
}

public void OnMapStart()
{
	PrecacheSound(g_teleSound);
	CreateTimer(0.1, RecordGhosterPos, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT); // move this to loadclips so we dont need to fail the plugin
	LoadGhostClips(); // can't detect trigger vecs on mapinit
}

public Action RecordGhosterPos(Handle timer)
{
	if(g_ghostClipAreaCount == 0 || g_ghost <= 0 || !g_ghostCarried || !IsValidEntity(g_ghost))
	{
		return Plugin_Continue;
	}
	
	int carrier = GetEntPropEnt(g_ghost, Prop_Data, "m_hOwnerEntity");
	
	if(carrier <= 0 || !IsClientInGame(carrier) || !IsPlayerAlive(carrier))
	{
		return Plugin_Continue;
	}
	
	// check if ghoster inside zone and dont record as valid tele spot
	float clientOrigin[3];
	GetClientAbsOrigin(carrier, clientOrigin);
	
	if(IsInsideArea(clientOrigin))
	{
		return Plugin_Continue;
	}

	if (GetEntityFlags(carrier) & FL_ONGROUND)
	{
		#if DEBUG
		PrintToServer("recording ghost pos %d", GetGameTickCount());
		#endif
		
		for(int i = 0; i < 3; i++)
		{
			g_ghostLastSafePos[i] = clientOrigin[i];
		}
		
		// constant tele method makes it appear on it's side for some reason
		// so we need a little height to stop it from being partially in the ground
		#if DEBUG
		g_ghostLastSafePos[2] += 16.0;
		#else
		g_ghostLastSafePos[2] += 6.0;
		#endif
		
		g_recordedSafePos = true;
	}

	return Plugin_Continue;
}

public void OnMapInit()
{
	if(!HookEventEx("game_round_start", Event_RoundStartPre, EventHookMode_Pre))
	{
		SetFailState("%s Error: Failed to hook round start", g_tag);
	}
}

public void LoadGhostClips()
{
	#if DEBUG
	PrintToServer("%s Finding Ghost Clip triggers", g_tag);
	#endif
	
	g_ghostClipAreaCount = 0;
	
	int ent = -1;
	char buffer[64];
	
	while ((ent = FindEntityByClassname(ent, "trigger_multiple")) != -1)
	{
		if (g_ghostClipAreaCount >= MAX_GHOST_AREAS)
		{
			LogError("%s Error: More than 32 areas in GhostClip file", g_tag);
			break;
		}
				
		GetEntPropString(ent, Prop_Data, "m_iName", buffer, sizeof(buffer));
		
		if (StrContains(buffer, "ghost_clip", false) == 0)
		{
			float origin[3], mins[3], maxs[3];
			
			GetEntPropVector(ent, Prop_Data, "m_vecOrigin", origin);
			GetEntPropVector(ent, Prop_Data, "m_vecMins", mins);
			GetEntPropVector(ent, Prop_Data, "m_vecMaxs", maxs);
			
			#if DEBUG
			PrintToServer("Trigger %d: mins %.1f %.1f %.1f  maxs %.1f %.1f %.1f origin: %.1f %.1f %.1f", 
			ent, mins[0], mins[1], mins[2], maxs[0], maxs[1], maxs[2], origin[0], origin[1], origin[2]);
			#endif
			
			for (int i = 0; i < 3; i++)
			{
				g_ghostClipAreasMins[g_ghostClipAreaCount][i] = origin[i] + mins[i];
				g_ghostClipAreasMaxs[g_ghostClipAreaCount][i] = origin[i] + maxs[i];
			}
			
			g_ghostClipAreaCount++;
		}
	}
	
	if(g_ghostClipAreaCount > 0)
	{	
		return; // we found ghost triggers we wont try to load anything from the cfg file
	}
	
	#if DEBUG
	PrintToServer("%s Did not find any triggers, looking in cfg file", g_tag);
	#endif
	
	GetCurrentMap(g_mapName, sizeof(g_mapName));
	
	KeyValues kv = new KeyValues("GhostClips");
  
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/ghostclips/ghostclipareas.txt");
	
	if (!kv.ImportFromFile(path))
	{
		#if !DEBUG
		SetFailState("%s Error: Ghost clip file not found", g_tag);
		#endif
	}
	
	#if DEBUG
	PrintToServer("%s Found areas", g_tag);
	#endif
		
	if (kv.JumpToKey(g_mapName, false)) // go into the current map section
	{
		if (kv.GotoFirstSubKey(true))
		{
			do
			{
				if (g_ghostClipAreaCount >= MAX_GHOST_AREAS)
				{
					LogError("%s Error: More than 32 areas in GhostClip file", g_tag);
					break;
				}
					 
				float areaMins[3], areaMaxs[3];
				
				kv.GetVector("min", areaMins);
				kv.GetVector("max", areaMaxs);

				for (int i = 0; i < 3; i++)
				{
					#if DEBUG
					PrintToServer("%s Adding areas", g_tag);
					#endif
					
					g_ghostClipAreasMins[g_ghostClipAreaCount][i] = areaMins[i];
					g_ghostClipAreasMaxs[g_ghostClipAreaCount][i] = areaMaxs[i];
				}
					
				g_ghostClipAreaCount++;
					
			}
			while (kv.GotoNextKey(true));
		}
		else
		{
			#if !DEBUG
			SetFailState("%s Map had no areas defined in GhostClip file", g_tag);
			#endif
		}
	}
	else
	{
		#if !DEBUG
		SetFailState("%s Map not found in GhostClip file", g_tag);
		#endif
	}
	
	delete kv;
	
	#if DEBUG
	PrintToServer("%s Loaded %d areas", g_tag, g_ghostClipAreaCount);
	#endif
}

public Action Event_RoundStartPre(Event event, const char[] name, bool dontBroadcast)
{
	#if DEBUG
	PrintToServer("%s Round Start", g_tag);
	#endif
	
	if(g_ghost > 0 && IsValidEntity(g_ghost))
	{
		SDKUnhook(g_ghost, SDKHook_OnTakeDamage, OnGhostDamage);
		#if DEBUG
		PrintToServer("%s Unhooking ghost", g_tag);
		#endif
	}
	
	g_freezeGhost = false;
	
	for(int i = 0; i < 3; i++)
	{
		g_oldGhostPos[i] = 76543.0;
	}
	
	g_ghost = -1;
	g_ghostCarried = false; // its not carried yet
	g_recordedSafePos = false;
	g_doneTeleOnce = false;
	
	if(IsValidHandle(g_findGhostTimer))
	{
		delete g_findGhostTimer;
	}
	
	// dunno what happens if a player picks it up before 0.5s - shud be ok as we can still find ghost
	// but pos will be of the player instead...
	g_findGhostTimer = CreateTimer(0.5, FindGhostTimer,_, TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Continue;
}

public void OnMapEnd()
{
	g_freezeGhost = false;
	g_ghostClipAreaCount = 0;
	g_ghost = -1;
	g_ghostCarried = false;
	g_recordedSafePos = false;
	g_doneTeleOnce = false;
	
	for(int i = 0; i < 3; i++)
	{
		g_oldGhostPos[i] = 76543.0;
	}
}

public Action FindGhostTimer(Handle timer)
{
	FindTheGhost();
	return Plugin_Stop;
}

void FindTheGhost()
{
	int ghost = FindEntityByClassname(-1, "weapon_ghost");
	
	if(ghost <= 0)
	{
		#if DEBUG
		PrintToServer("%s Ghost not found", g_tag);
		#endif
	}
	else
	{
		g_ghost = ghost;
		GetEntPropVector(g_ghost, Prop_Data, "m_vecAbsOrigin", g_ghostSpawnPos);
		
		#if DEBUG
		PrintToServer("%d %f %f %f", g_ghost, g_ghostSpawnPos[0], g_ghostSpawnPos[1], g_ghostSpawnPos[2]);
		PrintToServer("ghost found");
		#endif
		
		if(!SDKHookEx(g_ghost, SDKHook_OnTakeDamage, OnGhostDamage))
		{
			PrintToServer("%s Error hooking ghost damage", g_tag);
		}
		#if DEBUG
		else
		{
			PrintToServer("%s Hooking ghost", g_tag);
		}
		#endif
	}
}

public Action OnGhostDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
	g_freezeGhost = false;
	
	#if DEBUG
	PrintToServer("%s Ghost was DAMAGED!", g_tag);
	#endif
	return Plugin_Continue;
}

public void OnGhostSpawn(int ghost)
{
	#if DEBUG
	PrintToServer("%s Ghost spawned %d!", g_tag, ghost);
	#endif
	
	g_freezeGhost = false;
	g_ghostCarried = false; // its not carried yet - might be carried again upon spawn finish
	
	if(IsValidHandle(g_findGhostTimer))
	{
		delete g_findGhostTimer;
	}
	
	// dunno what happens if a player picks it up before 0.5s - shud be ok as we can still find ghost
	// but pos will be of the player instead...
	g_findGhostTimer = CreateTimer(0.5, FindGhostTimer,_, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnEntityDestroyed(int entity)
{
	char buf[16];
	
	GetEntityClassname(entity, buf, sizeof(buf));
	
	if(StrEqual(buf, "weapon_ghost", false))
	{
		g_ghost = -1;
		
		// we don't need to unhook, it's automatic on entity removal
		#if DEBUG
		PrintToServer("%s Ghost was DESTROYED!", g_tag);
		#endif
	}
}

public void OnGhostPickUp(int carrier)
{
	#if DEBUG
	PrintToChatAll("%N (%d) picked up the ghost!", carrier, carrier);
	#endif
	
	g_freezeGhost = false;
	g_ghostCarried = true;
}

public void OnGhostDrop(int client)
{
	#if DEBUG
	PrintToChatAll("%N (%d) dropped the ghost!", client, client);
	#endif
	
	g_freezeGhost = false;
	g_ghostCarried = false;
}

public void OnGhostCapture(int client)
{
	#if DEBUG
	PrintToChatAll("%N (%d) retrieved the ghost!", client, client);
	#endif
	
	g_freezeGhost = false;
	//g_ghost = -1; // don't do this here
}
