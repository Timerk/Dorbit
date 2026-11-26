extends "res://tests/network_test.gd"
## Measures server snapshot traffic with ten pilots and five aliens on M1.
## Measures ENet host counters on every schema and world payloads on schema 26+.

const SNAPSHOTS := 100


func run() -> void:
	var server := make_sector("TrafficServer", true, 24871)
	server.multiplayer.auth_timeout = 15.0
	var clients: Array[Sector] = []
	for index in range(10):
		var client := make_sector("TrafficClient%d" % index)
		client.session.credential_id = "pilot%d" % index
		client.session.credential_token = test_token(index)
		client.multiplayer.auth_timeout = 15.0
		clients.append(client)
	for client in clients:
		client.session.join("127.0.0.1", test_port(24871))
	var deadline := Time.get_ticks_msec() + 20000
	while (server.session.ships.size() < 10 or clients.any(func(peer: Sector): return not peer.session.active)) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(server.session.ships.size() == 10, "Ten pilots join")
	var on_map := server.world_aliens.values().filter(func(alien: Alien): return alien.map_id == 0 and alien.alive).size()
	check(on_map == 5, "Five living aliens share M1")
	# Warm-up delivers join state; the measurement covers steady-state ticks only.
	deadline = Time.get_ticks_msec() + 8000
	while clients.any(func(peer: Sector): return not peer.session.received_snapshot) and Time.get_ticks_msec() < deadline:
		server.session.send_snapshot()
		await process_frame
	for frame in range(20):
		server.session.send_snapshot()
		await process_frame
		acknowledge(clients)
	await settle(0.3)
	var host: ENetConnection = (server.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var before := payload_counters(server)
	var moved := 0
	for index in range(SNAPSHOTS):
		# Keep every pilot and alien moving so no entity state is repeated.
		for ship: Pilot in server.session.ships.values():
			ship.position += Vector3(0.25, 0.1, -0.2)
			ship.rotation.y = wrapf(ship.rotation.y + 0.05, -PI, PI)
		for alien: Alien in server.world_aliens.values():
			alien.position += Vector3(-0.2, 0.05, 0.3)
		server.session.send_snapshot()
		moved += 1
		await process_frame
		acknowledge(clients)
	await settle(0.3)
	var bytes := host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var packets := host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var per_client_snapshot := float(bytes) / moved / clients.size()
	var result := {
		"pilots": server.session.ships.size(), "aliens_on_map": on_map, "snapshots": moved,
		"enet_bytes_per_client_per_snapshot": snappedf(per_client_snapshot, 0.1),
		"enet_bytes_per_client_per_second_at_20hz": roundi(per_client_snapshot * 20),
		"enet_packets_per_client_per_snapshot": snappedf(float(packets) / moved / clients.size(), 0.01),
		"client_kbit_per_second_at_20hz": snappedf(per_client_snapshot * 20 * 8 / 1000.0, 0.1),
		"server_mbit_per_second_at_20hz": snappedf(float(bytes) / moved * 20 * 8 / 1_000_000.0, 0.01),
	}
	if not before.is_empty():
		var after := payload_counters(server)
		var payload_per_tick := float(after["bytes"] - before["bytes"]) / moved / clients.size()
		result["world_bytes_per_client_per_snapshot"] = snappedf(payload_per_tick, 0.1)
		result["world_bytes_per_client_per_second_at_20hz"] = roundi(payload_per_tick * 20)
		result["full_fallbacks"] = after["full"] - before["full"]
		result["delta_share"] = 1.0 - float(result["full_fallbacks"]) / moved / clients.size()
	print("SNAPSHOT_TRAFFIC=", JSON.stringify(result))
	finish()


func acknowledge(clients: Array[Sector]) -> void:
	# This benchmark drives snapshots directly with client simulation disabled.
	for client in clients:
		if client.session.has_method("send_snapshot_ack"):
			client.session.call("send_snapshot_ack")


func payload_counters(server: Sector) -> Dictionary:
	var traffic: Variant = server.session.get("snapshot_traffic")
	if traffic == null:
		return {}
	var result := {"bytes": 0, "full": 0}
	for viewer in traffic.values():
		result["bytes"] += viewer.total_bytes
		result["full"] += viewer.full_fallbacks
	return result

