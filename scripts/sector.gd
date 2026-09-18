class_name Sector
extends Node3D
## Builds the shared sector for server or client; retains the offline development fixture.

const STATION_POSITION := Vector3(-38.0, -8.0, 0.0)
const SPAWN_POSITION := Vector3(0.0, 0.0, 45.0)
const REPAIR_RADIUS: float = 60.0
const KILL_REWARD: int = 75
const RESPAWN_FEE: int = 10
const WINDOW_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 600), Vector2i(1280, 720), Vector2i(1440, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]

# Fixed slots bound the population. Slot 0 remains the reference Sentinel for development fixtures.
const ALIEN_SPAWNS := [
	{"kind": "Sentinel", "home": Vector3(0, 8, -440)},
	{"kind": "Scout", "home": Vector3(-85, 8, -150)},
	{"kind": "Scout", "home": Vector3(85, -12, -175)},
	{"kind": "Sentinel", "home": Vector3(-230, 35, -430)},
	{"kind": "Heavy", "home": Vector3(320, 15, -390)},
]
var player: Pilot
var aliens: Dictionary[int, Alien] = {}
var alien: Alien:
	get: return aliens[0]
var target: SpaceShip
var hud: FlightHud
var credits: int = 0
var kills: int = 0
var active_contracts: Dictionary = {}
var cargo: Dictionary = {}
var cargo_capacity: int = CargoResources.SHIP_CAPACITIES["pathfinder"]
var loot: ResourceLoot
var auto_fire: bool = false
var paused: bool = false
var player_respawn: float = 0.0
var toast: String = "Welcome to Outpost 01. Hold right mouse to steer."
var toast_time: float = 8.0
var objective_stage: int = 0
var show_performance: bool = false
var low_quality: bool = false
var weapon_status: String = "NO TARGET"
var session: FlightSession
var shop: StationShop
var equipment_menu: ShipEquipment
var dedicated_server: bool = false
var client_only: bool = true
var server_port: int = FlightSession.PORT
var audio: FeedbackAudio
var settings := GameSettings.new()
var settings_menu: SettingsMenu


func _ready() -> void:
	dedicated_server = dedicated_server or "--server" in OS.get_cmdline_user_args()
	client_only = client_only and not "--offline" in OS.get_cmdline_user_args()
	if not dedicated_server:
		settings.load_from()
	settings.configure_input()
	SectorVisuals.environment(self, not dedicated_server)
	SectorVisuals.station(self, STATION_POSITION, not dedicated_server)
	if not dedicated_server:
		audio = FeedbackAudio.new()
		add_child(audio)
		player = Pilot.new()
		player.position = SPAWN_POSITION
		add_child(player)
		player.mouse_sensitivity = settings.sensitivity
		toast = "Welcome to Outpost 01. Hold %s to steer." % GameSettings.binding_text("steer")
		player.destroyed.connect(on_destroyed)
		player.fired.connect(on_laser)
	for id in range(ALIEN_SPAWNS.size()):
		var enemy := Alien.new()
		enemy.alien_id = id
		enemy.name = "Alien%d" % id
		enemy.kind = ALIEN_SPAWNS[id]["kind"]
		enemy.home_position = ALIEN_SPAWNS[id]["home"]
		enemy.position = enemy.home_position
		enemy.render_enabled = not dedicated_server
		aliens[id] = enemy
		add_child(enemy)
		enemy.destroyed.connect(on_destroyed)
		enemy.fired.connect(on_laser)
	if not dedicated_server:
		var layer := CanvasLayer.new()
		add_child(layer)
		hud = FlightHud.new()
		hud.sector = self
		layer.add_child(hud)
	session = FlightSession.new()
	session.name = "FlightSession"
	session.sector = self
	add_child(session)
	loot = ResourceLoot.new()
	loot.sector = self
	loot.name = "ResourceLoot"
	add_child(loot)
	if "--print-protocol" in OS.get_cmdline_user_args():
		return
	if not dedicated_server:
		var shop_layer := CanvasLayer.new()
		shop_layer.layer = 4
		add_child(shop_layer)
		shop = StationShop.new()
		shop.sector = self
		equipment_menu = ShipEquipment.new()
		equipment_menu.sector = self
		shop_layer.add_child(shop)
		shop_layer.add_child(equipment_menu)
	if not dedicated_server:
		apply_graphics()
		var layer := CanvasLayer.new()
		layer.layer = 6
		add_child(layer)
		settings_menu = SettingsMenu.new()
		settings_menu.sector = self
		layer.add_child(settings_menu)
	if dedicated_server:
		var port := server_port
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--port="):
				var value := argument.trim_prefix("--port=")
				if not value.is_valid_int() or int(value) < 1 or int(value) > 65535:
					printerr("Invalid server port: expected 1..65535")
					get_tree().quit(1)
					return
				port = int(value)
		if session.host(port) != OK:
			printerr(session.status)
			get_tree().quit(1)
	elif client_only:
		session.open_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(player):
		set_paused(true)


func _unhandled_input(event: InputEvent) -> void:
	if dedicated_server:
		return
	if event.is_echo():
		return
	if settings_menu.panel.visible:
		return
	if event.is_action_pressed("fullscreen"):
		settings.fullscreen = DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
		apply_graphics(false)
		settings.save()
	if event.is_action_pressed("performance"):
		settings.show_performance = not show_performance
		apply_graphics(false)
		settings.save()
	if event.is_action_pressed("quality"):
		settings.low_quality = not low_quality
		apply_graphics(false)
		settings.save()
	if paused and event.is_action_pressed("resolution_down"):
		cycle_resolution(-1)
	if paused and event.is_action_pressed("resolution_up"):
		cycle_resolution(1)
	if client_only and not session.active:
		if event.is_action_pressed("quit_game"):
			get_tree().quit()
		return
	if event.is_action_pressed("multiplayer_menu"):
		hud.contract_panel.hide()
		shop.hide()
		equipment_menu.hide()
		session.open_menu()
		return
	if event.is_action_pressed("contracts") and session.active:
		hud.toggle_contracts()
		return
	if event.is_action_pressed("station_shop"):
		if shop.visible:
			shop.close()
		else:
			shop.open()
		return
	if event.is_action_pressed("ship_equipment"):
		if equipment_menu.visible:
			equipment_menu.close()
		else:
			equipment_menu.open()
		return
	if event.is_action_pressed("pause_game"):
		hud.contract_panel.hide()
		if equipment_menu.visible:
			equipment_menu.close()
			return
		if shop.visible:
			shop.close()
			return
		session.menu.hide()
		set_paused(not paused)
		return
	if event.is_action_pressed("quit_game") and paused:
		get_tree().quit()
	if paused or not player.alive:
		return
	player.handle_mouse(event)
	if event.is_action_pressed("cycle_target"):
		cycle_target()
	if event.is_action_pressed("select_target"):
		pick_target(get_viewport().get_mouse_position())
	if event.is_action_pressed("fire"):
		if is_instance_valid(target) and target.alive:
			auto_fire = not auto_fire
		else:
			notify("Select an alien with %s or %s first." % [GameSettings.binding_text("cycle_target"), GameSettings.binding_text("select_target")])
	if event.is_action_pressed("repair"):
		request_repair()


func available_resolutions() -> Array[Vector2i]:
	var available: Array[Vector2i] = []
	var screen := DisplayServer.window_get_current_screen()
	# Leave room for window borders and the desktop taskbar.
	var usable := DisplayServer.screen_get_usable_rect(screen)
	for resolution in WINDOW_RESOLUTIONS:
		if resolution.x <= usable.size.x - 32 and resolution.y <= usable.size.y - 64:
			available.append(resolution)
	return available


func cycle_resolution(direction: int) -> void:
	var available := available_resolutions()
	if available.is_empty():
		return
	var current := DisplayServer.window_get_size()
	var index := available.find(current)
	if index < 0:
		index = -1 if direction > 0 else 0
	settings.resolution = available[posmod(index + direction, available.size())]
	settings.fullscreen = false
	apply_graphics()
	settings.save()


func apply_graphics(resize_window: bool = true) -> void:
	low_quality = settings.low_quality
	show_performance = settings.show_performance
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if low_quality else Viewport.MSAA_4X
	if DisplayServer.get_name() == "headless":
		return
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if resize_window:
			var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			var pixels := settings.resolution.min((usable.size - Vector2i(32, 64)).max(Vector2i(960, 600)))
			DisplayServer.window_set_size(pixels)
			DisplayServer.window_set_position(usable.position + (usable.size - pixels) / 2)


func _physics_process(delta: float) -> void:
	if is_instance_valid(session) and (session.active or session.connecting):
		session.tick(delta)
		return
	if dedicated_server or client_only:
		return
	if paused:
		return
	toast_time = maxf(0.0, toast_time - delta)
	validate_target()
	player.tick_combat(delta)
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
	for enemy: Alien in aliens.values():
		enemy.tick_combat(delta)
		if enemy.alive:
			enemy.fly(delta, player if player.alive and player.position.distance_to(STATION_POSITION) > 75.0 and player.position.distance_to(enemy.position) < float(enemy.tuning()["detection"]) else null, STATION_POSITION)
		else:
			enemy.respawn = maxf(0.0, enemy.respawn - delta)
			if enemy.respawn <= 0.0:
				enemy.position = enemy.home_position
				enemy.returning = false
				enemy.reset_encounter()
	weapon_status = player.firing_blocker(target)
	loot.tick(delta)


func _process(_delta: float) -> void:
	if is_instance_valid(hud):
		hud.queue_redraw()


func set_paused(value: bool) -> void:
	paused = value
	if not paused and is_instance_valid(settings_menu):
		settings_menu.dismiss()
	if paused:
		if is_instance_valid(player):
			player.release_mouse()
		auto_fire = false


func pick_target(screen_position: Vector2) -> void:
	var camera := player.camera
	var start := camera.project_ray_origin(screen_position)
	var finish := start + camera.project_ray_normal(screen_position) * 1500.0
	var query := PhysicsRayQueryParameters3D.create(start, finish, 3)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider is Alien and target_available(hit.collider):
		select_target(hit.collider)
	else:
		select_target(null)


func target_available(enemy: Alien) -> bool:
	return is_instance_valid(enemy) and enemy.available() and enemy.is_visible_in_tree()


func validate_target() -> void:
	if target != null and (not is_instance_valid(target) or not target.alive):
		select_target(null)
	elif target is Alien and target.returning:
		auto_fire = false


func cycle_target(screen_position: Vector2 = Vector2.INF) -> void:
	var camera := player.camera
	var viewport := get_viewport()
	var cursor := viewport.get_mouse_position() if screen_position == Vector2.INF else screen_position
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cursor = viewport.get_visible_rect().get_center()
	var nearest: Alien = null
	var nearest_distance: float = INF
	for enemy: Alien in aliens.values():
		if not target_available(enemy) or camera.is_position_behind(enemy.global_position):
			continue
		var enemy_screen_position := camera.unproject_position(enemy.global_position)
		if not viewport.get_visible_rect().has_point(enemy_screen_position):
			continue
		var distance := cursor.distance_squared_to(enemy_screen_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	# Pressing Tab again over the same enemy must not interrupt its fire intent.
	if nearest != null and nearest != target:
		select_target(nearest)


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
	if ship is Alien:
		var enemy := ship as Alien
		loot.spawn_drop(enemy)
		var reward: int = enemy.tuning()["reward"]
		if attacker == player:
			credits += reward
			kills += 1
			objective_stage = maxi(objective_stage, 3)
			notify("Alien destroyed. +%d credits. Return to Outpost 01 to repair." % reward)
		if target == enemy:
			select_target(null)
		enemy.respawn = enemy.tuning()["respawn"]
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
	select_target(null)


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
	SectorVisuals.sound(self, "purchase", player.position)
	return true


func notify(message: String) -> void:
	toast = message
	toast_time = 7.0
