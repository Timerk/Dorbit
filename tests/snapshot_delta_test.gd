extends SceneTree
## Schema 26 wire bounds and baseline behavior without sockets or frame timing.

var failures := 0


func _initialize() -> void:
	test_quantization()
	test_baselines()
	test_mtu()
	quit(failures)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func player(map: int = 0) -> Dictionary:
	return {"map": map, "visit": 4, "life": 8, "alive": true, "docked": false,
		"position": SectorMaps.origin(map) + Vector3(715.123, -388.123, 901.987),
		"rotation": Vector3(-1.111111, PI - 0.00001, TAU - 0.00003),
		"hull": 999999.127, "shield": 43000.123, "energy": 81.23456, "since_hit": 3.1234,
		"systems": PackedFloat32Array([2.75, 0.0, 0.0])}


func test_quantization() -> void:
	var data := player(6)
	var entry := SnapshotCodec.player_entry(9, data, 12)
	var key := SnapshotCodec.player_key(entry)
	var packet := SnapshotCodec.encode_world(1, 4, 987654, {key: entry})[0]
	var world := SnapshotCodec.decode_world(packet)
	var state: Dictionary = world["players"][9]
	check(world["tick"] == 987654 and state["map"] == 6 and state["life"] == 8 and state["visit"] == 4,
		"Exact tick, life, map and visit survive quantization")
	var input_position: Vector3 = data["position"]
	var input_rotation: Vector3 = data["rotation"]
	for axis in 3:
		check(absf(state["position"][axis] - input_position[axis]) <= 1.0 / 512.0, "Position error is at most half a quantum")
		check(absf(angle_difference(state["rotation"][axis], input_rotation[axis])) <= TAU / 131072.0, "Wrapped angle error is at most half a quantum")
	check(absf(state["hull"] - data["hull"]) <= 0.125 and absf(state["shield"] - data["shield"]) <= 0.125, "Health error is at most one eighth of a point")
	check(absf(state["energy"] - data["energy"]) <= 1.0 / 512.0, "Energy error is at most half a quantum")
	check(absf(state["since_hit"] - data["since_hit"]) <= 0.005, "Public hit timer error is at most 5 ms")
	data["position"] = SectorMaps.origin(6) + Vector3(-35000.5, 53000.125, 900.25)
	data["since_hit"] = 100.0
	entry = SnapshotCodec.player_entry(9, data, 12)
	state = SnapshotCodec.decode_world(SnapshotCodec.encode_world(2, 4, 987657, {key: entry})[0])["players"][9]
	check(state["position"] == data["position"] and state["since_hit"] == 6.0, "Distant positions escape to float32 and public hit timers cap at six seconds")
	data.merge({"credits": 7, "kills": 1, "stage": 1, "respawn": 0.0, "velocity": Vector3(7.125, 1.25, -3.5)})
	entry = SnapshotCodec.player_entry(9, data, 12)
	state = SnapshotCodec.decode_world(SnapshotCodec.encode_world(3, 4, 987660, {SnapshotCodec.player_key(entry): entry})[0])["players"][9]
	check(state["position"] == data["position"] and state["rotation"] == data["rotation"] and state["velocity"] == data["velocity"]
		and state["energy"] == float(PackedFloat32Array([data["energy"]])[0]) and state["hull"] == data["hull"] and state["shield"] == data["shield"],
		"Owner reconciliation and health keep schema 25 precision")


func test_baselines() -> void:
	var sent := SnapshotHistory.new()
	var received := SnapshotHistory.new()
	sent.set_scope(4, 0)
	received.set_scope(4, 0)
	var data := player()
	var key := Vector2i(SnapshotCodec.PUBLIC_PLAYER, 9)
	var removed := Vector2i(SnapshotCodec.PUBLIC_PLAYER, 10)
	var first := {key: SnapshotCodec.player_entry(9, data, 7), removed: SnapshotCodec.player_entry(10, data, 7)}
	var full := SnapshotCodec.encode_world(10, 4, 30, first, sent.baseline_for(10))[0]
	check(full.decode_u32(12) == 0, "First packet is full when no acknowledgement exists")
	sent.remember_sent(10, first)
	sent.acknowledge(11)
	check(sent.acknowledged == 0, "The sender ignores acknowledgements for unsent packets")
	check(not receive(received, full).is_empty(), "Client stores a full baseline")
	sent.acknowledge(received.acknowledged)
	var second := {key: first[key]}
	var delta := SnapshotCodec.encode_world(11, 4, 33, second, sent.baseline_for(11))[0]
	check(delta.decode_u16(SnapshotCodec.HEADER_BYTES) == 0 and delta.size() == SnapshotCodec.HEADER_BYTES + 6,
		"Unchanged player uses a zero mask and only its ID")
	data["hull"] = 1000.0
	var third := {key: SnapshotCodec.player_entry(9, data, 7), Vector2i(SnapshotCodec.PUBLIC_PLAYER, 12): SnapshotCodec.player_entry(12, data, 7)}
	var later := SnapshotCodec.encode_world(12, 4, 36, third, sent.baseline_for(12))[0]
	check(later.decode_u16(SnapshotCodec.HEADER_BYTES) == 1 << 3, "Only the changed hull bit is transmitted")
	check(SnapshotCodec.decode_world(later).is_empty(), "Loss of the required baseline rejects a delta")
	var current := receive(received, later)
	check(current.get("entries") == third and current["players"][9]["hull"] == 1000.0, "Sending against one acknowledged base tolerates a lost intermediate packet")
	var older := receive(received, delta)
	check(older.get("entries") == second and older["tick"] == 33 and not older["players"].has(10),
		"Reordered deltas use their named base, retain the tick sample, and exclude absent entities")
	check(received.acknowledged == 12 and receive(received, delta).is_empty(), "An older or duplicated packet cannot regress the acknowledgement")
	check(not current["players"][9].has("velocity") and not current["players"][9].has("credits") and current["owner"].is_empty(),
		"Viewer deltas carry no owner's private state")
	data["life"] += 1
	var respawn := {key: SnapshotCodec.player_entry(9, data, 7)}
	var lifecycle := SnapshotCodec.encode_world(13, 4, 39, respawn, sent.baseline_for(13))[0]
	check(lifecycle.decode_u16(SnapshotCodec.HEADER_BYTES) == 255, "A new life sends a full entity record")
	var expired := SnapshotCodec.encode_world(42, 4, 126, respawn, sent.baseline_for(42))[0]
	check(expired.decode_u32(12) == 0, "An expired acknowledgement falls back to full")
	check(not receive(received, expired).is_empty() and received.find(10).is_empty() and receive(received, later).is_empty(),
		"An overwritten ring slot cannot substitute for an old sequence")
	sent.set_scope(5, 1)
	received.set_scope(5, 1)
	sent.acknowledge(10)
	check(sent.baseline_for(43).is_empty() and received.acknowledged == 0 and receive(received, expired).is_empty(),
		"Changing map visits clears baselines and rejects in-flight packets from the old visit")
	sent.remember_sent(43, first)
	sent.acknowledge(43)
	sent.set_scope(5, 0)
	check(sent.baseline_for(44).is_empty(), "Changing map resets scope even with a matching visit value")


func test_mtu() -> void:
	var data := player(6)
	var own := data.duplicate()
	own.merge({"credits": 7, "kills": 1, "stage": 1, "respawn": 0.0, "velocity": Vector3.ZERO})
	var owner := SnapshotCodec.player_entry(10, own, 12)
	var entries := {SnapshotCodec.player_key(owner): owner}
	for id in range(1, 10):
		var entry := SnapshotCodec.player_entry(id, data, 12)
		entries[SnapshotCodec.player_key(entry)] = entry
	var alien := data.duplicate()
	alien.merge({"encounter": 1, "returning": false, "engaged": true, "respawn": 0.0})
	for id in range(1, 21):
		alien["id"] = id
		var entry := SnapshotCodec.alien_entry(alien, 8)
		entries[SnapshotCodec.alien_key(entry)] = entry
	var packets := SnapshotCodec.encode_world(20, 4, 60, entries)
	check(packets.size() > 1 and packets.all(func(packet: PackedByteArray) -> bool: return packet.size() <= SnapshotCodec.MAX_PACKET_BYTES),
		"Ten pilots and the largest arena roster split below the MTU guard")
	var received := SnapshotHistory.new()
	received.set_scope(4, 6)
	var partial := receive(received, packets[-1])
	check(not partial.is_empty() and partial["owner"].is_empty() and received.acknowledged == 0,
		"A reordered part applies without the owner or acknowledgement of the incomplete tick")
	var baseline := {"sequence": 20, "visit": 4, "entries": entries}
	var delta := SnapshotCodec.encode_world(21, 4, 63, entries, baseline)[0]
	check(receive(received, delta).is_empty(), "A partially received tick cannot serve as a baseline")
	for index in range(packets.size() - 1):
		check(not receive(received, packets[index]).is_empty(), "Remaining parts decode independently")
	check(received.acknowledged == 20 and received.find(20)["entries"] == entries, "All parts together restore the full roster")
	check(receive(received, delta).get("entries") == entries and received.acknowledged == 21, "Delta against the completed multipart baseline restores every entity")


func receive(history: SnapshotHistory, packet: PackedByteArray) -> Dictionary:
	return history.receive(packet, SnapshotCodec.header(packet))
