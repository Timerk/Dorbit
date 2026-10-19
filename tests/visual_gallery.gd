extends SceneTree
## Rendered in-flight gallery for visual review; writes PNGs to build/validation/gallery.
## Usage: godot --path . --script res://tests/visual_gallery.gd -- [--gallery-tag=name] [--gallery-max]

const OUTPUT := "res://build/validation/gallery"

var sector: Sector
var tag := "current"
var frame_delta: float = 1.0 / 60.0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--gallery-tag="):
			tag = argument.get_slice("=", 1)
	run.call_deferred()


func _process(delta: float) -> bool:
	frame_delta = delta
	if is_instance_valid(sector):
		sector.set_paused(false)
	return false


func frames(count: int) -> void:
	for index in range(count):
		await process_frame


func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_texture().get_image().save_png(OUTPUT.path_join("%s-%s.png" % [tag, label]))


func pose(position: Vector3, look: Vector3) -> void:
	sector.player.position = position
	sector.player.velocity = Vector3.ZERO
	sector.player.look_at(look)
	await frames(12)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual gallery requires a rendered window")
		quit(1)
		return
	root.content_scale_size = Vector2i(1600, 900)
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	current_scene = sector
	sector.set_physics_process(false)
	sector.settings = GameSettings.new()
	if "--gallery-max" in OS.get_cmdline_user_args():
		sector.settings.bloom = true
		sector.settings.ssao = true
		sector.settings.shadow_quality = 3
	sector.apply_graphics(false)
	root.size = Vector2i(1600, 900)
	sector.session.menu.hide()
	if is_instance_valid(sector.main_menu):
		sector.main_menu.hide()
	sector.preflight = false
	sector.hud.hide()
	await frames(30)
	for enemy: Alien in sector.aliens.values():
		enemy.set_physics_process(false)
	# Station departure, facing the outpost.
	await pose(Sector.STATION_POSITION + Vector3(60, 25, 90), Sector.STATION_POSITION + Vector3(0, 60, 0))
	await capture("01-station")
	# Looking out across the asteroid field and the backdrop.
	var rock := sector.get_node("Asteroid4") as Node3D
	await pose(rock.position + Vector3(30, 12, 60), rock.position)
	await capture("02-asteroid")
	await pose(Vector3(0, 10, 40), Vector3(0, 0, -400))
	await capture("03-field")
	await pose(Vector3(0, 10, 40), Vector3(400, 30, 200))
	await capture("04-backdrop")
	var sun_direction := Basis.from_euler(SectorVisuals.SUN_ROTATION * PI / 180.0).z
	await pose(Vector3(0, 10, 40), Vector3(0, 10, 40) + sun_direction * 100.0 + Vector3(0, -30, 0))
	await capture("04b-sun")
	# Cruise and boost through the field so dust streaks show motion.
	for speed: float in [41.0, 78.0]:
		await pose(Vector3(120, 40, 160), Vector3(120, 40, -400))
		for index in range(30):
			await process_frame
			sector.player.position += Vector3(0, 0, -speed) * frame_delta
		await capture("04c-flight-%d" % speed)
	# Alien close-up and lasers.
	var enemy := sector.alien
	await pose(Vector3(200, 100, 50), Vector3(214, 102, 18))
	enemy.position = Vector3(214, 102, 18)
	enemy.look_at(sector.player.position)
	await frames(8)
	await capture("05-alien")
	sector.player.boosting = true
	for index in range(4):
		SectorVisuals.laser(sector, sector.player.position + Vector3(0, -0.4, -2), enemy.position, false)
		await frames(3)
	SectorVisuals.laser(sector, enemy.position, sector.player.position, true)
	SectorVisuals.impact(enemy, enemy.position, false, true)
	await frames(2)
	await capture("06-combat")
	await frames(30)
	SectorVisuals.explosion(sector, enemy.position, 12.0)
	await create_timer(0.15).timeout
	await capture("07-explosion")
	await create_timer(0.35).timeout
	await capture("08-explosion-late")
	sector.player.boosting = false
	sector.queue_free()
	await process_frame
	quit(0)
