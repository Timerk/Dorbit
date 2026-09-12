class_name FlightSession
extends Node
## Session transport and host-simulated movement for the shared encounter.

const PORT: int = 24567
const MAX_PLAYERS: int = 10
const COMMAND_TIMEOUT: float = 0.5
const CONNECT_TIMEOUT: float = 10.0

var sector: Sector
var active: bool = false
var connecting: bool = false
var status: String = "Enter the server address to connect."
var ships: Dictionary[int, Pilot] = {}
var commands: Dictionary[int, Dictionary] = {}
var goals: Dictionary[int, Dictionary] = {}
var send_clock: float = 0.0
var connect_clock: float = 0.0
var received_snapshot: bool = false
var snapshot_sequence: int = 0
var player_sequences: Dictionary[int, int] = {}
var alien_sequence: int = -1
var host_port: int = PORT
var menu: PanelContainer
var address: LineEdit
var status_label: Label
var host_button: Button
var join_button: Button
var leave_button: Button
var back_button: Button
var port_field: SpinBox
var combat: SessionCombat
var store: PilotStore
var pilot_ids: Dictionary[int, String] = {}
var challenges: Dictionary[int, PackedByteArray] = {}
# May also be supplied by a client UI. Neither value is a wallet selector in gameplay RPCs.
var credential_id: String = ""
var credential_token: String = ""
var auth_proof_sent: bool = false


func _ready() -> void:
	combat = SessionCombat.new()
	combat.name = "Combat"
	combat.session = self
	add_child(combat)
	multiplayer.auth_callback = authenticate
	multiplayer.auth_timeout = 5.0
	multiplayer.peer_authenticating.connect(begin_authentication)
	multiplayer.peer_authentication_failed.connect(authentication_failed)
	multiplayer.peer_disconnected.connect(peer_left)
	multiplayer.connected_to_server.connect(connected)
	multiplayer.connection_failed.connect(func(): disconnect_session("Connection failed. Check the server address and UDP port."))
	multiplayer.server_disconnected.connect(func(): disconnect_session("The server disconnected. Connect again when it is available."))
	if not sector.dedicated_server:
		build_menu()


func build_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	menu = PanelContainer.new()
	var panel_style := FlightHud.panel_style()
	panel_style.bg_color.a = 0.98
	menu.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -310
	menu.offset_right = 310
	menu.offset_top = -270
	menu.offset_bottom = 270
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	menu.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "CONNECT TO DORBIT"
	title.add_theme_font_size_override("font_size", 26)
	rows.add_child(title)
	var help := Label.new()
	help.text = "Join the same sector, alone or with friends.\nYour pilot's credits are saved on the server."
	rows.add_child(help)
	address = LineEdit.new()
	address.placeholder_text = "Server address"
	address.text = "127.0.0.1"
	rows.add_child(address)
	port_field = SpinBox.new()
	port_field.min_value = 1
	port_field.max_value = 65535
	port_field.value = PORT
	port_field.prefix = "UDP port: "
	rows.add_child(port_field)
	host_button = add_button(rows, "Host encounter (development)", func(): host())
	host_button.visible = not sector.client_only
	join_button = add_button(rows, "Connect", func(): join(address.text.strip_edges(), int(port_field.value)))
	leave_button = add_button(rows, "Disconnect", func(): disconnect_session("Disconnected. Choose a server to play."))
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 540
	rows.add_child(status_label)
	back_button = add_button(rows, "Back to flight", func(): menu.hide(); sector.set_paused(false))
	add_button(rows, "Quit to desktop", func(): get_tree().quit())
	menu.hide()


func add_button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func open_menu() -> void:
	sector.set_paused(true)
	menu.show()
	address.grab_focus()


func _process(_delta: float) -> void:
	if sector.dedicated_server:
		return
	status_label.text = status
	host_button.disabled = active or connecting
	join_button.disabled = active or connecting
	address.editable = not active and not connecting
	leave_button.disabled = not active and not connecting
	port_field.editable = not active and not connecting
	back_button.disabled = sector.client_only and not active


func host(port: int = PORT) -> Error:
	if active or connecting:
		return ERR_ALREADY_IN_USE
	if sector.dedicated_server:
		store = PilotStore.new()
		if not store.open(OS.get_environment("DORBIT_DATA_DIR")):
			status = store.error
			store.close()
			return ERR_FILE_CANT_OPEN
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS if sector.dedicated_server else MAX_PLAYERS - 1)
	if error != OK:
		if store != null:
			store.close()
		status = "Cannot host: UDP port %d may already be in use." % port
		return error
	multiplayer.server_relay = false
	multiplayer.multiplayer_peer = peer
	host_port = port
	start_flight()
	if not sector.dedicated_server:
		spawn(1, Sector.SPAWN_POSITION)
	status = "Server listening on UDP %d. Players: %d/%d" % [port, ships.size(), MAX_PLAYERS]
	if sector.dedicated_server:
		print(status)
	return OK


func join(host_address: String, port: int = PORT) -> Error:
	if active or connecting:
		return ERR_ALREADY_IN_USE
	if host_address.is_empty():
		status = "Enter the host address first."
		return ERR_INVALID_PARAMETER
	if credential_token.is_empty():
		var credential_path := OS.get_environment("DORBIT_PILOT_FILE")
		if not credential_path.is_empty() and FileAccess.file_exists(credential_path):
			var json := JSON.new()
			var credential: Variant = json.data if json.parse(FileAccess.get_file_as_string(credential_path)) == OK else null
			if credential is Dictionary and credential.get("id") is String and credential.get("token") is String:
				credential_id = credential["id"]
				credential_token = credential["token"]
	if sector.client_only and (not PilotStore.valid_id(credential_id) or not PilotStore.valid_hex(credential_token)):
		status = "Set DORBIT_PILOT_FILE to the pilot credential file supplied by the server operator."
		return ERR_UNAUTHORIZED
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_address, port)
	if error != OK:
		status = "Could not connect to that address."
		return error
	multiplayer.multiplayer_peer = peer
	connecting = true
	auth_proof_sent = false
	connect_clock = 0.0
	sector.set_paused(true)
	status = "Connecting to %s..." % host_address
	return OK


func begin_authentication(id: int) -> void:
	if not multiplayer.is_server():
		return
	var nonce := Crypto.new().generate_random_bytes(32) if sector.dedicated_server else PackedByteArray([0])
	challenges[id] = nonce
	multiplayer.send_auth(id, nonce)


func authenticate(id: int, data: PackedByteArray) -> void:
	if not multiplayer.is_server():
		if id == 1 and auth_proof_sent and data == PackedByteArray([1]):
			multiplayer.complete_auth(id)
			return
		if id != 1 or (data.size() != 32 and (sector.client_only or data != PackedByteArray([0]))):
			multiplayer.disconnect_peer(id)
			return
		var proof := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, credential_token.sha256_buffer(), data)
		multiplayer.send_auth(id, JSON.stringify({"id": credential_id, "proof": proof.hex_encode()}).to_utf8_buffer())
		auth_proof_sent = true
		return
	if not challenges.has(id):
		return
	var nonce := challenges[id]
	challenges.erase(id) # Each connection gets exactly one attempt with a fresh challenge.
	if sector.dedicated_server:
		var json := JSON.new()
		var response: Variant = json.data if data.size() <= 256 and json.parse(data.get_string_from_utf8()) == OK else null
		if not response is Dictionary or not response.get("id") is String or not response.get("proof") is String:
			multiplayer.disconnect_peer(id)
			return
		var pilot: String = response["id"]
		var proof: String = response["proof"]
		if pilot in pilot_ids.values() or not PilotStore.valid_hex(proof) or not store.verifies(pilot, nonce, proof.hex_decode()):
			multiplayer.disconnect_peer(id)
			return
		pilot_ids[id] = pilot
	multiplayer.send_auth(id, PackedByteArray([1]))
	multiplayer.complete_auth(id)


func authentication_failed(id: int) -> void:
	challenges.erase(id)
	pilot_ids.erase(id)
	if not multiplayer.is_server():
		disconnect_session.call_deferred("Authentication failed. Check credentials, matching builds, or an existing pilot login.")


# Called only by server combat, before applying any visible reward or charge.
func save_balances(balances: Dictionary[int, int]) -> bool:
	if not sector.dedicated_server:
		return true
	if store.failed:
		return false
	var wallets: Dictionary = {}
	for id: int in balances:
		if not pilot_ids.has(id):
			store.fail("Wallet update without an authenticated pilot.")
			break
		wallets[pilot_ids[id]] = balances[id]
	if not store.failed and store.commit(wallets):
		return true
	printerr("Persistence stopped the server: " + store.error)
	# Stop simulation immediately; close peers outside any active combat callback.
	sector.set_physics_process(false)
	get_tree().quit(1)
	return false


func start_flight() -> void:
	active = true
	connecting = false
	sector.select_target(null)
	combat.begin()
	if sector.dedicated_server:
		return
	sector.player.reset_health()
	sector.player.energy = 100.0
	sector.player.position = Sector.SPAWN_POSITION
	sector.player.rotation = Vector3.ZERO
	# Players cannot push each other, but can block weapon line of sight.
	sector.player.collision_mask = 1
	sector.set_paused(false)
	menu.hide()


func connected() -> void:
	start_flight()
	status = "Connected. Waiting for the host's sector..."
	ready_for_flight.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func ready_for_flight() -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if sector.dedicated_server and not pilot_ids.has(id):
		return
	if ships.has(id) or ships.size() >= MAX_PLAYERS:
		return
	for existing: int in ships:
		spawn.rpc_id(id, existing, ships[existing].position)
	var occupied: Array[int] = []
	for existing: int in ships:
		occupied.append(int(ships[existing].get_meta("spawn_slot", 0)))
	var slot := 1
	while slot in occupied:
		slot += 1
	var location := Vector3(-24 + (slot % 5) * 6, int(slot / 5) * 6, 33)
	spawn.rpc(id, location)
	ships[id].set_meta("spawn_slot", slot)
	status = "Server on UDP %d. Players: %d/%d" % [host_port, ships.size(), MAX_PLAYERS]
	if sector.dedicated_server:
		print(status)


@rpc("authority", "call_local", "reliable")
func spawn(id: int, location: Vector3) -> void:
	if ships.has(id):
		return
	var ship: Pilot
	if id == multiplayer.get_unique_id():
		ship = sector.player
	else:
		ship = Pilot.new()
		ship.render_enabled = not sector.dedicated_server
		sector.add_child(ship)
		if not sector.dedicated_server:
			ship.camera.current = false
		ship.collision_mask = 1
		ship.destroyed.connect(sector.on_destroyed)
		ship.fired.connect(sector.on_laser)
		if not sector.dedicated_server:
			var label := Label3D.new()
			label.text = "HOST" if id == 1 else "PILOT %d" % id
			label.position.y = 4.0
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 32
			ship.add_child(label)
	ship.position = location
	ships[id] = ship
	combat.add_player(id, location)
	if not sector.dedicated_server:
		sector.player.camera.make_current()


func peer_left(id: int) -> void:
	pilot_ids.erase(id)
	challenges.erase(id)
	if active and multiplayer.is_server():
		despawn(id)
		announce_departure.call_deferred(id)
		status = "Server on UDP %d. Players: %d/%d" % [host_port, ships.size(), MAX_PLAYERS]
		if sector.dedicated_server:
			print(status)


func announce_departure(id: int) -> void:
	# Let ENet finish processing simultaneous disconnects before notifying remaining clients.
	if not active or not multiplayer.is_server():
		return
	for peer_id in multiplayer.get_peers():
		var peer: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(peer_id)
		if peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			despawn.rpc_id(peer_id, id)


@rpc("authority", "call_local", "reliable")
func despawn(id: int) -> void:
	if ships.has(id) and ships[id] != sector.player:
		ships[id].queue_free()
	ships.erase(id)
	commands.erase(id)
	goals.erase(id)
	player_sequences.erase(id)
	combat.remove_player(id)


func tick(delta: float) -> void:
	if connecting:
		connect_clock += delta
		if connect_clock >= CONNECT_TIMEOUT:
			disconnect_session("Connection timed out. Check the server address and UDP port.")
		return
	if not active:
		return
	sector.toast_time = maxf(0.0, sector.toast_time - delta)
	if not sector.dedicated_server:
		sector.weapon_status = sector.player.firing_blocker(sector.target)
	var movement := Vector3.ZERO if sector.dedicated_server or sector.paused else sector.player.read_movement()
	var boost := not sector.dedicated_server and not sector.paused and Input.is_action_pressed("boost")
	send_clock += delta
	if multiplayer.is_server():
		if not sector.dedicated_server and sector.player.alive:
			sector.player.fly_command(delta, movement, boost)
		for id: int in ships:
			var ship := ships[id]
			if not ship.alive:
				continue
			if id != 1:
				var command: Dictionary = commands.get(id, {})
				var fresh: bool = not command.is_empty() and Time.get_ticks_msec() - command["time"] < COMMAND_TIMEOUT * 1000
				if fresh:
					ship.rotation = command["rotation"]
				ship.fly_command(delta, command["movement"] if fresh else Vector3.ZERO, command["boost"] if fresh else false)
			bound_ship(ship)
		combat.tick(delta)
		if send_clock >= 0.05:
			send_clock = 0.0
			send_snapshot()
	else:
		if not received_snapshot:
			connect_clock += delta
			if connect_clock >= CONNECT_TIMEOUT:
				disconnect_session("The server did not send a sector. Use matching client and server builds.")
			return
		if sector.player.alive:
			sector.player.fly_command(delta, movement, boost)
		bound_ship(sector.player)
		if send_clock >= 0.05:
			send_clock = 0.0
			command_flight.rpc_id(1, movement, sector.player.rotation, boost, sector.auto_fire and sector.target == sector.alien and not sector.paused, int(sector.player.get_meta("life", 0)), combat.encounter)
		combat.interpolate(delta)
		for id: int in goals:
			if not ships.has(id):
				continue
			var ship := ships[id]
			var goal: Dictionary = goals[id]
			if ship == sector.player:
				continue
			ship.position = ship.position.lerp(goal["position"], minf(1.0, delta * 15.0))
			var angles: Vector3 = goal["rotation"]
			ship.rotation.x = lerp_angle(ship.rotation.x, angles.x, minf(1.0, delta * 15.0))
			ship.rotation.y = lerp_angle(ship.rotation.y, angles.y, minf(1.0, delta * 15.0))


func send_snapshot() -> void:
	if multiplayer.get_peers().is_empty():
		return
	# Keep each datagram below the ENet MTU even at the ten-player limit.
	var state: Dictionary = {}
	snapshot_sequence += 1
	for id: int in ships:
		var ship := ships[id]
		state[id] = {"position": ship.position, "rotation": ship.rotation, "velocity": ship.velocity, "energy": ship.energy}
		state[id].merge(combat.pack_player(id))
		if state.size() == 2:
			snapshot.rpc(state, combat.pack_alien(), snapshot_sequence)
			state = {}
	if not state.is_empty():
		snapshot.rpc(state, combat.pack_alien(), snapshot_sequence)


func bound_ship(ship: Pilot) -> void:
	if ship.position.length() > 700.0:
		ship.position = ship.position.normalized() * 699.0
		ship.velocity = Vector3.ZERO


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func command_flight(movement: Vector3, angles: Vector3, boost: bool, fire: bool = false, life: int = 0, encounter: int = 0) -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not ships.has(id) or not movement.is_finite() or not angles.is_finite():
		return
	if not ships[id].alive or combat.records[id]["life"] != life:
		return
	commands[id] = {
		"movement": movement.limit_length(),
		"rotation": Vector3(clampf(angles.x, -1.48, 1.48), wrapf(angles.y, -PI, PI), 0),
		"boost": boost, "time": Time.get_ticks_msec(),
		"fire": fire, "encounter": encounter,
	}


@rpc("authority", "call_remote", "unreliable", 2)
func snapshot(state: Dictionary, alien_state: Dictionary, sequence: int) -> void:
	if not active:
		return
	# Chunks may arrive out of order. Reject stale state per entity, not per whole packet.
	if sequence > alien_sequence:
		combat.apply_alien(alien_state)
		alien_sequence = sequence
	for id: int in state:
		if not ships.has(id) or sequence <= player_sequences.get(id, -1):
			continue
		player_sequences[id] = sequence
		var data: Dictionary = state[id]
		goals[id] = data
		var ship := ships[id]
		var reset := combat.apply_player(id, data)
		if reset:
			ship.position = data["position"]
			ship.rotation = data["rotation"]
		ship.energy = data["energy"]
		if ship == sector.player:
			# Predict locally for immediate controls; reconcile against host position.
			var location: Vector3 = data["position"]
			if not received_snapshot or ship.position.distance_to(location) > 10.0:
				ship.position = location
			else:
				ship.position = ship.position.lerp(location, 0.2)
			ship.velocity = data["velocity"] if ship.alive else Vector3.ZERO
			received_snapshot = true
	status = "Connected. Players: %d/%d" % [ships.size(), MAX_PLAYERS]


func disconnect_session(message: String) -> void:
	active = false
	connecting = false
	pilot_ids.clear()
	challenges.clear()
	if store != null:
		store.close()
	combat.finish()
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for ship: Pilot in ships.values():
		if ship != sector.player:
			ship.queue_free()
	ships.clear()
	commands.clear()
	goals.clear()
	received_snapshot = false
	snapshot_sequence = 0
	player_sequences.clear()
	alien_sequence = -1
	send_clock = 0.0
	if sector.dedicated_server:
		status = message
		return
	sector.player.collision_mask = 3
	sector.respawn_player()
	sector.set_paused(true)
	status = message
	menu.show()


func _exit_tree() -> void:
	if store != null:
		store.close()
	if active or connecting:
		multiplayer.multiplayer_peer.close()
