extends SceneTree
## Capture the real exported model in the production Compatibility renderer.
## Run rendered, with -- --interactive for an orbitable inspection window.

var stage: SubViewport
var room: Node3D
var camera: Camera3D
var yaw := 0.55
var pitch := 0.18
var distance := 430.0
var focus := Vector3(0, 62, 0)
var dragging := false
var output := "res://art/station-review"


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Station rendering requires a graphics display.")
		quit(1)
		return
	DisplayServer.window_set_title("Dorbit — Outpost 01 model review")
	DisplayServer.window_set_size(Vector2i(1000, 900))
	stage = SubViewport.new()
	stage.size = Vector2i(1060, 1484)
	stage.own_world_3d = true
	stage.msaa_3d = Viewport.MSAA_4X
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var display := TextureRect.new()
	display.texture = stage.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	room = Node3D.new()
	stage.add_child(room)
	SectorVisuals.environment(room)
	SectorVisuals.station(room, Vector3.ZERO)
	camera = Camera3D.new()
	camera.fov = 46
	camera.far = 10000
	room.add_child(camera)
	camera.current = true
	update_camera()
	if "--interactive" in OS.get_cmdline_user_args():
		display.gui_input.connect(orbit_input)
		return
	await capture("godot-hero")
	var preferences := GameSettings.new()
	preferences.shadow_quality = 3
	SectorVisuals.apply_graphics(room, preferences)
	await capture("godot-hero-shadows")
	preferences.shadow_quality = 0
	SectorVisuals.apply_graphics(room, preferences)
	yaw = PI
	pitch = .14
	update_camera()
	await capture("godot-rear")
	yaw = -.7
	pitch = -.65
	update_camera()
	await capture("godot-underside")
	focus = Vector3(0, 40, 8)
	distance = 165
	yaw = .35
	pitch = .15
	update_camera()
	await capture("godot-hangars")
	# A real flight view and slow approach into the service hangar.
	room.free()
	stage.size = Vector2i(1440, 900)
	var sector := preload("res://scenes/sector.tscn").instantiate()
	sector.offline = true
	sector.client_only = false
	stage.add_child(sector)
	sector.set_physics_process(false)
	sector.main_menu.hide()
	sector.preflight = false
	sector.set_paused(false)
	sector.player.position = Sector.STATION_POSITION + Vector3(65, 35, 175)
	sector.player.look_at(Sector.STATION_POSITION + Vector3(0, 65, 0))
	sector.player.camera.current = true
	await capture("godot-flight")
	sector.player.position = Sector.STATION_POSITION + Vector3(0, 0, 50)
	sector.player.look_at(Sector.STATION_POSITION)
	sector.player.velocity = Vector3.ZERO
	for frame in range(85):
		sector.player.fly_command(1.0 / 60.0, Vector3.FORWARD, false)
		await physics_frame
	sector.player.velocity = Vector3.ZERO
	if not sector.repair_blocker().is_empty():
		push_error("Rendered hangar approach did not reach station services.")
		quit(1)
		return
	await capture("godot-dock")
	print("Rendered station hero, rear, underside, hangars, flight and service approach.")
	quit()


func update_camera() -> void:
	camera.position = focus + Vector3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch))*distance
	camera.look_at(focus)


func orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 85, 900)
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * .007
		pitch = clampf(pitch + event.relative.y * .007, -1.4, 1.4)
	update_camera()


func capture(label: String) -> void:
	for frame in range(32):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := stage.get_texture().get_image().save_png(output.path_join(label + ".png"))
	if error != OK:
		push_error("Could not save station view: " + label)
		quit(1)
