class_name SnapshotCodec
extends RefCounted
## Compact binary world snapshot: one unreliable packet per viewer and tick.
## Frequently changing state is packed once per entity. Rarely changing profile
## fields (model, stats, fitting, contracts, alien kind and home) travel
## separately as reliable arrays only when they change; see FlightSession.
## Each entry names the revision of the profile it was packed with, so clients
## never merge fresh state with an outdated profile.

const OWNER := 1
const ALIVE := 2
const DOCKED := 4
const REPAIRING := 8
const BOOSTS := 16
const RETURNING := 4
const ENGAGED := 8


## Public movement and health for one pilot. `extras` (owner entries only) adds
## velocity, private progress, ammunition, rocket and boost state.
static func player_entry(id: int, data: Dictionary, revision: int, extras: Dictionary = {}) -> PackedByteArray:
	var owner := data.has("credits")
	var systems: PackedFloat32Array = data["systems"]
	var flags := (OWNER if owner else 0) | (ALIVE if data["alive"] else 0) | (DOCKED if data["docked"] else 0) | (REPAIRING if systems[2] > 0.0 else 0)
	if owner and extras.has("boosts"):
		flags |= BOOSTS
	var buffer := StreamPeerBuffer.new()
	buffer.put_u32(id)
	buffer.put_u8(flags)
	buffer.put_u16(revision)
	buffer.put_u32(data["life"])
	buffer.put_u8(data["map"])
	buffer.put_u32(data["visit"])
	put_vector(buffer, data["position"])
	put_vector(buffer, data["rotation"])
	# Health stays 64-bit so repair costs and HUD thresholds match the server exactly.
	buffer.put_double(data["hull"])
	buffer.put_double(data["shield"])
	for value: float in [data["energy"], data["since_hit"], systems[0]]:
		buffer.put_float(value)
	if not owner:
		return buffer.data_array
	put_vector(buffer, data["velocity"])
	buffer.put_u32(data["credits"])
	buffer.put_u32(data["kills"])
	buffer.put_u8(data["stage"])
	buffer.put_float(data["respawn"])
	var rounds: PackedInt32Array = extras.get("rounds", PackedInt32Array())
	buffer.put_u8(rounds.size())
	for value in rounds:
		buffer.put_32(value)
	var rockets: Dictionary = extras.get("rockets", {})
	buffer.put_u8(1 if not rockets.is_empty() else 0)
	if not rockets.is_empty():
		buffer.put_u8(Ammunition.ROCKETS.keys().find(rockets["single_type"]))
		buffer.put_u8(Ammunition.ROCKETS.keys().find(rockets["launcher_type"]))
		buffer.put_float(rockets["single_cooldown"])
		buffer.put_float(rockets["launcher_cooldown"])
		buffer.put_u16(rockets["capacity"])
		buffer.put_u16(rockets["loaded"])
		buffer.put_u8(1 if rockets["loading"] else 0)
		buffer.put_float(rockets["load_clock"])
	if flags & BOOSTS:
		var boosts: Dictionary = extras["boosts"]
		buffer.put_u32(extras["revision"])
		buffer.put_u8(boosts.size())
		for group: String in boosts:
			buffer.put_u8(ResourceBoosts.GROUPS.keys().find(group))
			buffer.put_u8(ResourceBoosts.BONUSES.keys().find(boosts[group]["resource"]))
			buffer.put_double(boosts[group]["remaining"])
	return buffer.data_array


## Fields that change only with fitting, hull, repair extras or contracts.
static func player_profile(data: Dictionary) -> Array:
	var profile: Array = [data["model"], data["stats"], data["fitting"], data["systems"][1]]
	if data.has("contracts"):
		profile.append(data["contracts"].duplicate(true))
	return profile


static func alien_entry(data: Dictionary, revision: int) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_u16(data["id"])
	buffer.put_u8((ALIVE if data["alive"] else 0) | (RETURNING if data["returning"] else 0) | (ENGAGED if data["engaged"] else 0))
	buffer.put_u16(revision)
	buffer.put_u8(data["map"])
	buffer.put_u32(data["encounter"])
	put_vector(buffer, data["position"])
	put_vector(buffer, data["rotation"])
	buffer.put_double(data["hull"])
	buffer.put_double(data["shield"])
	buffer.put_float(data["since_hit"])
	buffer.put_float(data["respawn"])
	return buffer.data_array


static func alien_profile(data: Dictionary) -> Array:
	return [data["kind"], data["home"]]


static func world(sequence: int, visit: int, players: Array[PackedByteArray], aliens: Array[PackedByteArray]) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_u32(sequence)
	buffer.put_u32(visit)
	buffer.put_u8(players.size())
	buffer.put_u8(aliens.size())
	var packet := buffer.data_array
	for entry in players:
		packet.append_array(entry)
	for entry in aliens:
		packet.append_array(entry)
	return packet


## Returns {sequence, visit, players: {id: state}, aliens: {id: state}, owner}.
## Each state's `profile` names its profile revision. States lack profile fields
## until merged with `player_state` or `alien_state`. `owner` holds ammunition, rockets and boosts, or is empty.
static func decode_world(packet: PackedByteArray) -> Dictionary:
	if packet.size() < 10:
		return {}
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = packet
	var result := {"sequence": buffer.get_u32(), "visit": buffer.get_u32(), "players": {}, "aliens": {}, "owner": {}}
	var player_count := buffer.get_u8()
	var alien_count := buffer.get_u8()
	for index in range(player_count):
		var id := buffer.get_u32()
		var flags := buffer.get_u8()
		var data := {"profile": buffer.get_u16(), "life": buffer.get_u32(), "map": buffer.get_u8(), "visit": buffer.get_u32(),
			"position": get_vector(buffer), "rotation": get_vector(buffer), "hull": buffer.get_double(),
			"shield": buffer.get_double(), "energy": buffer.get_float(), "since_hit": buffer.get_float()}
		data["alive"] = flags & ALIVE != 0
		data["docked"] = flags & DOCKED != 0
		data["radiation"] = buffer.get_float()
		data["repairing"] = flags & REPAIRING != 0
		if flags & OWNER:
			data["velocity"] = get_vector(buffer)
			data["credits"] = buffer.get_u32()
			data["kills"] = buffer.get_u32()
			data["stage"] = buffer.get_u8()
			data["respawn"] = buffer.get_float()
			var owner := {"rounds": PackedInt32Array(), "rockets": {}}
			for count in range(buffer.get_u8()):
				owner["rounds"].append(buffer.get_32())
			if buffer.get_u8() == 1:
				owner["rockets"] = {"single_type": Ammunition.ROCKETS.keys()[buffer.get_u8()],
					"launcher_type": Ammunition.ROCKETS.keys()[buffer.get_u8()],
					"single_cooldown": buffer.get_float(), "launcher_cooldown": buffer.get_float(),
					"capacity": buffer.get_u16(), "loaded": buffer.get_u16(),
					"loading": buffer.get_u8() == 1, "load_clock": buffer.get_float()}
			if flags & BOOSTS:
				owner["revision"] = buffer.get_u32()
				var boosts := {}
				for count in range(buffer.get_u8()):
					var group: String = ResourceBoosts.GROUPS.keys()[buffer.get_u8()]
					var resource: String = ResourceBoosts.BONUSES.keys()[buffer.get_u8()]
					var remaining := buffer.get_double()
					boosts[group] = {"resource": resource, "remaining": int(remaining) if group in ["lasers", "rockets"] else remaining}
				owner["boosts"] = boosts
			result["owner"] = owner
		result["players"][id] = data
	for index in range(alien_count):
		var id := buffer.get_u16()
		var flags := buffer.get_u8()
		result["aliens"][id] = {"id": id, "profile": buffer.get_u16(), "alive": flags & ALIVE != 0, "returning": flags & RETURNING != 0,
			"engaged": flags & ENGAGED != 0, "map": buffer.get_u8(), "encounter": buffer.get_u32(),
			"position": get_vector(buffer), "rotation": get_vector(buffer), "hull": buffer.get_double(),
			"shield": buffer.get_double(), "since_hit": buffer.get_float(), "respawn": buffer.get_float()}
	return result if buffer.get_position() == packet.size() else {}


## Rebuilds the same dictionary as `FlightSession.player_state`.
static func player_state(state: Dictionary, profile: Array) -> Dictionary:
	var data := state.duplicate()
	data["model"] = profile[0]
	data["stats"] = profile[1]
	data["fitting"] = profile[2]
	data["systems"] = PackedFloat32Array([data["radiation"], profile[3], 1.0 if data["repairing"] else 0.0])
	data.erase("radiation")
	data.erase("repairing")
	data.erase("profile")
	if data.has("credits"):
		data["contracts"] = profile[4].duplicate(true) if profile.size() > 4 else {}
	return data


## Rebuilds the same dictionary as `SessionCombat.pack_alien`.
static func alien_state(state: Dictionary, profile: Array) -> Dictionary:
	var data := state.duplicate()
	data["kind"] = profile[0]
	data["home"] = profile[1]
	data.erase("profile")
	return data


static func put_vector(buffer: StreamPeerBuffer, value: Vector3) -> void:
	buffer.put_float(value.x)
	buffer.put_float(value.y)
	buffer.put_float(value.z)


static func get_vector(buffer: StreamPeerBuffer) -> Vector3:
	return Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
