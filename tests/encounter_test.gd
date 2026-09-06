extends SceneTree
## Headless integration checks against the actual encounter and physics world.

var sector: Sector
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func sync_physics() -> void:
	await physics_frame
	await process_frame


func tap_key(code: Key, physical: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code if physical else KEY_NONE
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	root.add_child(sector)
	sector.set_physics_process(false)
	await sync_physics()
	var player := sector.player
	var alien := sector.alien
	await tap_key(KEY_TAB)
	check(sector.target == alien, "Tab input selects the alien")
	await tap_key(KEY_SPACE)
	check(sector.auto_fire, "Space input toggles laser fire")
	await tap_key(KEY_F3)
	check(sector.show_performance, "F3 input toggles performance overlay")
	await tap_key(KEY_F3, false)
	check(not sector.show_performance, "Logical-only keyboard input is supported")
	await tap_key(KEY_ESCAPE)
	check(sector.paused, "Escape input pauses the game")
	await tap_key(KEY_ESCAPE)
	check(not sector.paused, "Escape input resumes the game")
	sector.select_target(null)

	# Shields must absorb first, with only excess damage reaching the hull.
	player.take_damage(80.0, alien)
	check(is_equal_approx(player.shield, 0.0), "Damage depletes shields before hull")
	check(is_equal_approx(player.hull, 110.0), "Only shield overflow damages hull")
	player.tick_combat(5.0)
	check(is_zero_approx(player.shield), "Shields wait before regenerating")
	player.tick_combat(1.0)
	check(player.shield > 0.0, "Shields regenerate after the combat delay")
	player.reset_health()

	# A shot needs range, aim, line of sight, and an available cooldown.
	player.position = Vector3(0, 60, 0)
	player.rotation = Vector3.ZERO
	alien.position = Vector3(0, 60, -100)
	await sync_physics()
	check(player.try_fire(alien), "Valid target can be fired on")
	var after_first_shot := alien.shield
	check(not player.try_fire(alien), "Cooldown prevents an immediate second shot")
	check(is_equal_approx(alien.shield, after_first_shot), "Blocked shot does not apply damage")
	player.tick_combat(1.0)
	alien.position.z = -250
	await sync_physics()
	check(not player.try_fire(alien), "Out-of-range target cannot be hit")
	alien.position.z = 100
	await sync_physics()
	check(not player.try_fire(alien), "Target behind ship cannot be hit")
	alien.position.z = -100
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 60, -50)
	sector.add_child(wall)
	await sync_physics()
	check(not player.try_fire(alien), "An obstacle blocks laser damage")
	wall.queue_free()
	await sync_physics()
	check(player.try_fire(alien), "Removing an obstacle restores line of sight")

	# Death is one transition: repeated hits never award repeated rewards.
	sector.select_target(alien)
	sector.auto_fire = true
	alien.take_damage(999.0, player)
	alien.take_damage(999.0, player)
	check(sector.credits == Sector.KILL_REWARD, "One kill awards exactly one reward")
	check(sector.kills == 1 and not alien.alive, "Alien destruction updates the encounter")
	check(sector.target == null and not sector.auto_fire, "Destroyed target clears lock and autofire")
	check(sector.alien_respawn > 0.0, "A replacement alien is scheduled")

	# Repair must require a safe, slow station approach, and allow recovery at zero credits.
	player.take_damage(100.0, alien)
	player.time_since_hit = 10.0
	check(not sector.request_repair(), "Repairs are rejected away from the station")
	player.position = Sector.SPAWN_POSITION
	player.velocity = Vector3(20, 0, 0)
	check(not sector.request_repair(), "Repairs require slowing down")
	player.velocity = Vector3.ZERO
	player.time_since_hit = 0.0
	check(not sector.request_repair(), "Recent damage prevents instant repairs")
	player.time_since_hit = 6.0
	var expected_cost := sector.repair_cost()
	check(expected_cost > 0, "Hull damage has a repair cost")
	check(sector.request_repair(), "Docking repairs succeed")
	check(sector.credits == Sector.KILL_REWARD - expected_cost, "Repair cost is deducted once")
	check(player.hull == player.max_hull and player.shield == player.max_shield, "Repair restores hull and shields")
	check(sector.objective_stage == 4, "Hunt and repair complete the first encounter")
	sector.credits = 0
	player.take_damage(100.0, alien)
	player.time_since_hit = 6.0
	check(sector.request_repair() and sector.credits == 0, "A broke player can recover without negative credits")

	# Destruction and rescue preserve remaining credits and reset motion and target state.
	sector.credits = 25
	player.take_damage(999.0, alien)
	player.take_damage(999.0, alien)
	check(sector.credits == 15, "Rescue fee is charged once")
	check(not player.alive and sector.player_respawn > 0.0, "Destruction schedules rescue")
	sector._physics_process(3.1)
	check(player.alive and player.position.is_equal_approx(Sector.SPAWN_POSITION), "Rescue respawns at station")
	check(player.velocity.is_zero_approx() and player.hull == player.max_hull, "Rescue resets health and velocity")
	check(alien.alive and alien.position.distance_to(alien.home_position) < 1.0, "Rescue resets alien away from station")

	# Verify input wiring, braking, pause, and boost through actual movement.
	var start := player.position
	Input.action_press("forward")
	for frame in range(30):
		player.fly(1.0 / 60.0)
		await sync_physics()
	Input.action_release("forward")
	check(player.position.z < start.z - 1.0, "W moves forward along the ship axis")
	for frame in range(50):
		player.fly(1.0 / 60.0)
	check(player.velocity.is_zero_approx(), "Releasing movement brakes the ship")
	Input.action_press("move_up")
	Input.action_press("boost")
	player.fly(0.1)
	Input.action_release("boost")
	Input.action_release("move_up")
	check(player.velocity.y > 0.0 and player.energy < 100.0, "Vertical movement and boost consume energy")
	var mouse_button := InputEventMouseButton.new()
	mouse_button.button_index = MOUSE_BUTTON_RIGHT
	mouse_button.pressed = true
	player.handle_mouse(mouse_button)
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(100, -50)
	player.handle_mouse(mouse_motion)
	check(player.rotation.y < 0.0 and player.rotation.x > 0.0, "Right-mouse steering changes yaw and pitch")
	mouse_motion.relative = Vector2(0, -10000)
	player.handle_mouse(mouse_motion)
	check(player.rotation.x <= 1.481, "Camera pitch stays within comfortable limits")
	sector.set_paused(true)
	check(not player.steering and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pause releases mouse capture")
	var paused_position := player.position
	sector._physics_process(1.0)
	check(player.position == paused_position, "Pause freezes simulation")
	sector.set_paused(false)

	print("Encounter checks: %d passed, %d failed" % [checks - failures, failures])
	sector.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
