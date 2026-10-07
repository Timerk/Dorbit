class_name ShipHangarPreview
extends TextureRect
## An isolated, on-demand view of the same hull and PBR materials used in flight.

var stage: SubViewport
var room: Node3D
var hull: Node3D
var camera: Camera3D
var model_id := ""
var hull_only := false
var yaw := -2.48
var pitch := 0.55
var distance := 9.2
var dragging := false
var frames_pending := 0


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Drag to rotate your ship. Scroll to zoom. Double-click to reset the view."
	stage = SubViewport.new()
	stage.name = "HangarViewport"
	stage.own_world_3d = true
	stage.size = Vector2i(640, 360)
	stage.msaa_3d = get_viewport().msaa_3d
	stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(stage)
	texture = stage.get_texture()
	room = Node3D.new()
	room.name = "Hangar"
	stage.add_child(room)
	build_room()
	camera = Camera3D.new()
	camera.fov = 38
	camera.near = .1
	camera.far = 80
	camera.current = true
	room.add_child(camera)
	update_camera()
	resized.connect(update_size)
	update_size()
	visibility_changed.connect(update_visibility)
	add_to_group("graphics_previews")


func surface(color: Color, metallic: float, roughness: float, emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 3.0
	return material


func box(position: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	return SectorVisuals.box(room, position, dimensions, material)


func build_room() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101823")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("aec3db")
	environment.ambient_light_energy = .38
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.sky = Sky.new()
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_256
	var sky := ShaderMaterial.new()
	sky.shader = preload("res://shaders/hangar_reflections.gdshader")
	environment.sky.sky_material = sky
	world.environment = environment
	room.add_child(world)
	var dark := surface(Color("18232f"), .7, .42)
	var steel := surface(Color("34414d"), .8, .32)
	var floor_material := ShaderMaterial.new()
	floor_material.shader = preload("res://shaders/hangar_floor.gdshader")
	box(Vector3(0, -1.25, 0), Vector3(20, .2, 22), floor_material)
	box(Vector3(0, 3, 7), Vector3(20, 8, .3), dark)
	for side in [-1, 1]:
		box(Vector3(side * 9, 3, 0), Vector3(.3, 8, 14), dark)
		for z in [-5, 0, 5]:
			box(Vector3(side * 8.7, 2.6, z), Vector3(.4, 7.5, .45), steel)
		box(Vector3(side * 7.9, 5.3, .5), Vector3(.12, .12, 12), surface(Color("cfdded"), 0, .5, true))
		box(Vector3(side * 6.3, -.75, 3), Vector3(3, .08, .09), surface(Color("ff9d35"), 0, .5, true))
	for x in [-6, -3, 0, 3, 6]:
		box(Vector3(x, 2.6, 6.75), Vector3(2.7, 6.6, .13), steel)
		box(Vector3(x, 1.6, 6.60), Vector3(.10, 2.5, .04), surface(Color("ffad50"), 0, .5, true))
	# The cradle and actual directional shadow ground the hull above the deck.
	for side in [-1, 1]:
		box(Vector3(side * 1.05, -.91, .9), Vector3(.38, .5, 1.5), dark)
		box(Vector3(side * 1.05, -.61, .9), Vector3(.55, .10, 1.65), steel)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -28, 0)
	key.light_color = Color("e6efff")
	key.light_energy = 1.1
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	key.shadow_opacity = .7
	key.directional_shadow_max_distance = 30
	room.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 130, 0)
	fill.light_color = Color("a7caff")
	fill.light_energy = .4
	room.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-3, 3, 4)
	rim.light_color = Color("ffd6a2")
	rim.light_energy = 1.8
	rim.omni_range = 12
	room.add_child(rim)
	if hull_only:
		# Keep the approved menu backdrop behind the live, separately lit hull.
		stage.transparent_bg = true
		environment.background_mode = Environment.BG_CLEAR_COLOR
		for node: MeshInstance3D in room.find_children("*", "MeshInstance3D", true, false):
			node.hide()


func set_model(value: String) -> void:
	value = ShipCatalog.canonical(value)
	if value == model_id:
		return
	model_id = value
	if is_instance_valid(hull):
		room.remove_child(hull)
		hull.queue_free()
	hull = ShipCatalog.model_scene(value)
	hull.name = "PreviewHull"
	room.add_child(hull)
	apply_graphics()


func apply_graphics() -> void:
	stage.msaa_3d = get_viewport().msaa_3d
	if is_instance_valid(hull):
		SectorVisuals.configure_texture_filtering(hull, SectorVisuals.texture_filtering_enabled(self))
	request_render()


func update_size() -> void:
	stage.size = Vector2i(size.clamp(Vector2(240, 160), Vector2(1280, 900)))
	request_render()


func update_visibility() -> void:
	dragging = false
	if is_visible_in_tree():
		request_render()
	else:
		frames_pending = 0
		stage.render_target_update_mode = SubViewport.UPDATE_DISABLED


func request_render() -> void:
	if not is_visible_in_tree() or not is_instance_valid(stage):
		return
	# Allow the sky radiance and first shadow frame to settle, then cache the view.
	frames_pending = 12
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _process(_delta: float) -> void:
	if frames_pending > 0:
		frames_pending -= 1
		if frames_pending == 0:
			stage.render_target_update_mode = SubViewport.UPDATE_DISABLED


func update_camera() -> void:
	var target := Vector3(0, -.12, 0)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)
	request_render()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.double_click:
				yaw = -2.48
				pitch = .55
				distance = 9.2
				update_camera()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance + (-.6 if event.button_index == MOUSE_BUTTON_WHEEL_UP else .6), 7.5, 16)
			update_camera()
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * .009
		pitch = clampf(pitch + event.relative.y * .006, .10, 1.45)
		update_camera()
		accept_event()
