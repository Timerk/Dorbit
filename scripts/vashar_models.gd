class_name VasharModels
extends RefCounted
## Procedural playtest models for the Vashar Gate faction: obsidian crystal hulls
## with violet seams. Each fits a ~7 m diameter before Alien.VISUAL_SCALE and
## faces -Z. Authored models can replace these after concept approval.

const KINDS := ["Shardling", "Spireguard", "Mothership"]
const OBSIDIAN := Color("4a3a63")
const PLATE := Color("7a5aa3")
const GLOW := Color("c86bff")
const HOT := Color("ff5fa8")


static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind + "Model"
	var hull := SectorVisuals.material(OBSIDIAN)
	hull.metallic = 0.6
	hull.roughness = 0.35
	# A faint self-lit sheen keeps the dark hulls readable against the rift nebula.
	hull.emission_enabled = true
	hull.emission = Color("3a1d5a")
	hull.emission_energy_multiplier = 0.6
	var plate := SectorVisuals.material(PLATE)
	plate.roughness = 0.45
	var glow := SectorVisuals.material(GLOW, true)
	var hot := SectorVisuals.material(HOT, true)
	match kind:
		"Shardling": shardling(root, hull, plate, glow)
		"Spireguard": spireguard(root, hull, plate, glow, hot)
		_: mothership(root, hull, plate, glow, hot)
	for part: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func part(parent: Node3D, mesh: Mesh, location: Vector3, rotation: Vector3, size: Vector3, surface: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = surface
	instance.position = location
	instance.rotation = rotation
	instance.scale = size
	parent.add_child(instance)
	return instance


# A six-sided double cone: the faction's recurring crystal blade.
static func crystal(sides: int = 6) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh


static func orb() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


static func ring(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 32
	mesh.ring_segments = 8
	return mesh


static func shardling(root: Node3D, hull: Material, plate: Material, glow: Material) -> void:
	var blade := crystal()
	# Long forward spike and a shorter rear cone form the fuselage.
	part(root, blade, Vector3(0, 0, -1.6), Vector3(-PI / 2, 0, 0), Vector3(1.5, 3.4, 1.1), hull)
	part(root, blade, Vector3(0, 0, 1.2), Vector3(PI / 2, 0, 0), Vector3(1.5, 1.6, 1.1), hull)
	part(root, orb(), Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 0.8, 1.4), glow)
	# Three swept fins with glowing leading edges.
	for index in range(3):
		var angle := TAU * index / 3.0 + PI / 2
		var direction := Vector3(cos(angle), sin(angle), 0)
		var fin := part(root, blade, direction * 1.5 + Vector3(0, 0, 0.6), Vector3(0, 0, angle - PI / 2), Vector3(0.7, 2.6, 0.18), plate)
		fin.rotate_object_local(Vector3.RIGHT, 0.45)
		part(root, blade, direction * 2.5 + Vector3(0, 0, 1.0), Vector3(0, 0, angle - PI / 2), Vector3(0.18, 0.9, 0.18), glow)
	part(root, orb(), Vector3(0, 0, 2.0), Vector3.ZERO, Vector3(0.6, 0.6, 0.35), glow)


static func spireguard(root: Node3D, hull: Material, plate: Material, glow: Material, hot: Material) -> void:
	var blade := crystal()
	# A tall armored spire laid along the flight axis, braced by a glowing ring.
	part(root, blade, Vector3(0, 0, -1.4), Vector3(-PI / 2, 0, 0), Vector3(2.2, 3.6, 2.2), hull)
	part(root, blade, Vector3(0, 0, 1.4), Vector3(PI / 2, 0, 0), Vector3(2.2, 2.0, 2.2), hull)
	part(root, ring(1.1, 1.45), Vector3(0, 0, 0.2), Vector3(PI / 2, 0, 0), Vector3.ONE, glow)
	for side: float in [-1.0, 1.0]:
		# Heavy shoulder plates and paired cannons.
		part(root, BoxMesh.new(), Vector3(side * 1.6, 0.3, 0.3), Vector3(0, 0, side * 0.35), Vector3(1.2, 0.35, 2.4), plate)
		part(root, blade, Vector3(side * 2.3, 0.0, 0.0), Vector3(0, 0, side * -PI / 2), Vector3(0.6, 1.2, 0.6), hull)
		part(root, CylinderMesh.new(), Vector3(side * 1.4, -0.4, -1.6), Vector3(PI / 2, 0, 0), Vector3(0.22, 1.6, 0.22), plate)
		part(root, orb(), Vector3(side * 1.4, -0.4, -2.45), Vector3.ZERO, Vector3.ONE * 0.32, hot)
	part(root, orb(), Vector3(0, 0, 2.4), Vector3.ZERO, Vector3(0.9, 0.9, 0.4), glow)


static func mothership(root: Node3D, hull: Material, plate: Material, glow: Material, hot: Material) -> void:
	var blade := crystal()
	# A broad saucer hull with a raised command spire and a hangar mouth below.
	part(root, orb(), Vector3.ZERO, Vector3.ZERO, Vector3(5.6, 1.2, 6.2), hull)
	part(root, orb(), Vector3(0, 0.35, 0), Vector3.ZERO, Vector3(4.2, 1.0, 4.8), plate)
	part(root, blade, Vector3(0, 1.4, 0.4), Vector3.ZERO, Vector3(1.2, 2.4, 1.2), hull)
	part(root, orb(), Vector3(0, 1.0, 0.4), Vector3.ZERO, Vector3.ONE * 0.9, glow)
	part(root, ring(2.9, 3.2), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3.ONE, glow)
	part(root, orb(), Vector3(0, -0.5, -0.6), Vector3.ZERO, Vector3(2.2, 0.35, 1.6), hot)
	# Crystal spines radiate from the rim; every third carries a glowing tip.
	for index in range(12):
		var angle := TAU * index / 12.0
		var direction := Vector3(sin(angle), 0, cos(angle))
		var spine := part(root, blade, direction * 3.1, Vector3.ZERO, Vector3(0.45, 1.6, 0.45), hull)
		spine.quaternion = Quaternion(Vector3.UP, (direction + Vector3.UP * 0.2).normalized())
		if index % 3 == 0:
			part(root, orb(), direction * 3.85 + Vector3.UP * 0.15, Vector3.ZERO, Vector3.ONE * 0.28, glow)
	# Forward prow and rear drives.
	part(root, blade, Vector3(0, 0, -3.4), Vector3(-PI / 2, 0, 0), Vector3(1.6, 1.8, 0.7), plate)
	for side: float in [-1.6, 0.0, 1.6]:
		part(root, CylinderMesh.new(), Vector3(side, 0, 3.0), Vector3(PI / 2, 0, 0), Vector3(0.55, 0.9, 0.55), plate)
		part(root, orb(), Vector3(side, 0, 3.5), Vector3.ZERO, Vector3(0.5, 0.5, 0.25), hot)
