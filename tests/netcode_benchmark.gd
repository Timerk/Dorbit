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
## - jitter_mean_ms / jitter_p95_ms / jitter_max_ms: |snapshot inter-arrival
##   time - 50 ms| as handled by the client, so frame timing is included.
## - error_*_m: distance from the predicted local ship to the authoritative
##   position in each applied snapshot, before reconciliation (mean/p95/max).
## - correction_*_m: distance reconciliation moved the local ship for each
##   snapshot. The current reconciliation applies it within one frame, so this
##   is also the visible jump beyond expected motion.
## - gap_*_m: distance from the client's ship to the server's current position
##   of the same ship, sampled every frame (possible because both run in this
##   process). Accurate prediction leads the server by the upstream delay times
##   speed; dragging the ship toward old snapshots shows up as error staying
##   small while this gap reflects the delay instead.
## - commands_sent / commands_applied: flight commands the client sent and the
##   server accepted; commands_lost is their difference, as a count and percent.
##   ENet discards duplicated and out-of-order sequenced commands itself.

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
	var results: Array[Dictionary] = []
	for condition: Array in conditions:
		results.append(await measure(server, client, everyone.size(), condition))
	release_inputs()
	print_table(results)
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
	var sent_before := net.commands_sent
	var applied_before: int = server.session.net_stats.commands_received.get(id, 0)
	var up_before := net.total_up_bytes
	var down_before := net.total_down_bytes
	var host: ENetConnection = (server.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var started := Time.get_ticks_usec()
	var frames := Engine.get_process_frames()
	var rtts := await fly(client, float(options["seconds"]), server)
	var seconds := (Time.get_ticks_usec() - started) / 1_000_000.0
	frames = Engine.get_process_frames() - frames
	net.keep_samples = false
	var server_bytes := host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var relay_stats: Dictionary = relay.stats()
	var sent := net.commands_sent - sent_before
	var applied: int = server.session.net_stats.commands_received.get(id, 0) - applied_before
	return {
		"rtt_added_ms": condition[0], "jitter_ms": condition[1], "loss_percent": condition[2], "duplicate_percent": condition[3],
		"seconds": snappedf(seconds, 0.01), "rtt_ms": snappedf(NetStats.mean(rtts), 0.1),
		"fps": roundi(frames / seconds), "speed_mps": snappedf(NetStats.mean(speeds), 0.1),
		"up_bps": roundi((net.total_up_bytes - up_before) / seconds),
		"down_bps": roundi((net.total_down_bytes - down_before) / seconds),
		"server_bps": roundi(relay_stats["down"]["received_bytes"] / seconds),
		"server_avg_bps": roundi(server_bytes / seconds / clients),
		"snapshots": net.jitter_samples.size(),
		"jitter_mean_ms": snappedf(NetStats.mean(net.jitter_samples), 0.1),
		"jitter_p95_ms": snappedf(NetStats.percentile(net.jitter_samples, 0.95), 0.1),
		"jitter_max_ms": snappedf(NetStats.percentile(net.jitter_samples, 1.0), 0.1),
		"error_mean_m": snappedf(NetStats.mean(net.error_samples), 0.01),
		"error_p95_m": snappedf(NetStats.percentile(net.error_samples, 0.95), 0.01),
		"error_max_m": snappedf(NetStats.percentile(net.error_samples, 1.0), 0.01),
		"correction_mean_m": snappedf(NetStats.mean(net.correction_samples), 0.01),
		"correction_p95_m": snappedf(NetStats.percentile(net.correction_samples, 0.95), 0.01),
		"correction_max_m": snappedf(NetStats.percentile(net.correction_samples, 1.0), 0.01),
		"gap_mean_m": snappedf(NetStats.mean(gaps), 0.01),
		"gap_p95_m": snappedf(NetStats.percentile(gaps, 0.95), 0.01),
		"commands_sent": sent, "commands_applied": applied, "commands_lost": sent - applied,
		"commands_lost_percent": snappedf(100.0 * (sent - applied) / maxi(sent, 1), 0.1),
		"relay_dropped": relay_stats["up"]["dropped_packets"] + relay_stats["down"]["dropped_packets"],
	}


var speeds := PackedFloat32Array()
var gaps := PackedFloat32Array()


## Flies the input pattern for `seconds`; returns RTT samples taken every 0.5 s.
func fly(client: Sector, seconds: float, server: Sector = null) -> PackedFloat32Array:
	var rtts := PackedFloat32Array()
	speeds = PackedFloat32Array()
	gaps = PackedFloat32Array()
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
		last = now
		if server != null:
			# Keep combat from interrupting the measurement; positions stay authoritative.
			for ship: Pilot in server.session.ships.values():
				ship.hull = ship.max_hull
				ship.shield = ship.max_shield
		speeds.append(client.player.velocity.length())
		if server != null and server.session.ships.has(id):
			gaps.append(client.player.position.distance_to(server.session.ships[id].position))
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
	print("| Added RTT | Loss | RTT | Speed | Client up | Client down | Server to client | Snapshot jitter mean / p95 / max | Prediction error mean / p95 / max | Correction mean / p95 / max | Gap to server now mean / p95 | Commands sent / applied / lost |")
	print("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	for row: Dictionary in results:
		var jitter := "" if row["jitter_ms"] == 0.0 else " ± %d" % row["jitter_ms"]
		print("| %d%s ms | %s%% | %.0f ms | %.1f m/s | %.1f KB/s | %.1f KB/s | %.1f KB/s | %.1f / %.1f / %.1f ms | %.2f / %.2f / %.2f m | %.2f / %.2f / %.2f m | %.2f / %.2f m | %d / %d / %d (%.1f%%) |" % [
			row["rtt_added_ms"], jitter, str(row["loss_percent"]), row["rtt_ms"], row["speed_mps"],
			row["up_bps"] / 1000.0, row["down_bps"] / 1000.0, row["server_bps"] / 1000.0,
			row["jitter_mean_ms"], row["jitter_p95_ms"], row["jitter_max_ms"],
			row["error_mean_m"], row["error_p95_m"], row["error_max_m"],
			row["correction_mean_m"], row["correction_p95_m"], row["correction_max_m"],
			row["gap_mean_m"], row["gap_p95_m"],
			row["commands_sent"], row["commands_applied"], row["commands_lost"], row["commands_lost_percent"]])
