class_name Alien
extends SpaceShip

const RETURN_TIMEOUT: float = 30.0
const TYPES := {
	"Scout": {"hull": 60.0, "shield": 20.0, "damage": 6.0, "interval": 0.85, "range": 120.0, "speed": 29.0, "detection": 155.0, "leash": 170.0, "reward": 30, "respawn": 10.0, "scale": Vector3(0.7, 0.7, 0.85), "color": Color("ffc875")},
	"Sentinel": {"hull": 130.0, "shield": 50.0, "damage": 10.0, "interval": 0.75, "range": 155.0, "speed": 18.0, "detection": 180.0, "leash": 230.0, "reward": 75, "respawn": 12.0, "scale": Vector3.ONE, "color": Color("ff8176")},
	"Heavy": {"hull": 340.0, "shield": 140.0, "damage": 23.0, "interval": 0.9, "range": 165.0, "speed": 12.0, "detection": 220.0, "leash": 180.0, "reward": 180, "respawn": 18.0, "scale": Vector3(1.5, 1.6, 1.25), "color": Color("d2a0ff")},
}

var alien_id: int = 0
var kind: String = "Sentinel"
var home_position := Vector3(0.0, 8.0, -440.0)
var patrol_time: float = 0.0
var engaged: bool = false
var returning: bool = false
var return_time: float = 0.0
var life: int = 0
var respawn: float = 0.0
var contributors: Array[int] = []
var snapshot_goal: Dictionary = {}


func tuning() -> Dictionary:
	return TYPES[kind]


func _ready() -> void:
	var stats := tuning()
	max_hull = stats["hull"]
	max_shield = stats["shield"]
	laser_damage = stats["damage"]
	laser_interval = stats["interval"]
	laser_range = stats["range"]
	super._ready()
	if render_enabled:
		model.scale = stats["scale"]
		var stripe := SectorVisuals.material(stats["color"], true)
		SectorVisuals.box(model, Vector3(0, 1, 0), Vector3(1.5, 0.15, 2.5), stripe)
		if kind == "Heavy":
			SectorVisuals.box(model, Vector3(0, -0.6, 0), Vector3(4.5, 0.8, 3.5), SectorVisuals.material(Color("58446f")))


func available() -> bool:
	return alive and not returning


func reset_encounter() -> void:
	life += 1
	contributors.clear()
	engaged = false
	reset_health()


# Check before pilot fire as well as movement, so a lethal shot cannot win a leash reset race.
func check_retreat(player: Pilot) -> void:
	if not available():
		return
	if position.distance_to(home_position) >= float(tuning()["leash"]) or (engaged and not is_instance_valid(player)):
		returning = true
		return_time = 0.0
		reset_encounter()


func take_damage(amount: float, attacker: SpaceShip) -> void:
	if not available() or position.distance_to(home_position) >= float(tuning()["leash"]):
		return
	# Protected pilots cannot farm enemies that are forbidden to retaliate.
	if attacker is Pilot and attacker.position.distance_to(Sector.STATION_POSITION) <= 75.0:
		return
	if simulation_authority and amount > 0.0:
		engaged = true
	super.take_damage(amount, attacker)


func _init() -> void:
	hostile = true


func fly(delta: float, player: Pilot, station_position: Vector3) -> void:
	patrol_time += delta
	check_retreat(player)
	engaged = is_instance_valid(player) and player.alive
	engaged = engaged and player.global_position.distance_to(station_position) > 75.0
	engaged = engaged and global_position.distance_to(player.global_position) < float(tuning()["detection"])
	engaged = engaged and not returning
	var destination := home_position + Vector3(sin(patrol_time * 0.22) * 18.0, sin(patrol_time * 0.35) * 8.0, 0.0)
	if returning:
		return_time += delta
		destination = home_position
		# A rock or ship can block direct flight. Never strand an invulnerable spawn slot.
		if position.distance_to(home_position) <= 3.0 or return_time >= RETURN_TIMEOUT:
			position = home_position
			returning = false
			reset_health()
	if engaged:
		var away := (global_position - player.global_position).normalized()
		var lateral := away.cross(Vector3.UP).normalized()
		destination = player.global_position + away * 75.0 + lateral * sin(patrol_time * 0.6) * 25.0
	var offset := destination - global_position
	velocity = velocity.move_toward(offset.limit_length(1.0) * minf(float(tuning()["speed"]), offset.length()), delta * 22.0)
	var look_point := player.global_position if engaged else destination
	if global_position.distance_squared_to(look_point) > 0.1:
		var desired := Transform3D(global_basis, global_position).looking_at(look_point, Vector3.UP)
		global_basis = global_basis.slerp(desired.basis, minf(1.0, delta * 3.0)).orthonormalized()
	move_and_slide()
	if engaged:
		try_fire(player)
