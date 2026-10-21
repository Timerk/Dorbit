class_name SectorMaps
extends RefCounted
## Small shared universe. Positions use separated origins in the same physics world.
## Membership, rather than proximity alone, authorizes every world interaction.

const JUMP_RADIUS := 50.0
const PROTECTION_RADIUS := 75.0
const JUMP_COOLDOWN := 2.0
const MAPS := {
	0: {"name": "M1 / Outpost 01", "color": Color("76b9ef"), "aliens": ["Sentinel", "Scout", "Scout", "Sentinel", "Heavy"], "description": "Home station / repairs, fitting, trade and hunting contracts"},
	1: {"name": "M2 / Outer Patrol", "color": Color("67dfb5"), "aliens": ["Skirmisher", "Skirmisher", "Skirmisher", "Raider", "Raider"], "description": "Tier 1 / Skirmishers and Raiders / no station"},
	2: {"name": "M3 / Debris Fields", "color": Color("efb35f"), "aliens": ["Marauder", "Marauder", "Marauder", "Warden", "Warden"], "description": "Tier 2 / Marauders and Wardens / no station"},
	3: {"name": "M4 / Frontier", "color": Color("d48eef"), "aliens": ["Ravager", "Ravager", "Ravager", "Overlord", "Overlord"], "description": "Tier 3 / Ravagers and Overlords / no station"},
}
const GATES := {
	0: {1: Vector3(0, 120, -900)},
	1: {0: Vector3(0, -80, 900), 2: Vector3(-780, 180, -350), 3: Vector3(780, -180, -350)},
	2: {1: Vector3(750, -120, 300), 3: Vector3(-720, 220, -400)},
	3: {1: Vector3(-760, 80, 300), 2: Vector3(730, -160, -400)},
}

# Short map label such as "M2", used where a gate names its destination.
static func code(map: int) -> String:
	return MAPS[map]["name"].get_slice(" / ", 0)

static func origin(map: int) -> Vector3:
	return Vector3(map * 15000.0, 0, 0)

static func gate_position(map: int, destination: int) -> Vector3:
	return origin(map) + GATES[map][destination]

static func arrival(map: int, source: int, slot: int = 0) -> Vector3:
	var gate: Vector3 = GATES[map][source]
	var inward := -gate.normalized()
	var side := inward.cross(Vector3.UP).normalized()
	return origin(map) + gate + inward * 30.0 + side * ((slot % 5) - 2) * 6.0 + Vector3.UP * (slot / 5) * 6.0

static func protected(ship: SpaceShip) -> bool:
	if ship.map_id == 0 and ship.position.distance_to(Sector.STATION_POSITION) <= Sector.PROTECTION_RADIUS:
		return true
	if ship.get_parent() is Sector:
		for destination: int in GATES[ship.map_id]:
			if ship.position.distance_to(gate_position(ship.map_id, destination)) <= PROTECTION_RADIUS:
				return true
	return false

static func first_hop(source: int, destination: int) -> int:
	if source == destination:
		return -1
	var pending: Array[int] = [source]
	var previous := {source: -1}
	while not pending.is_empty():
		var map: int = pending.pop_front()
		for neighbor: int in GATES[map]:
			if previous.has(neighbor):
				continue
			previous[neighbor] = map
			if neighbor == destination:
				while previous[neighbor] != source:
					neighbor = previous[neighbor]
				return neighbor
			pending.append(neighbor)
	return -1

static func gate_model(parent: Node3D, map: int, destination: int) -> void:
	var root := Node3D.new()
	root.name = "GateToM%d" % (destination+1)
	root.position = gate_position(map, destination)
	parent.add_child(root)
	root.look_at(origin(map), Vector3.UP)
	var model := (load("res://assets/sector/transit-gate.glb") as PackedScene).instantiate() as Node3D
	model.name = "TransitGate"
	root.add_child(model)
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.layers = 2
		for index in part.mesh.get_surface_count():
			var surface := part.mesh.surface_get_material(index) as BaseMaterial3D
			if surface.resource_name == "Gate cyan":
				surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				surface.albedo_color = Color(0.02,0.72,1.0)
				surface.emission_energy_multiplier = 0.4
	SectorVisuals.configure_texture_filtering(model)
	var aperture := QuadMesh.new()
	aperture.size = Vector2.ONE*25.2
	var energy := ShaderMaterial.new()
	energy.shader = preload("res://shaders/gate_portal.gdshader")
	energy.set_shader_parameter("turbulence",preload("res://assets/sector/nebula-panorama.png"))
	var portal := SectorVisuals.mesh(root,aperture,Vector3.ZERO,energy)
	portal.name = "Portal"
	portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Restrict the portal spill to gate armor; nearby ships and scenery keep their
	# existing lighting. Two soft lights make both approaches readable without bloom.
	for side in [-1,1]:
		var light := OmniLight3D.new()
		light.position = Vector3(0,0,side*5.0)
		light.light_color = Color("48e6f5")
		light.light_energy = 5.0
		light.omni_range = 29
		light.omni_attenuation = 0.8
		light.light_cull_mask = 2
		root.add_child(light)
	var label := Label3D.new()
	label.text = "GATE TO " + code(destination)
	label.position = Vector3(0, 27, 0)
	label.font_size = 40
	label.pixel_size = 0.08
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = MAPS[destination]["color"]
	root.add_child(label)
