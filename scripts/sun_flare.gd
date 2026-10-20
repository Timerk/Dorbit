class_name SunFlare
extends CanvasLayer
## Client-only lens flare for the sector's star. Asteroids, the station and
## ships block it with a physics ray; it fades as the sun leaves the view.

const FLARE_SHADER := preload("res://shaders/sun_flare.gdshader")
const OCCLUSION_DISTANCE: float = 4000.0
const FADE_RATE: float = 10.0

var sector: Node3D
var overlay := ColorRect.new()
var surface := ShaderMaterial.new()
var intensity: float = 0.0


static func attach(parent: Node3D) -> SunFlare:
	var flare := SunFlare.new()
	flare.name = "SunFlare"
	flare.sector = parent
	# Below the HUD and menus, above the 3D view.
	flare.layer = -1
	parent.add_child(flare)
	return flare


func _ready() -> void:
	surface.shader = FLARE_SHADER
	overlay.material = surface
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)


func _process(delta: float) -> void:
	var target := visibility()
	intensity = lerpf(intensity, target, 1.0 - exp(-delta * FADE_RATE))
	overlay.visible = intensity > 0.002
	surface.set_shader_parameter("intensity", intensity)


func visibility() -> float:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	var world := sector.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if camera == null or world == null or viewport.disable_3d:
		return 0.0
	var sky := world.environment.sky.sky_material as ShaderMaterial
	var direction := (sky.get_shader_parameter("sun_direction") as Vector3).normalized()
	surface.set_shader_parameter("sun_color", sky.get_shader_parameter("sun_color"))
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	if forward.dot(direction) <= 0.2:
		return 0.0
	var size := viewport.get_visible_rect().size
	var screen := camera.unproject_position(origin + direction * 1000.0) / size
	surface.set_shader_parameter("sun_position", screen)
	surface.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	# Fade over the last stretch before the sun leaves the screen.
	var edge := minf(minf(screen.x, 1.0 - screen.x), minf(screen.y, 1.0 - screen.y))
	var framing := clampf(edge / 0.08 + 1.0, 0.0, 1.0)
	if framing <= 0.0:
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * OCCLUSION_DISTANCE, 1)
	if not sector.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return 0.0
	return framing
