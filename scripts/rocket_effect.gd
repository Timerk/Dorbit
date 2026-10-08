class_name RocketEffect
extends Node3D
## Cosmetic homing only: never deals damage or infers a hit from collision.

var sector: Sector
var target: WeakRef
var encounter: int
var event_id: String
var speed: float
var bend: Vector3
var age: float = 0.0
var trail: MeshInstance3D


static func spawn(parent: Sector, event: Dictionary) -> void:
	if SectorVisuals.effects_quality(parent) == 0:
		return
	var limit := 32 if SectorVisuals.effects_quality(parent) == 1 else SectorVisuals.EFFECT_LIMIT
	if parent.get_tree().get_nodes_in_group("transient_feedback").size() >= limit:
		return
	var enemy: Alien = parent.aliens.get(event["target"])
	if not is_instance_valid(enemy) or enemy.life != event["life"]:
		return
	var effect := RocketEffect.new()
	effect.sector = parent
	effect.target = weakref(enemy)
	effect.encounter = event["life"]
	effect.event_id = event["id"]
	effect.speed = Ammunition.ROCKETS[event["kind"]]["speed"]
	var angle := TAU * float(event["index"]) / float(event["count"])
	effect.bend = Vector3(cos(angle), sin(angle), 0) * (18.0 if event["count"] > 1 else 0.0)
	parent.add_child(effect)
	effect.global_position = event["origin"]
	effect.add_to_group("transient_feedback")
	effect.add_to_group("rocket_feedback")
	SectorVisuals.box(effect, Vector3.ZERO, Vector3(0.28, 0.28, 1.5), SectorVisuals.material(Color("d9dee5")))
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.20
	nose.height = 0.65
	nose.radial_segments = 6
	SectorVisuals.mesh(effect, nose, Vector3(0, 0, -1.0), SectorVisuals.material(Color("f4c778"))).rotation.x = -PI / 2
	var exhaust := CylinderMesh.new()
	exhaust.top_radius = 0.16
	exhaust.bottom_radius = 0.015
	exhaust.height = 5.0
	exhaust.radial_segments = 6
	effect.trail = SectorVisuals.mesh(effect, exhaust, Vector3(0, 0, 3.1), SectorVisuals.material(Color("ff985a"), true))
	effect.trail.rotation.x = PI / 2
	SectorVisuals.sound(parent, "laser", effect.position)


static func resolve(parent: Sector, id: String, location: Vector3, hit: bool) -> void:
	for node: Node in parent.get_tree().get_nodes_in_group("rocket_feedback"):
		if node is RocketEffect and node.sector == parent and node.event_id == id:
			node.queue_free()
	if hit:
		var impact := SectorVisuals.feedback_root(parent, location, 0.4)
		if impact != null:
			SectorVisuals.glow(impact, Vector3.ZERO, Vector2.ONE * 5, Color("ffb76e"), 0.4)
			SectorVisuals.sparks(impact, Vector3.ZERO, Vector3.ZERO, 4, 0.7, 0.4)


func _process(delta: float) -> void:
	age += delta
	var enemy := target.get_ref() as Alien
	if not is_instance_valid(enemy) or not enemy.available() or enemy.life != encounter or age > RocketWeapons.MAX_FLIGHT_TIME + 1:
		queue_free()
		return
	var destination := enemy.global_position + bend * maxf(0.0, 1.0 - age * 1.5)
	var offset := destination - global_position
	if offset.length_squared() > 0.01:
		look_at(destination, Vector3.RIGHT if absf(offset.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP)
		global_position = global_position.move_toward(destination, speed * delta)
	trail.scale.y = 0.85 + sin(age * 50) * 0.15
