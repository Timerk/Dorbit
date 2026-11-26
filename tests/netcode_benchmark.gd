extends "res://tests/network_test.gd"
## Netcode measurement tool (not part of the check suites). Runs a dedicated
## server, one measured client routed through NetSimulator and a few extra
## clients connected directly, all flying the same scripted input, then prints a
## markdown table and a NETCODE_BENCHMARK= JSON line per run.
##
## Usage (from the project root):
##   godot --headless --path . --script res://tests/netcode_benchmark.gd -- [options]
## Options:
##   --scenario=baseline   0, 100 and 200 ms added RTT, each at 0% and 5% loss (default)
##   --scenario=degraded   150 ± 30 ms added RTT with 5% loss
##   --condition=RTT,JITTER,LOSS[,DUPLICATE]   add a custom condition (repeatable;
##                         replaces the scenario)
##   --seconds=20          measured seconds per condition (after a 15 s warm-up)
##   --extra-clients=3     directly connected pilots flying alongside
##   --seed=1              relay random seed
##
## Conditions: "RTT" is round trip added by the relay, split evenly per
## direction ("100 ms" adds 50 ms each way). "JITTER" is ± round-trip jitter,
## also split evenly. LOSS and DUPLICATE apply independently in both directions.
##
## Metrics, all for the measured client over the measured window:
## - speed_mps: mean speed of the predicted local ship, sampled every frame.
## - fps: frames per second of the benchmark process, which hosts the server
##   and every client; ENet is serviced once per frame.
## - rtt_ms: mean of ENet's smoothed round trip to the server, sampled every 0.5 s.
##   ENet updates it by 1/8 per reliable acknowledgement, so it lags changes.
## - up_bps / down_bps: UDP payload bytes per second sent and received by the
##   client's ENet host (ENet headers included; IP/UDP headers excluded).
## - server_bps: bytes per second the server sent toward this client, counted
##   by the relay before simulated loss. server_avg_bps is the server host's
##   total sent bytes per second divided by the number of connected clients.
## - server_bytes_per_snapshot: the relay's server bytes divided by the number
##   of server snapshot ticks. On schema 26+, world_bps and
##   world_bytes_per_snapshot count only this viewer's snapshot payloads.
##   delta_share and full_fallbacks describe baseline use in the sample.
## - jitter_mean_ms / jitter_p95_ms / jitter_max_ms: |snapshot inter-arrival
##   time - 50 ms| as handled by the client, so frame timing is included.
## - error_*_m: simulation error at each reconciliation: how far rewinding to
##   the authoritative state and replaying unacknowledged inputs moved the
##   predicted ship (mean/p95/max). Before phase 2 (network schema 23) this was
##   the distance from the predicted ship to the round-trip-old authoritative
##   position, which mostly measured latency rather than misprediction.
## - correction_*_m: the visual offset hiding corrections, sampled every client
##   physics tick: how far the drawn ship is from the simulated one. Before
##   phase 2 it was how far each snapshot's 20% lerp moved the ship, a visible
##   jump within one frame.
## - gap_*_m: distance from the client's ship to the server's current position
##   of the same ship, sampled every frame (possible because both run in this
##   process). Accurate prediction leads the server by the upstream delay and
##   the server's input buffer times speed.
## - replay_mean / replay_max: unacknowledged inputs replayed per reconciliation.
## - depth_mean: inputs the server had buffered for this pilot, sampled every frame.
## - inputs_sent / inputs_applied / inputs_lost: inputs the client sampled, the
##   server applied, and the server skipped because they never arrived. late,
##   dropped (catch-up) and starved (ticks reusing the last input) are the
##   server's InputBuffer counters. Before phase 2 these columns counted 20 Hz
##   flight commands, each lost with its datagram.
##
## Remote smoothness (phase 3), needing at least one extra client: the measured
## client watches the first extra pilot, which flies the same pattern and also
## turns. Once per physics tick the benchmark records where the measured client
## draws it and where the server has it, on the server's tick.
## - remote_path_*_m: distance from the drawn ship to the server's path over
##   the last 1.5 s (the nearest point on the polyline of its tick positions):
##   how far the drawn motion strays from a path the ship really flew, at any
##   delay. remote_lag_ms is how far behind the server's current tick that
##   nearest point is, on average.
## - remote_render_*_m: distance from the drawn ship to the server's position
##   at the client's render tick (ServerClock): the interpolation error proper.
##   Only builds with snapshot interpolation report it.
## - remote_accel_p95/max: acceleration of the drawn ship, from second
##   differences of its position per physics tick, in m/s^2. Stutter shows as
##   spikes far above server_accel_p95/max, the same measure of the server's
##   own path.
## - remote_spikes: share of ticks whose drawn acceleration exceeds three
##   times the server's p95 acceleration (a collision can make the server's
##   maximum an outlier).
## - extrapolated_share, underruns, depth_min/mean_ms: NetStats interpolation
##   counters over the window: share of remote entity ticks drawn past their
##   newest sample, buffers that ran dry, and how far the newest snapshot was
##   ahead of the render time (min and mean, ms).

const BASE_PORT := 24911
# ENet smooths its RTT by 1/8 per reliable acknowledgement, about two per
# second here, so each condition settles before it is measured.
const WARM_UP := 15.0
const SCENARIOS := {
	"baseline": [[0.0, 0.0, 0.0, 0.0], [100.0, 0.0, 0.0, 0.0], [200.0, 0.0, 0.0, 0.0],
		[0.0, 0.0, 5.0, 0.0], [100.0, 0.0, 5.0, 0.0], [200.0, 0.0, 5.0, 0.0]],
	"degraded": [[150.0, 30.0, 5.0, 0.0]],
}
# Scripted input cycle: [seconds, actions, yaw radians per second]. The second
# half mirrors the first so the pilot stays near the protected station.
const PATTERN := [
	[0.8, ["forward"], 0.0], [0.6, ["forward", "boost"], 0.0], [0.5, ["strafe_right"], 0.0],
	[0.6, ["forward", "strafe_left"], 1.6], [0.5, [], 0.0],
	[0.8, ["backward"], 0.0], [0.6, ["backward", "boost"], 0.0], [0.5, ["strafe_left"], 0.0],
	[0.6, ["backward", "strafe_right"], -1.6], [0.5, [], 0.0],
]
const ACTIONS := ["forward", "backward", "strafe_left", "strafe_right", "boost"]

var options := {"scenario": "baseline", "seconds": 20.0, "extra-clients": 3, "seed": 1}
var custom: Array = []


func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--condition="):
			var parts := argument.trim_prefix("--condition=").split(",")
			var condition := [0.0, 0.0, 0.0, 0.0]
			for index in mini(parts.size(), 4):
				condition[index] = float(parts[index])
			custom.append(condition)
		elif argument.begins_with("--") and "=" in argument:
			var key := argument.trim_prefix("--").get_slice("=", 0)
			if options.has(key):
				var value := argument.get_slice("=", 1)
				if key == "scenario":
					options[key] = value
				else:
					options[key] = float(value)
	var conditions: Array = custom if not custom.is_empty() else SCENARIOS.get(options["scenario"], [])
	if conditions.is_empty():
		push_error("Unknown scenario %s" % options["scenario"])
		quit(1)
		return
	var server := make_sector("BenchServer", true, BASE_PORT)
	server.multiplayer.auth_timeout = 15.0
	server.set_physics_process(true)
	var client := make_sector("BenchClient")
	var everyone: Array[Sector] = [client]
	for index in range(int(options["extra-clients"])):
		everyone.append(make_sector("BenchExtra%d" % index))
	for index in everyone.size():
		everyone[index].session.credential_id = "pilot%d" % index
		everyone[index].session.credential_token = test_token(index)
		everyone[index].multiplayer.auth_timeout = 15.0
		everyone[index].set_physics_process(true)
	await settle()
	client.session.use_net_simulator = true
	client.session.net_simulator.set_seed(int(options["seed"]))
	for sector in everyone:
		check(sector.session.join("127.0.0.1", test_port(BASE_PORT)) == OK, "%s starts joining" % sector.name)
	var deadline := Time.get_ticks_msec() + 20000
	while everyone.any(func(peer: Sector): return not peer.session.received_snapshot) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(everyone.all(func(peer: Sector): return peer.session.received_snapshot), "Every pilot joins and receives snapshots")
	if failures > 0:
		finish()
		return
	if everyone.size() > 1:
		watched = everyone[1]
	var results: Array[Dictionary] = []
	for condition: Array in conditions:
		results.append(await measure(server, client, everyone.size(), condition))
	release_inputs()
	print_table(results)
	print_remote_table(results)
	print("Process frame rate: %s fps (server and all clients share one process)." % ", ".join(results.map(func(row: Dictionary): return str(row["fps"]))))
	print("NETCODE_BENCHMARK=", JSON.stringify({"options": options, "results": results}))
	finish()


func measure(server: Sector, client: Sector, clients: int, condition: Array) -> Dictionary:
	var relay := client.session.net_simulator
	relay.set_round_trip(condition[0], condition[1], condition[2], condition[3])
	# Restart every pilot at its spawn point, outside the measured window.
	for ship: Pilot in server.session.ships.values():
		ship.position = server.session.combat.records[server.session.ships.find_key(ship)]["spawn"]
		ship.velocity = Vector3.ZERO
	await fly(client, WARM_UP)
	var net := client.session.net_stats
	net.reset_extremes()
	net.keep_samples = true
	relay.reset_stats()
	var id := client.multiplayer.get_unique_id()
	var sent_before := net.inputs_sent
	var packets_before := net.input_packets_sent
	var inputs_before: Dictionary = server.session.input_buffers[id].counters()
	var up_before := net.total_up_bytes
	var down_before := net.total_down_bytes
	var snapshots_before := server.session.snapshot_sequence
	var traffic: Variant = server.session.get("snapshot_traffic")
	var viewer: Variant = traffic.get(id) if traffic != null else null
	var payload_before: int = viewer.total_bytes if viewer != null else 0
	var full_before: int = viewer.full_fallbacks if viewer != null else 0
	var host: ENetConnection = (server.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var started := Time.get_ticks_usec()
	var frames := Engine.get_process_frames()
	clear_remote_samples()
	var sampler := sample_remote.bind(server, client)
	if watched != null:
		physics_frame.connect(sampler)
	var rtts := await fly(client, float(options["seconds"]), server)
	if watched != null:
		physics_frame.disconnect(sampler)
	var seconds := (Time.get_ticks_usec() - started) / 1_000_000.0
	frames = Engine.get_process_frames() - frames
	net.keep_samples = false
	var server_bytes := host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var relay_stats: Dictionary = relay.stats()
	var sent := net.inputs_sent - sent_before
	var inputs: Dictionary = server.session.input_buffers[id].counters()
	for key: String in inputs:
		inputs[key] -= inputs_before[key]
	var sent_snapshots := server.session.snapshot_sequence - snapshots_before
	var row := {
		"rtt_added_ms": condition[0], "jitter_ms": condition[1], "loss_percent": condition[2], "duplicate_percent": condition[3],
		"seconds": snappedf(seconds, 0.01), "rtt_ms": snappedf(NetStats.mean(rtts), 0.1),
		"fps": roundi(frames / seconds), "speed_mps": snappedf(NetStats.mean(speeds), 0.1),
		"up_bps": roundi((net.total_up_bytes - up_before) / seconds),
		"down_bps": roundi((net.total_down_bytes - down_before) / seconds),
		"server_bps": roundi(relay_stats["down"]["received_bytes"] / seconds),
		"server_bytes_per_snapshot": snappedf(float(relay_stats["down"]["received_bytes"]) / maxi(1, sent_snapshots), 0.1),
		"server_avg_bps": roundi(server_bytes / seconds / clients),
		"snapshots": net.jitter_samples.size(),
		"jitter_mean_ms": snappedf(NetStats.mean(net.jitter_samples), 0.1),
		"jitter_p95_ms": snappedf(NetStats.percentile(net.jitter_samples, 0.95), 0.1),
		"jitter_max_ms": snappedf(NetStats.percentile(net.jitter_samples, 1.0), 0.1),
		"error_mean_m": snappedf(NetStats.mean(net.error_samples), 0.01),
		"error_p95_m": snappedf(NetStats.percentile(net.error_samples, 0.95), 0.01),
		"error_max_m": snappedf(NetStats.percentile(net.error_samples, 1.0), 0.01),
		"correction_mean_m": snappedf(NetStats.mean(net.offset_samples), 0.01),
		"correction_p95_m": snappedf(NetStats.percentile(net.offset_samples, 0.95), 0.01),
		"correction_max_m": snappedf(NetStats.percentile(net.offset_samples, 1.0), 0.01),
		"replay_mean": snappedf(NetStats.mean(net.replay_samples), 0.1),
		"replay_max": roundi(NetStats.percentile(net.replay_samples, 1.0)),
		"depth_mean": snappedf(NetStats.mean(depths), 0.1),
		"gap_mean_m": snappedf(NetStats.mean(gaps), 0.01),
		"gap_p95_m": snappedf(NetStats.percentile(gaps, 0.95), 0.01),
		"inputs_sent": sent, "inputs_applied": inputs["applied"], "inputs_lost": inputs["lost"],
		"inputs_late": inputs["late"], "inputs_dropped": inputs["dropped"], "inputs_starved": inputs["starved"],
		"inputs_duplicates": inputs["duplicates"],
		"input_packets": net.input_packets_sent - packets_before,
		"relay_dropped": relay_stats["up"]["dropped_packets"] + relay_stats["down"]["dropped_packets"],
	}
	if viewer != null and sent_snapshots > 0:
		var payload: int = viewer.total_bytes - payload_before
		row["world_bps"] = roundi(payload / seconds)
		row["world_bytes_per_snapshot"] = snappedf(float(payload) / sent_snapshots, 0.1)
		row["full_fallbacks"] = viewer.full_fallbacks - full_before
		row["delta_share"] = 1.0 - float(row["full_fallbacks"]) / sent_snapshots
	row.merge(remote_metrics(net))
	return row


var speeds := PackedFloat32Array()
var gaps := PackedFloat32Array()
var depths := PackedFloat32Array()
## The extra pilot the measured client watches, or null without extra clients.
var watched: Sector = null
# Per physics tick while measuring: the watched ship as drawn by the measured
# client, the client's render tick (or -1), and the server's tick.
var drawn: Array[Vector3] = []
var render_ticks := PackedFloat64Array()
var sample_ticks := PackedInt32Array()
# Server position of the watched ship per server tick.
var server_path: Dictionary[int, Vector3] = {}


func clear_remote_samples() -> void:
	drawn.clear()
	render_ticks = PackedFloat64Array()
	sample_ticks = PackedInt32Array()
	server_path.clear()


func sample_remote(server: Sector, client: Sector) -> void:
	var id := watched.multiplayer.get_unique_id()
	if not server.session.ships.has(id) or not client.session.ships.has(id):
		return
	var tick := server.session.server_tick
	server_path[tick] = server.session.ships[id].position
	drawn.append(client.session.ships[id].position)
	sample_ticks.append(tick)
	# Builds before snapshot interpolation have no render clock.
	var clock: Object = client.session.get("clock")
	render_ticks.append(clock.call("render_tick") if clock != null and clock.get("synced") else -1.0)


## Server position at fractional `tick`, or null outside the recorded path.
func server_at(tick: float) -> Variant:
	var low := floori(tick)
	if not server_path.has(low) or not server_path.has(low + 1):
		return server_path.get(low) if is_equal_approx(tick, low) else null
	return server_path[low].lerp(server_path[low + 1], tick - low)


func remote_metrics(net: NetStats) -> Dictionary:
	var path_errors := PackedFloat32Array()
	var lags := PackedFloat32Array()
	var render_errors := PackedFloat32Array()
	var accelerations := PackedFloat32Array()
	var server_accelerations := PackedFloat32Array()
	var rate := float(Engine.physics_ticks_per_second)
	for index in drawn.size():
		var now := sample_ticks[index]
		var point := drawn[index]
		# Nearest point on the server's path over the last 1.5 s.
		var best := INF
		var best_tick := float(now)
		for tick in range(now - 90, now):
			if not server_path.has(tick) or not server_path.has(tick + 1):
				continue
			var from: Vector3 = server_path[tick]
			var segment: Vector3 = server_path[tick + 1] - from
			var along := clampf((point - from).dot(segment) / segment.length_squared(), 0.0, 1.0) if segment.length_squared() > 1e-8 else 0.0
			var distance := point.distance_to(from + segment * along)
			if distance < best:
				best = distance
				best_tick = tick + along
		if best < INF:
			path_errors.append(best)
			lags.append((now - best_tick) * 1000.0 / rate)
		if render_ticks[index] >= 0.0:
			var truth: Variant = server_at(render_ticks[index])
			if truth != null:
				render_errors.append(point.distance_to(truth))
		# Second differences need three consecutive ticks.
		if index >= 2 and sample_ticks[index] - sample_ticks[index - 2] == 2:
			accelerations.append((drawn[index] - 2.0 * drawn[index - 1] + drawn[index - 2]).length() * rate * rate)
	for tick: int in server_path:
		if server_path.has(tick + 1) and server_path.has(tick + 2):
			server_accelerations.append((server_path[tick + 2] - 2.0 * server_path[tick + 1] + server_path[tick]).length() * rate * rate)
	var server_max := NetStats.percentile(server_accelerations, 1.0)
	var spike_limit := NetStats.percentile(server_accelerations, 0.95) * 3.0
	var spikes := 0
	for value in accelerations:
		if value > spike_limit:
			spikes += 1
	var has_interpolation := net.get("extrapolated_ticks") != null
	var depth_samples: PackedFloat32Array = net.get("depth_samples") if has_interpolation else PackedFloat32Array()
	return {
		"remote_samples": drawn.size(),
		"remote_path_mean_m": snappedf(NetStats.mean(path_errors), 0.01),
		"remote_path_p95_m": snappedf(NetStats.percentile(path_errors, 0.95), 0.01),
		"remote_path_max_m": snappedf(NetStats.percentile(path_errors, 1.0), 0.01),
		"remote_lag_ms": roundi(NetStats.mean(lags)),
		"remote_render_mean_m": snappedf(NetStats.mean(render_errors), 0.01) if not render_errors.is_empty() else -1.0,
		"remote_render_p95_m": snappedf(NetStats.percentile(render_errors, 0.95), 0.01) if not render_errors.is_empty() else -1.0,
		"remote_render_max_m": snappedf(NetStats.percentile(render_errors, 1.0), 0.01) if not render_errors.is_empty() else -1.0,
		"remote_accel_p95": roundi(NetStats.percentile(accelerations, 0.95)),
		"remote_accel_max": roundi(NetStats.percentile(accelerations, 1.0)),
		"server_accel_p95": roundi(NetStats.percentile(server_accelerations, 0.95)),
		"server_accel_max": roundi(server_max),
		"remote_spikes": snappedf(float(spikes) / maxi(1, accelerations.size()), 0.001),
		"extrapolated_share": snappedf(net.call("extrapolation_share"), 0.001) if has_interpolation else -1.0,
		"underruns": net.get("underruns") if has_interpolation else -1,
		"depth_min_ms": roundi(NetStats.percentile(depth_samples, 0.0)) if not depth_samples.is_empty() else -1,
		"depth_mean_ms": roundi(NetStats.mean(depth_samples)) if not depth_samples.is_empty() else -1,
	}


## Flies the input pattern for `seconds`; returns RTT samples taken every 0.5 s.
func fly(client: Sector, seconds: float, server: Sector = null) -> PackedFloat32Array:
	var rtts := PackedFloat32Array()
	speeds = PackedFloat32Array()
	gaps = PackedFloat32Array()
	depths = PackedFloat32Array()
	var id := client.multiplayer.get_unique_id()
	var started := Time.get_ticks_msec()
	var next_rtt := 500
	var cycle := 0.0
	for segment: Array in PATTERN:
		cycle += segment[0]
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
		if watched != null:
			# The watched pilot turns too, so its drawn path curves.
			watched.player.pending_look.x += segment[2] * (now - last) / 1000.0
		last = now
		if server != null:
			# Keep combat from interrupting the measurement; positions stay authoritative.
			for ship: Pilot in server.session.ships.values():
				ship.hull = ship.max_hull
				ship.shield = ship.max_shield
		speeds.append(client.player.velocity.length())
		if server != null and server.session.ships.has(id):
			gaps.append(client.player.position.distance_to(server.session.ships[id].position))
			if server.session.input_buffers.has(id):
				depths.append(server.session.input_buffers[id].depth())
		if now - started >= next_rtt:
			next_rtt += 500
			rtts.append(client.session.net_stats.rtt_ms)
		await process_frame
	return rtts


func release_inputs() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)


func print_table(results: Array[Dictionary]) -> void:
	print("\nAdded RTT is split evenly per direction (100 ms = +50 ms each way); loss and duplication apply both ways.")
	print("| Added RTT | Loss | RTT | Speed | Client up | Client down | Server to client | Snapshot jitter mean / p95 / max | Sim error mean / p95 / max | Visual offset mean / p95 / max | Gap to server now mean / p95 | Replay mean / max | Server buffer | Inputs sent / applied / lost | Late / dropped / starved |")
	print("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	for row: Dictionary in results:
		var jitter := "" if row["jitter_ms"] == 0.0 else " ± %d" % row["jitter_ms"]
		print("| %d%s ms | %s%% | %.0f ms | %.1f m/s | %.1f KB/s | %.1f KB/s | %.1f KB/s | %.1f / %.1f / %.1f ms | %.2f / %.2f / %.2f m | %.2f / %.2f / %.2f m | %.2f / %.2f m | %.1f / %d | %.1f | %d / %d / %d | %d / %d / %d |" % [
			row["rtt_added_ms"], jitter, str(row["loss_percent"]), row["rtt_ms"], row["speed_mps"],
			row["up_bps"] / 1000.0, row["down_bps"] / 1000.0, row["server_bps"] / 1000.0,
			row["jitter_mean_ms"], row["jitter_p95_ms"], row["jitter_max_ms"],
			row["error_mean_m"], row["error_p95_m"], row["error_max_m"],
			row["correction_mean_m"], row["correction_p95_m"], row["correction_max_m"],
			row["gap_mean_m"], row["gap_p95_m"], row["replay_mean"], row["replay_max"], row["depth_mean"],
			row["inputs_sent"], row["inputs_applied"], row["inputs_lost"],
			row["inputs_late"], row["inputs_dropped"], row["inputs_starved"]])


func print_remote_table(results: Array[Dictionary]) -> void:
	if watched == null:
		return
	print("\nRemote smoothness: the measured client watching one extra pilot, sampled every physics tick.")
	print("| Added RTT | Loss | Path error mean / p95 / max | Lag behind server | Render-time error mean / p95 / max | Drawn accel p95 / max | Server accel p95 / max | Spikes | Extrapolated | Underruns | Buffer depth min / mean |")
	print("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	for row: Dictionary in results:
		var jitter := "" if row["jitter_ms"] == 0.0 else " ± %d" % row["jitter_ms"]
		var render := "-" if row["remote_render_mean_m"] < 0.0 else "%.2f / %.2f / %.2f m" % [row["remote_render_mean_m"], row["remote_render_p95_m"], row["remote_render_max_m"]]
		var extrapolated := "-" if row["extrapolated_share"] < 0.0 else "%.1f%%" % (row["extrapolated_share"] * 100.0)
		var depth := "-" if row["depth_mean_ms"] < 0 else "%d / %d ms" % [row["depth_min_ms"], row["depth_mean_ms"]]
		print("| %d%s ms | %s%% | %.2f / %.2f / %.2f m | %d ms | %s | %d / %d m/s² | %d / %d m/s² | %.1f%% | %s | %s | %s |" % [
			row["rtt_added_ms"], jitter, str(row["loss_percent"]),
			row["remote_path_mean_m"], row["remote_path_p95_m"], row["remote_path_max_m"], row["remote_lag_ms"], render,
			row["remote_accel_p95"], row["remote_accel_max"], row["server_accel_p95"], row["server_accel_max"],
			row["remote_spikes"] * 100.0, extrapolated, "-" if row["underruns"] < 0 else str(row["underruns"]), depth])
