class_name SpaceShip
extends CharacterBody3D
## Shared combat state. Visual effects listen to signals and never apply damage.

signal destroyed(ship: SpaceShip, attacker: SpaceShip)
signal fired(origin: Vector3, destination: Vector3, hostile: bool)
signal damaged(ship: SpaceShip, attacker: SpaceShip)

@export var max_hull: float = Equipment.STARTER_HULL
@export var max_shield: float = 1000.0
@export_range(0.0, 1.0) var shield_absorption: float = 0.4
@export var laser_damage: float = 65.0
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
var simulation_authority: bool = true
var render_enabled: bool = true
var npc_laser_damage: float = 0.0
var shield_regen_bonus: float = 0.0
var map_id: int = 0
var map_visit: int = 0


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
	if render_enabled:
		model = SectorVisuals.ship_model(hostile)
		add_child(model)


func tick_combat(delta: float) -> void:
	if not simulation_authority:
		return
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	time_since_hit += delta
	if alive and time_since_hit >= 6.0:
		shield = minf(max_shield, shield + delta * max_shield / 12.0 * (1.0 + shield_regen_bonus))


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
	if not simulation_authority or not alive or amount <= 0.0:
		return
	if attacker != null and attacker.map_id != map_id:
		return
	time_since_hit = 0.0
	var absorbed := minf(shield, amount * clampf(shield_absorption, 0.0, 1.0))
	shield -= absorbed
	hull = maxf(0.0, hull - (amount - absorbed))
	present_impact(absorbed > 0.0, amount > absorbed)
	damaged.emit(self, attacker)
	if hull <= 0.0:
		alive = false
		velocity = Vector3.ZERO
		set_collision_layer_value(2, false)
		hide()
		destroyed.emit(self, attacker)


func present_impact(shield_hit: bool, hull_hit: bool) -> void:
	if render_enabled and (shield_hit or hull_hit):
		SectorVisuals.impact(self, global_position, shield_hit, hull_hit)


func firing_blocker(target: SpaceShip) -> String:
	if laser_damage <= 0.0:
		return "NO LASER INSTALLED"
	if not alive or not is_instance_valid(target) or not target.alive:
		return "NO TARGET"
	if target.map_id != map_id:
		return "TARGET IN ANOTHER MAP"
	if target is Alien and not target.available():
		return "TARGET RETURNING"
	if (hostile and target is Pilot and SectorMaps.protected(target)) or (self is Pilot and target is Alien and SectorMaps.protected(self)):
		return "STATION PROTECTION"
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
	if not simulation_authority or shot_cooldown > 0.0 or not firing_blocker(target).is_empty():
		return false
	var damage := shot_damage(target)
	if not spend_ammo():
		return false
	shot_cooldown = laser_interval
	var endpoint := target.global_position
	fired.emit(global_position - global_basis.z * 3.0, endpoint, hostile)
	target.take_damage(damage, self)
	return true


func spend_ammo() -> bool:
	return true # Aliens do not use pilot ammunition.


func shot_damage(target: SpaceShip) -> float:
	return laser_damage + (npc_laser_damage if target is Alien else 0.0)
