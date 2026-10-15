extends "res://tests/connected_maps_test.gd"
## Compact world snapshots: payload round trips, size and reliable profile redelivery.


func same(a: Variant, b: Variant) -> bool:
	# Wire floats are 32-bit; everything else must survive exactly.
	if a is float or b is float:
		return (a is float or a is int) and (b is float or b is int) and absf(a - b) <= maxf(0.001, absf(b) * 1e-6)
	if a is Vector3 or a is Vector4:
		return typeof(a) == typeof(b) and a.is_equal_approx(b)
	if a is PackedFloat32Array or a is Array:
		return a.size() == b.size() and range(a.size()).all(func(index: int) -> bool: return same(a[index], b[index]))
	if a is Dictionary:
		return b is Dictionary and a.size() == b.size() and a.keys().all(func(key: Variant) -> bool: return b.has(key) and same(a[key], b[key]))
	return typeof(a) == typeof(b) and a == b


func round_trip_player(id: int, data: Dictionary, extras: Dictionary = {}) -> Dictionary:
	var packet := SnapshotCodec.world(7, 3, [SnapshotCodec.player_entry(id, data, extras)], [])
	var world := SnapshotCodec.decode_world(packet)
	check(world.get("sequence") == 7 and world.get("visit") == 3 and world["players"].has(id), "World header and player ID decode")
	return world


func legacy_bytes(server: Sector, viewer: int) -> int:
	# The pre-batching wire payload for one viewer: one RPC per entity, plus ammunition and boosts.
	var session := server.session
	var bytes := var_to_bytes([{viewer: session.player_state(viewer, true)}, {}, 1, 0]).size()
	for id: int in session.ships:
		if id != viewer:
			bytes += var_to_bytes([{id: session.player_state(id, false)}, {}, 1, 0]).size()
	for enemy: Alien in server.map_rosters[0].values():
		bytes += var_to_bytes([{}, session.combat.pack_alien(enemy), 1, 0]).size()
	bytes += var_to_bytes([session.combat.ammo_rounds(viewer), 1, session.ships[viewer].rockets.state(), 0]).size()
	return bytes + var_to_bytes([session.ships[viewer].resource_boosts, 1, 1]).size()


func run() -> void:
	var server := make_sector("CodecServer", true)
	var first := make_sector("CodecFirst")
	var second := make_sector("CodecSecond")
	var late := make_sector("CodecLate")
	var clients: Array[Sector] = [first, second, late]
	for index in range(2):
		clients[index].client_only = true
		clients[index].session.credential_id = "pilot%d" % index
		clients[index].session.credential_token = test_token(index)
		clients[index].session.join("127.0.0.1", test_port(24683))
	await settle(0.6)
	check(server.session.ships.size() == 2, "Two authenticated pilots connect")
	if server.session.ships.size() != 2:
		await finish()
		return
	await replicate(server)
	for client in [first, second]:
		client.session.launch()
	await settle()
	await replicate(server)
	var session := server.session
	var combat := session.combat
	var id := first.multiplayer.get_unique_id()
	var other := second.multiplayer.get_unique_id()
	var ship := session.ships[id]

	# Public player state survives the binary entry and the reliable profile.
	session.ships[other].position = Vector3(12.5, -40.25, 1999.75)
	session.ships[other].rotation = Vector3(0.3, -2.1, 0.0)
	session.ships[other].radiation_exposure = 4.5
	session.ships[other].robot_repairing = true
	session.ships[other].hull -= 33.3
	var public := session.player_state(other, false)
	var world := round_trip_player(other, public)
	var decoded := SnapshotCodec.player_state(world["players"][other], SnapshotCodec.player_profile(public))
	public.erase("velocity") # Only owners use their velocity; viewers interpolate positions.
	check(same(decoded, public), "Public player state packs and unpacks")
	check(world["owner"].is_empty() and SessionCombat.PRIVATE_FIELDS.all(func(field: String) -> bool: return not decoded.has(field)), "Public entries carry no private progress")
	check(SnapshotCodec.player_profile(public).size() == 4, "Public profiles omit contracts")

	# Owner state adds velocity, progress, contracts, ammunition, rockets and boosts.
	combat.records[id].merge({"credits": 1_999_999_999, "kills": 12, "stage": 4, "respawn": 1.5, "contracts": {"scout": HuntingContracts.accept("scout"), "heavy": HuntingContracts.accept("heavy"), "sentinel": HuntingContracts.accept("sentinel")}}, true)
	ship.velocity = Vector3(1, 2, 3)
	ship.ammo["x2"] = 123456
	ship.ammo_type = "x2"
	ship.rockets.launcher_type = "hstrm-01"
	ship.rockets.loading = true
	ship.rockets.loaded = 3
	ship.rockets.load_clock = 0.4
	ship.resource_boosts = {"lasers": {"resource": "seprom", "remaining": 1_500_000_001}, "shields": {"resource": "promerium", "remaining": 512.25}}
	var owner := session.player_state(id, true)
	var extras := session.owner_extras(id)
	world = round_trip_player(id, owner, extras)
	decoded = SnapshotCodec.player_state(world["players"][id], SnapshotCodec.player_profile(owner))
	check(same(decoded, owner), "Owner player state packs and unpacks with private progress and contracts")
	var unpacked: Dictionary = world["owner"]
	check(unpacked.get("rounds") == extras["rounds"], "Owner ammunition counts and selection unpack exactly")
	check(same(unpacked.get("rockets"), extras["rockets"]), "Owner rocket launcher state unpacks")
	check(same(unpacked.get("boosts"), extras["boosts"]) and unpacked["boosts"]["lasers"]["remaining"] is int and unpacked["boosts"]["lasers"]["remaining"] == 1_500_000_001, "Owner boosts unpack, with exact integer laser reserves")
	check(unpacked.get("revision") == extras["revision"], "Owner boost revision unpacks")
	check(ResourceBoosts.valid({"starter": unpacked["boosts"]}, {"ships": {"starter": {}}}), "Unpacked boosts remain valid boost data")

	# Aliens.
	var enemy: Alien = server.map_rosters[0].values()[4]
	enemy.returning = true
	enemy.engaged = true
	enemy.respawn = 2.5
	var alien := combat.pack_alien(enemy)
	var alien_packet := SnapshotCodec.world(9, 0, [], [SnapshotCodec.alien_entry(alien)])
	world = SnapshotCodec.decode_world(alien_packet)
	check(same(SnapshotCodec.alien_state(world["aliens"][enemy.alien_id], SnapshotCodec.alien_profile(alien)), alien), "Alien state packs and unpacks")
	check(SnapshotCodec.decode_world(alien_packet.slice(0, 8)).is_empty() and SnapshotCodec.decode_world(alien_packet + PackedByteArray([0])).is_empty(), "Short or oversized packets are rejected")

	# Ten pilots and five aliens fit one datagram and shrink at least fivefold.
	var players: Array[PackedByteArray] = [SnapshotCodec.player_entry(id, owner, extras)]
	for index in range(9):
		players.append(SnapshotCodec.player_entry(other, session.player_state(other, false)))
	var aliens: Array[PackedByteArray] = []
	for each: Alien in server.map_rosters[0].values():
		aliens.append(SnapshotCodec.alien_entry(combat.pack_alien(each)))
	var batch := var_to_bytes(SnapshotCodec.world(1, 0, players, aliens)).size()
	var legacy := legacy_bytes(server, id) + 8 * var_to_bytes([{other: session.player_state(other, false)}, {}, 1, 0]).size()
	print("SNAPSHOT_PAYLOAD=", JSON.stringify({"legacy_bytes": legacy, "batched_bytes": batch, "ratio": snappedf(float(legacy) / batch, 0.01)}))
	check(batch < 1200, "Ten pilots and five aliens fit below the ENet datagram budget")
	check(legacy >= batch * 5, "Batched payload is at least five times smaller")
	combat.records[id].merge({"respawn": 0.0}, true)
	ship.resource_boosts = {}

	# Joining clients receive every visible profile reliably.
	await replicate(server)
	check(first.session.player_profiles.has(id) and first.session.player_profiles.has(other), "Pilots receive profiles for themselves and visible pilots")
	check(first.session.player_profiles[id].size() == 5 and first.session.player_profiles[other].size() == 4, "Only the owner's profile carries contracts")
	check(server.map_rosters[0].keys().all(func(alien_id: int) -> bool: return first.session.alien_profiles.get(alien_id, [""])[0] == server.world_aliens[alien_id].kind), "Pilots receive alien kinds for their map")
	check(first.active_contracts.size() == 3 and first.credits == 1_999_999_999, "Owner progress and contracts apply from the batch and profile")
	session.ships[other].laser_damage = 4321.0
	await replicate(server)
	check(first.session.ships[other].laser_damage == 4321.0, "Changed profiles are resent")
	late.client_only = true
	late.session.credential_id = "pilot2"
	late.session.credential_token = test_token(2)
	late.session.join("127.0.0.1", test_port(24683))
	await settle(0.6)
	await replicate(server)
	late.session.launch()
	await settle()
	await replicate(server)
	check(late.session.player_profiles.has(id) and late.session.player_profiles.has(other), "A late joiner receives profiles of pilots already flying")
	check(late.session.ships[other].laser_damage == 4321.0 and late.aliens.values().all(func(each: Alien) -> bool: return each.home_position == server.world_aliens[each.alien_id].home_position), "A late joiner applies current fitting stats and alien homes")

	# Arrival delivers the new map's alien profiles.
	await travel(server, first, 1)
	check(session.sent_profiles[id]["visit"] == ship.map_visit, "The server restarts profile tracking for the new visit")
	check(server.map_rosters[1].keys().all(func(alien_id: int) -> bool: return first.session.alien_profiles.get(alien_id, [""])[0] == server.world_aliens[alien_id].kind), "Arrival delivers alien profiles for the new map")
	await travel(server, first, 0)

	# A docked pilot vanishes for viewers; relaunching restores it from cached profiles.
	second.session.quit_to_menu()
	await settle(0.3)
	check(not first.session.ships.has(other), "Viewers remove a docked pilot")
	second.session.launch()
	await settle(0.3)
	await replicate(server)
	check(first.session.ships.has(other) and first.session.goals.has(other) and first.session.ships[other].visible, "A relaunched pilot replicates again")

	# Unchanged profiles are sent once per visit. A client missing one waits, and
	# the next visit to the map redelivers it.
	first.session.player_profiles.erase(other)
	var before: int = first.session.player_sequences.get(other, -1)
	for attempt in range(5):
		session.send_snapshot()
		await settle(0.05)
	check(not first.session.player_profiles.has(other) and first.session.player_sequences.get(other, -1) == before, "Unchanged profiles are not resent, and entities wait for their profile")
	for destination in [1, 0]:
		ship.position = SectorMaps.gate_position(ship.map_id, destination)
		session.jump_until.erase(id)
		check(session.jump(id, combat.records[id]["life"], destination).is_empty(), "Server transfers the pilot to M%d" % (destination + 1))
		await settle(0.2)
		await replicate(server)
	check(first.session.player_profiles.has(other) and first.session.player_sequences.get(other, -1) > before, "Returning to a map redelivers profiles and resumes state")
	check(first.session.ships[other].laser_damage == 4321.0, "Redelivered profiles apply to remote pilots")
	await finish()
