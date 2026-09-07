class_name Sector
extends Node3D
## Owns the local encounter. Multiplayer authority replaces this local orchestration later.

const STATION_POSITION := Vector3(-38.0, -8.0, 0.0)
const SPAWN_POSITION := Vector3(0.0, 0.0, 45.0)
const REPAIR_RADIUS: float = 60.0
const KILL_REWARD: int = 75
const RESPAWN_FEE: int = 10
const WINDOW_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 600), Vector2i(1280, 720), Vector2i(1440, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]

var player: Pilot
var alien: Alien
var target: SpaceShip
var hud: FlightHud
var credits: int = 0
var kills: int = 0
var auto_fire: bool = false
var paused: bool = false
var alien_respawn: float = 0.0
var player_respawn: float = 0.0
var toast: String = "Welcome to Outpost 01. Hold right mouse to steer."
var toast_time: float = 8.0
var objective_stage: int = 0
var show_performance: bool = false
var low_quality: bool = false
var weapon_status: String = "NO TARGET"
var session: FlightSession


func _ready() -> void:
	configure_input()
	SectorVisuals.environment(self)
	SectorVisuals.station(self, STATION_POSITION)
	player = Pilot.new()
	player.position = SPAWN_POSITION
	add_child(player)
	alien = Alien.new()
	alien.position = alien.home_position
	add_child(alien)
	player.destroyed.connect(on_destroyed)
	alien.destroyed.connect(on_destroyed)
	player.fired.connect(on_laser)
	alien.fired.connect(on_laser)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = FlightHud.new()
	hud.sector = self
	layer.add_child(hud)
	session = FlightSession.new()
	session.name = "FlightSession"
	session.sector = self
	add_child(session)


func configure_input() -> void:
	var bindings := {
		"forward": KEY_W, "backward": KEY_S, "strafe_left": KEY_A,
		"strafe_right": KEY_D, "move_down": KEY_Q, "move_up": KEY_E,
		"boost": KEY_SHIFT, "cycle_target": KEY_TAB, "fire": KEY_SPACE,
		"repair": KEY_R, "pause_game": KEY_ESCAPE, "fullscreen": KEY_F11,
		"performance": KEY_F3, "quality": KEY_F4, "quit_game": KEY_F10,
		"resolution_down": KEY_F5, "resolution_up": KEY_F6,
		"multiplayer_menu": KEY_F7,
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key)
		# Remote and accessibility input may supply a logical key without a scancode.
		var logical_key := InputEventKey.new()
		logical_key.keycode = bindings[action]
		InputMap.action_add_event(action, logical_key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(player):
		set_paused(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("multiplayer_menu"):
		session.open_menu()
		return
	if event.is_action_pressed("pause_game"):
		session.menu.hide()
		set_paused(not paused)
	if event.is_action_pressed("quit_game") and paused:
		get_tree().quit()
	if event.is_action_pressed("fullscreen"):
		var mode := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if event.is_action_pressed("performance"):
		show_performance = not show_performance
	if event.is_action_pressed("quality"):
		low_quality = not low_quality
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED if low_quality else Viewport.MSAA_4X
		notify("Graphics: %s" % ("low / antialiasing off" if low_quality else "high / 4x antialiasing"))
	if paused and event.is_action_pressed("resolution_down"):
		cycle_resolution(-1)
	if paused and event.is_action_pressed("resolution_up"):
		cycle_resolution(1)
	if paused or not player.alive:
		return
	player.handle_mouse(event)
	if event.is_action_pressed("cycle_target"):
		select_target(alien if alien.alive else null)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pick_target(event.position)
	if event.is_action_pressed("fire"):
		if is_instance_valid(target) and target.alive:
			auto_fire = not auto_fire
		else:
			notify("Select an alien with Tab or left click first.")
	if event.is_action_pressed("repair"):
		request_repair()


func cycle_resolution(direction: int) -> void:
	var available: Array[Vector2i] = []
	var screen := DisplayServer.window_get_current_screen()
	# Leave room for window borders and the desktop taskbar.
	var usable := DisplayServer.screen_get_usable_rect(screen)
	for resolution in WINDOW_RESOLUTIONS:
		if resolution.x <= usable.size.x - 32 and resolution.y <= usable.size.y - 64:
			available.append(resolution)
	if available.is_empty():
		return
	var current := DisplayServer.window_get_size()
	var index := available.find(current)
	if index < 0:
		index = -1 if direction > 0 else 0
	var next := available[posmod(index + direction, available.size())]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(next)
	DisplayServer.window_set_position(usable.position + (usable.size - next) / 2)


func _physics_process(delta: float) -> void:
	if is_instance_valid(session) and (session.active or session.connecting):
		session.tick(delta)
		return
	if paused:
		return
	toast_time = maxf(0.0, toast_time - delta)
	player.tick_combat(delta)
	alien.tick_combat(delta)
	if player.alive:
		player.fly(delta)
		if player.position.length() > 700.0:
			player.position = player.position.normalized() * 699.0
			player.velocity = Vector3.ZERO
			notify("Sector boundary. Turn back toward the outpost.")
		if objective_stage == 0 and player.position.distance_to(STATION_POSITION) > 75.0:
			objective_stage = 1
		if auto_fire and is_instance_valid(target):
			player.try_fire(target)
	elif player_respawn > 0.0:
		player_respawn -= delta
		if player_respawn <= 0.0:
			respawn_player()
	if alien.alive:
		alien.fly(delta, player, STATION_POSITION)
	elif alien_respawn > 0.0:
		alien_respawn -= delta
		if alien_respawn <= 0.0:
			alien.position = alien.home_position
			alien.reset_health()
	weapon_status = player.firing_blocker(target)


func _process(_delta: float) -> void:
	if is_instance_valid(hud):
		hud.queue_redraw()


func set_paused(value: bool) -> void:
	paused = value
	if paused:
		player.release_mouse()
		auto_fire = false


func pick_target(screen_position: Vector2) -> void:
	var camera := player.camera
	var start := camera.project_ray_origin(screen_position)
	var finish := start + camera.project_ray_normal(screen_position) * 1500.0
	var query := PhysicsRayQueryParameters3D.create(start, finish, 3)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider == alien and alien.alive:
		select_target(alien)
	else:
		select_target(null)


func select_target(ship: SpaceShip) -> void:
	target = ship
	auto_fire = false
	if ship != null:
		objective_stage = maxi(objective_stage, 2)


func on_laser(start: Vector3, finish: Vector3, hostile: bool) -> void:
	if session.active:
		if multiplayer.is_server():
			session.combat.show_laser.rpc(start, finish, hostile)
		return
	SectorVisuals.laser(self, start, finish, hostile)


func on_destroyed(ship: SpaceShip, attacker: SpaceShip) -> void:
	if session.active:
		session.combat.destroyed(ship)
		return
	SectorVisuals.explosion(self, ship.global_position)
	if ship == alien:
		if attacker == player:
			credits += KILL_REWARD
			kills += 1
			objective_stage = maxi(objective_stage, 3)
			notify("Alien destroyed. +%d credits. Return to Outpost 01 to repair." % KILL_REWARD)
		select_target(null)
		alien_respawn = 12.0
	else:
		var fee := mini(credits, RESPAWN_FEE)
		credits -= fee
		player_respawn = 3.0
		auto_fire = false
		target = null
		player.release_mouse()
		notify("Ship lost. Rescue dispatched. Recovery cost: %d credits." % fee)


func respawn_player() -> void:
	player.position = SPAWN_POSITION
	player.rotation = Vector3.ZERO
	player.energy = 100.0
	player.reset_health()
	player_respawn = 0.0
	# Reset the encounter so enemies cannot camp the rescue position.
	alien.position = alien.home_position
	alien.reset_health()
	alien_respawn = 0.0


func repair_blocker(ship: Pilot = null) -> String:
	if ship == null:
		ship = player
	if not ship.alive:
		return "Wait for rescue."
	if ship.position.distance_to(STATION_POSITION) > REPAIR_RADIUS:
		return "Move within 60 m of Outpost 01 to repair."
	if ship.velocity.length() > 8.0:
		return "Release movement controls and slow down to repair."
	if ship.time_since_hit < 5.0:
		return "Repairs available five seconds after the last hit."
	return ""


func repair_cost(ship: Pilot = null, balance: int = -1) -> int:
	if ship == null:
		ship = player
	return mini(credits if balance < 0 else balance, ceili((ship.max_hull - ship.hull) * 0.12))


func request_repair() -> bool:
	if session.active:
		return session.combat.request_repair()
	var blocker := repair_blocker()
	if not blocker.is_empty():
		notify(blocker)
		return false
	var cost := repair_cost()
	credits -= cost
	player.reset_health()
	player.energy = 100.0
	auto_fire = false
	if objective_stage >= 3:
		objective_stage = 4
	notify("Repairs complete. Hull, shields and boost restored. Cost: %d credits." % cost)
	return true


func notify(message: String) -> void:
	toast = message
	toast_time = 7.0
