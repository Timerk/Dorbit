class_name SpaceShip
extends CharacterBody3D
## Shared combat state. Visual effects listen to signals and never apply damage.

signal destroyed(ship: SpaceShip, attacker: SpaceShip)
signal fired(origin: Vector3, destination: Vector3, hostile: bool)

@export var max_hull: float = 120.0
@export var max_shield: float = 70.0
@export var laser_damage: float = 11.0
@export var laser_interval: float = 0.42
@export var laser_range: float = 170.0
@export_range(-1.0, 1.0) var firing_arc_cosine: float = 0.25

var hull: float
var shield: float
var alive: bool = true
var hostile: bool = false
var shot_cooldown: float = 0.0
var time_since_hit: float = 100.0
var model: Node3D


func _ready() -> void:
	reset_health()
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 3
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2
	shape.shape = sphere
	add_child(shape)
	model = SectorVisuals.ship_model(hostile)
	add_child(model)


func tick_combat(delta: float) -> void:
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	time_since_hit += delta
	if alive and time_since_hit >= 6.0:
		shield = minf(max_shield, shield + delta * 6.0)


func reset_health() -> void:
	hull = max_hull
	shield = max_shield
	alive = true
	shot_cooldown = 0.0
	time_since_hit = 100.0
	velocity = Vector3.ZERO
	show()
	set_collision_layer_value(2, true)


func take_damage(amount: float, attacker: SpaceShip) -> void:
	if not alive or amount <= 0.0:
		return
	time_since_hit = 0.0
	var absorbed := minf(shield, amount)
	shield -= absorbed
	hull = maxf(0.0, hull - (amount - absorbed))
	if hull <= 0.0:
		alive = false
		velocity = Vector3.ZERO
		set_collision_layer_value(2, false)
		hide()
		destroyed.emit(self, attacker)


func firing_blocker(target: SpaceShip) -> String:
	if not alive or not is_instance_valid(target) or not target.alive:
		return "NO TARGET"
	var offset := target.global_position - global_position
	if offset.length() > laser_range:
		return "OUT OF RANGE"
	if offset.length_squared() < 0.01:
		return "TOO CLOSE"
	if -global_basis.z.dot(offset.normalized()) < firing_arc_cosine:
		return "TURN TOWARD TARGET"
	var query := PhysicsRayQueryParameters3D.create(global_position, target.global_position, 3)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != target:
		return "LINE OF SIGHT BLOCKED"
	return ""


func try_fire(target: SpaceShip) -> bool:
	if shot_cooldown > 0.0 or not firing_blocker(target).is_empty():
		return false
	shot_cooldown = laser_interval
	var endpoint := target.global_position
	fired.emit(global_position - global_basis.z * 3.0, endpoint, hostile)
	target.take_damage(laser_damage, self)
	return true
