class_name Pilot
extends SpaceShip

@export var cruise_speed: float = 36.0
@export var boost_speed: float = 78.0
@export var acceleration: float = 40.0
@export var braking: float = 60.0
@export var counter_thrust: float = 80.0
@export_range(0.01, 0.2) var steering_response: float = 0.065
@export var mouse_sensitivity: float = 0.003

var energy: float = 100.0
var boosting: bool = false
var steering: bool = false
var camera: Camera3D
var arm: SpringArm3D
var pending_look: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	if not render_enabled:
		return
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


func reset_health() -> void:
	super.reset_health()
	pending_look = Vector2.ZERO


func handle_mouse(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		steering = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if steering else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and steering:
		# Screen-relative motion is unaffected by viewport stretch or resolution.
		pending_look -= event.screen_relative * mouse_sensitivity
		pending_look.y = clampf(rotation.x + pending_look.y, -1.48, 1.48) - rotation.x


func release_mouse() -> void:
	steering = false
	pending_look = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func fly(delta: float) -> void:
	fly_command(delta, read_movement(), Input.is_action_pressed("boost"))


func read_movement() -> Vector3:
	return Vector3(
		Input.get_axis("strafe_left", "strafe_right"),
		Input.get_axis("move_down", "move_up"),
		Input.get_axis("forward", "backward")
	).limit_length()


func fly_command(delta: float, movement: Vector3, boost: bool) -> void:
	# Ease mouse motion over a few frames; remote ships receive the resulting angles.
	var look_step := pending_look * (1.0 - exp(-delta / steering_response))
	pending_look -= look_step
	rotation.y += look_step.x
	rotation.x = clampf(rotation.x + look_step.y, -1.48, 1.48)
	movement = movement.limit_length()
	boosting = boost and movement.length() > 0.1 and energy > 1.0
	if boosting:
		energy = maxf(0.0, energy - 28.0 * delta)
	else:
		energy = minf(100.0, energy + 18.0 * delta)
	var speed := boost_speed if boosting else cruise_speed
	var desired_velocity := global_basis * movement * speed
	var thrust := acceleration
	# Keep world-space momentum through turns, with stronger assistance when stopping or reversing.
	if velocity.dot(desired_velocity) < 0.0:
		thrust = counter_thrust
	elif desired_velocity.length_squared() < velocity.length_squared():
		thrust = braking
	velocity = velocity.move_toward(desired_velocity, thrust * delta)
	move_and_slide()
	if render_enabled:
		model.rotation.z = lerp_angle(model.rotation.z, -movement.x * 0.23, delta * 5.0)
		camera.fov = lerpf(camera.fov, 83.0 if boosting else 75.0, delta * 3.0)
