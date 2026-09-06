class_name Pilot
extends SpaceShip

@export var cruise_speed: float = 36.0
@export var boost_speed: float = 78.0
@export var acceleration: float = 55.0
@export var mouse_sensitivity: float = 0.003

var energy: float = 100.0
var boosting: bool = false
var steering: bool = false
var camera: Camera3D
var arm: SpringArm3D


func _ready() -> void:
	super._ready()
	arm = SpringArm3D.new()
	arm.position = Vector3(0.0, 2.5, 0.0)
	arm.rotation.x = -0.12
	arm.spring_length = 16.0
	arm.margin = 0.5
	arm.collision_mask = 1
	arm.add_excluded_object(get_rid())
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = 6000.0
	camera.current = true
	arm.add_child(camera)


func handle_mouse(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		steering = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if steering else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and steering:
		# Screen-relative motion is unaffected by viewport stretch or resolution.
		rotation.y -= event.screen_relative.x * mouse_sensitivity
		rotation.x = clampf(rotation.x - event.screen_relative.y * mouse_sensitivity, -1.48, 1.48)


func release_mouse() -> void:
	steering = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func fly(delta: float) -> void:
	var movement := Vector3(
		Input.get_axis("strafe_left", "strafe_right"),
		Input.get_axis("move_down", "move_up"),
		Input.get_axis("forward", "backward")
	).limit_length()
	boosting = Input.is_action_pressed("boost") and movement.length() > 0.1 and energy > 1.0
	if boosting:
		energy = maxf(0.0, energy - 28.0 * delta)
	else:
		energy = minf(100.0, energy + 18.0 * delta)
	var speed := boost_speed if boosting else cruise_speed
	velocity = velocity.move_toward(global_basis * movement * speed, acceleration * delta)
	move_and_slide()
	model.rotation.z = lerp_angle(model.rotation.z, -movement.x * 0.23, delta * 5.0)
	camera.fov = lerpf(camera.fov, 83.0 if boosting else 75.0, delta * 3.0)
