class_name FlightSession
extends Node
## Session transport and host-simulated movement for the shared encounter.

const PORT: int = 24567
const MAX_PLAYERS: int = 10
## Server ticks a pilot's latest fire intent stays valid without new input packets.
const INPUT_TIMEOUT_TICKS: int = InputBuffer.TIMEOUT_TICKS
const CONNECT_TIMEOUT: float = 10.0
# Bump when packet contents or shared physics change without an RPC signature change.
const NETWORK_SCHEMA: int = 26
## ENet packet throttle for every server/client peer: [interval ms,
## acceleration, deceleration]. ENet's default deceleration (2) discards
## unreliable packets at the sender whenever one round trip exceeds the
## previous interval's by twice its variance, which a steady high-latency link
## does constantly. Dorbit's unreliable traffic is small and paced, and inputs
## are redundant, so deceleration 0 keeps the throttle open. Reliable traffic
## keeps ENet's own windowing and resends.
const ENET_THROTTLE := [5000, 2, 0]
## Laser and explosion points within this distance (m) of an entity's newest
## received position are moved onto where that entity is drawn.
const ANCHOR_RADIUS := 8.0
const BUILD_MISMATCH := "Client and server builds are incompatible. Use the matching client and server from the same release or PR preview."

var sector: Sector
var active: bool = false
var connecting: bool = false
var status: String = "Choose a server and connect."
var ships: Dictionary[int, Pilot] = {}
## Server: each pilot's latest intent from its newest input packet:
## {movement, rotation, boost, fire, encounter, target, seq, tick}. Movement
## comes from input_buffers; this keeps fire and targeting.
var commands: Dictionary[int, Dictionary] = {}
## Server: buffered flight inputs per pilot, consumed one per tick.
var input_buffers: Dictionary[int, InputBuffer] = {}
## Server simulation tick, advanced once per server physics tick.
var server_tick: int = 0
## Client: local pilot inputs, prediction and reconciliation.
var prediction := FlightPrediction.new()
## Client: newest applied state of each pilot, keyed by peer.
var goals: Dictionary[int, Dictionary] = {}
## Client: estimated server time and the render time remote entities use.
var clock := ServerClock.new()
## Client: interpolation buffers of remote pilots, keyed by peer. Cleared
## with `goals` at every discontinuity.
var remote_buffers: Dictionary[int, SnapshotBuffer] = {}
var send_clock: float = 0.0
var connect_clock: float = 0.0
var received_snapshot: bool = false
var snapshot_sequence: int = 0
var sent_snapshots: Dictionary[int, SnapshotHistory] = {}
var received_snapshots := SnapshotHistory.new()
var snapshot_traffic: Dictionary[int, NetStats.SnapshotTraffic] = {}
var player_sequences: Dictionary[int, int] = {}
var alien_sequences: Dictionary[int, int] = {}
# Client caches of rarely changing fields as [revision, profile], keyed by peer or alien ID.
var player_profiles: Dictionary[int, Array] = {}
var alien_profiles: Dictionary[int, Array] = {}
# Server: profile revisions each viewer has been sent during its current map visit.
var sent_profiles: Dictionary[int, Dictionary] = {}
# Server: [revision, profile] per public (0), owner (1) or alien (2) profile ID.
var profile_revisions: Dictionary[Vector2i, Array] = {}
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
var store: PilotStore
var benchmark_timing := false
var benchmark_phases: Dictionary = {}
var pilot_ids: Dictionary[int, String] = {}
var challenges: Dictionary[int, PackedByteArray] = {}
# May also be supplied by a client UI. Neither value is a wallet selector in gameplay RPCs.
var credential_id: String = ""
var credential_token: String = ""
var auth_proof_sent: bool = false
var incompatible_build: bool = false
var shutdown_file: String = ""
var preview_tools_enabled: bool = false
var preview_pilots: PackedStringArray = []
var lab_clock: float = 0.0
var jump_pending := false
var jump_cover: CanvasLayer
var jump_until: Dictionary[int, int] = {}
## Netcode measurements; see NetStats. Clients feed and the F8 overlay reads them.
var net_stats := NetStats.new()
## Debug relay between this client and the server. Its conditions persist
## between connections; it runs only while a connection uses it.
var net_simulator := NetSimulator.new()
## Route the next join() through net_simulator. Off for normal play.
var use_net_simulator := false


func _ready() -> void:
	if sector.dedicated_server:
		shutdown_file = OS.get_environment("DORBIT_SHUTDOWN_FILE")
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
	multiplayer.connection_failed.connect(func(): disconnect_session("Connection failed. Check the address and UDP port, then try again."))
	multiplayer.server_disconnected.connect(func(): disconnect_session("Connection to the server was lost. You can try connecting again."))
	if not sector.dedicated_server:
		use_net_simulator = net_simulator.configure_from_args(OS.get_cmdline_user_args())
		build_menu()
	if "--print-protocol" in OS.get_cmdline_user_args():
		# Operator/CI diagnostic. No network connection or pilot credentials are needed.
		print("DORBIT_PROTOCOL=" + protocol_fingerprint())
		get_tree().quit()


func build_menu() -> void:
	preferences.load_from()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	menu = PanelContainer.new()
	layer.add_child(menu)
	StationUi.frame(menu, Vector2(500, 430))
	var page := StationUi.rows(menu, 16)
	page.add_theme_constant_override("separation", 10)
	StationUi.header(page, "CONNECTION", "SYSTEM")
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var form := StationUi.card(body)
	form.custom_minimum_size.x = 520
	form.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var rows := StationUi.rows(form, 22)
	rows.add_theme_constant_override("separation", 12)
	StationUi.heading(rows, "SERVER ADDRESS", 16, StationUi.MUTED)
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
	var actions := HBoxContainer.new()
	rows.add_child(actions)
	join_button = add_button(actions, "CONNECT", connect_from_menu)
	StationUi.primary(join_button)
	leave_button = add_button(actions, "DISCONNECT", func(): disconnect_session("Connection cancelled." if connecting else "Disconnected. You can connect again when ready."))
	leave_button.custom_minimum_size.y = 48
	address.text_submitted.connect(func(_text: String): connect_from_menu())
	port_field.get_line_edit().text_submitted.connect(func(_text: String): connect_from_menu.call_deferred())
	preference_label = StationUi.text(rows, "", 16, FlightHud.RED)
	status_label = StationUi.text(rows, "", 18, StationUi.MUTED)
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var footer := HBoxContainer.new()
	rows.add_child(footer)
	back_button = add_button(footer, "Back", func(): menu.hide(); sector.set_paused(false))
	add_button(footer, "Settings", func(): sector.settings_menu.open(true))
	add_button(footer, "Quit to desktop", func(): get_tree().quit())
	menu.hide()


func layout_menu() -> void:
	if is_instance_valid(sector.main_menu) and sector.main_menu.visible:
		sector.main_menu.fit_panel(menu, Vector2(500, 430))
		return
	StationUi.set_panel_style(menu, StationUi.window_style())
	var dimensions := Vector2(500, 430).max(menu.get_combined_minimum_size())
	var viewport_size := sector.get_viewport().get_visible_rect().size
	var area := viewport_size - Vector2(32, 32)
	var factor := minf(1.0, minf(area.x / dimensions.x, area.y / dimensions.y))
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	menu.size = dimensions
	menu.scale = Vector2.ONE * factor
	menu.position = (viewport_size - dimensions * factor) / 2


func add_button(parent: Node, title: String, action: Callable) -> Button:
	var button := StationUi.button(parent, title, action)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func open_menu() -> void:
	if is_instance_valid(sector.main_menu) and sector.main_menu.route_page("connection"):
		return
	sector.set_paused(true)
	if is_instance_valid(sector.settings_menu):
		sector.settings_menu.dismiss()
	menu.show()
	layout_menu()
	if active:
		back_button.grab_focus()
	elif connecting:
		leave_button.grab_focus()
	else:
		join_button.grab_focus()


func _process(_delta: float) -> void:
	if sector.dedicated_server:
		if not shutdown_file.is_empty() and FileAccess.file_exists(shutdown_file):
			print("Server shutdown requested; closing pilot store.")
			get_tree().quit()
		return
	if active and not multiplayer.is_server():
		net_stats.sample_transport(multiplayer.multiplayer_peer)
	if menu.visible:
		layout_menu()
	status_label.text = status
	if not attempted_address.is_empty():
		status_label.text = "%s | UDP %d\n%s" % [attempted_address, attempted_port, status]
	if net_simulator.is_running():
		status_label.text += "\nRouted through the network simulator (debug)."
	if connecting:
		status_label.text += "\nWaiting for the server, up to %d seconds." % int(CONNECT_TIMEOUT)
	preference_label.text = "Could not save this connection for the next launch." if preferences.save_failed else "Remembers the last successful connection on this device."
	preference_label.visible = preferences.save_failed
	host_button.visible = not sector.client_only
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
	if sector.dedicated_server:
		# Read only server configuration. Client environment variables grant no permissions.
		preview_tools_enabled = OS.get_environment("DORBIT_PREVIEW_TOOLS") == "1"
		preview_pilots = OS.get_environment("DORBIT_PREVIEW_PILOTS").split(",", false)
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
	sector.preflight = false
	start_flight()
	if not sector.dedicated_server:
		spawn(1, Sector.SPAWN_POSITION)
	status = "Server listening on UDP %d. Players: %d/%d" % [port, ships.size(), MAX_PLAYERS]
	if sector.dedicated_server:
		print(status)
	return OK


func can_grant_test_credits(id: int) -> bool:
	return sector.dedicated_server and active and multiplayer.is_server() and preview_tools_enabled and pilot_ids.has(id) and pilot_ids[id] in preview_pilots


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
	# The debug relay is opt-in; the menu and status keep the real address.
	var connect_address := host_address
	var connect_port := port
	if use_net_simulator:
		var relay_error := net_simulator.start(host_address, port)
		if relay_error != OK:
			status = "Could not start the network simulator: %s." % error_string(relay_error)
			return relay_error
		connect_address = "127.0.0.1"
		connect_port = net_simulator.listen_port
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(connect_address, connect_port)
	if error != OK:
		net_simulator.stop()
		status = "Could not start the connection: %s. Check the address and UDP port." % error_string(error)
		return error
	net_stats.reset()
	multiplayer.multiplayer_peer = peer
	connecting = true
	auth_proof_sent = false
	incompatible_build = false
	connect_clock = 0.0
	sector.set_paused(true)
	status = "Connecting..."
	leave_button.disabled = false
	leave_button.grab_focus()
	return OK


func rpc_signature(node: Node) -> Array:
	var config: Dictionary = {}
	var script: Script = node.get_script()
	while script != null:
		# Derived scripts take precedence over inherited RPC declarations.
		config.merge(script.get_rpc_config(), false)
		script = script.get_base_script()
	# StringName ordering depends on the runtime's interned names. Sort text so
	# release templates and editor/server runtimes hash the same RPC definitions.
	var names: Array[String] = []
	for method_name in config:
		names.append(str(method_name))
	names.sort()
	var signature: Array = []
	for method_name in names:
		var settings: Dictionary = config[method_name]
		for method in node.get_method_list():
			if method["name"] != method_name:
				continue
			var args: Array = []
			for argument in method["args"]:
				args.append([argument["type"], str(argument["class_name"])])
			signature.append([str(method_name), settings.get("rpc_mode", 0),
				settings.get("call_local", false), settings.get("transfer_mode", 0),
				settings.get("channel", 0), args, method["default_args"],
				method["return"]["type"], str(method["return"]["class_name"])])
			break
	return signature


func protocol_fingerprint(schema: int = NETWORK_SCHEMA) -> String:
	# Story progress travels as an index into the shared sequence.
	var step_ids: Array[String] = []
	for step in Story.STEPS:
		step_ids.append(step["id"])
	return JSON.stringify([schema, rpc_signature(self), rpc_signature(combat), step_ids]).sha256_text()


func begin_authentication(id: int) -> void:
	if not multiplayer.is_server():
		return
	configure_throttle(id)
	var nonce := Crypto.new().generate_random_bytes(32) if sector.dedicated_server else PackedByteArray([0])
	challenges[id] = nonce
	multiplayer.send_auth(id, JSON.stringify({"nonce": nonce.hex_encode(), "protocol": protocol_fingerprint()}).to_utf8_buffer())


func authenticate(id: int, data: PackedByteArray) -> void:
	if not multiplayer.is_server():
		if id == 1 and auth_proof_sent and data == PackedByteArray([1]):
			multiplayer.complete_auth(id)
			return
		if id != 1:
			multiplayer.disconnect_peer(id)
			return
		# Older servers send a binary nonce, which must not be decoded as UTF-8 JSON.
		if data.is_empty() or data.size() == 32 or data[0] != 123:
			incompatible_build = true
			disconnect_session.call_deferred(BUILD_MISMATCH)
			return
		var json := JSON.new()
		var challenge: Variant = json.data if data.size() <= 512 and json.parse(data.get_string_from_utf8()) == OK else null
		if not challenge is Dictionary or challenge.get("protocol", "") != protocol_fingerprint():
			incompatible_build = true
			disconnect_session.call_deferred(BUILD_MISMATCH)
			return
		var nonce_hex: Variant = challenge.get("nonce")
		if not nonce_hex is String or (not PilotStore.valid_hex(nonce_hex) and (sector.client_only or nonce_hex != "00")):
			multiplayer.disconnect_peer(id)
			return
		var proof := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, credential_token.sha256_buffer(), nonce_hex.hex_decode())
		multiplayer.send_auth(id, JSON.stringify({"id": credential_id, "proof": proof.hex_encode(), "protocol": protocol_fingerprint()}).to_utf8_buffer())
		auth_proof_sent = true
		return
	if not challenges.has(id):
		return
	var nonce := challenges[id]
	challenges.erase(id) # Each connection gets exactly one attempt with a fresh challenge.
	var json := JSON.new()
	var response: Variant = json.data if data.size() <= 512 and json.parse(data.get_string_from_utf8()) == OK else null
	if not response is Dictionary or response.get("protocol", "") != protocol_fingerprint():
		multiplayer.disconnect_peer(id)
		return
	if sector.dedicated_server:
		if not response.get("id") is String or not response.get("proof") is String:
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
		disconnect_session.call_deferred(BUILD_MISMATCH if incompatible_build else "Authentication failed. Check credentials, matching builds, or an existing pilot login.")


# Called only by server combat, before applying any visible reward or charge.
func save_balances(balances: Dictionary[int, int], contracts: Dictionary[int, Dictionary] = {}, research: Dictionary[int, int] = {}, stories: Dictionary[int, Dictionary] = {}) -> bool:
	if not sector.dedicated_server:
		return true
	if store.failed:
		return false
	var wallets: Dictionary = {}
	var saved_contracts: Dictionary = {}
	for id: int in balances:
		if not pilot_ids.has(id):
			store.fail("Wallet update without an authenticated pilot.")
			break
		wallets[pilot_ids[id]] = balances[id]
	for id: int in contracts:
		if not pilot_ids.has(id):
			store.fail("Contract update without an authenticated pilot.")
			break
		saved_contracts[pilot_ids[id]] = contracts[id]
	var earned: Dictionary = {}
	for id: int in research:
		if research[id] > 0 and pilot_ids.has(id):
			earned[pilot_ids[id]] = research[id]
	var saved_stories: Dictionary = {}
	for id: int in stories:
		if not pilot_ids.has(id):
			store.fail("Story update without an authenticated pilot.")
			break
		saved_stories[pilot_ids[id]] = stories[id]
	if not store.failed and store.commit(wallets, saved_contracts, {}, {}, {}, earned, saved_stories):
		return true
	stop_for_save_failure()
	return false


func stop_for_save_failure() -> void:
	printerr("Persistence stopped the server: " + store.error)
	# Stop simulation immediately; close peers outside any active combat callback.
	sector.set_physics_process(false)
	get_tree().quit(1)


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
	sector.player.map_id = 0
	sector.player.map_visit = 0
	prediction = FlightPrediction.new()
	prediction.reset(sector.player)
	sector.activate_map(0)
	# Players cannot push each other, but can block weapon line of sight.
	sector.player.collision_mask = 1
	sector.set_paused(sector.preflight)
	if not sector.preflight:
		sector.main_menu.hide()
		sector.main_menu.hide_pages()
	menu.hide()


## Applies ENET_THROTTLE to one ENet peer (ENet tells the other end too).
func configure_throttle(id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var peer := enet.get_peer(id)
	if peer != null:
		peer.throttle_configure(ENET_THROTTLE[0], ENET_THROTTLE[1], ENET_THROTTLE[2])


func connected() -> void:
	configure_throttle(1)
	if sector.client_only:
		preferences.remember(attempted_address, attempted_port)
	sector.preflight = sector.client_only
	start_flight()
	if sector.preflight:
		sector.main_menu.show_home()
	status = "Connected. Waiting for the server's sector..."
	ready_for_flight.rpc_id(1, sector.preflight)


@rpc("any_peer", "call_remote", "reliable")
func ready_for_flight(docked: bool = false) -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if sector.dedicated_server and not pilot_ids.has(id):
		return
	if ships.has(id) or ships.size() >= MAX_PLAYERS:
		return
	for existing: int in ships:
		if not ships[existing].get_meta("docked", false):
			spawn.rpc_id(id, existing, ships[existing].position, false, ships[existing].map_id)
	var occupied: Array[int] = []
	for existing: int in ships:
		occupied.append(int(ships[existing].get_meta("spawn_slot", 0)))
	var slot := 1
	while slot in occupied:
		slot += 1
	var location := Vector3(-24 + (slot % 5) * 6, int(slot / 5) * 6, 33)
	if docked:
		spawn(id, location, true)
		spawn.rpc_id(id, id, location, true)
	else:
		spawn.rpc(id, location)
	ships[id].set_meta("spawn_slot", slot)
	if can_grant_test_credits(id) and not store.preview_max_lab(pilot_ids[id], Skylab.now()):
		stop_for_save_failure()
		return
	combat.publish_inventory(id)
	combat.gate_state.rpc_id(id, combat.gate.state_for(id))
	combat.loot_state.rpc_id(id, loot_for_map(0), ships[id].map_visit)
	status = "Server on UDP %d. Players: %d/%d" % [host_port, ships.size(), MAX_PLAYERS]
	if sector.dedicated_server:
		print(status)


@rpc("authority", "call_local", "reliable")
func spawn(id: int, location: Vector3, docked: bool = false, map: int = 0) -> void:
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
		ship.fired.connect(sector.on_laser.bind(ship))
	ship.position = location
	ship.map_id = map
	ships[id] = ship
	remote_buffers.erase(id)
	combat.add_player(id, location)
	ship.set_meta("docked", docked)
	if docked:
		ship.hide()
		ship.collision_layer = 0
	if not sector.dedicated_server:
		ship.visible = ship.alive and not docked and map == sector.map_id
		ship.collision_layer = 2 if not docked and (ship.simulation_authority or ship.visible) else 0
		sector.player.camera.make_current()


func launch() -> void:
	if offline_main_menu() and sector.preflight and sector.player.alive:
		sector.preflight = false
		sector.main_menu.hide()
		sector.main_menu.hide_pages()
		menu.hide()
		sector.set_paused(false)
		return
	if active and sector.preflight and sector.player.alive and received_snapshot and not combat.inventory.is_empty() and not combat.station_pending:
		launch_request.rpc_id(1)


func quit_to_menu() -> void:
	if offline_main_menu():
		open_offline_main_menu()
		return
	if active and sector.offline and multiplayer.is_server():
		# Listen hosting is a temporary development fixture, without a docked inventory.
		disconnect_session("Development host stopped.")
		open_offline_main_menu()
		return
	if active and not sector.preflight and not multiplayer.is_server():
		sector.set_paused(true)
		dock_request.rpc_id(1)


func offline_main_menu() -> bool:
	return sector.offline and not active and not connecting


func open_offline_main_menu() -> void:
	if sector.player.map_id != 0:
		sector.player.map_id = 0
		sector.player.map_visit += 1
		sector.player.position = Sector.SPAWN_POSITION
		sector.player.velocity = Vector3.ZERO
		sector.player.radiation_exposure = 0.0
		sector.player.rockets.unload()
		sector.activate_map(0)
	sector.preflight = true
	sector.select_target(null)
	sector.set_paused(true)
	menu.hide()
	sector.main_menu.show_home()


@rpc("any_peer", "call_remote", "reliable")
func dock_request() -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not ships.has(id) or ships[id].get_meta("docked", false):
		return
	var ship := ships[id]
	if GalaxyGates.is_arena(ship.map_id):
		combat.gate.retreated(id)
	ship.set_meta("docked", true)
	if ship.map_id != 0:
		ship.map_visit += 1
	ship.map_id = 0
	ship.rockets.unload()
	ship.hide()
	ship.collision_layer = 0
	ship.position = combat.records[id]["spawn"]
	ship.rotation = Vector3.ZERO
	ship.velocity = Vector3.ZERO
	combat.records[id]["life"] += 1
	ship.set_meta("life", combat.records[id]["life"])
	clear_commands(id)
	for enemy: Alien in sector.world_aliens.values():
		enemy.contributors.erase(id)
	for peer_id in multiplayer.get_peers():
		flight_docked.rpc_id(peer_id, id, player_state(id, peer_id == id), snapshot_sequence)


@rpc("authority", "call_remote", "reliable")
func flight_docked(id: int, data: Dictionary, sequence: int) -> void:
	if not active or not ships.has(id):
		return
	if id != multiplayer.get_unique_id():
		if sector.target == ships[id]:
			sector.select_target(null)
		despawn(id)
	else:
		sector.preflight = true
		sector.select_target(null)
		sector.player.set_meta("docked", true)
		combat.apply_player(id, data, sequence)
		sector.player.position = data["position"]
		sector.player.rotation = data["rotation"]
		sector.player.velocity = Vector3.ZERO
		sector.player.energy = data["energy"]
		prediction.reset(sector.player)
		sector.set_paused(true)
		sector.main_menu.show_home()
	# Keep a sequence barrier when an observer later receives the same peer's relaunch.
	player_sequences[id] = maxi(player_sequences.get(id, -1), sequence)


@rpc("any_peer", "call_remote", "reliable")
func launch_request() -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not ships.has(id) or not ships[id].get_meta("docked", false) or not ships[id].alive:
		return
	ships[id].set_meta("docked", false)
	ships[id].show()
	ships[id].collision_layer = 2
	clear_commands(id)
	for peer_id in multiplayer.get_peers():
		if peer_id != id:
			spawn.rpc_id(peer_id, id, ships[id].position)
	flight_launched.rpc(id)


@rpc("authority", "call_remote", "reliable")
func flight_launched(id: int) -> void:
	if not active or not ships.has(id):
		return
	ships[id].set_meta("docked", false)
	ships[id].show()
	ships[id].collision_layer = 2
	if id == multiplayer.get_unique_id():
		prediction.reset(sector.player)
		sector.preflight = false
		sector.main_menu.hide()
		sector.main_menu.hide_pages()
		menu.hide()
		sector.set_paused(false)
		sector.notify("Launched at Outpost 01. Hold %s to steer." % GameSettings.binding_text("steer"))


func peer_left(id: int) -> void:
	if active and sector.dedicated_server and not combat.flush_boosts([id]):
		stop_for_save_failure()
	# Disconnecting mid-wave is a retreat, like quitting to the station. Run
	# lives are keyed by pilot identity, so settle them before it is erased.
	if active and multiplayer.is_server() and ships.has(id) and GalaxyGates.is_arena(ships[id].map_id):
		combat.gate.retreated(id, false)
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
	jump_until.erase(id)
	sent_profiles.erase(id)
	sent_snapshots.erase(id)
	snapshot_traffic.erase(id)
	profile_revisions.erase(Vector2i(0, id))
	profile_revisions.erase(Vector2i(1, id))
	ships.erase(id)
	commands.erase(id)
	input_buffers.erase(id)
	goals.erase(id)
	remote_buffers.erase(id)
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
		sector.validate_target()
		sector.weapon_status = sector.player.firing_blocker(sector.target)
	var movement := Vector3.ZERO if sector.dedicated_server or sector.paused else sector.read_flight_movement(delta)
	var boost := not sector.dedicated_server and not sector.paused and not sector.autopilot.enabled and Input.is_action_pressed("boost")
	send_clock += delta
	if multiplayer.is_server():
		server_tick += 1
		var phase_started := Time.get_ticks_usec() if benchmark_timing else 0
		if benchmark_timing: benchmark_phases.clear()
		if sector.dedicated_server:
			lab_clock += delta
			if lab_clock >= 1.0:
				lab_clock = 0.0
				combat.advance_labs()
		if benchmark_timing:
			benchmark_phases["industry_us"] = Time.get_ticks_usec() - phase_started
			phase_started = Time.get_ticks_usec()
		if not sector.dedicated_server and sector.player.alive:
			sector.player.fly_command(delta, movement, boost)
		for id: int in ships:
			var ship := ships[id]
			if ship.get_meta("docked", false):
				continue
			if not ship.alive:
				continue
			if id != 1:
				simulate_pilot(id, delta)
			sector.tick_radiation(ship, delta)
		if benchmark_timing:
			benchmark_phases["flight_us"] = Time.get_ticks_usec() - phase_started
			phase_started = Time.get_ticks_usec()
		combat.tick(delta)
		if benchmark_timing:
			benchmark_phases["combat_us"] = Time.get_ticks_usec() - phase_started
			phase_started = Time.get_ticks_usec()
		if send_clock >= 0.05:
			send_clock = 0.0
			send_snapshot()
		if benchmark_timing: benchmark_phases["snapshot_us"] = Time.get_ticks_usec() - phase_started
	else:
		if not received_snapshot:
			connect_clock += delta
			if connect_clock >= CONNECT_TIMEOUT:
				disconnect_session("Connected, but no sector arrived. Check that client and server builds match, then try again.")
			return
		predict_local(delta, movement, boost)
		render_remote(delta)


## Client: draws remote pilots and aliens at the render time, between buffered
## snapshots (see ServerClock and SnapshotBuffer). Runs once per physics tick,
## so they step in time with the local ship and camera.
func render_remote(delta: float) -> void:
	clock.advance(delta)
	if not clock.synced:
		return
	var render_tick := clock.render_tick()
	var counts := PackedInt32Array([0, 0, 0, 0])
	for id: int in remote_buffers:
		var ship: Pilot = ships.get(id)
		if ship == null or ship == sector.player or ship.map_id != sector.map_id:
			continue
		draw_sample(ship, remote_buffers[id], render_tick, counts, false)
	combat.interpolate(render_tick, counts)
	net_stats.record_interpolation(clock, counts[0], counts[1], counts[2], counts[3])


## Moves one entity to its buffered transform at `render_tick` and counts the
## SnapshotBuffer mode used in `counts`: [interpolated, extrapolated, held,
## underruns].
static func draw_sample(node: Node3D, buffer: SnapshotBuffer, render_tick: float, counts: PackedInt32Array, all_axes: bool) -> void:
	var underruns := buffer.underruns
	var result := buffer.sample(render_tick)
	if result.is_empty():
		return
	node.position = result["position"]
	var angles: Vector3 = result["rotation"]
	if all_axes:
		node.rotation = angles
	else:
		# Pilots replicate pitch and yaw; roll is cosmetic banking on the model.
		node.rotation.x = angles.x
		node.rotation.y = angles.y
	match int(result["mode"]):
		SnapshotBuffer.Mode.INTERPOLATED: counts[0] += 1
		SnapshotBuffer.Mode.EXTRAPOLATED: counts[1] += 1
		SnapshotBuffer.Mode.HELD: counts[2] += 1
	counts[3] += buffer.underruns - underruns


## Client: moves a world-space effect point the server placed at an entity's
## position onto where that entity is drawn. Remote entities are drawn about
## ServerClock.INTERPOLATION_DELAY in the past and the local ship ahead of the
## server, so lasers would otherwise start and end beside their ships.
func drawn_point(point: Vector3) -> Vector3:
	if not active or multiplayer.is_server():
		return point
	var best := ANCHOR_RADIUS
	var shift := Vector3.ZERO
	if net_stats.has_server_state and sector.player.alive:
		var distance := point.distance_to(net_stats.server_position)
		if distance < best:
			best = distance
			shift = sector.player.position + sector.player.visual_offset - net_stats.server_position
	for id: int in remote_buffers:
		var ship: Pilot = ships.get(id)
		var buffer := remote_buffers[id]
		if ship == null or ship == sector.player or not ship.visible or buffer.is_empty():
			continue
		var distance := point.distance_to(buffer.newest_position())
		if distance < best:
			best = distance
			shift = ship.position - buffer.newest_position()
	for alien: Alien in sector.aliens.values():
		if not alien.visible or alien.snapshot_buffer.is_empty():
			continue
		var distance := point.distance_to(alien.snapshot_buffer.newest_position())
		if distance < best:
			best = distance
			shift = alien.position - alien.snapshot_buffer.newest_position()
	return point + shift


## Server: consumes this tick's input for a remote pilot and simulates it with
## the same step the owner predicts with. Only movement, boost and requested
## facing come from the client; position and velocity never do.
func simulate_pilot(id: int, delta: float) -> void:
	var ship := ships[id]
	var buffer: InputBuffer = input_buffers.get_or_add(id, InputBuffer.new())
	var input := buffer.consume()
	var movement: Vector3 = input.get("movement", Vector3.ZERO)
	# Keep the exact simulation facing between ticks. Reading `rotation` back
	# after move_and_slide() decomposes the basis, so it is adopted only when
	# something else (spawn, jump, dock or respawn) set a new facing.
	if not ship.rotation.is_equal_approx(ship.sim_rotation):
		ship.sim_rotation = ship.rotation
	# Idle pilots hold their facing and brake.
	ship.simulate_input(delta, movement, input.get("boost", false), input.get("facing", ship.rotation))
	ship.rotation = ship.sim_rotation
	ship.present_motion(delta, movement)


## Client: reconciles the local ship against the newest snapshot, then samples,
## predicts and periodically sends this tick's input.
func predict_local(delta: float, movement: Vector3, boost: bool) -> void:
	prediction.client_tick += 1
	var ship := sector.player
	if not ship.alive or sector.preflight:
		ship.set_visual_offset(Vector3.ZERO)
		if prediction.client_tick % FlightPrediction.SEND_INTERVAL_TICKS == 0:
			send_snapshot_ack()
		return
	prediction.reconcile(ship, delta, net_stats)
	prediction.predict(ship, delta, movement, boost)
	net_stats.inputs_sent += 1
	if prediction.client_tick % FlightPrediction.SEND_INTERVAL_TICKS == 0:
		var enemy := sector.target as Alien
		net_stats.input_packets_sent += 1
		flight_inputs.rpc_id(1, prediction.packet(int(ship.get_meta("life", 0)), sector.auto_fire and enemy != null and not sector.paused,
			enemy.life if enemy != null else -1, enemy.alien_id if enemy != null else -1, snapshot_ack()))
	prediction.smooth(ship, delta)
	net_stats.unacked_inputs = prediction.pending.size()
	net_stats.record_visual_offset(ship.visual_offset.length())


## Sends one input outside local prediction, for scripted clients and tests.
## The server validates it exactly like predicted inputs.
func send_command(movement: Vector3, angles: Vector3, boost: bool, fire: bool = false, life: int = 0, encounter: int = 0, target_id: int = -1) -> void:
	var input := {"seq": prediction.next_seq, "movement": movement, "boost": boost, "facing": angles}
	prediction.next_seq += 1
	flight_inputs.rpc_id(1, FlightInput.encode(life, fire, encounter, target_id, prediction.client_tick, [input], snapshot_ack()))


func snapshot_ack() -> int:
	received_snapshots.set_scope(sector.player.map_visit, sector.player.map_id)
	return received_snapshots.acknowledged


## Idle clients still acknowledge snapshots through the flight input channel.
func send_snapshot_ack() -> void:
	var ack := snapshot_ack()
	if ack > 0:
		flight_inputs.rpc_id(1, FlightInput.encode(0, false, -1, -1, prediction.client_tick, [], ack))


## Server: forgets a pilot's intent and buffered inputs when its flight or life
## ends, so nothing from the previous flight can steer or fire.
func clear_commands(id: int) -> void:
	commands.erase(id)
	if input_buffers.has(id):
		input_buffers[id].reset()


## Player snapshot including transform. `owner_view` adds private progress and is
## sent only to the owning peer.
func player_state(id: int, owner_view: bool) -> Dictionary:
	var ship := ships[id]
	# Remote pilots send their exact simulation facing, which owners replay from.
	var facing := ship.sim_rotation if id != 1 and ship.rotation.is_equal_approx(ship.sim_rotation) else ship.rotation
	var data := {"position": ship.position, "rotation": facing, "velocity": ship.velocity, "energy": ship.energy}
	data.merge(combat.pack_player(id, owner_view))
	return data


func send_snapshot() -> void:
	if multiplayer.get_peers().is_empty():
		return
	snapshot_sequence += 1
	# Pack public entities once per tick. Each viewer gets its own delta, with
	# the owner first. Profiles go reliably, only when they change.
	var ids := ships.keys()
	ids.sort()
	var entries: Dictionary[int, PackedByteArray] = {}
	var profiles: Dictionary[int, Array] = {}
	for id: int in ids:
		var data := player_state(id, false)
		profiles[id] = profile_revision(Vector2i(0, id), SnapshotCodec.player_profile(data))
		entries[id] = SnapshotCodec.player_entry(id, data, profiles[id][0])
	var map_aliens: Dictionary[int, Dictionary] = {}
	var alien_profiles_by_map: Dictionary[int, Dictionary] = {}
	var alien_ids := sector.world_aliens.keys()
	alien_ids.sort()
	for viewer: int in ids:
		var map := ships[viewer].map_id
		if viewer == 1 or map_aliens.has(map):
			continue
		var packed := {}
		var known := {}
		for alien_id in alien_ids:
			var enemy: Alien = sector.world_aliens[alien_id]
			if enemy.map_id == map:
				var data := combat.pack_alien(enemy)
				known[enemy.alien_id] = profile_revision(Vector2i(2, enemy.alien_id), SnapshotCodec.alien_profile(data))
				packed[Vector2i(SnapshotCodec.ALIEN, enemy.alien_id)] = SnapshotCodec.alien_entry(data, known[enemy.alien_id][0])
		map_aliens[map] = packed
		alien_profiles_by_map[map] = known
	var now := Time.get_ticks_usec()
	for viewer: int in ids:
		if viewer == 1:
			continue
		var map := ships[viewer].map_id
		var visit := ships[viewer].map_visit
		if not sent_snapshots.has(viewer):
			sent_snapshots[viewer] = SnapshotHistory.new()
			snapshot_traffic[viewer] = NetStats.SnapshotTraffic.new()
		var history := sent_snapshots[viewer]
		var traffic := snapshot_traffic[viewer]
		history.set_scope(visit, map)
		var own := player_state(viewer, true)
		var visible := {viewer: profile_revision(Vector2i(1, viewer), SnapshotCodec.player_profile(own))}
		var extras := owner_extras(viewer)
		extras["traffic"] = traffic.report
		var frame := {Vector2i(SnapshotCodec.OWNER_PLAYER, viewer): SnapshotCodec.player_entry(viewer, own, visible[viewer][0], extras)}
		for id: int in ids:
			if id != viewer and not ships[id].get_meta("docked", false) and ships[id].map_id == map:
				frame[Vector2i(SnapshotCodec.PUBLIC_PLAYER, id)] = entries[id]
				visible[id] = profiles[id]
		frame.merge(map_aliens[map])
		send_profiles(viewer, visible, alien_profiles_by_map[map])
		var baseline := history.baseline_for(snapshot_sequence)
		var packets := SnapshotCodec.encode_world(snapshot_sequence, visit, server_tick, frame, baseline)
		if packets.is_empty():
			continue
		var bytes := 0
		for packet in packets:
			world_snapshot.rpc_id(viewer, packet)
			bytes += packet.size()
		history.remember_sent(snapshot_sequence, frame)
		traffic.record(bytes, not baseline.is_empty(), now)


## Private ammunition, rocket and boost state carried in the owner's entry.
func owner_extras(id: int) -> Dictionary:
	var ship := ships[id]
	var extras := {"rounds": combat.ammo_rounds(id), "rockets": ship.rockets.state(), "turn_budget": ship.turn_budget}
	if input_buffers.has(id):
		var buffer := input_buffers[id]
		extras["ack"] = maxi(buffer.last_seq, 0)
		extras["depth"] = buffer.depth()
		extras["inputs"] = buffer.counters()
	if sector.dedicated_server:
		extras["boosts"] = ship.resource_boosts
		extras["revision"] = store.pilots[pilot_ids[id]]["equipment"]["revision"]
	return extras


## Returns [revision, profile], advancing the revision whenever the profile changes.
func profile_revision(key: Vector2i, profile: Array) -> Array:
	var known: Array = profile_revisions.get(key, [0, []])
	if known[1] != profile:
		known = [(known[0] + 1) % 65536, profile]
		profile_revisions[key] = known
	return known


## Reliably sends [revision, profile] pairs the viewer lacks. Each new map visit resends all of them.
func send_profiles(viewer: int, players: Dictionary, aliens: Dictionary) -> void:
	var visit := ships[viewer].map_visit
	if sent_profiles.get(viewer, {}).get("visit", -1) != visit:
		sent_profiles[viewer] = {"visit": visit, "players": {}, "aliens": {}}
	var known: Dictionary = sent_profiles[viewer]
	var changed_players := {}
	var changed_aliens := {}
	for id: int in players:
		if known["players"].get(id) != players[id][0]:
			changed_players[id] = players[id]
			known["players"][id] = players[id][0]
	for id: int in aliens:
		if known["aliens"].get(id) != aliens[id][0]:
			changed_aliens[id] = aliens[id]
			known["aliens"][id] = aliens[id][0]
	if not changed_players.is_empty() or not changed_aliens.is_empty():
		entity_profiles.rpc_id(viewer, changed_players, changed_aliens)


## A client's recent flight inputs; see FlightInput. Unsequenced: the input
## buffer orders and deduplicates them, and stale fire intent is ignored.
@rpc("any_peer", "call_remote", "unreliable", 1)
func flight_inputs(packet: PackedByteArray) -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var decoded := FlightInput.decode(packet)
	if not ships.has(id) or decoded.is_empty():
		return
	if sent_snapshots.has(id):
		var history := sent_snapshots[id]
		history.set_scope(ships[id].map_visit, ships[id].map_id)
		history.acknowledge(decoded["snapshot_ack"])
	if decoded["inputs"].is_empty():
		return
	if ships[id].get_meta("docked", false):
		return
	if not ships[id].alive or combat.records[id]["life"] != decoded["life"]:
		return
	var buffer: InputBuffer = input_buffers.get_or_add(id, InputBuffer.new())
	for input: Dictionary in decoded["inputs"]:
		buffer.receive(input["seq"], {"movement": input["movement"].limit_length(), "boost": input["boost"], "facing": input["facing"]})
	var newest: Dictionary = decoded["inputs"][-1]
	if newest["seq"] >= int(commands.get(id, {}).get("seq", -1)):
		commands[id] = {
			"movement": newest["movement"].limit_length(), "rotation": newest["facing"], "boost": newest["boost"],
			"fire": decoded["fire"], "encounter": decoded["encounter"], "target": decoded["target"],
			"seq": newest["seq"], "tick": server_tick,
		}


@rpc("authority", "call_remote", "reliable")
func entity_profiles(players: Dictionary, aliens: Dictionary) -> void:
	if not active:
		return
	for id: int in players:
		player_profiles[id] = players[id]
	for id: int in aliens:
		alien_profiles[id] = aliens[id]


@rpc("authority", "call_remote", "unreliable", 2)
func world_snapshot(packet: PackedByteArray) -> void:
	if not active:
		return
	var header := SnapshotCodec.header(packet)
	if header.is_empty() or not receives_map(header["visit"]):
		return
	received_snapshots.set_scope(sector.player.map_visit, sector.player.map_id)
	var world := received_snapshots.receive(packet, header)
	if world.is_empty():
		return
	var sequence: int = world["sequence"]
	var visit: int = world["visit"]
	if world["first_part"]:
		net_stats.record_snapshot_arrival()
		net_stats.server_tick = maxi(net_stats.server_tick, world["tick"])
		clock.observe(world["tick"])
	var owner: Dictionary = world["owner"]
	if not owner.is_empty():
		net_stats.record_server_snapshot_traffic(sequence, owner["traffic"])
		combat.ammo_snapshot(owner["rounds"], sequence, owner["rockets"], visit)
		if owner.has("boosts"):
			combat.boost_state(owner["boosts"], sequence, owner["revision"])
	# An entity waits until the reliable profile revision its state was packed
	# with arrives, which takes at most one round trip.
	var players := {}
	for id: int in world["players"]:
		var state: Dictionary = world["players"][id]
		var profile: Array = player_profiles.get(id, [-1])
		if profile[0] == state["profile"]:
			players[id] = SnapshotCodec.player_state(state, profile[1])
	snapshot(players, {}, sequence, visit, world["tick"])
	for id: int in world["aliens"]:
		var state: Dictionary = world["aliens"][id]
		var profile: Array = alien_profiles.get(id, [-1])
		if profile[0] == state["profile"]:
			snapshot({}, SnapshotCodec.alien_state(state, profile[1]), sequence, visit, world["tick"])


## Applies decoded world state sent on server `tick`. Each entity rejects state
## older than its last update, though an older packet's transform can still
## fill a remote entity's interpolation buffer. Direct calls without a tick
## (tests) reuse the newest received tick.
func snapshot(state: Dictionary, alien_state: Dictionary, sequence: int, visit: int = -1, tick: int = -1) -> void:
	if not active or not receives_map(visit):
		return
	if tick < 0:
		tick = maxi(clock.latest_tick, 0)
	# Packets may arrive out of order. Reject stale state per entity, not per whole packet.
	if not alien_state.is_empty():
		var alien_id: int = alien_state["id"]
		if sequence > alien_sequences.get(alien_id, -1):
			combat.apply_alien(alien_state, tick)
			alien_sequences[alien_id] = sequence
		else:
			combat.buffer_late_alien(alien_state, tick)
	for id: int in state:
		if not ships.has(id):
			continue
		var data: Dictionary = state[id]
		if sequence <= player_sequences.get(id, -1):
			# Same life and state: the transform still belongs to the current motion.
			var late := ships[id]
			if late != sector.player and remote_buffers.has(id) and int(data["life"]) == int(late.get_meta("life", 0)) and bool(data["alive"]) == late.alive:
				remote_buffers[id].push(tick, data["position"], data["rotation"])
			continue
		if int(data["life"]) < int(ships[id].get_meta("life", 0)):
			continue
		# Reliable dock/launch acknowledgements and snapshots travel on different channels.
		if ships[id] == sector.player and bool(data["docked"]) != sector.preflight:
			continue
		player_sequences[id] = sequence
		goals[id] = data
		var ship := ships[id]
		var reset := combat.apply_player(id, data, sequence)
		if reset:
			ship.position = data["position"]
			ship.rotation = data["rotation"]
		if ship != sector.player:
			ship.energy = data["energy"]
			# A new life, or the first state after a spawn or launch, starts a new motion.
			var buffer: SnapshotBuffer = remote_buffers.get_or_add(id, SnapshotBuffer.new())
			if reset or buffer.is_empty():
				buffer.clear()
				ship.position = data["position"]
				ship.rotation.x = data["rotation"].x
				ship.rotation.y = data["rotation"].y
			buffer.push(tick, data["position"], data["rotation"], true)
		else:
			var authoritative := {"position": data["position"], "rotation": data["rotation"], "energy": data["energy"],
				"velocity": data["velocity"] if ship.alive else Vector3.ZERO}
			for key: String in ["ack", "input_depth", "turn_budget"]:
				if data.has(key):
					authoritative[key] = data[key]
			if reset or not received_snapshot:
				# A new life or connection starts from the server's state.
				prediction.reset(ship)
				ship.position = data["position"]
				ship.velocity = authoritative["velocity"]
				ship.energy = data["energy"]
				ship.sim_rotation = data["rotation"]
				ship.turn_budget = authoritative.get("turn_budget", ship.turn_budget)
				prediction.last_ack = maxi(prediction.last_ack, int(authoritative.get("ack", 0)))
			else:
				# Rewind and replay in the next physics tick (FlightPrediction.reconcile).
				prediction.authoritative = authoritative
				if prediction.pending.is_empty():
					# Nothing to replay while not predicting (docked, destroyed or
					# scripted): adopt the state now, without move_and_slide().
					prediction.reconcile(ship, 1.0 / Engine.physics_ticks_per_second, net_stats)
			net_stats.record_server_state(data["position"], data["rotation"])
			if data.has("inputs"):
				net_stats.server_inputs = data["inputs"]
			received_snapshot = true
	status = "Connected. Players: %d/%d" % [ships.size(), MAX_PLAYERS]


func disconnect_session(message: String) -> void:
	clear_jump_cover()
	if active and sector.dedicated_server and not combat.flush_boosts():
		stop_for_save_failure()
	sector.preflight = false
	if is_instance_valid(sector.main_menu):
		sector.main_menu.hide()
		sector.main_menu.hide_pages()
	active = false
	connecting = false
	pilot_ids.clear()
	challenges.clear()
	if store != null:
		var already_failed := store.failed
		if not store.close() and not already_failed: stop_for_save_failure()
	combat.finish()
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	net_simulator.stop()
	net_stats.has_server_state = false
	for ship: Pilot in ships.values():
		if ship != sector.player:
			ship.queue_free()
	ships.clear()
	commands.clear()
	input_buffers.clear()
	server_tick = 0
	goals.clear()
	remote_buffers.clear()
	clock.reset()
	received_snapshot = false
	snapshot_sequence = 0
	player_sequences.clear()
	alien_sequences.clear()
	player_profiles.clear()
	alien_profiles.clear()
	sent_profiles.clear()
	sent_snapshots.clear()
	received_snapshots = SnapshotHistory.new()
	snapshot_traffic.clear()
	profile_revisions.clear()
	jump_pending = false
	jump_until.clear()
	send_clock = 0.0
	if sector.dedicated_server:
		status = message
		return
	sector.player.collision_mask = 3
	sector.respawn_player()
	status = message
	join_button.disabled = false
	if sector.offline:
		open_offline_main_menu()
	open_menu()


func _exit_tree() -> void:
	if store != null:
		var already_failed := store.failed
		if active and sector.dedicated_server and not store.failed:
			combat.flush_boosts()
		if not store.close() and not already_failed: get_tree().quit(1)
	if active or connecting:
		multiplayer.multiplayer_peer.close()
	net_simulator.stop()


func receives_map(visit: int) -> bool:
	return visit < 0 or is_instance_valid(sector.player) and sector.player.map_visit == visit


func map_event(method: String, arguments: Array, map: int) -> void:
	# Each recipient's visit travels with world events, including reliable loot.
	# Returning to the same map cannot revive packets from its previous visit.
	for id: int in ships:
		if ships[id].map_id != map or ships[id].get_meta("docked", false):
			continue
		var args := arguments + [ships[id].map_visit]
		if id == 1:
			combat.callv(method, args)
		else:
			Callable(combat, "rpc_id").callv([id, method] + args)


func request_jump() -> void:
	if jump_pending or sector.paused or sector.preflight or not sector.player.alive:
		return
	var destination := -1
	var nearest := SectorMaps.JUMP_RADIUS
	for map: int in SectorMaps.links(sector.map_id):
		var distance := sector.player.position.distance_to(SectorMaps.gate_position(sector.map_id, map))
		if distance <= nearest:
			nearest = distance
			destination = map
	if destination < 0:
		sector.notify("Fly within 50 m of a gate, then press %s to jump." % GameSettings.binding_text("jump_gate"))
		return
	if not sector.map_scenery.has(destination) and DisplayServer.get_name() != "headless":
		# Present a frame before synchronous geometry construction on first entry.
		# The authoritative transfer, cooldown and visit epochs stay unchanged.
		jump_pending = true
		var visit := sector.player.map_visit
		var was_active := active
		jump_cover = CanvasLayer.new()
		jump_cover.layer = 20
		var curtain := ColorRect.new()
		curtain.color = Color("071723")
		curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		jump_cover.add_child(curtain)
		var caption := Label.new()
		caption.text = "GATE TRANSIT"
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		curtain.add_child(caption)
		add_child(jump_cover)
		await RenderingServer.frame_post_draw
		jump_pending = false
		if active != was_active or sector.player.map_visit != visit or sector.paused or sector.preflight or not sector.player.alive:
			clear_jump_cover()
			return
	if active:
		if multiplayer.is_server():
			var reason := jump(1, int(sector.player.get_meta("life", 0)), destination)
			if not reason.is_empty():
				sector.notify(reason)
				clear_jump_cover()
		else:
			jump_pending = true
			jump_request.rpc_id(1, int(sector.player.get_meta("life", 0)), destination)
	else:
		if Time.get_ticks_msec() < jump_until.get(1, 0):
			sector.notify("Gate stabilizing. Wait two seconds between jumps.")
			clear_jump_cover()
			return
		jump_until[1] = Time.get_ticks_msec() + int(SectorMaps.JUMP_COOLDOWN * 1000)
		var source := sector.player.map_id
		sector.player.map_id = destination
		sector.player.map_visit += 1
		sector.player.set_meta("life", int(sector.player.get_meta("life", 0)) + 1)
		sector.player.position = SectorMaps.arrival(destination, source)
		finish_local_jump()


@rpc("any_peer", "call_remote", "reliable")
func jump_request(life: int, destination: int) -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := jump(id, life, destination)
	if not reason.is_empty():
		jump_feedback.rpc_id(id, reason)


@rpc("authority", "call_remote", "reliable")
func jump_feedback(reason: String) -> void:
	jump_pending = false
	clear_jump_cover()
	sector.notify(reason)


func clear_jump_cover() -> void:
	if is_instance_valid(jump_cover):
		jump_cover.queue_free()
	jump_cover = null


func reveal_jump() -> void:
	if not is_instance_valid(jump_cover):
		return
	# Allow the destination's first shader/sky draw to finish under the curtain.
	var cover := jump_cover
	jump_cover = null
	await RenderingServer.frame_post_draw
	if is_instance_valid(cover):
		var fade := create_tween()
		fade.tween_property(cover.get_child(0), "modulate:a", 0.0, 0.18)
		fade.tween_callback(cover.queue_free)


func jump(id: int, life: int, destination: int) -> String:
	if not active or not multiplayer.is_server() or not ships.has(id):
		return "Jump unavailable."
	var ship := ships[id]
	if life != combat.records[id]["life"] or not ship.alive or ship.get_meta("docked", false):
		return "Jump unavailable for this flight."
	if not SectorMaps.links(ship.map_id).has(destination):
		return "No gate connects these maps."
	if ship.position.distance_to(SectorMaps.gate_position(ship.map_id, destination)) > SectorMaps.JUMP_RADIUS:
		return "Fly within 50 m of the gate to jump."
	if Time.get_ticks_msec() < jump_until.get(id, 0):
		return "Gate stabilizing. Wait two seconds between jumps."
	if GalaxyGates.is_arena(destination):
		var blocker := combat.gate.entry_blocker(id, destination)
		if not blocker.is_empty():
			return blocker
	if GalaxyGates.is_arena(ship.map_id):
		var sealed := combat.gate.exit_blocker()
		if not sealed.is_empty():
			return sealed
	jump_until[id] = Time.get_ticks_msec() + int(SectorMaps.JUMP_COOLDOWN * 1000)
	transfer(id, destination)
	if GalaxyGates.is_arena(destination):
		combat.gate.entered(id)
	return ""


## Moves a living pilot to another map's arrival point, invalidating the previous visit.
func transfer(id: int, destination: int) -> void:
	var ship := ships[id]
	var source := ship.map_id
	ship.map_id = destination
	ship.map_visit += 1
	ship.position = SectorMaps.arrival(destination, source, int(ship.get_meta("spawn_slot", 0)))
	ship.velocity = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	ship.radiation_exposure = 0.0
	ship.look_at(SectorMaps.origin(destination), Vector3.UP)
	ship.rockets.unload()
	combat.records[id]["life"] += 1
	ship.set_meta("life", combat.records[id]["life"])
	clear_commands(id)
	for enemy: Alien in sector.world_aliens.values():
		enemy.contributors.erase(id)
	announce_map_change(id)


func announce_map_change(id: int) -> void:
	for peer_id in multiplayer.get_peers():
		map_changed.rpc_id(peer_id, id, player_state(id, peer_id == id), snapshot_sequence)
	map_changed(id, player_state(id, id == multiplayer.get_unique_id()), snapshot_sequence)


@rpc("authority", "call_local", "reliable")
func map_changed(id: int, data: Dictionary, sequence: int) -> void:
	if not active or not ships.has(id) or int(data["life"]) < int(ships[id].get_meta("life", 0)):
		return
	var ship := ships[id]
	if not multiplayer.is_server():
		combat.apply_player(id, data, sequence)
		ship.position = data["position"]
		ship.rotation = data["rotation"]
		ship.energy = data["energy"]
		ship.velocity = data["velocity"]
		if ship == sector.player:
			prediction.reset(ship)
			ship.sim_rotation = data["rotation"]
	goals.erase(id)
	remote_buffers.erase(id)
	player_sequences[id] = maxi(player_sequences.get(id, -1), sequence)
	if ship == sector.player:
		sector.activate_map(ship.map_id)
		if not multiplayer.is_server():
			sector.loot.clear()
		combat.ammo_sequence = maxi(combat.ammo_sequence, sequence)
		jump_pending = false
		finish_local_jump()
	if multiplayer.is_server() and id != 1:
		combat.loot_state.rpc_id(id, loot_for_map(ship.map_id), ship.map_visit)


func loot_for_map(map: int) -> Dictionary:
	var result := {}
	for id: int in sector.loot.drops:
		if int(sector.loot.drops[id].get("map", 0)) == map:
			result[id] = sector.loot.drops[id]
	return result


func finish_local_jump() -> void:
	sector.player.velocity = Vector3.ZERO
	sector.player.pending_look = Vector2.ZERO
	sector.player.radiation_exposure = 0.0
	sector.player.rockets.unload()
	sector.player.release_mouse()
	sector.player.look_at(SectorMaps.origin(sector.player.map_id), Vector3.UP)
	sector.activate_map(sector.player.map_id)
	sector.set_paused(false)
	for effect in get_tree().get_nodes_in_group("transient_feedback"):
		if sector.is_ancestor_of(effect):
			effect.queue_free()
	var arena := GalaxyGates.for_map(sector.map_id)
	if not arena.is_empty():
		sector.notify("Entered the %s. The gate behind you returns to M1 between waves (%s)." % [GalaxyGates.info(arena)["arena"], GameSettings.binding_text("jump_gate")])
	else:
		sector.notify("Arrived at %s. Gates are protected; press %s nearby to return." % [SectorMaps.MAPS[sector.map_id]["name"], GameSettings.binding_text("jump_gate")])
	reveal_jump()
