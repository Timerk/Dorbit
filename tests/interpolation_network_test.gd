extends "res://tests/network_test.gd"
## Snapshot interpolation through the network simulator: an observer behind
## 150 ± 30 ms round trip with 5% loss watches a directly connected pilot fly
## a scripted, turning pattern on a dedicated server. The observer draws it
## close to the server's path at the render time, with acceleration near the
## server's own and little extrapolation. The test also replays the previous
## per-tick lerp toward the newest snapshot from the same packets and checks
## that interpolation removes the stutter that lerp shows.

const PORT := 24931
## Bounds, against two runs over 12 s on a Windows desktop: render-time error
## p95 0.03-0.04 m and max 0.1-0.25 m; drawn acceleration p95 1.7-2.0x the
## server's (2.5x in the suite at 60 fps); spikes (above 3x the server's p95) on 0-3% of ticks, against 86%
## for the per-tick lerp; 2-3% of entity ticks extrapolated. Limits leave room
## for slower CI hosts.
const RENDER_P95_ERROR := 0.5
const RENDER_MAX_ERROR := 3.0
const ACCEL_P95_RATIO := 4.0
const MAX_SPIKE_SHARE := 0.1
const MAX_EXTRAPOLATED_SHARE := 0.12
# Scripted input cycle: [seconds, actions, yaw radians per second].
const PATTERN := [
	[0.7, ["forward"], 0.0], [0.5, ["forward", "boost"], 0.0], [0.4, ["strafe_right"], 0.0],
	[0.6, ["forward", "strafe_left"], 1.6], [0.4, [], 0.0],
	[0.7, ["backward"], 0.0], [0.5, ["backward", "boost"], 0.0], [0.4, ["strafe_left"], 0.0],
	[0.6, ["backward", "strafe_right"], -1.6], [0.4, [], 0.0],
]
const ACTIONS := ["forward", "backward", "strafe_left", "strafe_right", "boost"]

var server: Sector
var observer: Sector
var mover: Sector
var mover_id := 0
var drawn: Array[Vector3] = []
var legacy: Array[Vector3] = []
var legacy_position := Vector3.ZERO
var render_errors := PackedFloat32Array()
var path: Dictionary[int, Vector3] = {}
var ticks := PackedInt32Array()


func run() -> void:
	server = make_sector("InterpServer", true, PORT)
	observer = make_sector("InterpObserver")
	mover = make_sector("InterpMover")
	for index in 2:
		var peer: Sector = [observer, mover][index]
		peer.session.credential_id = "pilot%d" % index
		peer.session.credential_token = test_token(index)
	for peer: Sector in [server, observer, mover]:
		peer.set_physics_process(true)
	await settle()
	observer.session.use_net_simulator = true
	observer.session.net_simulator.set_seed(5)
	observer.session.net_simulator.set_round_trip(150.0, 30.0, 5.0)
	check(observer.session.join("127.0.0.1", test_port(PORT)) == OK and mover.session.join("127.0.0.1", test_port(PORT)) == OK, "Both pilots start joining")
	var deadline := Time.get_ticks_msec() + 15000
	while not (observer.session.received_snapshot and mover.session.received_snapshot) and Time.get_ticks_msec() < deadline:
		await process_frame
	mover_id = mover.multiplayer.get_unique_id()
	check(observer.session.received_snapshot and mover.session.received_snapshot and server.session.ships.has(mover_id), "Both pilots join the dedicated server")
	if failures > 0:
		finish()
		return
	await fly(3.0)
	check(observer.session.remote_buffers.has(mover_id) and observer.session.clock.synced, "The observer buffers the remote pilot and synchronizes its clock")
	var net := observer.session.net_stats
	net.reset_extremes()
	net.keep_samples = true
	legacy_position = observer.session.ships[mover_id].position
	physics_frame.connect(sample)
	await fly(12.0)
	physics_frame.disconnect(sample)
	net.keep_samples = false
	release_inputs()

	var accelerations := second_differences(drawn)
	var legacy_accelerations := second_differences(legacy)
	var truth := PackedFloat32Array()
	for tick: int in path:
		if path.has(tick + 1) and path.has(tick + 2):
			truth.append((path[tick + 2] - 2.0 * path[tick + 1] + path[tick]).length() * 3600.0)
	var server_max := NetStats.percentile(truth, 1.0)
	# Three times the server's p95: a collision can make its maximum an outlier.
	var spike_limit := NetStats.percentile(truth, 0.95) * 3.0
	var spikes := spike_share(accelerations, spike_limit)
	var legacy_spikes := spike_share(legacy_accelerations, spike_limit)
	print("Render-time error p95 %.3f m, max %.3f m; accel p95 %.0f (server %.0f, max %.0f) m/s^2; spikes %.1f%% (per-tick lerp %.1f%%, accel p95 %.0f); extrapolated %.1f%%, %d underruns, depth %s ms" % [
		NetStats.percentile(render_errors, 0.95), NetStats.percentile(render_errors, 1.0),
		NetStats.percentile(accelerations, 0.95), NetStats.percentile(truth, 0.95), server_max,
		spikes * 100.0, legacy_spikes * 100.0, NetStats.percentile(legacy_accelerations, 0.95),
		net.extrapolation_share() * 100.0, net.underruns, net.buffer_depth()])
	check(render_errors.size() > 500, "The remote pilot is drawn every tick while measured")
	check(NetStats.percentile(render_errors, 0.95) <= RENDER_P95_ERROR and NetStats.percentile(render_errors, 1.0) <= RENDER_MAX_ERROR, "The drawn pilot follows the server's path at the render time")
	check(NetStats.percentile(accelerations, 0.95) <= NetStats.percentile(truth, 0.95) * ACCEL_P95_RATIO, "Drawn acceleration stays near the server's own")
	check(spikes <= MAX_SPIKE_SHARE, "Few ticks show acceleration spikes (%.1f%%)" % (spikes * 100.0))
	check(legacy_spikes > MAX_SPIKE_SHARE and legacy_spikes > spikes * 3.0, "The previous per-tick lerp stutters on the same packets (%.1f%% spikes)" % (legacy_spikes * 100.0))
	check(net.extrapolation_share() <= MAX_EXTRAPOLATED_SHARE, "The buffer rarely runs dry (%.1f%% extrapolated)" % (net.extrapolation_share() * 100.0))
	check(net.buffer_depth().y > 0.0 and net.interpolation_delay_ms == ServerClock.INTERPOLATION_DELAY * 1000.0, "Buffer depth and delay are reported")
	# A stall over ServerClock.SNAP_ERROR (a slow CI host) may snap once; jitter must not.
	check(observer.session.clock.snaps <= 1, "Jitter does not snap the observer's render clock (%d snaps)" % observer.session.clock.snaps)

	# Leaving forgets the remote pilot's buffer.
	mover.session.disconnect_session("Test leave")
	deadline = Time.get_ticks_msec() + 5000
	while observer.session.ships.has(mover_id) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not observer.session.ships.has(mover_id) and not observer.session.remote_buffers.has(mover_id), "A departed pilot's interpolation buffer is cleared")
	observer.session.disconnect_session("Test leave")
	check(not observer.session.clock.synced and observer.session.remote_buffers.is_empty(), "Disconnecting resets the clock and buffers")
	finish()


## Records, once per physics tick, the drawn remote pilot, the server's path
## and a replay of the previous lerp (25% per tick toward the newest snapshot).
func sample() -> void:
	if not server.session.ships.has(mover_id) or not observer.session.ships.has(mover_id):
		return
	var tick := server.session.server_tick
	path[tick] = server.session.ships[mover_id].position
	ticks.append(tick)
	drawn.append(observer.session.ships[mover_id].position)
	if observer.session.goals.has(mover_id):
		legacy_position = legacy_position.lerp(observer.session.goals[mover_id]["position"], 0.25)
	legacy.append(legacy_position)
	var render := observer.session.clock.render_tick()
	var low := floori(render)
	if path.has(low) and path.has(low + 1):
		render_errors.append(drawn[-1].distance_to(path[low].lerp(path[low + 1], render - low)))


func second_differences(points: Array[Vector3]) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for index in range(2, points.size()):
		if ticks[index] - ticks[index - 2] == 2:
			values.append((points[index] - 2.0 * points[index - 1] + points[index - 2]).length() * 3600.0)
	return values


func spike_share(values: PackedFloat32Array, limit: float) -> float:
	var spikes := 0
	for value in values:
		if value > limit:
			spikes += 1
	return float(spikes) / maxi(1, values.size())


func fly(seconds: float) -> void:
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
		mover.player.pending_look.x += segment[2] * (now - last) / 1000.0
		last = now
		# Keep combat from interrupting the flight; positions stay authoritative.
		for ship: Pilot in server.session.ships.values():
			ship.hull = ship.max_hull
			ship.shield = ship.max_shield
		await process_frame


func release_inputs() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)
