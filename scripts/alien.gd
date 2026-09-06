class_name Alien
extends SpaceShip

var home_position := Vector3(0.0, 8.0, -180.0)
var patrol_time: float = 0.0
var engaged: bool = false


func _init() -> void:
	hostile = true
	max_shield = 50.0
	max_hull = 130.0
	laser_damage = 10.0
	laser_interval = 0.75
	laser_range = 155.0


func fly(delta: float, player: Pilot, station_position: Vector3) -> void:
	patrol_time += delta
	engaged = player.alive and player.global_position.distance_to(station_position) > 75.0
	engaged = engaged and global_position.distance_to(player.global_position) < 260.0
	engaged = engaged and global_position.distance_to(home_position) < 350.0
	var destination := home_position + Vector3(sin(patrol_time * 0.22) * 18.0, sin(patrol_time * 0.35) * 8.0, 0.0)
	if engaged:
		var away := (global_position - player.global_position).normalized()
		var lateral := away.cross(Vector3.UP).normalized()
		destination = player.global_position + away * 75.0 + lateral * sin(patrol_time * 0.6) * 25.0
	var offset := destination - global_position
	velocity = velocity.move_toward(offset.limit_length(1.0) * minf(18.0, offset.length()), delta * 22.0)
	var look_point := player.global_position if engaged else destination
	if global_position.distance_squared_to(look_point) > 0.1:
		var desired := Transform3D(global_basis, global_position).looking_at(look_point, Vector3.UP)
		global_basis = global_basis.slerp(desired.basis, minf(1.0, delta * 3.0)).orthonormalized()
	move_and_slide()
	if engaged:
		try_fire(player)
