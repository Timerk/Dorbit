class_name Pilot
extends SpaceShip

const INERTIA_REFERENCE_SPEED: float = 41.0 # Starter Liberator with its Ion engine.
const INERTIA_FALLOFF_SPEED: float = 40.0
const MIN_INERTIA_RATIO: float = 0.3
# Servers turn remote ships toward commanded angles no faster than this. Mouse
# easing completes ~95% of a turn in 0.2 s; 720°/s plus the allowance covers a
# 180° flick in that time, so honest steering is not visibly delayed.
const MAX_TURN_RATE: float = TAU * 2.0
const TURN_LATENCY_ALLOWANCE: float = 0.05 # One command interval absorbs jittered packets.
const ARM_POSITION := Vector3(0.0, 2.5, 0.0)

@export var cruise_speed: float = 41.0
@export var boost_speed: float = 83.0
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
var ship_model: String = "liberator"
var radiation_exposure: float = 0.0
var ammo: Dictionary = Ammunition.starter()
var ammo_type: String = "x1"
var laser_count: int = 1 # Offline starter fitting; server fittings update this.
var ammo_debit: Callable # Dedicated server commits consumption before firing.

var resource_boosts: Dictionary = {}
var laser_loadout: Array = []
var rockets := RocketWeapons.new()
var repair_seconds: float = 0.0
var repair_auto: bool = false
var repair_requested: bool = false
var robot_repairing: bool = false
var time_since_attack: float = 100.0
var extras_clock: float = 0.0
var repair_visual: RepairBotVisual
var exhaust: ShipExhaust
var turn_budget: float = 0.0
## Facing used by simulate_input(). The server copies it to `rotation`; the
## owning client keeps its view in `rotation` instead.
var sim_rotation: Vector3 = Vector3.ZERO
## World-space render offset of the model and camera; see set_visual_offset().
var visual_offset: Vector3 = Vector3.ZERO


func firing_blocker(target: SpaceShip) -> String:
	var reason := super.firing_blocker(target)
	if reason.is_empty() and int(ammo.get(ammo_type, 0)) < laser_count:
		return "OUT OF AMMO / NEED %d ROUNDS / SELECT ANOTHER TYPE" % laser_count
	return reason


func spend_ammo() -> bool:
	if laser_count <= 0 or int(ammo.get(ammo_type, 0)) < laser_count:
		return false
	if ammo_debit.is_valid() and not ammo_debit.call():
		return false
	ammo[ammo_type] -= laser_count
	time_since_attack = 0.0
	repair_requested = false
	return true


func shot_damage(target: SpaceShip) -> float:
	var damage := super.shot_damage(target)
	if ResourceBoosts.remaining(resource_boosts, "lasers") > 0:
		damage = ResourceBoosts.laser_damage(laser_loadout, target is Alien, resource_boosts)
	return damage * int(Ammunition.TYPES[ammo_type]["multiplier"])


func set_ship_model(value: String) -> void:
	value = ShipCatalog.canonical(value)
	if ship_model == value:
		return
	ship_model = value
	if render_enabled and is_instance_valid(model):
		remove_child(model)
		model.queue_free()
		attach_model()


func attach_model() -> void:
	model = ShipCatalog.model_scene(ship_model)
	add_child(model)
	SectorVisuals.configure_texture_filtering(model, SectorVisuals.texture_filtering_enabled(self))
	exhaust = ShipExhaust.attach(model, self)


func _ready() -> void:
	rockets.ship = self
	super._ready()
	if not render_enabled:
		return
	remove_child(model)
	model.queue_free()
	attach_model()
	arm = SpringArm3D.new()
	arm.position = ARM_POSITION
	arm.rotation.x = -0.12
	arm.spring_length = 16.0
	arm.margin = 0.5
	arm.collision_mask = 1
	arm.add_excluded_object(get_rid())
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = 8500.0 # Distant campaign landmarks remain visible across the sector.
	camera.current = true
	arm.add_child(camera)


func _process(_delta: float) -> void:
	if render_enabled and robot_repairing and not is_instance_valid(repair_visual):
		repair_visual = RepairBotVisual.new()
		add_child(repair_visual)


func reset_health() -> void:
	super.reset_health()
	repair_requested = false
	robot_repairing = false
	time_since_attack = 100.0
	pending_look = Vector2.ZERO
	radiation_exposure = 0.0
	rockets.unload()


func tick_combat(delta: float) -> void:
	super.tick_combat(delta)
	rockets.tick(delta)


func handle_mouse(event: InputEvent) -> void:
	if event.is_action("steer"):
		steering = event.is_action_pressed("steer")
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


func thrust_multiplier() -> float:
	# Fitted cruise speed gives braking and redirection consistent assistance
	# on clients and the server, including while boosting.
	var speed := maxf(cruise_speed, INERTIA_REFERENCE_SPEED)
	var inertia := MIN_INERTIA_RATIO + (1.0 - MIN_INERTIA_RATIO) * exp(
		-(speed - INERTIA_REFERENCE_SPEED) / INERTIA_FALLOFF_SPEED)
	return speed / INERTIA_REFERENCE_SPEED / inertia


func turn_toward(angles: Vector3, delta: float) -> void:
	# Clients predict their own facing; the server only follows it at a bounded rate.
	rotation = bounded_turn(rotation, angles, delta)


## Steps `from` toward `angles` within the turn budget, spending it.
func bounded_turn(from: Vector3, angles: Vector3, delta: float) -> Vector3:
	turn_budget = minf(turn_budget + MAX_TURN_RATE * delta, MAX_TURN_RATE * (delta + TURN_LATENCY_ALLOWANCE))
	var step := Vector2(angle_difference(from.y, angles.y), angles.x - from.x).limit_length(turn_budget)
	turn_budget -= step.length()
	return Vector3(clampf(from.x + step.y, -1.48, 1.48), wrapf(from.y + step.x, -PI, PI), 0.0)


func fly_command(delta: float, movement: Vector3, boost: bool) -> void:
	apply_look(delta)
	thrust(delta, movement, boost, global_basis)
	present_motion(delta, movement)


## Eases mouse motion over a few frames; remote ships receive the resulting angles.
func apply_look(delta: float) -> void:
	var look_step := pending_look * (1.0 - exp(-delta / steering_response))
	pending_look -= look_step
	rotation.y += look_step.x
	rotation.x = clampf(rotation.x + look_step.y, -1.48, 1.48)


## One networked input tick, run identically by the server and, when
## predicting and replaying, by the owning client: turn `sim_rotation` toward
## the requested facing within the turn limit, then thrust along it. The body
## moves with the simulation facing, so collision contacts match on both
## sides; the node's previous `rotation` is restored afterwards, so the
## owner's view can lead the turn-limited simulation facing during flicks.
func simulate_input(delta: float, movement: Vector3, boost: bool, facing: Vector3) -> void:
	sim_rotation = bounded_turn(sim_rotation, facing, delta)
	var view := rotation
	rotation = sim_rotation
	thrust(delta, movement, boost, Basis.from_euler(sim_rotation))
	rotation = view


func thrust(delta: float, movement: Vector3, boost: bool, facing: Basis) -> void:
	movement = movement.limit_length()
	boosting = boost and movement.length() > 0.1 and energy > 1.0
	if boosting:
		energy = maxf(0.0, energy - 28.0 * delta)
	else:
		energy = minf(100.0, energy + 18.0 * delta)
	var speed := boost_speed if boosting else cruise_speed
	var desired_velocity := facing * movement * speed
	var thrust_rate := acceleration
	# Keep world-space momentum through turns, with stronger assistance when stopping or reversing.
	if velocity.dot(desired_velocity) < 0.0:
		thrust_rate = counter_thrust
	elif desired_velocity.length_squared() < velocity.length_squared():
		thrust_rate = braking
	var next_velocity := velocity.move_toward(desired_velocity, thrust_rate * thrust_multiplier() * delta)
	# Assistance can shed or redirect momentum, but gaining speed retains the
	# original acceleration, including launch, boost and recovery after a turn.
	velocity = next_velocity.limit_length(velocity.length() + acceleration * delta)
	move_and_slide()


## Cosmetic banking and boost field of view; never part of the simulation.
func present_motion(delta: float, movement: Vector3) -> void:
	if render_enabled:
		model.rotation.z = lerp_angle(model.rotation.z, -movement.limit_length().x * 0.23, delta * 5.0)
		camera.fov = lerpf(camera.fov, 83.0 if boosting else 75.0, delta * 3.0)


## Draws the model and camera `offset` (world space) away from the simulated
## position. Owner prediction uses it to hide reconciliation corrections.
func set_visual_offset(offset: Vector3) -> void:
	visual_offset = offset
	if not render_enabled or not is_instance_valid(model):
		return
	var local := global_basis.inverse() * offset
	model.position = local
	if is_instance_valid(arm):
		arm.position = ARM_POSITION + local
