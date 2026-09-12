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


func run() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	var server: bool = options.get("role", "client") == "server"
	sector = make_sector("Workload", server)
	physics_frame.connect(step)
	if not server:
		check(sector.session.join("127.0.0.1", 24683) == OK, "Workload client joins")
		return
	sector.alien.damaged.connect(record_hit)
	sector.alien.destroyed.connect(func(_ship: SpaceShip, _attacker: SpaceShip):
		if measuring: deaths += 1)
	sector.alien.fired.connect(func(_a: Vector3, _b: Vector3, _hostile: bool):
		if measuring: alien_shots += 1)
	print("BENCHMARK_READY")
	var deadline := Time.get_ticks_msec() + 30000
	while sector.session.ships.size() != 10 and Time.get_ticks_msec() < deadline:
		await settle(0.1)
	check(sector.session.ships.size() == 10, "Ten clients connected before warmup")
	if failures:
		await finish()
		return
	await settle(float(options.get("warmup", "15")))
	for id: int in sector.session.ships:
		positions[id] = sector.session.ships[id].position
		distances[id] = 0.0
		hits[id] = 0
	started = Time.get_ticks_usec()
	started_unix = Time.get_unix_time_from_system()
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
	check(deaths > 0 and alien_shots > 0, "Alien fights and dies during measurement")
	write_json("server.json", {
		"passed": failures == 0, "elapsed_seconds": elapsed,
		"physics_ticks": tick_us.size(), "ticks_per_second": tick_us.size() / elapsed,
		"system_elapsed_seconds": wall_elapsed, "ticks_per_system_second": tick_us.size() / wall_elapsed,
		"session_tick_us": distribution(tick_us), "tick_interval_us": distribution(interval_us),
		"alien_alive_session_tick_us": distribution(combat_tick_us),
		"engine_physics_ms": distribution(physics_ms), "minimum_roster": minimum_roster,
		"distance_m_by_peer": distances, "hits_by_peer": hits,
		"alien_shots": alien_shots, "alien_deaths": deaths,
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
	var alien_was_alive := sector.alien.alive
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
	if sector.alien.alive:
		alive_ticks += 1
	for id: int in sector.session.ships:
		var location := sector.session.ships[id].position
		distances[id] = distances.get(id, 0.0) + location.distance_to(positions.get(id, location))
		positions[id] = location


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
	var target := sector.alien.position
	var destination := target + Vector3(cos(phase) * 100.0, 25.0 + sin(phase * 0.7) * 15.0, sin(phase) * 100.0)
	var facing := Basis.looking_at((target - location).normalized(), Vector3.UP)
	var movement := (facing.inverse() * (destination - location) / 25.0).limit_length()
	sector.session.command_flight.rpc_id(1, movement, facing.get_euler(), false,
		sector.alien.alive, int(sector.player.get_meta("life", 0)), sector.session.combat.encounter)


func record_hit(_ship: SpaceShip, attacker: SpaceShip) -> void:
	if measuring:
		var id: int = sector.session.ships.find_key(attacker)
		hits[id] = hits.get(id, 0) + 1


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
