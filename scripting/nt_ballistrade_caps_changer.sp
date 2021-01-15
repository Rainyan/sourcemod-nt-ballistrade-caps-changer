#include <sourcemod>
#include <sdktools>

#pragma semicolon 1

#define PLUGIN_VERSION "0.4"

#define POSITION_REMOVE_ME_X 1234.5
#define POSITION_REMOVE_ME_Y 6789.0
#define POSITION_REMOVE_ME_Z -1337.0
// Set capzone new coordinates to this value to mark it for removal.
#define POSITION_REMOVE_ME POSITION_REMOVE_ME_X,POSITION_REMOVE_ME_Y,POSITION_REMOVE_ME_Z

#define NEO_MAX_PLAYERS 32

// HACK: these should go to a nt_ghostcap native include
native int GhostEvents_RemoveCapzone(int capzone_entity);
native int GhostEvents_UpdateCapzone(int capzone_entity);

public Plugin myinfo = {
	name = "nt_ballistrade capzone changer",
	description = "Modify nt_ballistrade cap zones amount and location.",
	author = "Rain",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rainyan/sourcemod-nt-ballistrade-caps-changer"
};

public void OnMapStart()
{
	decl String:map_name[PLATFORM_MAX_PATH];
	if (GetCurrentMap(map_name, sizeof(map_name)) < 1) {
		return;
	}

	if (!StrEqual(map_name, "nt_ballistrade_ctg")) {
		return;
	}

	// Because we can't know plugin load order, and it's critical that we touch the capzones last, delaying a few seconds here.
	CreateTimer(5.0, Timer_ModifyCapZones);
}

public Action Timer_ModifyCapZones(Handle timer)
{
	ModifyCapZones();
	return Plugin_Stop;
}

void ModifyCapZones()
{
#define NUM_CAPZONES 4

	// These are the original capzone coordinates to use for identification.
	float cap_original_positions[NUM_CAPZONES][3] = {
		{ 564.0,		1161.0,		131.0	}, // CAPZONE_STREET
		{ 521.0,		-3134.0,		131.0	}, // CAPZONE_STREET_WHITE_BUS_SIDE
		{ 1749.0,		-3041.0,		256.0	}, // CAPZONE_PARKING_LOT
		{ 2587.0,		-760.0,		115.0	}, // CAPZONE_QUICK_CAP
	};

	// These are the new capzone positions wanted. Use POSITION_REMOVE_ME to remove a capzone.
	float cap_new_positions[NUM_CAPZONES][3] = {
		{ -20.0,		684.0,			131.0	}, // CAPZONE_STREET
		{ POSITION_REMOVE_ME					}, // CAPZONE_STREET_WHITE_BUS_SIDE
		{ 1749.0,		-3041.0,		256.0	}, // CAPZONE_PARKING_LOT
		{ POSITION_REMOVE_ME					}, // CAPZONE_QUICK_CAP
	};

	int offset_capzone_vecpos = FindSendPropInfo("CNeoGhostRetrievalPoint", "m_Position");
	if (offset_capzone_vecpos == -1) {
		SetFailState("Failed to find datatable offset for CNeoGhostRetrievalPoint m_Position");
	}

	int max_entities = GetMaxEntities(), num_identified_capzones = 0;
	decl String:classname[25 + 1]; // need length of "neo_ghost_retrieval_point" + \0 = 26
	float pos[3];

	for (int ent = NEO_MAX_PLAYERS + 1; ent <= max_entities; ++ent) {
		if (!IsValidEntity(ent)) {
			continue;
		}
		else if (!GetEntityClassname(ent, classname, sizeof(classname))) {
			continue;
		}
		else if (!StrEqual(classname, "neo_ghost_retrieval_point")) {
			continue;
		}

		GetEntDataVector(ent, offset_capzone_vecpos, pos);

		bool this_capzone_identified = false;
		for (int pos_idx = 0; pos_idx < NUM_CAPZONES; ++pos_idx) {
			// First, try to find an exact match for this capzone position.
			this_capzone_identified = (VectorsEqual(pos, cap_original_positions[pos_idx]));

			// If there was no perfect match, try within half a unit error margin.
			// This could happen if the mapper placed the capzone off-grid.
			if (!this_capzone_identified) {
				this_capzone_identified = (VectorsEqual(pos, cap_original_positions[pos_idx], 0.5));
			}

			if (this_capzone_identified) {
				if (ShouldRemovePosition(cap_new_positions[pos_idx])) {
					GhostEvents_RemoveCapzone(ent); // Not checking return value because we don't have guarantees on plugin load order
					if (!AcceptEntityInput(ent, "kill")) {
						ThrowError("Failed to kill capzone ent %d (pos: %f %f %f)", ent, pos[0], pos[1], pos[2]);
					}
				}
				else {
					SetEntDataVector(ent, offset_capzone_vecpos, cap_new_positions[pos_idx], true);
					SetEntPropVector(ent, Prop_Data, "m_vecOrigin", cap_new_positions[pos_idx]);
					GhostEvents_UpdateCapzone(ent); // Not checking return value because we don't have guarantees on plugin load order
				}
				break;
			}
		}

		if (this_capzone_identified) {
			++num_identified_capzones;
		}
		else {
			//PrintToServer("Found unidentified capzone ent %d (pos: %f %f %f)", ent, pos[0], pos[1], pos[2]);
		}
	}

	if (num_identified_capzones != NUM_CAPZONES) {
		ThrowError("Expected to identify %d capzones, but only identified %d of them.", NUM_CAPZONES, num_identified_capzones);
	}
}

bool ShouldRemovePosition(const float[3] pos)
{
	float remove_location_id[3] = { POSITION_REMOVE_ME };
	return VectorsEqual(pos, remove_location_id);
}

bool VectorsEqual(const float[3] v1, const float[3] v2, const float max_ulps = 0.0)
{
	// Needs to exactly equal.
	if (max_ulps == 0) {
		return v1[0] == v2[0] && v1[1] == v2[1] && v1[2] == v2[2];
	}
	// Allow an inaccuracy of size max_ulps.
	else {
		if (FloatAbs(v1[0] - v2[0]) > max_ulps) { return false; }
		if (FloatAbs(v1[1] - v2[1]) > max_ulps) { return false; }
		if (FloatAbs(v1[2] - v2[2]) > max_ulps) { return false; }
		//PrintToServer("%f %f %f roughly equaled (max_ulps: %f) %f %f %f", v1[0], v1[1], v1[2], max_ulps, v2[0], v2[1], v2[2]);
		return true;
	}
}
