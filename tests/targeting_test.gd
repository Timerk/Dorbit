extends "res://tests/encounter_test.gd"
## Cursor selection and persistent locks through the actual input and snapshot paths.


var cursor: Vector2


func target_at(position: Vector2) -> void:
	cursor = position
	if DisplayServer.get_name() == "headless":
		# The headless display cannot move an OS cursor. Use the same selection method.
		sector.cycle_target(cursor)
	else:
		root.warp_mouse(cursor)
		await process_frame
		await tap_key(KEY_TAB)


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	sector.weapon_status = sector.player.firing_blocker(sector.target)
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://build/validation")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	sector.player.position = Vector3(0, 200, 0)
	sector.player.rotation = Vector3.ZERO
	sector.aliens[0].position = Vector3(0, 200, -650)
	sector.aliens[1].position = Vector3(-65, 200, -140)
	sector.aliens[2].position = Vector3(65, 200, -140)
	sector.aliens[3].position = Vector3(0, 200, 90)
	sector.aliens[4].position = Vector3(900, 200, -100)
	await sync_physics()
	var camera := sector.player.camera
	await target_at(camera.unproject_position(sector.aliens[2].global_position))
	check(sector.target == sector.aliens[2], "Tab selects the enemy nearest the cursor rather than the pilot")
	await capture("targeting-cursor")
	await tap_key(KEY_SPACE)
	await target_at(cursor)
	check(sector.target == sector.aliens[2] and sector.auto_fire, "Repeated Tab keeps the closest target and active fire")
	await target_at(camera.unproject_position(sector.aliens[1].global_position))
	check(sector.target == sector.aliens[1] and not sector.auto_fire, "Moving the cursor and pressing Tab manually retargets")
	await target_at(camera.unproject_position(sector.aliens[0].global_position))
	check(sector.target == sector.aliens[0], "Cursor selection can acquire an enemy beyond the old 550 m limit")
	sector.select_target(sector.aliens[2])
	sector.auto_fire = true
	sector.aliens[2].position = Vector3(0, 200, -900)
	sector.validate_target()
	check(sector.target == sector.aliens[2] and sector.auto_fire, "Leaving selection and weapon range preserves lock and fire intent")
	check(sector.player.firing_blocker(sector.target) == "OUT OF RANGE", "A retained lock cannot bypass weapon range")
	await capture("targeting-distant-lock")
	sector.aliens[2].position = Vector3(0, 200, 90)
	sector.validate_target()
	check(sector.target == sector.aliens[2], "Turning away from an enemy preserves its lock")
	sector.aliens[2].returning = true
	sector.validate_target()
	check(sector.target == sector.aliens[2] and not sector.auto_fire, "A living enemy returning home remains locked while fire stops")
	sector.auto_fire = true
	var snapshot := sector.session.combat.pack_alien(sector.aliens[2])
	snapshot["encounter"] += 1
	sector.session.combat.apply_alien(snapshot)
	check(sector.target == sector.aliens[2] and not sector.auto_fire, "Encounter reset preserves the living target and stops stale fire")
	sector.aliens[2].alive = false
	sector.validate_target()
	check(sector.target == null and not sector.auto_fire, "Destroyed targets clear the lock and fire")
	sector.aliens[0].returning = true
	await target_at(camera.unproject_position(sector.aliens[0].global_position))
	check(sector.target == sector.aliens[1], "Tab excludes returning, behind-camera and off-screen candidates")
	sector.aliens[0].returning = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await target_at(Vector2.ZERO)
		check(sector.target == sector.aliens[0], "Tab uses screen center while steering captures the mouse")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var retained := sector.target
	for enemy: Alien in sector.aliens.values():
		enemy.position = Vector3(0, 200, 90)
	await target_at(cursor)
	check(sector.target == retained, "Tab with no on-screen candidate preserves the existing lock")
	sector.select_target(null)
	await target_at(cursor)
	check(sector.target == null, "Tab never selects enemies behind the camera")
	print("Targeting checks: %d assertions, %d failures" % [checks, failures])
	sector.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
