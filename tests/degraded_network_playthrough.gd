extends "res://tests/network_test.gd"
## Three authenticated clients fly over independent lossy links and then hunt
## a Scout together. The third pilot sees the fight but does not contribute.

const PORT := 24941
const SEEDS := [5, 11, 29]
const SCOUT := 1
const SHOOTERS := 2
const FLIGHT_TICKS := 1200
const FLIGHT_BPS_LIMIT := 8000
const COMBAT_BPS_LIMIT := 9000
const SIM_P95_LIMIT := 0.25
const SIM_MAX_LIMIT := 3.0
const OFFSET_LIMIT := 4.0
const PATH_P95_LIMIT := 0.5
const PATH_MAX_LIMIT := 3.0
const EXTRAPOLATED_LIMIT := 0.15
const PUBLIC_HEALTH_TOLERANCE := 0.125
const ACTIONS := ["forward", "backward", "strafe_left", "strafe_right", "boost"]
# End tick, controls, yaw radians/second. Mirrored turns keep the formation
# near its starting course while changing both thrust and facing.
const PATTERN := [
	[36, ["forward"], 0.0], [66, ["forward", "boost"], 0.0], [90, ["strafe_right"], 0.0],
	[120, ["forward", "strafe_left"], 1.2],
	[156, ["backward"], 0.0], [186, ["backward", "boost"], 0.0], [210, ["strafe_left"], 0.0],
	[240, ["backward", "strafe_right"], -1.2],
]

var server: Sector
var clients: Array[Sector] = []
var peer_ids: Array[int] = []
var relays: Array[MeasuredRelay] = []
var scout: Alien


# The relay receives uncompressed ENet datagrams before simulated loss. Count
# reliable send commands (including retransmits and fragments) separately from
# the full UDP payload. The shared datagram header is counted only in the total.
# Layout: Godot 4.7.2 thirdparty/enet/enet/protocol.h.
class MeasuredRelay extends NetSimulator:
	const COMMAND_SIZES := [0, 8, 48, 44, 8, 4, 6, 8, 24, 8, 8, 16, 24]
	const SENT_TIME := 0x80
	const COMPRESSED := 0x40
	const SEND_RELIABLE := 6
	const SEND_UNRELIABLE := 7
	const SEND_FRAGMENT := 8
	const SEND_UNSEQUENCED := 9
	const SEND_UNRELIABLE_FRAGMENT := 12

	var traffic_lock := Mutex.new()
	var traffic := Vector3i.ZERO # Datagram bytes, reliable command bytes, parse errors.

	func totals() -> Vector3i:
		traffic_lock.lock()
		var result := traffic
		traffic_lock.unlock()
		return result

	func _schedule(direction: int, now: int, packet: PackedByteArray) -> void:
		if direction == DOWN:
			var reliable := reliable_bytes(packet)
			traffic_lock.lock()
			traffic += Vector3i(packet.size(), maxi(0, reliable), int(reliable < 0))
			traffic_lock.unlock()
		super._schedule(direction, now, packet)

	static func reliable_bytes(packet: PackedByteArray) -> int:
		if packet.size() < 2 or packet[0] & COMPRESSED:
			return -1
		var cursor := 4 if packet[0] & SENT_TIME else 2
		var total := 0
		while cursor < packet.size():
			var command := packet[cursor] & 0x0f
			if command == 0 or command >= COMMAND_SIZES.size():
				return -1
			var header: int = COMMAND_SIZES[command]
			if cursor + header > packet.size():
				return -1
			var size := header
			if command in [SEND_RELIABLE, SEND_UNRELIABLE, SEND_FRAGMENT, SEND_UNSEQUENCED, SEND_UNRELIABLE_FRAGMENT]:
				var length_at := cursor + 4 if command == SEND_RELIABLE else cursor + 6
				size += (packet[length_at] << 8) | packet[length_at + 1]
			if command == SEND_RELIABLE or command == SEND_FRAGMENT:
				total += size
			cursor += size
		return total if cursor == packet.size() else -1


func run() -> void:
	var started := Time.get_ticks_msec()
	if not await admit_pilots():
		finish()
		return
	var summary := await measure_flight()
	summary["combat"] = await play_combat()
	summary["runtime_s"] = (Time.get_ticks_msec() - started) / 1000.0
	for index in clients.size():
		var counters: Dictionary = server.session.input_buffers[peer_ids[index]].counters()
		summary["pilots"][index]["inputs"] = counters
		check(counters["lost"] == 0, "Pilot %d loses no inputs (%s)" % [index, counters])
	print("DEGRADED_NETWORK " + JSON.stringify(summary))
	finish()


func admit_pilots() -> bool:
	server = make_sector("DegradedServer", true, PORT)
	for id: int in server.aliens:
		# Keep the normal M1 population in snapshots while its patrols stay away
		# from the flight course. Move just one Scout into range for combat.
		place_alien(server.aliens[id], Vector3((id - 2) * 125.0, -500.0, -200.0))
	scout = server.aliens[SCOUT]
	for index in SEEDS.size():
		var client := make_sector("DegradedPilot%d" % index)
		clients.append(client)
		var relay := MeasuredRelay.new()
		relays.append(relay)
		relay.set_seed(SEEDS[index])
		relay.set_round_trip(150.0, 30.0, 5.0)
		client.session.net_simulator = relay
		client.session.use_net_simulator = true
		client.session.credential_id = "pilot%d" % index
		client.session.credential_token = test_token(index)
		client.set_physics_process(true)
	server.set_physics_process(true)
	if not check_until(await wait_for(func() -> bool: return server.session.active), "Dedicated server opens its ENet port"):
		return false
	# Establish one roster entry at a time. The next pilot joins after the
	# previous one has authenticated and received its first playable state.
	for index in clients.size():
		var client := clients[index]
		if not check_until(client.session.join("127.0.0.1", test_port(PORT)) == OK, "Pilot %d starts joining through its relay" % index):
			return false
		var joined := await wait_for(func() -> bool:
			return client.session.received_snapshot and not client.session.combat.inventory.is_empty(), 10000)
		if not check_until(joined, "Pilot %d receives its initial snapshot and inventory (%s)" % [index, client.session.status]):
			return false
		var id := client.multiplayer.get_unique_id()
		peer_ids.append(id)
		check(server.session.pilot_ids.get(id) == "pilot%d" % index, "Server admits the expected pilot identity")
	if not check_until(await wait_for(roster_ready), "Each authenticated client receives the full roster and flight state"):
		return false
	for client: Sector in clients:
		client.session.combat.request_contract("accept", "scout")
	if not check_until(await wait_for(func() -> bool: return contracts_at_start()), "Every pilot accepts the same Scout hunt at Outpost 01"):
		return false

	var observer := clients[-1]
	var life := int(observer.player.get_meta("life", 0))
	var run_id: String = observer.active_contracts["scout"]["run"]
	var baseline := progress_state(observer, peer_ids[-1])
	observer.session.combat.contract_request.rpc_id(1, life + 1, "abandon", "scout", run_id)
	# The valid request follows on the same reliable channel, so its response
	# establishes that the server processed the wrong-life request first.
	observer.session.combat.request_contract("accept", "sentinel")
	if not check_until(await wait_for(func() -> bool: return observer.active_contracts.has("sentinel")), "The valid follow-up contract request reaches the server"):
		return false
	check(progress_state(observer, peer_ids[-1]) == baseline, "Wrong-life contract request leaves the Scout hunt, wallet and health untouched")

	Input.action_press("move_up")
	var climbed := await wait_for(func() -> bool:
		for id: int in peer_ids:
			if server.session.ships[id].position.y < 240.0:
				return false
		return true)
	Input.action_release("move_up")
	return check_until(climbed and await wait_for(stopped), "Pilots fly clear of station protection and brake before measurement")


func roster_ready() -> bool:
	if server.session.pilot_ids.size() != clients.size():
		return false
	for client: Sector in clients:
		if client.session.ships.size() != clients.size() or client.session.remote_buffers.size() != clients.size() - 1:
			return false
	return true


func contracts_at_start() -> bool:
	for index in clients.size():
		if contract_progress(clients[index].active_contracts) != 0 or contract_progress(server.session.combat.records[peer_ids[index]]["contracts"]) != 0:
			return false
	return true


func progress_state(client: Sector, id: int) -> Array:
	var record: Dictionary = server.session.combat.records[id]
	var ship := server.session.ships[id]
	return [client.active_contracts.get("scout", {}).duplicate(), record["contracts"].get("scout", {}).duplicate(),
		client.credits, record["credits"], client.kills, record["kills"], client.player.hull, client.player.shield, ship.hull, ship.shield]


func measure_flight() -> Dictionary:
	var observer := clients[-1]
	var mover_id := peer_ids[0]
	var buffer := observer.session.remote_buffers[mover_id]
	var path: Dictionary[int, Vector3] = {}
	var errors := PackedFloat32Array()
	var extrapolated := 0
	var start := traffic_totals()
	var start_usec := Time.get_ticks_usec()
	var start_tick := server.session.server_tick
	var start_frame := Engine.get_process_frames()
	var deadline := Time.get_ticks_msec() + 26000
	var mover := server.session.ships[mover_id]
	var distance := 0.0
	var previous := mover.position
	for client: Sector in clients:
		client.session.net_stats.reset_extremes()
		client.session.net_stats.keep_samples = true
	var last_actions: Array = []
	var last_tick := start_tick - 1
	while server.session.server_tick < start_tick + FLIGHT_TICKS and Time.get_ticks_msec() < deadline:
		var tick := server.session.server_tick
		if tick != last_tick:
			last_tick = tick
			var phase := (tick - start_tick) % int(PATTERN[-1][0])
			for segment: Array in PATTERN:
				if phase < segment[0]:
					if last_actions != segment[1]:
						set_actions(segment[1])
						last_actions = segment[1]
					for client: Sector in clients:
						client.player.pending_look.x += float(segment[2]) / Engine.physics_ticks_per_second
					break
			path[tick] = mover.position
			distance += mover.position.distance_to(previous)
			previous = mover.position
			var render := observer.session.clock.render_tick()
			var low := floori(render)
			if path.has(low) and path.has(low + 1) and observer.session.ships.has(mover_id):
				var truth := path[low].lerp(path[low + 1], render - low)
				errors.append(observer.session.ships[mover_id].position.distance_to(truth))
				if buffer.mode in [SnapshotBuffer.Mode.EXTRAPOLATED, SnapshotBuffer.Mode.HELD]:
					extrapolated += 1
		await physics_frame
	set_actions([])
	var seconds := (Time.get_ticks_usec() - start_usec) / 1000000.0
	var rates := traffic_rates(start, seconds)
	var smoothness := {"samples": errors.size(), "distance_flown_m": distance, "path_p95_m": NetStats.percentile(errors, 0.95),
		"path_max_m": NetStats.percentile(errors, 1.0), "extrapolated_share": float(extrapolated) / maxi(1, errors.size())}
	check(server.session.server_tick >= start_tick + FLIGHT_TICKS, "Flight completes 1200 physics ticks inside its deadline")
	check(distance >= 300.0, "The observed pilot flies the scripted course")
	check(errors.size() >= FLIGHT_TICKS * 0.9, "The observer has an authoritative path comparison for most physics ticks")
	check(smoothness["path_p95_m"] <= PATH_P95_LIMIT and smoothness["path_max_m"] <= PATH_MAX_LIMIT, "The drawn pilot follows the server path at render time")
	check(smoothness["extrapolated_share"] <= EXTRAPOLATED_LIMIT, "The observer rarely draws past the newest snapshot")

	var pilots: Array[Dictionary] = []
	for index in clients.size():
		var net := clients[index].session.net_stats
		net.keep_samples = false
		var rates_for_pilot := rates[index]
		var loss := relays[index].stats()
		var sample := {"seed": SEEDS[index], "reconciliations": net.corrections, "sim_p95_m": NetStats.percentile(net.error_samples, 0.95),
			"sim_max_m": net.max_error_m, "offset_max_m": net.max_offset_m, "traffic": rates_for_pilot,
			"up_dropped_datagrams": loss["up"]["dropped_packets"], "down_dropped_datagrams": loss["down"]["dropped_packets"],
			"snapshot_jitter_p95_ms": NetStats.percentile(net.jitter_samples, 0.95)}
		pilots.append(sample)
		check(loss["up"]["dropped_packets"] > 0 and loss["down"]["dropped_packets"] > 0, "Pilot %d sees real datagram loss in both directions" % index)
		check(net.corrections >= 250, "Pilot %d reconciles throughout the flight" % index)
		check(sample["sim_p95_m"] <= SIM_P95_LIMIT and net.max_error_m <= SIM_MAX_LIMIT, "Pilot %d stays within simulation correction limits" % index)
		check(net.max_offset_m <= OFFSET_LIMIT, "Pilot %d stays within the visual offset limit" % index)
		check(rates_for_pilot["enet_Bps"] <= FLIGHT_BPS_LIMIT and rates_for_pilot["parse_errors"] == 0, "Pilot %d stays within the steady-flight bandwidth budget" % index)
	return {"flight_s": seconds, "flight_fps": (Engine.get_process_frames() - start_frame) / seconds,
		"pilots": pilots, "observer": smoothness}


func play_combat() -> Dictionary:
	if not check_until(await wait_for(stopped), "Pilot formation brakes for the encounter"):
		return {}
	var first := server.session.ships[peer_ids[0]]
	var second := server.session.ships[peer_ids[1]]
	place_alien(scout, (first.position + second.position) * 0.5 + Vector3(0, 0, -90))
	scout.reset_encounter()
	var health_before: Array[Vector2] = []
	for id: int in peer_ids:
		var ship := server.session.ships[id]
		health_before.append(Vector2(ship.hull, ship.shield))
	var start := traffic_totals()
	var start_usec := Time.get_ticks_usec()
	var ready := await wait_for(func() -> bool:
		for client: Sector in clients:
			var enemy: Alien = client.aliens[SCOUT]
			if not enemy.available() or enemy.life != scout.life:
				return false
		return true)
	if not check_until(ready, "The new Scout encounter reaches all clients"):
		return {}
	for index in SHOOTERS:
		clients[index].select_target(clients[index].aliens[SCOUT])
		clients[index].auto_fire = true
	var deadline := Time.get_ticks_msec() + 14000
	while scout.alive and Time.get_ticks_msec() < deadline:
		for index in SHOOTERS:
			var client := clients[index]
			var ship := client.player
			var direction := client.aliens[SCOUT].position - ship.position
			var aim := Basis.looking_at(direction).get_euler()
			ship.pending_look = Vector2(angle_difference(ship.rotation.y, aim.y), aim.x - ship.rotation.x)
		await physics_frame
	for client: Sector in clients:
		client.auto_fire = false
	check(not scout.alive and scout.hull == 0.0 and scout.shield == 0.0, "The authoritative Scout dies to the pilots' fire")
	var pool: int = scout.tuning()["reward"]
	var reward := pool / SHOOTERS
	check(reward * SHOOTERS == pool, "The Scout bounty divides evenly between the two shooters")
	var replicated := false
	if not scout.alive:
		replicated = await wait_for_outcomes(reward)
		check(replicated, "Every client sees the authoritative death and hull/shield state; only contributors receive a split, kill and contract progress")
	var seconds := (Time.get_ticks_usec() - start_usec) / 1000000.0
	var traffic := traffic_rates(start, seconds)
	var outcomes: Array[Dictionary] = []
	var took_hull_and_shield_damage := false
	for index in clients.size():
		var id := peer_ids[index]
		var record: Dictionary = server.session.combat.records[id]
		var ship := server.session.ships[id]
		var stored: Dictionary = server.session.store.pilots[server.session.pilot_ids[id]]
		took_hull_and_shield_damage = took_hull_and_shield_damage or (ship.hull < health_before[index].x and ship.shield < health_before[index].y)
		check(stored["credits"] == record["credits"] and stored["contracts"] == record["contracts"], "Pilot %d authoritative reward and contract progress are persisted" % index)
		check(traffic[index]["enet_Bps"] <= COMBAT_BPS_LIMIT and traffic[index]["parse_errors"] == 0, "Pilot %d stays within the combined combat bandwidth budget" % index)
		check(traffic[index]["reliable_bytes"] > 0, "Pilot %d receives reliable traffic during combat" % index)
		var client := clients[index]
		outcomes.append({"credits": record["credits"], "kills": record["kills"], "contract": contract_progress(record["contracts"]),
			"hull": ship.hull, "shield": ship.shield, "traffic": traffic[index],
			"displayed_credits": client.credits, "displayed_kills": client.kills, "displayed_contract": contract_progress(client.active_contracts),
			"displayed_hull": client.player.hull, "displayed_shield": client.player.shield, "displayed_scout_alive": client.aliens[SCOUT].alive,
			"loot_received": client.loot.drops.has(server.loot.next_id), "toast": client.toast})
	check(took_hull_and_shield_damage, "Scout retaliation exercises both hull and shield updates")
	return {"seconds": seconds, "scout_alive": scout.alive, "replicated": replicated, "pilots": outcomes}


func wait_for_outcomes(reward: int) -> bool:
	var last_sequence := server.session.snapshot_sequence
	var health_frames: Dictionary[int, Dictionary] = {}
	var reward_notices: Array[bool] = [false, false]
	var expected_notice := "Alien destroyed. Your share: +%d credits." % reward
	return await wait_for(func() -> bool:
		var sequence := server.session.snapshot_sequence
		# After the kill, shield regeneration can make the authority's current
		# health differ from what it sent. Capture at the snapshot tick and
		# compare each replica against the authoritative values at its sequence.
		if sequence > last_sequence and not health_frames.has(sequence):
			var health: Dictionary[int, Dictionary] = {}
			for id: int in peer_ids:
				health[id] = server.session.combat.health(server.session.ships[id])
			health_frames[sequence] = health
		for index in SHOOTERS:
			reward_notices[index] = reward_notices[index] or clients[index].toast == expected_notice
		return outcomes_replicated(reward, health_frames, reward_notices), 5000)


func outcomes_replicated(reward: int, health_frames: Dictionary[int, Dictionary], reward_notices: Array[bool]) -> bool:
	var loot_id := server.loot.next_id
	if not server.loot.drops.has(loot_id):
		return false
	for index in clients.size():
		var client := clients[index]
		if not client.loot.drops.has(loot_id):
			return false
		var record: Dictionary = server.session.combat.records[peer_ids[index]]
		var contributor := index < SHOOTERS
		var credits := reward if contributor else 0
		var kills := int(contributor)
		if record["credits"] != credits or client.credits != credits or record["kills"] != kills or client.kills != kills:
			return false
		if contract_progress(record["contracts"]) != kills or contract_progress(client.active_contracts) != kills:
			return false
		if contributor and not reward_notices[index]:
			return false
		if not health_matches(client.aliens[SCOUT], server.session.combat.health(scout), PUBLIC_HEALTH_TOLERANCE):
			return false
		for id: int in peer_ids:
			var replica: Pilot = client.session.ships.get(id)
			var tolerance := 0.0 if id == peer_ids[index] else PUBLIC_HEALTH_TOLERANCE
			var sequence: int = client.session.player_sequences.get(id, -1)
			if replica == null or not health_frames.has(sequence) or not health_matches(replica, health_frames[sequence][id], tolerance):
				return false
	return true


func traffic_totals() -> Array[Vector3i]:
	var totals: Array[Vector3i] = []
	for relay: MeasuredRelay in relays:
		totals.append(relay.totals())
	return totals


func traffic_rates(baseline: Array[Vector3i], seconds: float) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for index in relays.size():
		var delta := relays[index].totals() - baseline[index]
		results.append({"enet_Bps": roundi(delta.x / seconds), "reliable_Bps": roundi(delta.y / seconds),
			"reliable_bytes": delta.y, "parse_errors": delta.z})
	return results


func stopped() -> bool:
	for id: int in peer_ids:
		if server.session.ships[id].velocity.length() > 1.0:
			return false
	return true


func wait_for(condition: Callable, timeout_ms: int = 7000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await physics_frame
	return condition.call()


func check_until(condition: bool, description: String) -> bool:
	check(condition, description)
	return condition


static func contract_progress(contracts: Dictionary) -> int:
	return contracts.get("scout", {}).get("progress", -1)


static func health_matches(replica: SpaceShip, authority: Dictionary, tolerance: float) -> bool:
	return replica.alive == authority["alive"] and absf(replica.hull - authority["hull"]) <= tolerance and absf(replica.shield - authority["shield"]) <= tolerance


static func place_alien(alien: Alien, location: Vector3) -> void:
	alien.position = location
	alien.home_position = location
	alien.velocity = Vector3.ZERO


static func set_actions(active: Array) -> void:
	for action: String in ACTIONS:
		if action in active:
			Input.action_press(action)
		else:
			Input.action_release(action)
