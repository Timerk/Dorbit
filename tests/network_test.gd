extends SceneTree
## Real ENet peers with separate multiplayer APIs and physics worlds.

var failures: int = 0
var checks: int = 0
var worlds: Array[SubViewport] = []


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func make_sector(label: String, dedicated: bool = false) -> Sector:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	root.add_child(viewport)
	worlds.append(viewport)
	set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var sector := preload("res://scenes/sector.tscn").instantiate()
	sector.dedicated_server = dedicated
	sector.server_port = 24683
	sector.client_only = false
	viewport.add_child(sector)
	sector.set_physics_process(false)
	return sector


func settle(seconds: float = 0.15) -> void:
	await create_timer(seconds).timeout


func run() -> void:
	var host := make_sector("Host")
	var client := make_sector("Client")
	var late := make_sector("Late")
	await settle()
	check(host.session.host(24678) == OK, "Host opens an ENet server")
	check(client.session.join("127.0.0.1", 24678) == OK, "Client starts connecting")
	await settle(0.5)
	check(client.session.active, "Client connects to host")
	check(host.session.ships.size() == 2 and client.session.ships.size() == 2, "Both peers receive the same roster")
	if host.session.ships.size() != 2:
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	check(host.session.ships[id].position != host.player.position, "Players spawn in separate positions")
	check(host.alien.alive and client.alien.alive and not client.alien.simulation_authority, "Shared alien is simulated only by the host")
	check(client.player.camera.current, "The local camera stays active after remote ships spawn")
	var start := host.session.ships[id].position
	client.session.command_flight.rpc_id(1, Vector3(0, 0, -99), Vector3.ZERO, true)
	await settle()
	for frame in range(12):
		host.session.tick(1.0 / 60.0)
		await physics_frame
	check(host.session.ships[id].position.z < start.z, "Client commands move its ship on the host")
	check(host.player.position.is_equal_approx(Sector.SPAWN_POSITION), "Client commands cannot move the host player")
	check(host.session.commands[id]["movement"].length() <= 1.0, "Host bounds oversized movement commands")
	check(host.session.ships[id].energy < 100, "Host controls boost consumption")
	await settle()
	check(client.session.received_snapshot, "Client receives authoritative snapshots")
	check(client.player.energy < 100, "Host boost energy reaches the client")
	var command_before: Dictionary = host.session.commands[id].duplicate()
	client.session.command_flight.rpc_id(1, Vector3(NAN, 0, 0), Vector3.ZERO, true)
	await settle()
	check(host.session.commands[id] == command_before, "Host rejects non-finite commands")
	await settle(0.6)
	for frame in range(30):
		host.session.tick(1.0 / 60.0)
	check(host.session.ships[id].velocity.is_zero_approx(), "Missing commands time out and brake the ship")
	check(late.session.join("127.0.0.1", 24678) == OK, "A late player starts joining")
	await settle(0.5)
	check(host.session.ships.size() == 3 and client.session.ships.size() == 3 and late.session.ships.size() == 3, "Late join replicates all players to all peers")
	host.set_paused(true)
	client.session.command_flight.rpc_id(1, Vector3(0, 1, 0), Vector3.ZERO, false)
	await settle()
	var before_pause := host.session.ships[id].position
	host._physics_process(0.1)
	check(host.session.ships[id].position.y > before_pause.y, "Host menu does not pause remote players")
	client.session.disconnect_session("Test leave")
	await settle()
	check(host.session.ships.size() == 2 and late.session.ships.size() == 2, "Leaving removes the remote ship everywhere")
	check(client.alien.alive and not client.session.active, "Leaving restores the solo encounter")
	check(client.session.join("127.0.0.1", 24678) == OK, "A disconnected player can reconnect")
	await settle(0.5)
	check(host.session.ships.size() == 3 and client.session.ships.size() == 3, "Reconnect creates a fresh roster")
	host.session.disconnect_session("Host leaving")
	await settle(0.5)
	check(not client.session.active and not late.session.active, "Host disconnect returns all clients to solo")
	check(client.session.menu.visible and client.alien.alive, "Host disconnect shows status and restores solo gameplay")
	check(client.session.join("", 24678) == ERR_INVALID_PARAMETER, "An empty address is rejected")
	client.session.join("127.0.0.1", 24679)
	client.session.tick(FlightSession.CONNECT_TIMEOUT + 1.0)
	check(not client.session.connecting and client.session.menu.visible, "Unreachable host times out with a recoverable menu")
	finish()


func finish() -> void:
	print("Network checks: %d passed, %d failed" % [checks - failures, failures])
	for viewport in worlds:
		viewport.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
