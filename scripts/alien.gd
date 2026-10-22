class_name Alien
extends SpaceShip

const RETURN_TIMEOUT: float = 30.0
const HULL_RESET_DELAY: float = 30.0
# Engaged aliens close only to this fraction of their weapon range, not to point blank.
const STANDOFF: float = 0.75
# Baked asset diameters, before presentation scaling; independent of colliders.
const VISUAL_DIAMETERS := {
	"Scout": 7.547966,
	"Sentinel": 9.702295,
	"Heavy": 13.515700,
	"Skirmisher": 9.289846,
	"Raider": 10.575819,
	"Marauder": 12.480946,
	"Warden": 13.199097,
	"Ravager": 14.993888,
	"Overlord": 17.013710,
	"Shardling": 9.5,
	"Spireguard": 9.5,
	"Mothership": 16.0,
	"Husk": 9.5,
	"Bulwark": 12.0,
	"Siegebreaker": 12.0,
}
# Stronger encounters should remain easy to track among cooperating pilots.
const VISUAL_SCALE := {
	"Scout": 1.0,
	"Sentinel": 1.15,
	"Heavy": 1.5,
	"Skirmisher": 1.0,
	"Raider": 1.4,
	"Marauder": 2.0,
	"Warden": 2.4,
	"Ravager": 3.2,
	"Overlord": 3.5,
	"Shardling": 1.0,
	"Spireguard": 2.0,
	"Mothership": 4.0,
	"Husk": 1.3,
	"Bulwark": 2.4,
	"Siegebreaker": 9.0,
	"Wisp": 1.1,
	"Veilcaster": 2.6,
	"Ascendant": 11.0,
}
const TYPES := {
	"Scout": {"hull": 1000.0, "shield": 500.0, "damage": 1500.0, "interval": 0.85, "range": 205.0, "speed": 29.0, "detection": 230.0, "leash": 210.0, "reward": 300, "respawn": 10.0, "scale": Vector3(0.7, 0.7, 0.85), "color": Color("ffc875")},
	"Sentinel": {"hull": 4000.0, "shield": 2000.0, "damage": 5000.0, "interval": 0.75, "range": 235.0, "speed": 18.0, "detection": 250.0, "leash": 230.0, "reward": 1500, "respawn": 12.0, "scale": Vector3.ONE, "color": Color("ff8176")},
	"Heavy": {"hull": 10000.0, "shield": 5000.0, "damage": 12000.0, "interval": 0.9, "range": 245.0, "speed": 12.0, "detection": 285.0, "leash": 210.0, "reward": 10000, "respawn": 18.0, "scale": Vector3(1.5, 1.6, 1.25), "color": Color("d2a0ff")},
	"Skirmisher": {"hull": 2500.0, "shield": 1200.0, "damage": 2500.0, "interval": 0.9, "range": 210.0, "speed": 30.0, "detection": 240.0, "leash": 225.0, "reward": 900, "respawn": 12.0, "scale": Vector3(0.8, 0.8, 1.1), "color": Color("74e6b2")},
	"Raider": {"hull": 6500.0, "shield": 3200.0, "damage": 6500.0, "interval": 0.85, "range": 235.0, "speed": 23.0, "detection": 260.0, "leash": 240.0, "reward": 3500, "respawn": 15.0, "scale": Vector3(1.2, 0.85, 1.0), "color": Color("37bdb8")},
	"Marauder": {"hull": 14000.0, "shield": 7000.0, "damage": 14000.0, "interval": 0.85, "range": 245.0, "speed": 24.0, "detection": 275.0, "leash": 250.0, "reward": 14000, "respawn": 17.0, "scale": Vector3(1.3, 1.0, 1.3), "color": Color("ffc36e")},
	"Warden": {"hull": 24000.0, "shield": 12000.0, "damage": 18000.0, "interval": 0.8, "range": 255.0, "speed": 17.0, "detection": 285.0, "leash": 260.0, "reward": 22000, "respawn": 20.0, "scale": Vector3(1.6, 1.4, 1.1), "color": Color("ee7954")},
	"Ravager": {"hull": 36000.0, "shield": 18000.0, "damage": 24000.0, "interval": 0.8, "range": 260.0, "speed": 22.0, "detection": 295.0, "leash": 265.0, "reward": 32000, "respawn": 22.0, "scale": Vector3(1.4, 1.2, 1.7), "color": Color("b788fa")},
	"Overlord": {"hull": 60000.0, "shield": 30000.0, "damage": 32000.0, "interval": 0.75, "range": 270.0, "speed": 14.0, "detection": 310.0, "leash": 275.0, "reward": 50000, "respawn": 26.0, "scale": Vector3(2.0, 1.8, 1.5), "color": Color("ed70c1")},
	# Vashar Gate arena only. The run director spawns them; detection covers the arena and they never leash.
	"Shardling": {"hull": 4000.0, "shield": 2000.0, "damage": 2200.0, "interval": 0.85, "range": 220.0, "speed": 30.0, "detection": 2400.0, "leash": 5000.0, "reward": 1500, "respawn": 0.0, "scale": Vector3.ONE, "color": Color("c86bff")},
	"Spireguard": {"hull": 16000.0, "shield": 8000.0, "damage": 7500.0, "interval": 0.8, "range": 250.0, "speed": 17.0, "detection": 2400.0, "leash": 5000.0, "reward": 7000, "respawn": 0.0, "scale": Vector3.ONE, "color": Color("ff5fa8")},
	"Mothership": {"hull": 200000.0, "shield": 100000.0, "damage": 18000.0, "interval": 0.55, "range": 270.0, "speed": 5.0, "detection": 2400.0, "leash": 5000.0, "reward": 120000, "respawn": 0.0, "scale": Vector3.ONE, "color": Color("9b5cff"), "radius": 16.0},
	# Korrath Gate arena only; authored siege-engineer hulls use orange furnace cores.
	"Husk": {"hull": 8000.0, "shield": 4000.0, "damage": 4000.0, "interval": 0.8, "range": 230.0, "speed": 34.0, "detection": 2400.0, "leash": 5000.0, "reward": 3000, "respawn": 0.0, "scale": Vector3(0.9, 0.7, 1.2), "color": Color("ff8a3d")},
	"Bulwark": {"hull": 36000.0, "shield": 18000.0, "damage": 14000.0, "interval": 0.85, "range": 260.0, "speed": 15.0, "detection": 2400.0, "leash": 5000.0, "reward": 15000, "respawn": 0.0, "scale": Vector3(1.4, 1.2, 1.3), "color": Color("d0562a")},
	"Siegebreaker": {"hull": 500000.0, "shield": 250000.0, "damage": 30000.0, "interval": 0.5, "range": 270.0, "speed": 3.0, "detection": 2400.0, "leash": 5000.0, "reward": 300000, "respawn": 0.0, "scale": Vector3(1.6, 0.8, 1.6), "color": Color("ffb35c"), "radius": 22.0},
	# Sylith Gate arena only, with placeholder models until authored art exists.
	"Wisp": {"hull": 14000.0, "shield": 9000.0, "damage": 7000.0, "interval": 0.7, "range": 240.0, "speed": 40.0, "detection": 2400.0, "leash": 5000.0, "reward": 6000, "respawn": 0.0, "scale": Vector3(0.8, 0.5, 1.3), "color": Color("4fe3d2")},
	"Veilcaster": {"hull": 70000.0, "shield": 40000.0, "damage": 24000.0, "interval": 0.85, "range": 270.0, "speed": 14.0, "detection": 2400.0, "leash": 5000.0, "reward": 30000, "respawn": 0.0, "scale": Vector3(1.1, 1.6, 1.1), "color": Color("2fa8c9")},
	"Ascendant": {"hull": 1000000.0, "shield": 500000.0, "damage": 50000.0, "interval": 0.5, "range": 270.0, "speed": 2.0, "detection": 2400.0, "leash": 5000.0, "reward": 600000, "respawn": 0.0, "scale": Vector3(1.0, 1.8, 1.0), "color": Color("a6fff2"), "radius": 26.0},
}

var alien_id: int = 0
var kind: String = "Sentinel"
var home_position := Vector3(0.0, 8.0, -440.0)
var patrol_time: float = 0.0
var engaged: bool = false
var returning: bool = false
var return_time: float = 0.0
var recovery_time: float = 0.0
var life: int = 0
var respawn: float = 0.0
var contributors: Array[int] = []
# Weapons outrange detection; whoever damaged this life stays a target while eligible.
var last_attacker: Pilot = null
var snapshot_goal: Dictionary = {}


func tuning() -> Dictionary:
	return TYPES[kind]


static func model_scene(alien_kind: String) -> Node3D:
	if not VISUAL_DIAMETERS.has(alien_kind):
		var root := SectorVisuals.ship_model(true)
		root.scale = TYPES[alien_kind]["scale"] * float(VISUAL_SCALE[alien_kind])
		var surface := SectorVisuals.material(TYPES[alien_kind]["color"])
		for part: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if part.mesh is BoxMesh:
				part.material_override = surface
		return root
	var scene: PackedScene = load("res://assets/aliens/%s.glb" % alien_kind.to_lower())
	var instance := scene.instantiate() as Node3D
	instance.scale *= float(VISUAL_SCALE[alien_kind])
	var korrath: bool = alien_kind in GalaxyGates.info("korrath")["pool"]
	# Apply to shared materials at load time so existing imported assets also
	# receive the visibility finish. Keep dark machinery and recesses distinct.
	for node: MeshInstance3D in instance.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(surface) as BaseMaterial3D
			if material.resource_name.ends_with("coated armor"):
				material.emission_enabled = true
				material.emission = Color.WHITE
				material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				material.emission_texture = material.albedo_texture
				# Vashar armor stays dark so its violet seams carry the contrast.
				material.emission_energy_multiplier = 2.0 if alien_kind in ["Scout", "Sentinel", "Heavy"] else (0.12 if alien_kind in GalaxyGates.arena_kinds() else 0.35)
				if korrath:
					# Scorched iron has a broad dull finish under the strong sector sun.
					material.metallic_specular = 0.2
					material.clearcoat = 0.04
			elif korrath and material.resource_name.ends_with("sensor emission"):
				# Unlit furnace apertures retain orange instead of picking up white sun specular.
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.emission = Color("ff6508")
				material.emission_energy_multiplier = 0.4
	return instance


func _ready() -> void:
	var stats := tuning()
	max_hull = stats["hull"]
	max_shield = stats["shield"]
	shield_absorption = 0.8
	laser_damage = stats["damage"]
	laser_interval = stats["interval"]
	laser_range = stats["range"]
	super._ready()
	if stats.has("radius"):
		for child in get_children():
			if child is CollisionShape3D:
				(child.shape as SphereShape3D).radius = stats["radius"]
	if render_enabled:
		remove_child(model)
		model.queue_free()
		model = model_scene(kind)
		add_child(model)
		SectorVisuals.configure_texture_filtering(model, SectorVisuals.texture_filtering_enabled(self))


func available() -> bool:
	return alive and not returning


func reset_encounter(restore_health: bool = true) -> void:
	life += 1
	contributors.clear()
	engaged = false
	last_attacker = null
	recovery_time = 0.0
	if restore_health:
		reset_health()


func tick_combat(delta: float) -> void:
	super.tick_combat(delta) # Alien shields use the same delay and rate as pilots.
	if not simulation_authority or not alive:
		return
	if engaged:
		recovery_time = 0.0
	else:
		recovery_time = minf(HULL_RESET_DELAY, recovery_time + delta)
		if recovery_time >= HULL_RESET_DELAY:
			hull = max_hull


# Falls back to the last attacker when no pilot is inside detection range.
func pursue_target(player: Pilot) -> Pilot:
	if is_instance_valid(player):
		return player
	if is_instance_valid(last_attacker) and last_attacker.alive and last_attacker.map_id == map_id and not last_attacker.get_meta("docked", false) and not SectorMaps.protected(last_attacker):
		return last_attacker
	last_attacker = null
	return null


# Check before pilot fire as well as movement, so a lethal shot cannot win a leash reset race.
func check_retreat(player: Pilot) -> void:
	if not available():
		return
	player = pursue_target(player)
	if position.distance_to(home_position) >= float(tuning()["leash"]) or (engaged and not is_instance_valid(player)):
		returning = true
		return_time = 0.0
		# Invalidate stale fire and rewards without erasing the damage just dealt.
		reset_encounter(false)


func take_damage(amount: float, attacker: SpaceShip) -> void:
	if not available() or position.distance_to(home_position) >= float(tuning()["leash"]):
		return
	# Protected pilots cannot farm enemies that are forbidden to retaliate.
	if attacker != null and attacker.map_id != map_id:
		return
	if attacker is Pilot and SectorMaps.protected(attacker):
		return
	if simulation_authority and amount > 0.0:
		engaged = true
		recovery_time = 0.0
		if attacker is Pilot:
			last_attacker = attacker as Pilot
	super.take_damage(amount, attacker)


func _init() -> void:
	hostile = true


func fly(delta: float, player: Pilot, station_position: Vector3) -> void:
	patrol_time += delta
	check_retreat(player)
	player = pursue_target(player)
	engaged = is_instance_valid(player) and player.alive
	engaged = engaged and player.map_id == map_id and not SectorMaps.protected(player)
	engaged = engaged and (player == last_attacker or global_position.distance_to(player.global_position) < float(tuning()["detection"]))
	engaged = engaged and not returning
	if engaged:
		recovery_time = 0.0
	var destination := home_position + Vector3(sin(patrol_time * 0.22) * 18.0, sin(patrol_time * 0.35) * 8.0, 0.0)
	if returning:
		return_time += delta
		destination = home_position
		# A rock or ship can block direct flight. Never strand an invulnerable spawn slot.
		if position.distance_to(home_position) <= 3.0 or return_time >= RETURN_TIMEOUT:
			position = home_position
			returning = false
	if engaged:
		var away := (global_position - player.global_position).normalized()
		var lateral := away.cross(Vector3.UP).normalized()
		# Close to the standoff, but hold rather than retreat so rushing pilots cannot drag it past its leash.
		var hold := minf(laser_range * STANDOFF, global_position.distance_to(player.global_position))
		destination = player.global_position + away * hold + lateral * sin(patrol_time * 0.6) * 25.0
	var offset := destination - global_position
	velocity = velocity.move_toward(offset.limit_length(1.0) * minf(float(tuning()["speed"]), offset.length()), delta * 22.0)
	var look_point := player.global_position if engaged else destination
	if global_position.distance_squared_to(look_point) > 0.1:
		var direction := look_point - global_position
		var unit := direction.normalized()
		var look_up := Vector3.UP
		if absf(unit.dot(look_up)) > 0.98:
			# Near a vertical heading, carry the current roll through the pole.
			look_up = global_basis.y
			if absf(unit.dot(look_up)) > 0.98:
				look_up = global_basis.z
		# Compare a local direction; approximate point equality grows with map origins.
		var desired := Basis.looking_at(direction, look_up)
		global_basis = global_basis.slerp(desired, minf(1.0, delta * 3.0)).orthonormalized()
	move_and_slide()
	if engaged:
		try_fire(player)
