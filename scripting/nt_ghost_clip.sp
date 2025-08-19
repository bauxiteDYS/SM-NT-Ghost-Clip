#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define DEBUG false
#define MAX_GHOST_AREAS 32

Handle g_moveTimer;

char g_tag[] = "[Ghost Clip]";
char g_teleSound[] = "gameplay/ghost_pickup.wav";
char g_mapName[32];

float g_lastSound;
float g_lastTelePos[3];
float g_ghostSpawnPos[3];
float g_ghostLastSafePos[3];
float g_ghostClipAreasMins[MAX_GHOST_AREAS][3];
float g_ghostClipAreasMaxs[MAX_GHOST_AREAS][3];

int g_ghost = -1;
int g_ghostClipAreaCount;

bool g_ghostCarried;
bool g_recordedSafePos;
bool g_doneTeleOnce;
bool g_lateLoad;

public Plugin myinfo = {
	name = "NT Ghost Clip",
	description = "Provides the ability to setup rectangular volumes where the ghost cannot be dropped into",
	author = "bauxite",
	version = "0.1.0",
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
	
	if(g_ghost > 0 && IsValidEntity(g_ghost))
	{
		float ghostPos[3];

		GetEntPropVector(g_ghost, Prop_Data, "m_vecAbsOrigin", ghostPos);
		
		if(!(oldPos[0] == ghostPos[0] && oldPos[1] == ghostPos[1] && oldPos[2] == ghostPos[2]))
		{
			oldPos[0] = ghostPos[0];
			oldPos[1] = ghostPos[1];
			oldPos[2] = ghostPos[2];
			PrintToServer("%s GHOST HAS MOVED - %d", g_tag, GetGameTickCount());
		}
	}
	#endif
	
	if(g_ghost <= 0 || g_ghostCarried || !IsValidEntity(g_ghost))
	{
		return;
	}
	
	CheckGhostPos();
}

void CheckGhostPos()
{
	float ghostPos[3];

	GetEntPropVector(g_ghost, Prop_Data, "m_vecAbsOrigin", ghostPos);
	
	// maybe we check if its in the spawn origin
	// or simply forget working around the ghost spawning in a clip
	// or check if a valid position was recorded and if not do nothing
	// could also check if its being teled to the same place as before and do nothing
	
	if (IsInsideArea(ghostPos))
	{
		#if DEBUG
		PrintToServer("%d is inside an area - %d", g_ghost, GetGameTickCount());
		#endif
		
		// dont teleport into another ghostclip tho somehow ?
		// - only valid tele spots are where client was and round start origin/spawn 
		// so this should not be a problem as we check client before recording
		// or dont teleport if no spawn origin or round start origin, - but we shud always have this?
		// altho this can possibly be 0,0,0 if the ghost was somehow there so cant exclude this
		// but since we always record spawn and round start origin this shud be fine to tele
		// problem is if ghost spawns inside a ghost clip zone...

		if(g_recordedSafePos)
		{
			g_ghostCarried = false; // its not carried as we teleport it now - might be carried again upon teleport finish
			
			TeleportEntity(g_ghost, g_ghostLastSafePos, {0.0, 90.0, 270.0}, {0.0, 0.0, 0.0});
			
			for(int i = 0; i < 3; i++)
			{
				g_lastTelePos[i] = g_ghostLastSafePos[i];
			}
			
			g_doneTeleOnce = true;
		}
		else
		{
			// if we teled the ghost to spawn before and have no valid last safe pos, 
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
			
			TeleportEntity(g_ghost, g_ghostSpawnPos, {0.0, 90.0, 270.0}, {0.0, 0.0, 0.0});
			
			for(int i = 0; i < 3; i++)
			{
				g_lastTelePos[i] = g_ghostSpawnPos[i];
			}
			
			g_doneTeleOnce = true;
		}
		
		SetEntityMoveType(g_ghost, MOVETYPE_NONE); 
		// could be exploitable somehow since it doesnt respond to explosives, lets reset it after 3s?
		// seems to hold 0 grav after 3s but still able to be moved by explosives... better way to achieve this?
		
		if(IsValidHandle(g_moveTimer))
		{
			#if DEBUG
			PrintToServer("%s Already valid move timer handle, deleting", g_tag);
			#endif
			
			delete g_moveTimer;
		}
	
		#if DEBUG
		PrintToServer("%s Creating move timer", g_tag);
		#endif
	
		g_moveTimer = CreateTimer(3.0, ResetGhostMoveType, _, TIMER_FLAG_NO_MAPCHANGE);
		
		if(GetGameTime() > g_lastSound + 1.0)
		{
			g_lastSound = GetGameTime();
			EmitSoundToAll(g_teleSound, _, _, _, _, 0.6, 190);
		}
	}
}

public Action ResetGhostMoveType(Handle timer)
{
	if(g_ghost <= 0 || !IsValidEntity(g_ghost))
	{
		return Plugin_Stop;
	}
	
	int carrier = GetEntPropEnt(g_ghost, Prop_Data, "m_hOwnerEntity");
	
	if(carrier <= 0)
	{
		#if DEBUG
		PrintToServer("%s Resetting ghost move type, carrier: %d", g_tag, carrier);
		#endif
		
		SetEntityMoveType(g_ghost, MOVETYPE_VPHYSICS);
	}

	return Plugin_Stop;
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
	CreateTimer(0.1, RecordGhosterPos, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public Action RecordGhosterPos(Handle timer)
{
	if(g_ghost <= 0 || !g_ghostCarried || !IsValidEntity(g_ghost))
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
		
		#if DEBUG
		g_ghostLastSafePos[2] += 32.0;
		#else
		g_ghostLastSafePos[2] += 3.0;
		#endif
		
		g_recordedSafePos = true;
	}

	return Plugin_Continue;
}

public void OnMapInit()
{
	LoadGhostClips();
	
	if(!HookEventEx("game_round_start", Event_RoundStartPre, EventHookMode_Pre))
	{
		SetFailState("%s Error: Failed to hook round start", g_tag);
	}
}

public void LoadGhostClips()
{
	GetCurrentMap(g_mapName, sizeof(g_mapName));
		
	g_ghostClipAreaCount = 0;
	
	KeyValues kv = new KeyValues("GhostClips");
  
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/ghostclips/ghostclipareas.txt");
	
	if (!kv.ImportFromFile(path))
	{
		SetFailState("%s Error: Ghost clip file not found", g_tag);
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
				if (g_ghostClipAreaCount > MAX_GHOST_AREAS)
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
			SetFailState("%s Map had no areas defined in GhostClip file", g_tag);
		}
	}
	else
	{
		SetFailState("%s Map not found in GhostClip file", g_tag);
	}
	
	delete kv;
	
	#if DEBUG
	PrintToServer("%s Loaded %d areas", g_tag, g_ghostClipAreaCount);
	#endif
}

public Action Event_RoundStartPre(Event event, const char[] name, bool dontBroadcast)
{
	// dunno what happens if a player picks it up before 0.5s - shud be ok as we can still find ghost
	// but pos will be of the player instead...
	
	#if DEBUG
	PrintToServer("%s Round Start", g_tag);
	#endif
	
	g_ghostCarried = false; // its not carried yet
	g_recordedSafePos = false;
	g_doneTeleOnce = false;
	
	CreateTimer(0.5, FindGhostTimer,_, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public void OnMapEnd()
{
	g_ghost = -1;
	g_ghostCarried = false;
	g_recordedSafePos = false;
	g_doneTeleOnce = false;
}

public void OnGhostSpawn(int ghost)
{
	// dunno what happens if a player picks it up before 0.5s - shud be ok as we can still find ghost
	// but pos will be of the player instead...
	
	#if DEBUG
	PrintToChatAll("%s Ghost spawned %d!", g_tag, ghost);
	#endif
	
	g_ghostCarried = false; // its not carried yet - might be carried again upon spawn finish
	CreateTimer(0.5, FindGhostTimer,_, TIMER_FLAG_NO_MAPCHANGE);
}

public Action FindGhostTimer(Handle timer)
{
	FindTheGhost();
	return Plugin_Stop;
}

void FindTheGhost()
{
	// do we need to get the ghost pos when it stops moving and then store that
	
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
	}
}

public void OnGhostPickUp(int carrier)
{
	#if DEBUG
	PrintToChatAll("%N (%d) picked up the ghost!", carrier, carrier);
	#endif
	
	g_ghostCarried = true;
}

public void OnGhostDrop(int client)
{
	#if DEBUG
	PrintToChatAll("%N (%d) dropped the ghost!", client, client);
	#endif
	
	g_ghostCarried = false;
}

public void OnGhostCapture(int client)
{
	#if DEBUG
	PrintToChatAll("%N (%d) retrieved the ghost!", client, client);
	#endif
	
	g_ghost = -1;
}
