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
var status: String = "Choose a server and connect."
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
var preferences := ConnectionPreferences.new()
var attempted_address: String = ""
var attempted_port: int = PORT
var preference_label: Label
var combat: SessionCombat


func _ready() -> void:
	combat = SessionCombat.new()
	combat.name = "Combat"
	combat.session = self
	add_child(combat)
	multiplayer.peer_disconnected.connect(peer_left)
	multiplayer.connected_to_server.connect(connected)
	multiplayer.connection_failed.connect(func(): disconnect_session("Connection failed. Check the address and UDP port, then try again."))
	multiplayer.server_disconnected.connect(func(): disconnect_session("Connection to the server was lost. You can try connecting again."))
	if not sector.dedicated_server:
		build_menu()


func build_menu() -> void:
	preferences.load_from()
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
	help.text = "Join the same sector, alone or with friends.\nProgress is session-only in this server test build."
	rows.add_child(help)
	var address_label := Label.new()
	address_label.text = "Server address"
	rows.add_child(address_label)
	address = LineEdit.new()
	address.placeholder_text = "Server address"
	address.text = preferences.address
	rows.add_child(address)
	port_field = SpinBox.new()
	port_field.min_value = 1
	port_field.max_value = 65535
	port_field.value = preferences.port
	port_field.prefix = "UDP port: "
	rows.add_child(port_field)
	host_button = add_button(rows, "Host encounter (development)", func(): host())
	host_button.visible = not sector.client_only
	join_button = add_button(rows, "Connect", connect_from_menu)
	leave_button = add_button(rows, "Disconnect", func(): disconnect_session("Connection cancelled." if connecting else "Disconnected. You can connect again when ready."))
	address.text_submitted.connect(func(_text: String): connect_from_menu())
	port_field.get_line_edit().text_submitted.connect(func(_text: String): connect_from_menu.call_deferred())
	preference_label = Label.new()
	preference_label.text = "Remembers the last successful connection on this device."
	preference_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(preference_label)
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
	if active:
		back_button.grab_focus()
	elif connecting:
		leave_button.grab_focus()
	else:
		join_button.grab_focus()


func _process(_delta: float) -> void:
	if sector.dedicated_server:
		return
	status_label.text = status
	if not attempted_address.is_empty():
		status_label.text = "%s | UDP %d\n%s" % [attempted_address, attempted_port, status]
	if connecting:
		status_label.text += "\nWaiting for the server, up to %d seconds." % int(CONNECT_TIMEOUT)
	preference_label.text = "Could not save this connection for the next launch." if preferences.save_failed else "Remembers the last successful connection on this device."
	join_button.text = "Connect again" if not attempted_address.is_empty() else "Connect"
	leave_button.text = "Cancel connection" if connecting else "Disconnect"
	host_button.disabled = active or connecting
	join_button.disabled = active or connecting
	address.editable = not active and not connecting
	leave_button.disabled = not active and not connecting
	port_field.editable = not active and not connecting
	back_button.disabled = sector.client_only and not active


func connect_from_menu() -> void:
	port_field.apply()
	join(address.text.strip_edges(), int(port_field.value))


func host(port: int = PORT) -> Error:
	if active or connecting:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS if sector.dedicated_server else MAX_PLAYERS - 1)
	if error != OK:
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
	host_address = host_address.strip_edges()
	attempted_address = host_address
	attempted_port = port
	address.text = host_address
	port_field.value = port
	if host_address.is_empty():
		status = "Enter a server address first."
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_address, port)
	if error != OK:
		status = "Could not start the connection: %s. Check the address and UDP port." % error_string(error)
		return error
	multiplayer.multiplayer_peer = peer
	connecting = true
	connect_clock = 0.0
	sector.set_paused(true)
	status = "Connecting..."
	leave_button.disabled = false
	leave_button.grab_focus()
	return OK


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
	if sector.client_only:
		preferences.remember(attempted_address, attempted_port)
	start_flight()
	status = "Connected. Waiting for the server's sector..."
	ready_for_flight.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func ready_for_flight() -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
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
			disconnect_session("No connection after %d seconds. Check the address and UDP port, then try again." % int(CONNECT_TIMEOUT))
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
				disconnect_session("Connected, but no sector arrived. Check that client and server builds match, then try again.")
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
	join_button.disabled = false
	join_button.grab_focus()


func _exit_tree() -> void:
	if active or connecting:
		multiplayer.multiplayer_peer.close()
