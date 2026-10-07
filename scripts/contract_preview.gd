class_name ContractPreview
extends SubViewportContainer
## Isolated preview of the actual encounter model and its type-specific fittings.

var viewport: SubViewport
var model: Node3D
var camera: Camera3D
var selected_kind := ""


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 200)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b8c9dc")
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	camera.position = Vector3(8, 7, -10)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.8
	viewport.add_child(light)
	show_kind("Scout")


func show_kind(kind: String) -> void:
	if kind == selected_kind:
		return
	selected_kind = kind
	camera.size = {"Scout": 5.5, "Sentinel": 7.0, "Heavy": 10.0}[kind]
	if is_instance_valid(model):
		viewport.remove_child(model)
		model.queue_free()
	model = SectorVisuals.ship_model(true)
	var tuning: Dictionary = Alien.TYPES[kind]
	model.scale = tuning["scale"]
	SectorVisuals.box(model, Vector3(0, 1, 0), Vector3(1.5, 0.15, 2.5), SectorVisuals.material(tuning["color"], true))
	if kind == "Heavy":
		SectorVisuals.box(model, Vector3(0, -0.6, 0), Vector3(4.5, 0.8, 3.5), SectorVisuals.material(Color("58446f")))
	viewport.add_child(model)
