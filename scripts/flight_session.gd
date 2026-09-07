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
var status: String = "Choose Host or enter the host address."
var ships: Dictionary[int, Pilot] = {}
var commands: Dictionary[int, Dictionary] = {}
var goals: Dictionary[int, Dictionary] = {}
var send_clock: float = 0.0
var connect_clock: float = 0.0
var received_snapshot: bool = false
var host_port: int = PORT
var menu: PanelContainer
var address: LineEdit
var status_label: Label
var host_button: Button
var join_button: Button
var leave_button: Button
var combat: SessionCombat


func _ready() -> void:
	combat = SessionCombat.new()
	combat.name = "Combat"
	combat.session = self
	add_child(combat)
	multiplayer.peer_disconnected.connect(peer_left)
	multiplayer.connected_to_server.connect(connected)
	multiplayer.connection_failed.connect(func(): disconnect_session("Connection failed. Check the address and UDP port 24567."))
	multiplayer.server_disconnected.connect(func(): disconnect_session("The host disconnected. You are back in solo mode."))
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
	menu.offset_top = -210
	menu.offset_bottom = 210
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	menu.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "SHARED ENCOUNTER"
	title.add_theme_font_size_override("font_size", 26)
	rows.add_child(title)
	var help := Label.new()
	help.text = "Hunt together with up to 10 players. Progress is session-only.\nUse a LAN / VPN host address, or forward UDP port 24567."
	rows.add_child(help)
	address = LineEdit.new()
	address.placeholder_text = "Host address"
	address.text = "127.0.0.1"
	rows.add_child(address)
	host_button = add_button(rows, "Host encounter", func(): host())
	join_button = add_button(rows, "Join host", func(): join(address.text.strip_edges()))
	leave_button = add_button(rows, "Leave session / return to solo", func(): disconnect_session("Returned to solo mode."))
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 540
	rows.add_child(status_label)
	add_button(rows, "Back to flight", func(): menu.hide(); sector.set_paused(false))
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
	status_label.text = status
	host_button.disabled = active or connecting
	join_button.disabled = active or connecting
	address.editable = not active and not connecting
	leave_button.disabled = not active and not connecting


func host(port: int = PORT) -> Error:
	if active or connecting:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		status = "Cannot host: UDP port %d may already be in use." % port
		return error
	multiplayer.multiplayer_peer = peer
	host_port = port
	start_flight()
	spawn(1, Sector.SPAWN_POSITION)
	status = "Hosting on UDP %d. Players: 1/%d" % [port, MAX_PLAYERS]
	return OK


func join(host_address: String, port: int = PORT) -> Error:
	if active or connecting:
		return ERR_ALREADY_IN_USE
	if host_address.is_empty():
		status = "Enter the host address first."
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_address, port)
	if error != OK:
		status = "Could not connect to that address."
		return error
	multiplayer.multiplayer_peer = peer
	connecting = true
	connect_clock = 0.0
	sector.set_paused(true)
	status = "Connecting to %s..." % host_address
	return OK


func start_flight() -> void:
	active = true
	connecting = false
	sector.select_target(null)
	combat.begin()
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
	status = "Hosting on UDP %d. Players: %d/%d" % [host_port, ships.size(), MAX_PLAYERS]


@rpc("authority", "call_local", "reliable")
func spawn(id: int, location: Vector3) -> void:
	if ships.has(id):
		return
	var ship: Pilot
	if id == multiplayer.get_unique_id():
		ship = sector.player
	else:
		ship = Pilot.new()
		sector.add_child(ship)
		ship.camera.current = false
		ship.collision_mask = 1
		ship.destroyed.connect(sector.on_destroyed)
		ship.fired.connect(sector.on_laser)
		var label := Label3D.new()
		label.text = "HOST" if id == 1 else "PILOT %d" % id
		label.position.y = 4.0
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 32
		ship.add_child(label)
	ship.position = location
	ships[id] = ship
	combat.add_player(id, location)
	sector.player.camera.make_current()


func peer_left(id: int) -> void:
	if active and multiplayer.is_server():
		despawn.rpc(id)
		status = "Hosting on UDP %d. Players: %d/%d" % [host_port, ships.size(), MAX_PLAYERS]


@rpc("authority", "call_local", "reliable")
func despawn(id: int) -> void:
	if ships.has(id) and ships[id] != sector.player:
		ships[id].queue_free()
	ships.erase(id)
	commands.erase(id)
	goals.erase(id)
	combat.remove_player(id)


func tick(delta: float) -> void:
	if connecting:
		connect_clock += delta
		if connect_clock >= CONNECT_TIMEOUT:
			disconnect_session("Connection timed out. Check the host address and UDP port 24567.")
		return
	if not active:
		return
	sector.toast_time = maxf(0.0, sector.toast_time - delta)
	sector.weapon_status = sector.player.firing_blocker(sector.target)
	var movement := Vector3.ZERO if sector.paused else sector.player.read_movement()
	var boost := not sector.paused and Input.is_action_pressed("boost")
	send_clock += delta
	if multiplayer.is_server():
		if sector.player.alive:
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
			var state: Dictionary = {}
			for id: int in ships:
				var ship := ships[id]
				state[id] = {"position": ship.position, "rotation": ship.rotation, "velocity": ship.velocity, "energy": ship.energy}
				state[id].merge(combat.pack_player(id))
			if not multiplayer.get_peers().is_empty():
				snapshot.rpc(state, combat.pack_alien())
	else:
		if not received_snapshot:
			connect_clock += delta
			if connect_clock >= CONNECT_TIMEOUT:
				disconnect_session("The host did not send a sector. Use the same game version on both PCs.")
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


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func snapshot(state: Dictionary, alien_state: Dictionary) -> void:
	if not active:
		return
	combat.apply_alien(alien_state)
	goals.clear()
	for id: int in state:
		if not ships.has(id):
			continue
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
	send_clock = 0.0
	sector.player.collision_mask = 3
	sector.respawn_player()
	sector.set_paused(true)
	status = message
	menu.show()


func _exit_tree() -> void:
	if active or connecting:
		multiplayer.multiplayer_peer.close()
