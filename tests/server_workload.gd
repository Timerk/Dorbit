extends "res://tests/network_test.gd"
## Separate-process workload using the same worlds and ENet setup as the server tests.

var sector: Sector
var options: Dictionary[String, String] = {}
var measuring := false
var started := 0
var started_unix := 0.0
var previous_tick := 0
var tick_us: Array[float] = []
var combat_tick_us: Array[float] = []
var interval_us: Array[float] = []
var physics_ms: Array[float] = []
var distances: Dictionary[int, float] = {}
var positions: Dictionary[int, Vector3] = {}
var hits: Dictionary[int, int] = {}
var alien_shots := 0
var deaths := 0
var alive_ticks := 0
var minimum_roster := 10
var command_clock := 0.0
var hits_by_alien: Dictionary[int, int] = {}
var deaths_by_alien: Dictionary[int, int] = {}
var simultaneous_ticks := 0
var rocket_launches: Dictionary[int, int] = {}
var launcher_rounds := 0
var rocket_hits := 0
var map_combat_ticks: Dictionary[int, int] = {}
var configured := false
var rocket_clock := 0.0
var launcher_clock := 0.0
var workload_slot := -1


func run() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	var server: bool = options.get("role", "client") == "server"
	sector = make_sector("Workload", server)
	if server:
		seed_fleet()
	physics_frame.connect(step)
	if not server:
		var index := int(options.get("index", "0"))
		sector.session.credential_id = "pilot%d" % index
		sector.session.credential_token = test_token(index)
		check(sector.session.join("127.0.0.1", test_port(24683)) == OK, "Workload client joins")
		return
	for enemy: Alien in sector.world_aliens.values():
		enemy.damaged.connect(record_hit)
		enemy.destroyed.connect(func(ship: SpaceShip, _attacker: SpaceShip):
			if measuring:
				deaths += 1
				var alien_id := (ship as Alien).alien_id
				deaths_by_alien[alien_id] = deaths_by_alien.get(alien_id, 0) + 1)
		enemy.fired.connect(func(_a: Vector3, _b: Vector3, _hostile: bool):
			if measuring: alien_shots += 1)
	print("BENCHMARK_READY")
	var deadline := Time.get_ticks_msec() + 30000
	while sector.session.ships.size() != 10 and Time.get_ticks_msec() < deadline:
		await settle(0.1)
	check(sector.session.ships.size() == 10, "Ten clients connected before warmup")
	if failures:
		await finish()
		return
	deadline = Time.get_ticks_msec() + 30000
	while sector.session.ships.values().any(func(ship: Pilot): return ship.get_meta("docked", false)) and Time.get_ticks_msec() < deadline:
		await settle(0.1)
	check(sector.session.ships.values().all(func(ship: Pilot): return not ship.get_meta("docked", false)), "All ten pilots launch before placement")
	# Set up encounters once, before warmup. No fixture teleports or stat changes
	# occur during measurement; subsequent rescues/travel use gameplay rules.
	for id: int in sector.session.ships:
		var index := int(sector.session.pilot_ids[id].trim_prefix("pilot"))
		var ship := sector.session.ships[id]
		ship.map_id = assigned_map(index)
		var initial_slot := index / 4 if options.get("layout", "clustered") == "spread" else index % 5
		if options.get("layout", "clustered") == "spread" and ship.map_id >= 2: initial_slot = 0
		var enemy: Alien = sector.map_rosters[ship.map_id].values()[initial_slot]
		ship.position = enemy.position + Vector3(cos(index * TAU / 10) * 90, 25, sin(index * TAU / 10) * 90)
		sector.session.announce_map_change(id)
		ship.rockets.launched.connect(func(event: Dictionary):
			if measuring:
				rocket_launches[id] = rocket_launches.get(id, 0) + 1
				if Ammunition.ROCKETS[event["kind"]]["launcher"]: launcher_rounds += 1)
		ship.rockets.resolved.connect(func(_key: String, _point: Vector3, hit: bool):
			if measuring and hit: rocket_hits += 1)
	await settle(float(options.get("warmup", "15")))
	for id: int in sector.session.ships:
		positions[id] = sector.session.ships[id].position
		distances[id] = 0.0
		hits[id] = 0
	started = Time.get_ticks_usec()
	started_unix = Time.get_unix_time_from_system()
	network_totals() # Reset ENet host counters after warmup.
	previous_tick = 0
	measuring = true
	write_json("start.json", {"started_us": started})
	await settle(float(options.get("seconds", "120")))
	measuring = false
	var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
	var wall_elapsed := Time.get_unix_time_from_system() - started_unix
	check(minimum_roster == 10 and distances.size() == 10, "Ten pilots remain throughout measurement")
	check(distances.values().all(func(value: float): return value > 100.0), "Every pilot moves more than 100 m")
	check(hits.values().all(func(value: int): return value > 0), "Every pilot damages the alien")
	check(deaths > 0 and alien_shots > 0, "Aliens fight and die during measurement")
	var expected := 20 if options.get("layout", "clustered") == "spread" else 5
	check(sector.world_aliens.size() == 20 and sector.map_rosters.size() == 4, "Current four-map twenty-alien content is instantiated")
	check(hits_by_alien.size() == expected and deaths_by_alien.size() == expected and simultaneous_ticks > 0, "Every assigned alien fights and dies, with overlapping encounters")
	check(rocket_launches.size() == 10 and launcher_rounds > 0 and rocket_hits > 0, "Every pilot launches rockets, including launcher volleys and successful impacts")
	check(not sector.session.store.failed and sector.session.store.journal_sequence > 0, "Current combat journal remains healthy")
	write_json("server.json", {
		"enet_outbound": network_totals(),
		"layout": options.get("layout", "clustered"), "clustered_map": int(options.get("map", "0")),
		"alien_slots": sector.world_aliens.size(), "map_count": sector.map_rosters.size(),
		"rocket_launches_by_peer": rocket_launches, "launcher_rounds": launcher_rounds, "rocket_hits": rocket_hits,
		"combat_ticks_by_map": map_combat_ticks, "journal_sequence": sector.session.store.journal_sequence,
		"passed": failures == 0, "elapsed_seconds": elapsed,
		"physics_ticks": tick_us.size(), "ticks_per_second": tick_us.size() / elapsed,
		"system_elapsed_seconds": wall_elapsed, "ticks_per_system_second": tick_us.size() / wall_elapsed,
		"session_tick_us": distribution(tick_us), "tick_interval_us": distribution(interval_us),
		"alien_alive_session_tick_us": distribution(combat_tick_us),
		"engine_physics_ms": distribution(physics_ms), "minimum_roster": minimum_roster,
		"distance_m_by_peer": distances, "hits_by_peer": hits,
		"alien_shots": alien_shots, "alien_deaths": deaths,
		"hits_by_alien": hits_by_alien, "deaths_by_alien": deaths_by_alien,
		"simultaneous_combat_tick_fraction": float(simultaneous_ticks) / maxi(tick_us.size(), 1),
		"alien_alive_tick_fraction": float(alive_ticks) / maxi(tick_us.size(), 1),
	})
	# The runner stops clients first, then terminates this owned server process.
	print("BENCHMARK_DONE")


func step() -> void:
	var delta := 1.0 / Engine.physics_ticks_per_second
	if not sector.dedicated_server:
		drive_client(delta)
		return
	var before := Time.get_ticks_usec()
	var alien_was_alive := sector.world_aliens.values().any(func(enemy: Alien): return enemy.alive)
	sector._physics_process(delta)
	var elapsed := Time.get_ticks_usec() - before
	if not measuring:
		return
	tick_us.append(float(elapsed))
	if alien_was_alive:
		combat_tick_us.append(float(elapsed))
	if previous_tick != 0:
		interval_us.append(float(before - previous_tick))
	previous_tick = before
	physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	minimum_roster = mini(minimum_roster, sector.session.ships.size())
	if alien_was_alive:
		alive_ticks += 1
	if sector.world_aliens.values().filter(func(enemy: Alien): return enemy.alive and enemy.engaged).size() >= 2:
		simultaneous_ticks += 1
	for map: int in sector.map_rosters:
		if sector.map_rosters[map].values().any(func(enemy: Alien): return enemy.alive and enemy.engaged):
			map_combat_ticks[map] = map_combat_ticks.get(map, 0) + 1
	for id: int in sector.session.ships:
		var location := sector.session.ships[id].position
		distances[id] = distances.get(id, 0.0) + location.distance_to(positions.get(id, location))
		positions[id] = location


func drive_client(delta: float) -> void:
	if not sector.session.active or not sector.session.received_snapshot:
		return
	if sector.preflight:
		sector.session.launch()
		return
	if not configured:
		sector.session.combat.request_ammo("x3")
		configured = true
	sector.session.combat.interpolate(delta)
	command_clock += delta
	if command_clock < 0.05:
		return
	command_clock = 0.0
	var id := sector.multiplayer.get_unique_id()
	if not sector.session.goals.has(id):
		return
	var location: Vector3 = sector.session.goals[id]["position"]
	var index := int(options.get("index", "0"))
	var phase := Time.get_ticks_msec() / 1000.0 * 0.18 + index * TAU / 10.0
	var map := assigned_map(index)
	if sector.map_id != map:
		var hop := SectorMaps.first_hop(sector.map_id, map)
		var gate := SectorMaps.gate_position(sector.map_id, hop)
		var offset := gate - location
		var facing := Basis.looking_at(offset.normalized(), Vector3.UP)
		sector.session.command_flight.rpc_id(1, (facing.inverse() * offset / 25.0).limit_length(), facing.get_euler(), true, false, int(sector.player.get_meta("life", 0)))
		if offset.length() < 40: sector.session.request_jump()
		return
	var slot := index % 5
	if options.get("layout", "clustered") == "spread":
		if workload_slot < 0: workload_slot = index / 4 if map < 2 else 0
		# Finish each encounter before advancing. A timed rotation skipped hard
		# slots when an ordinary rescue and gate travel consumed most of a phase.
		for attempt in range(5):
			if sector.aliens.values()[workload_slot].alive: break
			workload_slot = (workload_slot + 1) % 5
		slot = workload_slot
	var enemy: Alien = sector.aliens.values()[slot]
	var target := enemy.position
	var destination := target + Vector3(cos(phase) * 100.0, 25.0 + sin(phase * 0.7) * 15.0, sin(phase) * 100.0)
	var facing := Basis.looking_at((target - location).normalized(), Vector3.UP)
	var movement := (facing.inverse() * (destination - location) / 25.0).limit_length()
	sector.session.command_flight.rpc_id(1, movement, facing.get_euler(), false,
		enemy.available() and location.distance_to(target) < 110.0 and (options.get("layout", "clustered") == "spread" or rocket_clock >= 1.0),
		int(sector.player.get_meta("life", 0)), enemy.life, enemy.alien_id)
	sector.select_target(enemy)
	rocket_clock += 0.05
	launcher_clock += 0.05
	if rocket_clock >= 2.1:
		rocket_clock = 0.0
		sector.session.combat.request_rocket("single")
	if launcher_clock >= 0.25:
		launcher_clock = 0.0
		var weapons := sector.player.rockets
		if weapons.launcher_cooldown <= 0 and not weapons.loading and (weapons.loaded == 0 or enemy.available()):
			sector.session.combat.request_rocket("launcher")


func assigned_map(index: int) -> int:
	return index % 4 if options.get("layout", "clustered") == "spread" else int(options.get("map", "0"))


func network_totals() -> Dictionary:
	var host: ENetConnection = (sector.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	return {"bytes": host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA),
		"packets": host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)}


func seed_fleet() -> void:
	var store := sector.session.store
	for pilot: Dictionary in store.pilots.values():
		var items := {}
		for slot: String in ShipCatalog.slots("goliath"):
			var model := ""
			if slot.begins_with("laser"): model = "lf-3"
			elif slot.begins_with("generator"): model = "sg3n-b02"
			elif slot.begins_with("launcher"): model = "hst-2"
			if not model.is_empty(): items[slot] = {"model": model, "ship": "starter", "slot": slot}
		pilot["equipment"] = {"revision": 1, "active_ship": "starter", "ships": {"starter": "goliath"}, "items": items}
		for kind: String in pilot["ammo"]: pilot["ammo"][kind] = 100000
	check(store.persist(store.pilots), "Persist legal fitted Goliath fleet before authentication")


func record_hit(ship: SpaceShip, attacker: SpaceShip) -> void:
	if measuring:
		var id: int = sector.session.ships.find_key(attacker)
		hits[id] = hits.get(id, 0) + 1
		var alien_id := (ship as Alien).alien_id
		hits_by_alien[alien_id] = hits_by_alien.get(alien_id, 0) + 1


func distribution(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {"count": sorted.size(), "mean": total / sorted.size(),
		"p50": sorted[ceili(sorted.size() * 0.5) - 1],
		"p95": sorted[ceili(sorted.size() * 0.95) - 1],
		"p99": sorted[ceili(sorted.size() * 0.99) - 1], "max": sorted[-1]}


func write_json(filename: String, data: Dictionary) -> void:
	var path := options["output"].path_join(filename)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
