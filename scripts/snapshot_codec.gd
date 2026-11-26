class_name SnapshotCodec
extends RefCounted
## Compact binary world snapshots, sent unreliably.
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
const MAX_PACKET_BYTES := 1200
const HEADER_BYTES := 20
const PUBLIC_PLAYER := 0
const OWNER_PLAYER := 1
const ALIEN := 2
const KIND_SHIFT := 14
const POSITION_SCALE := 256.0
const ANGLE_SCALE := 65536.0 / TAU
const HEALTH_SCALE := 4.0
const ENERGY_SCALE := 256.0
const HIT_TIME_SCALE := 100.0
const HIT_TIME_LIMIT := 6.0

# Mask bits follow field order. Metadata (bit 0) includes flags, revision and
# identity epochs. A change there starts a full entity record. Zero widths are
# variable fields with a leading u8 length (position escape and private extras).
const FIELDS := [
	[12, 0, 6, 3, 3, 2, 2, 4],                  # public pilot
	[12, 12, 12, 8, 8, 4, 4, 4, 12, 9, 24, 13, 12, 0], # owner
	[8, 0, 6, 3, 3, 2, 4],                       # alien
]
## Server input counters carried in the owner entry; see InputBuffer.
const INPUT_COUNTERS := ["applied", "duplicates", "late", "lost", "dropped", "starved"]


## Public movement and health for one pilot. `extras` (owner entries only) adds
## velocity, the input acknowledgement (last processed input `ack`, buffered
## `depth`, `turn_budget` and the server's `inputs` counters), private
## progress, ammunition, rocket and boost state.
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
	if not owner:
		put_public_pose(buffer, data)
		buffer.put_u16(roundi(clampf(data["energy"], 0.0, 100.0) * ENERGY_SCALE))
		put_hit_time(buffer, data["since_hit"])
		buffer.put_float(systems[0])
		return buffer.data_array
	put_vector(buffer, data["position"])
	put_vector(buffer, data["rotation"])
	# Owner values retain the precision used for reconciliation and repair costs.
	buffer.put_double(data["hull"])
	buffer.put_double(data["shield"])
	for value: float in [data["energy"], data["since_hit"], systems[0]]:
		buffer.put_float(value)
	put_vector(buffer, data["velocity"])
	buffer.put_u32(extras.get("ack", 0))
	buffer.put_u8(clampi(extras.get("depth", 0), 0, 255))
	buffer.put_float(extras.get("turn_budget", 0.0))
	var inputs: Dictionary = extras.get("inputs", {})
	for key: String in INPUT_COUNTERS:
		buffer.put_u32(inputs.get(key, 0))
	buffer.put_u32(data["credits"])
	buffer.put_u32(data["kills"])
	buffer.put_u8(data["stage"])
	buffer.put_float(data["respawn"])
	var traffic: Dictionary = extras.get("traffic", {})
	buffer.put_u32(traffic.get("bytes_per_second", 0))
	buffer.put_u16(traffic.get("bytes_per_tick", 0))
	buffer.put_u16(traffic.get("delta_permille", 0))
	buffer.put_u32(traffic.get("full_fallbacks", 0))
	var length_offset := buffer.get_position()
	buffer.put_u8(0)
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
	var entry := buffer.data_array
	entry[length_offset] = entry.size() - length_offset - 1
	return entry


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
	put_public_pose(buffer, data)
	put_hit_time(buffer, data["since_hit"])
	buffer.put_float(data["respawn"])
	return buffer.data_array


static func alien_profile(data: Dictionary) -> Array:
	return [data["kind"], data["home"]]


static func put_public_pose(buffer: StreamPeerBuffer, data: Dictionary) -> void:
	var position: Vector3 = data["position"] - SectorMaps.origin(data["map"])
	var magnitude := position.abs()
	if roundi(magnitude[magnitude.max_axis_index()] * POSITION_SCALE) <= 0x7fffff:
		buffer.put_u8(9)
		for axis in 3:
			put_u24(buffer, roundi(position[axis] * POSITION_SCALE))
	else:
		buffer.put_u8(12)
		put_vector(buffer, data["position"])
	var rotation: Vector3 = data["rotation"]
	for axis in 3:
		buffer.put_u16(roundi(wrapf(rotation[axis], 0.0, TAU) * ANGLE_SCALE) & 0xffff)
	for value: float in [data["hull"], data["shield"]]:
		put_u24(buffer, clampi(roundi(value * HEALTH_SCALE), 0, 0xffffff))


static func get_public_pose(buffer: StreamPeerBuffer, data: Dictionary) -> void:
	var length := buffer.get_u8()
	if length == 9:
		var position := Vector3.ZERO
		for axis in 3:
			var value := get_u24(buffer)
			position[axis] = (value - 0x1000000 if value & 0x800000 else value) / POSITION_SCALE
		data["position"] = SectorMaps.origin(data["map"]) + position
	else:
		data["position"] = get_vector(buffer)
	var rotation := Vector3.ZERO
	for axis in 3:
		var value := buffer.get_u16()
		rotation[axis] = (value - 65536 if value >= 32768 else value) / ANGLE_SCALE
	data["rotation"] = rotation
	data["hull"] = get_u24(buffer) / HEALTH_SCALE
	data["shield"] = get_u24(buffer) / HEALTH_SCALE


static func put_hit_time(buffer: StreamPeerBuffer, value: float) -> void:
	# Only the local pilot needs the exact timer for repair eligibility.
	buffer.put_u16(roundi(clampf(value, 0.0, HIT_TIME_LIMIT) * HIT_TIME_SCALE))


static func put_u24(buffer: StreamPeerBuffer, value: int) -> void:
	buffer.put_u16(value & 0xffff)
	buffer.put_u8((value >> 16) & 0xff)


static func get_u24(buffer: StreamPeerBuffer) -> int:
	return buffer.get_u16() | (buffer.get_u8() << 16)


## Entries are keyed by (record kind, entity ID). Owner and public entries
## always have distinct keys, including in the baseline.
static func player_key(entry: PackedByteArray) -> Vector2i:
	return Vector2i(OWNER_PLAYER if entry[4] & OWNER else PUBLIC_PLAYER, entry.decode_u32(0))


static func alien_key(entry: PackedByteArray) -> Vector2i:
	return Vector2i(ALIEN, entry.decode_u16(0))


## A part carries an exact sequence, visit, tick and baseline sequence (zero
## for full state). Parts can be applied as they arrive. Only a complete set
## can be acknowledged and used as a baseline.
static func encode_world(sequence: int, visit: int, tick: int, entries: Dictionary, baseline: Dictionary = {}) -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	var packet := PackedByteArray()
	packet.resize(HEADER_BYTES)
	var old: Dictionary = baseline.get("entries", {})
	var count := 0
	for key: Vector2i in entries:
		var record := encode_record(key.x, entries[key], old.get(key, PackedByteArray()))
		if record.size() > MAX_PACKET_BYTES - HEADER_BYTES:
			push_error("Snapshot entity exceeds the packet budget")
			return []
		if packet.size() + record.size() > MAX_PACKET_BYTES:
			packet.encode_u16(18, count)
			packets.append(packet)
			packet = PackedByteArray()
			packet.resize(HEADER_BYTES)
			count = 0
		packet.append_array(record)
		count += 1
	packet.encode_u16(18, count)
	packets.append(packet)
	if packets.size() > 255:
		push_error("Snapshot exceeds the part count limit")
		return []
	for index in packets.size():
		packet = packets[index]
		packet.encode_u32(0, sequence)
		packet.encode_u32(4, visit)
		packet.encode_u32(8, tick)
		packet.encode_u32(12, baseline.get("sequence", 0))
		packet[16] = index
		packet[17] = packets.size()
		packets[index] = packet
	return packets


static func encode_record(kind: int, entry: PackedByteArray, old: PackedByteArray) -> PackedByteArray:
	var id_size := 2 if kind == ALIEN else 4
	var widths: Array = FIELDS[kind]
	var record := PackedByteArray([0, 0])
	var mask := kind << KIND_SHIFT
	if entry == old:
		record.encode_u16(0, mask)
		record.append_array(entry.slice(0, id_size))
		return record
	if old.is_empty() or entry.slice(id_size, id_size + widths[0]) != old.slice(id_size, id_size + widths[0]):
		record.encode_u16(0, mask | ((1 << widths.size()) - 1))
		record.append_array(entry)
		return record
	record.append_array(entry.slice(0, id_size))
	var offset := id_size
	var previous := id_size
	for bit in widths.size():
		var width: int = widths[bit] if widths[bit] != 0 else entry[offset] + 1
		var old_width: int = widths[bit] if widths[bit] != 0 else old[previous] + 1
		var field := entry.slice(offset, offset + width)
		if width != old_width or field != old.slice(previous, previous + old_width):
			mask |= 1 << bit
			record.append_array(field)
		offset += width
		previous += old_width
	record.encode_u16(0, mask)
	return record


static func header(packet: PackedByteArray) -> Dictionary:
	if packet.size() < HEADER_BYTES or packet.size() > MAX_PACKET_BYTES or packet[16] >= packet[17]:
		return {}
	var sequence := packet.decode_u32(0)
	var baseline := packet.decode_u32(12)
	if sequence == 0 or baseline >= sequence:
		return {}
	return {"sequence": sequence, "visit": packet.decode_u32(4), "tick": packet.decode_u32(8),
		"baseline": baseline, "part": packet[16], "parts": packet[17]}


## Reconstructs this part's packed entries using the exact acknowledged state.
## An entity with a zero mask still yields a sample for this server tick.
static func decode_world(packet: PackedByteArray, baseline: Dictionary = {}) -> Dictionary:
	var result := header(packet)
	if result.is_empty() or result["baseline"] != baseline.get("sequence", 0):
		return {}
	if not baseline.is_empty() and result["visit"] != baseline["visit"]:
		return {}
	var old: Dictionary = baseline.get("entries", {})
	var entries := {}
	var offset := HEADER_BYTES
	for index in packet.decode_u16(18):
		if offset + 2 > packet.size():
			return {}
		var tag := packet.decode_u16(offset)
		var kind := tag >> KIND_SHIFT
		var mask := tag & ((1 << KIND_SHIFT) - 1)
		var id_size := 2 if kind == ALIEN else 4
		offset += 2
		if kind >= FIELDS.size() or offset + id_size > packet.size():
			return {}
		var id := packet.decode_u16(offset) if kind == ALIEN else packet.decode_u32(offset)
		var key := Vector2i(kind, id)
		if entries.has(key):
			return {}
		var widths: Array = FIELDS[kind]
		var full_mask := (1 << widths.size()) - 1
		if mask > full_mask:
			return {}
		var entry := packet.slice(offset, offset + id_size)
		offset += id_size
		var previous: PackedByteArray = old.get(key, PackedByteArray())
		if mask != full_mask and previous.is_empty():
			return {}
		if mask == 0:
			entries[key] = previous
			continue
		var old_offset := id_size
		for bit in widths.size():
			var width: int = widths[bit]
			var old_width := width
			if not previous.is_empty() and width == 0:
				old_width = previous[old_offset] + 1
			if mask & (1 << bit):
				if width == 0:
					if offset >= packet.size():
						return {}
					width = packet[offset] + 1
					if bit == 1 and width not in [10, 13]:
						return {}
				if offset + width > packet.size():
					return {}
				entry.append_array(packet.slice(offset, offset + width))
				offset += width
			else:
				entry.append_array(previous.slice(old_offset, old_offset + old_width))
			old_offset += old_width
		entries[key] = entry
	if offset != packet.size():
		return {}
	result["entries"] = entries
	result["players"] = {}
	result["aliens"] = {}
	result["owner"] = {}
	for key: Vector2i in entries:
		if not decode_entry(key, entries[key], result):
			return {}
	return result


static func decode_entry(key: Vector2i, entry: PackedByteArray, result: Dictionary) -> bool:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = entry
	if key.x == ALIEN:
		buffer.seek(2)
		var flags := buffer.get_u8()
		var data := {"id": key.y, "profile": buffer.get_u16(), "alive": flags & ALIVE != 0, "returning": flags & RETURNING != 0,
			"engaged": flags & ENGAGED != 0, "map": buffer.get_u8(), "encounter": buffer.get_u32()}
		get_public_pose(buffer, data)
		data["since_hit"] = buffer.get_u16() / HIT_TIME_SCALE
		data["respawn"] = buffer.get_float()
		result["aliens"][key.y] = data
	else:
		buffer.seek(4)
		var flags := buffer.get_u8()
		if (flags & OWNER != 0) != (key.x == OWNER_PLAYER) or result["players"].has(key.y):
			return false
		var data := {"profile": buffer.get_u16(), "life": buffer.get_u32(), "map": buffer.get_u8(), "visit": buffer.get_u32(),
			"alive": flags & ALIVE != 0, "docked": flags & DOCKED != 0, "repairing": flags & REPAIRING != 0}
		if key.x == PUBLIC_PLAYER:
			get_public_pose(buffer, data)
			data["energy"] = buffer.get_u16() / ENERGY_SCALE
			data["since_hit"] = buffer.get_u16() / HIT_TIME_SCALE
			data["radiation"] = buffer.get_float()
		else:
			if not result["owner"].is_empty():
				return false
			data["position"] = get_vector(buffer)
			data["rotation"] = get_vector(buffer)
			data["hull"] = buffer.get_double()
			data["shield"] = buffer.get_double()
			data["energy"] = buffer.get_float()
			data["since_hit"] = buffer.get_float()
			data["radiation"] = buffer.get_float()
			data["velocity"] = get_vector(buffer)
			data["ack"] = buffer.get_u32()
			data["input_depth"] = buffer.get_u8()
			data["turn_budget"] = buffer.get_float()
			var inputs := {}
			for counter: String in INPUT_COUNTERS:
				inputs[counter] = buffer.get_u32()
			data["inputs"] = inputs
			data["credits"] = buffer.get_u32()
			data["kills"] = buffer.get_u32()
			data["stage"] = buffer.get_u8()
			data["respawn"] = buffer.get_float()
			var traffic := {"bytes_per_second": buffer.get_u32(), "bytes_per_tick": buffer.get_u16(),
				"delta_permille": buffer.get_u16(), "full_fallbacks": buffer.get_u32()}
			var owner := {"rounds": PackedInt32Array(), "rockets": {}, "traffic": traffic}
			var length := buffer.get_u8()
			if length < 2 or buffer.get_available_bytes() != length:
				return false
			var rounds := buffer.get_u8()
			if buffer.get_available_bytes() < rounds * 4 + 1:
				return false
			for count in rounds:
				owner["rounds"].append(buffer.get_32())
			if buffer.get_u8() == 1:
				if buffer.get_available_bytes() < 19:
					return false
				var single := buffer.get_u8()
				var launcher := buffer.get_u8()
				if single >= Ammunition.ROCKETS.size() or launcher >= Ammunition.ROCKETS.size():
					return false
				owner["rockets"] = {"single_type": Ammunition.ROCKETS.keys()[single],
					"launcher_type": Ammunition.ROCKETS.keys()[launcher],
					"single_cooldown": buffer.get_float(), "launcher_cooldown": buffer.get_float(),
					"capacity": buffer.get_u16(), "loaded": buffer.get_u16(),
					"loading": buffer.get_u8() == 1, "load_clock": buffer.get_float()}
			if flags & BOOSTS:
				if buffer.get_available_bytes() < 5:
					return false
				owner["revision"] = buffer.get_u32()
				var boosts := {}
				var boost_count := buffer.get_u8()
				if buffer.get_available_bytes() != boost_count * 10:
					return false
				for count in boost_count:
					var group_id := buffer.get_u8()
					var resource_id := buffer.get_u8()
					if group_id >= ResourceBoosts.GROUPS.size() or resource_id >= ResourceBoosts.BONUSES.size():
						return false
					var group: String = ResourceBoosts.GROUPS.keys()[group_id]
					var resource: String = ResourceBoosts.BONUSES.keys()[resource_id]
					var remaining := buffer.get_double()
					boosts[group] = {"resource": resource, "remaining": int(remaining) if group in ["lasers", "rockets"] else remaining}
				owner["boosts"] = boosts
			result["owner"] = owner
		result["players"][key.y] = data
	return buffer.get_available_bytes() == 0


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
