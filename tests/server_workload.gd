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
var benchmark_store
var lasers: Dictionary[int, int] = {}
var rocket_launches: Dictionary = {}
var rocket_hits := 0
var pickup_units: Dictionary[int, int] = {}
var cargo_previous: Dictionary[int, int] = {}
var map_tick_counts: Dictionary = {}
var over_budget_ticks: Array[Dictionary] = []
var lab_before: Dictionary = {}
var target_slot := -1
var rocket_clock := 0.0
var launcher_clock := 0.0
var rocket_sequence := 0
var phase_us: Dictionary = {}


func run() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	var server: bool = options.get("role", "client") == "server"
	sector = make_sector("Workload", server)
	physics_frame.connect(step)
	if not server:
		var index := int(options.get("index", "0"))
		sector.session.credential_id = "pilot%d" % index
		sector.session.credential_token = test_token(index)
		check(sector.session.join("127.0.0.1", test_port(24683)) == OK, "Workload client joins")
		return
	# Reopen only this fixture's disposable ledger through the timing adapter.
	var directory := sector.session.store.path.get_base_dir()
	check(sector.session.store.close(), "Close fixture ledger before timing adapter")
	benchmark_store = preload("res://tests/benchmark_store.gd").new()
	check(benchmark_store.open(directory), "Timing adapter opens disposable ledger")
	sector.session.store = benchmark_store
	sector.session.benchmark_timing = true
	prepare_inventory()
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
	for id: int in sector.session.ships:
		prepare_peer(id)
	await settle(float(options.get("warmup", "15")))
	# Start near the ordinary ammunition-CPU threshold so automation is exercised
	# in the measured window, independent of how many warmup kills occurred.
	var initial_ammo := {}
	for id: int in sector.session.ships:
		sector.session.ships[id].ammo["x1"] = 990
		initial_ammo[sector.session.pilot_ids[id]] = sector.session.ships[id].ammo.duplicate()
	check(benchmark_store.commit_combat(initial_ammo), "Set measurement starting ammunition")
	check(benchmark_store.persist(benchmark_store.pilots), "Checkpoint fixture setup before measurement")
	for id: int in sector.session.ships:
		positions[id] = sector.session.ships[id].position
		distances[id] = 0.0
		hits[id] = 0
		lasers[id] = 0
		pickup_units[id] = 0
		cargo_previous[id] = cargo_units(id)
	for pilot_id: String in benchmark_store.pilots:
		lab_before[pilot_id] = benchmark_store.pilots[pilot_id]["skylab"].duplicate(true)
	started = Time.get_ticks_usec()
	started_unix = Time.get_unix_time_from_system()
	previous_tick = 0
	measuring = true
	benchmark_store.measuring = true
	write_json("start.json", {"started_us": started})
	await settle(float(options.get("seconds", "120")))
	measuring = false
	benchmark_store.measuring = false
	var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
	var wall_elapsed := Time.get_unix_time_from_system() - started_unix
	check(minimum_roster == 10 and distances.size() == 10, "Ten pilots remain throughout measurement")
	check(distances.values().all(func(value: float): return value > 100.0), "Every pilot moves more than 100 m")
	check(hits.values().all(func(value: int): return value > 0), "Every pilot damages the alien")
	check(deaths > 0 and alien_shots > 0, "Aliens fight and die during measurement")
	check(simultaneous_ticks > 0, "Overlapping encounters occur")
	check(lasers.values().all(func(value: int): return value > 0), "Every pilot fires lasers")
	check(int(rocket_launches.get("single", 0)) > 0 and int(rocket_launches.get("launcher", 0)) > 0 and rocket_hits > 0, "Single rockets and Hellstorm launch and hit")
	check(pickup_units.values().any(func(value: int): return value > 0), "Ordinary loot collection commits cargo")
	check(int(benchmark_store.counts.get("checkpoint_industry", 0)) > 0, "Skylab advances and checkpoints")
	check(int(benchmark_store.counts.get("checkpoint_extras", 0)) > 0, "Extras automation commits supplies")
	var save_timings := {}
	for kind: String in benchmark_store.samples:
		var values: Array[float] = []
		values.assign(benchmark_store.samples[kind])
		save_timings[kind] = distribution(values)
	var peer_ports := {}
	var phase_timings := {}
	for kind: String in phase_us:
		var values: Array[float] = []
		values.assign(phase_us[kind])
		phase_timings[kind] = distribution(values)
	var maps := {}
	var lab_after := {}
	for id: int in sector.session.ships:
		peer_ports[sector.session.pilot_ids[id]] = sector.multiplayer.multiplayer_peer.get_peer(id).get_remote_port()
		maps[sector.session.pilot_ids[id]] = sector.session.ships[id].map_id
	for pilot_id: String in benchmark_store.pilots:
		var lab: Dictionary = benchmark_store.pilots[pilot_id]["skylab"]
		check(lab["lastSimulatedAt"] > lab_before[pilot_id]["lastSimulatedAt"] and lab["inventory"] != lab_before[pilot_id]["inventory"], "Pilot industry produces resources during window")
		lab_after[pilot_id] = {"before_at": lab_before[pilot_id]["lastSimulatedAt"], "after_at": lab["lastSimulatedAt"], "before_inventory": lab_before[pilot_id]["inventory"], "after_inventory": lab["inventory"]}
	var expected_maps := 4 if options.get("scenario", "single-map") == "spread" else 1
	check(map_tick_counts.size() == expected_maps and map_tick_counts.values().all(func(count: int): return count >= tick_us.size() * 2), "Expected map membership is maintained throughout measurement")
	write_json("server.json", {
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
		"scenario": options.get("scenario", "single-map"), "world_maps": 4, "world_aliens": sector.world_aliens.size(),
		"lasers_by_peer": lasers, "rocket_launches": rocket_launches, "rocket_hits": rocket_hits,
		"pickup_units_by_peer": pickup_units, "map_pilot_ticks": map_tick_counts, "pilot_maps": maps,
		"peer_ports": peer_ports, "skylab": lab_after, "persistence_us": save_timings,
		"persistence_events": benchmark_store.events, "over_budget_ticks": over_budget_ticks,
		"snapshot_bytes_end": benchmark_store.saved_bytes, "journal_bytes_end": benchmark_store.journal_bytes,
		"phase_us": phase_timings,
	})
	# The runner stops clients first, then terminates this owned server process.
	print("BENCHMARK_DONE")
	while not FileAccess.file_exists(options["output"].path_join("stop")):
		await settle(0.05)
	var close_started := Time.get_ticks_usec()
	sector.session.disconnect_session("Benchmark complete")
	write_json("shutdown.json", {"duration_us": Time.get_ticks_usec() - close_started,
		"passed": not benchmark_store.failed})
	quit(int(failures > 0))


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
	if elapsed > 16667:
		over_budget_ticks.append({"started_us": before, "duration_us": elapsed, "phases": sector.session.benchmark_phases.duplicate()})
	for kind: String in sector.session.benchmark_phases:
		if not phase_us.has(kind): phase_us[kind] = []
		phase_us[kind].append(float(sector.session.benchmark_phases[kind]))
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
	for id: int in sector.session.ships:
		var location := sector.session.ships[id].position
		distances[id] = distances.get(id, 0.0) + location.distance_to(positions.get(id, location))
		positions[id] = location
		var map: int = sector.session.ships[id].map_id
		map_tick_counts[map] = int(map_tick_counts.get(map, 0)) + 1
		var units := cargo_units(id)
		pickup_units[id] = pickup_units.get(id, 0) + maxi(0, units - cargo_previous.get(id, units))
		cargo_previous[id] = units


func drive_client(delta: float) -> void:
	if not sector.session.active or not sector.session.received_snapshot:
		return
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
	var enemies := sector.aliens.values()
	if target_slot < 0: target_slot = (index / 4 if options.get("scenario", "single-map") == "spread" else index / 2) % enemies.size()
	var enemy: Alien = enemies[target_slot]
	var target := enemy.position
	var destination := target + Vector3(cos(phase) * 65.0, 15.0 + sin(phase * 0.7) * 10.0, sin(phase) * 65.0)
	var closest := 250.0
	for drop: Dictionary in sector.loot.drops.values():
		var distance := location.distance_to(drop["position"])
		if distance < closest and CargoResources.units(sector.cargo) < sector.cargo_capacity:
			closest = distance
			destination = drop["position"]
	var facing := Basis.looking_at((target - location).normalized(), Vector3.UP)
	var movement := (facing.inverse() * (destination - location) / 25.0).limit_length()
	sector.session.command_flight.rpc_id(1, movement, facing.get_euler(), false,
		enemy.available(), int(sector.player.get_meta("life", 0)), enemy.life, enemy.alien_id)
	rocket_clock += 0.05
	launcher_clock += 0.05
	if rocket_clock >= 2.1:
		rocket_clock = 0.0
		send_rocket("single", enemy)
	if launcher_clock >= 6.2:
		launcher_clock = 0.0
		send_rocket("launcher", enemy)


func send_rocket(action: String, enemy: Alien) -> void:
	rocket_sequence += 1
	sector.session.combat.rocket_request.rpc_id(1, rocket_sequence, int(sector.player.get_meta("life", 0)), action, "", enemy.alien_id, enemy.life)


func cargo_units(id: int) -> int:
	var pilot: Dictionary = sector.session.store.pilots[sector.session.pilot_ids[id]]
	return CargoResources.units(pilot["cargo"][pilot["equipment"]["active_ship"]])


func prepare_inventory() -> void:
	var next: Dictionary = benchmark_store.pilots.duplicate(true)
	for pilot: Dictionary in next.values():
		var equipment := {"revision": 1, "active_ship": "starter", "ships": {"starter": "goliath"}, "items": {}}
		for slot: String in ShipCatalog.slots("goliath"):
			var model := ""
			if slot.begins_with("laser"):
				if options.get("scenario", "single-map") == "spread": model = "lf-3"
				elif int(slot.trim_prefix("laser")) <= 4: model = "laser"
			elif slot.begins_with("generator"): model = "sg3n-b02" if int(slot.trim_prefix("generator")) <= 10 else "g3n-7900"
			elif slot == "launcher1": model = "hst-2"
			elif slot == "extra1": model = "ammo-cpu"
			elif slot == "extra2": model = "generator-cpu"
			elif slot == "extra3": model = "rep-2"
			if not model.is_empty():
				equipment["items"][slot] = {"model": model, "ship": "starter", "slot": slot}
				if model in ["ammo-cpu", "generator-cpu"]: equipment["items"][slot]["enabled"] = true
				if model == "ammo-cpu": equipment["items"][slot]["ammo_type"] = "x1"
		check(Equipment.valid(equipment), "Benchmark fitting uses valid catalog equipment")
		pilot["equipment"] = equipment
		pilot["credits"] = 10_000_000
		pilot["ammo"]["x1"] = 1800
		pilot["ammo"]["r-310"] = 1000
		pilot["ammo"]["eco-10"] = 1000
		check(Ammunition.valid(pilot["ammo"]), "Benchmark ammunition uses valid catalog IDs")
		pilot["cargo"]["starter"] = {"duranium": 10}
		check(CargoResources.valid(pilot["cargo"], equipment), "Benchmark initial cargo is valid")
	check(benchmark_store.persist(next), "Persist upgraded pilots before joins")


func prepare_peer(id: int) -> void:
	var index := int(sector.session.pilot_ids[id].trim_prefix("pilot"))
	var map := index % 4 if options.get("scenario", "single-map") == "spread" else 0
	var ship := sector.session.ships[id]
	# Initial placement is fixture setup, before warmup. Measurement uses normal input.
	ship.map_id = map
	ship.map_visit += 1
	ship.position = sector.map_rosters[map].values()[index / 4 if map != 0 else index / 2].position + Vector3(50 + index * 5, 30, 0)
	ship.velocity = Vector3.ZERO
	ship.fired.connect(func(_a: Vector3, _b: Vector3, _hostile: bool):
		if measuring: lasers[id] = lasers.get(id, 0) + 1)
	ship.rockets.launched.connect(func(event: Dictionary):
		if measuring:
			var kind: String = "launcher" if event["kind"] == "eco-10" else "single"
			rocket_launches[kind] = int(rocket_launches.get(kind, 0)) + 1)
	ship.rockets.resolved.connect(func(_key: String, _location: Vector3, hit: bool):
		if measuring and hit: rocket_hits += 1)
	sector.session.announce_map_change(id)


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
