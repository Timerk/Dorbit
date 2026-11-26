extends "res://tests/network_test.gd"
## Client prediction and server reconciliation through the network simulator:
## a scripted pilot flies a dedicated server through the relay. Without added
## delay the replayed simulation matches the prediction; at 150 ± 30 ms with
## 5% loss corrections stay small and no input is lost. The server never takes
## a client position and still limits turn rates.

const PORT := 24921
## Largest simulation error at a reconciliation without added delay or loss.
## Straight flight replays exactly (0 m); turning leaves float-rounding
## differences of a few millimetres (measured p95 0.004 m, max 0.035 m). An
## isolated server starvation tick costs one tick of motion (under 1.5 m at
## boost speed), which smoothing hides.
const CLEAN_MAX_ERROR := 1.5
const CLEAN_P95_ERROR := 0.02
## Bounds at 150 ± 30 ms round trip with 5% loss in both directions. Measured
## p95 0.005 m and max 0.63 m (one catch-up drop) over 12 seconds.
const DEGRADED_MAX_ERROR := 3.0
const DEGRADED_P95_ERROR := 0.25
# Scripted input cycle: [seconds, actions, yaw radians per second].
const PATTERN := [
	[0.7, ["forward"], 0.0], [0.5, ["forward", "boost"], 0.0], [0.4, ["strafe_right"], 0.0],
	[0.6, ["forward", "strafe_left"], 1.6], [0.4, [], 0.0],
	[0.7, ["backward"], 0.0], [0.5, ["backward", "boost"], 0.0], [0.4, ["strafe_left"], 0.0],
	[0.6, ["backward", "strafe_right"], -1.6], [0.4, [], 0.0],
]
const ACTIONS := ["forward", "backward", "strafe_left", "strafe_right", "boost"]


func run() -> void:
	var server := make_sector("ReconcileServer", true, PORT)
	var client := make_sector("ReconcileClient")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	server.set_physics_process(true)
	client.set_physics_process(true)
	await settle()
	client.session.use_net_simulator = true
	client.session.net_simulator.set_seed(11)
	check(client.session.join("127.0.0.1", test_port(PORT)) == OK, "Client joins through the simulator")
	var deadline := Time.get_ticks_msec() + 10000
	while not client.session.received_snapshot and Time.get_ticks_msec() < deadline:
		await process_frame
	check(client.session.received_snapshot, "Snapshots arrive through the relay")
	var id := client.multiplayer.get_unique_id()
	if not server.session.ships.has(id):
		finish()
		return
	var remote := server.session.ships[id]
	var net := client.session.net_stats

	# Clean link: replays reproduce the prediction.
	var clean := await measure(server, client, 2.0, 6.0)
	print("Clean link: ", clean)
	check(clean["reconciliations"] > 60, "Snapshots reconcile the local ship repeatedly")
	check(clean["error_p95"] <= CLEAN_P95_ERROR and clean["error_max"] <= CLEAN_MAX_ERROR, "Without added delay the replay matches the prediction (p95 %.4f m, max %.3f m)" % [clean["error_p95"], clean["error_max"]])
	check(clean["inputs"]["lost"] == 0 and clean["inputs"]["applied"] > 300, "Every input is applied without delay or loss")

	# Collisions replay identically: fly into Outpost 01's collision envelope.
	client.player.look_at(Sector.STATION_POSITION, Vector3.UP)
	await settle(0.4)
	net.reset_extremes()
	net.keep_samples = true
	var collided := 0
	var started := Time.get_ticks_msec()
	Input.action_press("forward")
	Input.action_press("boost")
	while Time.get_ticks_msec() - started < 3500:
		keep_alive(server)
		await physics_frame
		if remote.get_slide_collision_count() > 0:
			collided += 1
	release_inputs()
	net.keep_samples = false
	print("Collision run: %d colliding server ticks, max sim error %.4f m, p95 %.4f m" % [collided, net.max_error_m, NetStats.percentile(net.error_samples, 0.95)])
	check(collided > 10, "The pilot slides along the station's collision envelope")
	check(NetStats.percentile(net.error_samples, 0.95) <= CLEAN_P95_ERROR and net.max_error_m <= CLEAN_MAX_ERROR, "Replays through move_and_slide collisions match the server")

	# Degraded link: bounded corrections and no lost inputs.
	client.session.net_simulator.set_round_trip(150.0, 30.0, 5.0)
	var degraded := await measure(server, client, 3.0, 12.0)
	print("150 ± 30 ms, 5% loss: ", degraded)
	check(degraded["relay_dropped"] > 20, "The relay drops datagrams in both directions")
	check(degraded["replay_max"] >= 9, "Reconciliation replays a round trip of inputs")
	check(degraded["error_p95"] <= DEGRADED_P95_ERROR and degraded["error_max"] <= DEGRADED_MAX_ERROR, "Corrections stay bounded at 150 ± 30 ms with 5%% loss (p95 %.3f m, max %.3f m)" % [degraded["error_p95"], degraded["error_max"]])
	check(degraded["inputs"]["lost"] == 0 and degraded["inputs"]["late"] == 0, "Redundant input packets lose no inputs")
	check(degraded["offset_max"] <= FlightPrediction.SNAP_DISTANCE, "Corrections are smoothed rather than snapped")

	# The server never takes a client position: a local teleport is undone.
	client.session.net_simulator.set_round_trip(0.0)
	await settle(0.5)
	var server_before := remote.position
	client.player.position += Vector3(400, 0, 0)
	await settle(0.6)
	check(remote.position.distance_to(server_before) < 60.0, "A client-side teleport does not move the server ship")
	check(client.player.position.distance_to(remote.position) < 20.0, "Reconciliation returns the local ship to the server's path")

	# Turn limits hold for a client requesting an instant 180-degree flip.
	client.set_physics_process(false)
	await settle(0.3)
	var life := int(client.player.get_meta("life", 0))
	var start := remote.rotation
	var flipped := Vector3(0.0, wrapf(start.y + PI, -PI, PI), 0.0)
	var largest := 0.0
	var previous := start
	for attempt in 30:
		client.session.send_command(Vector3.ZERO, flipped, false, false, life)
		await physics_frame
		var turned := Vector2(angle_difference(previous.y, remote.rotation.y), remote.rotation.x - previous.x).length()
		largest = maxf(largest, turned)
		previous = remote.rotation
	var limit := Pilot.MAX_TURN_RATE * (1.0 / Engine.physics_ticks_per_second + Pilot.TURN_LATENCY_ALLOWANCE) + 0.001
	check(largest <= limit, "No server tick turns faster than the limit (%.3f rad, limit %.3f)" % [largest, limit])
	check(absf(angle_difference(remote.rotation.y, flipped.y)) < 0.01, "The limited turn still reaches the requested facing")
	client.set_physics_process(true)
	client.session.disconnect_session("Test leave")
	finish()


## Flies the pattern for a warm-up, then measures for `seconds`.
func measure(server: Sector, client: Sector, warm_up: float, seconds: float) -> Dictionary:
	await fly(server, client, warm_up)
	var id := client.multiplayer.get_unique_id()
	var net := client.session.net_stats
	net.reset_extremes()
	net.keep_samples = true
	client.session.net_simulator.reset_stats()
	var before: Dictionary = server.session.input_buffers[id].counters()
	await fly(server, client, seconds)
	net.keep_samples = false
	var inputs: Dictionary = server.session.input_buffers[id].counters()
	for key: String in inputs:
		inputs[key] -= before[key]
	var relay: Dictionary = client.session.net_simulator.stats()
	return {"reconciliations": net.error_samples.size(), "error_p95": NetStats.percentile(net.error_samples, 0.95),
		"error_max": net.max_error_m, "error_mean": NetStats.mean(net.error_samples), "offset_max": net.max_offset_m,
		"replay_max": net.max_replayed_ticks, "inputs": inputs,
		"relay_dropped": relay["up"]["dropped_packets"] + relay["down"]["dropped_packets"]}


func fly(server: Sector, client: Sector, seconds: float) -> void:
	var cycle := 0.0
	for segment: Array in PATTERN:
		cycle += segment[0]
	var started := Time.get_ticks_msec()
	var last := started
	while Time.get_ticks_msec() - started < seconds * 1000.0:
		var now := Time.get_ticks_msec()
		var phase := fmod((now - started) / 1000.0, cycle)
		var segment: Array = PATTERN[-1]
		for candidate: Array in PATTERN:
			if phase < candidate[0]:
				segment = candidate
				break
			phase -= candidate[0]
		for action: String in ACTIONS:
			if action in segment[1]:
				Input.action_press(action)
			else:
				Input.action_release(action)
		client.player.pending_look.x += segment[2] * (now - last) / 1000.0
		last = now
		keep_alive(server)
		await process_frame
	release_inputs()


## Keeps combat from interrupting the flight; positions stay authoritative.
func keep_alive(server: Sector) -> void:
	for ship: Pilot in server.session.ships.values():
		ship.hull = ship.max_hull
		ship.shield = ship.max_shield


func release_inputs() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)
