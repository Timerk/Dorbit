class_name SpaceDust
extends MultiMeshInstance3D
## Client-only drifting dust around the active camera. It gives flight a sense of
## speed and direction; velocity comes from camera motion, not network state.

const DUST_SHADER := preload("res://shaders/space_dust.gdshader")
const COUNT: int = 700
const BOX_SIZE: float = 140.0
const TELEPORT_SPEED: float = 400.0 # Rescues, jumps and corrections reset tracking.
const MAX_STREAK_SPEED: float = 120.0 # Frame hitches cannot stretch streaks across the view.

var surface := ShaderMaterial.new()
var last_position: Vector3
var tracking: bool = false
var velocity := Vector3.ZERO


static func attach(parent: Node3D) -> SpaceDust:
	var dust := SpaceDust.new()
	dust.name = "SpaceDust"
	parent.add_child(dust)
	return dust


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = quad
	instances.instance_count = COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 5519
	for index in range(COUNT):
		instances.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.35, 1.0)))
	multimesh = instances
	surface.shader = DUST_SHADER
	surface.set_shader_parameter("box_size", BOX_SIZE)
	material_override = surface
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader places every mote around the camera, so the node itself is never culled.
	custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or delta <= 0.0:
		return
	var location := camera.global_position
	if not tracking or location.distance_to(last_position) > TELEPORT_SPEED * delta:
		tracking = true
		velocity = Vector3.ZERO
	else:
		var measured := ((location - last_position) / delta).limit_length(MAX_STREAK_SPEED)
		velocity = velocity.lerp(measured, 1.0 - exp(-delta * 12.0))
	last_position = location
	surface.set_shader_parameter("velocity", velocity)
