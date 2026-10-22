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
	# Galaxy gate arenas: outside the connected network, entered only through an
	# open gate. Each pool matches its GalaxyGates definition; waves activate it.
	4: {"name": "VG / Vashar Rift", "color": Color("c86bff"), "instance": true,
		"aliens": ["Shardling", "Shardling", "Shardling", "Shardling", "Shardling", "Shardling", "Shardling", "Shardling", "Spireguard", "Spireguard", "Spireguard", "Spireguard", "Mothership"],
		"description": "Vashar Gate / staging fleet / waves end with the mothership"},
	5: {"name": "KG / Korrath Bastion", "color": Color("ff8a3d"), "instance": true,
		"aliens": ["Husk", "Husk", "Husk", "Husk", "Husk", "Husk", "Husk", "Husk", "Husk", "Husk", "Bulwark", "Bulwark", "Bulwark", "Bulwark", "Bulwark", "Siegebreaker"],
		"description": "Korrath Gate / siege bastion / waves end with the Siegebreaker"},
	6: {"name": "SG / Sylith Hollow", "color": Color("4fe3d2"), "instance": true,
		"aliens": ["Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Wisp", "Veilcaster", "Veilcaster", "Veilcaster", "Veilcaster", "Veilcaster", "Ascendant"],
		"description": "Sylith Gate / choir hollow / waves end with the Ascendant"},
}
const GATES := {
	0: {1: Vector3(0, 120, -900)},
	1: {0: Vector3(0, -80, 900), 2: Vector3(-780, 180, -350), 3: Vector3(780, -180, -350)},
	2: {1: Vector3(750, -120, 300), 3: Vector3(-720, 220, -400)},
	3: {1: Vector3(-760, 80, 300), 2: Vector3(730, -160, -400)},
}
# Galaxy gate endpoints: each gate's portal near Outpost 01 (see GalaxyGates
# "portal") and every arena's return gate.
const SPECIAL_GATES := {
	0: {4: Vector3(320, 40, -300), 5: Vector3(-340, -30, -330), 6: Vector3(250, -50, 400)},
	4: {0: Vector3(0, 0, 700)},
	5: {0: Vector3(0, 0, 700)},
	6: {0: Vector3(0, 0, 700)},
}
# Replicated from the server's gate run: the arena map whose Outpost 01 portal is
# open, or -1. Only one gate run is open at a time.
static var open_rift := -1
# Read-only link tables per map, rebuilt when the open portal changes. Hot paths
# (protection, contacts, HUD) look links up every tick without allocating.
static var link_cache := {}
static var link_cache_open := -1

# Maps in the connected network, excluding gate arenas.
static func network_maps() -> Array[int]:
	var result: Array[int] = []
	for map: int in MAPS:
		if not MAPS[map].get("instance", false):
			result.append(map)
	return result


# Every usable gate on a map, keyed by destination. Callers must not modify it.
static func links(map: int) -> Dictionary:
	if link_cache_open != open_rift:
		link_cache.clear()
		link_cache_open = open_rift
	if not link_cache.has(map):
		var result: Dictionary = GATES.get(map, {}).duplicate()
		for destination: int in SPECIAL_GATES.get(map, {}):
			if map != 0 or destination == open_rift:
				result[destination] = SPECIAL_GATES[map][destination]
		link_cache[map] = result
	return link_cache[map]


# Every gate endpoint on a map, open or closed; used to keep alien homes clear.
static func endpoints(map: int) -> Dictionary:
	var result: Dictionary = GATES.get(map, {}).duplicate()
	result.merge(SPECIAL_GATES.get(map, {}))
	return result


static func gate_label(destination: int) -> String:
	var gate := GalaxyGates.for_map(destination)
	return GalaxyGates.info(gate)["name"].to_upper() if not gate.is_empty() else "GATE TO " + code(destination)

# Short map label such as "M2", used where a gate names its destination.
static func code(map: int) -> String:
	return MAPS[map]["name"].get_slice(" / ", 0)

static func origin(map: int) -> Vector3:
	return Vector3(map * 15000.0, 0, 0)

static func gate_point(map: int, destination: int) -> Vector3:
	return GATES[map][destination] if GATES.get(map, {}).has(destination) else SPECIAL_GATES[map][destination]

static func gate_position(map: int, destination: int) -> Vector3:
	return origin(map) + gate_point(map, destination)

static func arrival(map: int, source: int, slot: int = 0) -> Vector3:
	var gate: Vector3 = gate_point(map, source)
	var inward := -gate.normalized()
	var side := inward.cross(Vector3.UP).normalized()
	return origin(map) + gate + inward * 30.0 + side * ((slot % 5) - 2) * 6.0 + Vector3.UP * (slot / 5) * 6.0

static func protected(ship: SpaceShip) -> bool:
	# The gate arena has no safe zone: aliens may pursue pilots to the exit.
	if GalaxyGates.is_arena(ship.map_id):
		return false
	if ship.map_id == 0 and ship.position.distance_to(Sector.STATION_POSITION) <= Sector.PROTECTION_RADIUS:
		return true
	if ship.get_parent() is Sector:
		for destination: int in links(ship.map_id):
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
		for neighbor: int in GATES.get(map, {}):
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
	# Galaxy gates and arena exits take their faction's color.
	var gate := GalaxyGates.for_map(destination if map == 0 else map)
	var glow: Color = GalaxyGates.info(gate)["glow"] if not gate.is_empty() else Color("48e6f5")
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
				if not gate.is_empty():
					# The imported material is shared by every gate; tint a copy.
					var tinted := surface.duplicate() as BaseMaterial3D
					tinted.albedo_color = glow
					tinted.emission = glow
					part.set_surface_override_material(index, tinted)
	SectorVisuals.configure_texture_filtering(model)
	var aperture := QuadMesh.new()
	aperture.size = Vector2.ONE*25.2
	var energy := ShaderMaterial.new()
	energy.shader = preload("res://shaders/gate_portal.gdshader")
	energy.set_shader_parameter("turbulence",preload("res://assets/sector/nebula-panorama.png"))
	if not gate.is_empty():
		energy.set_shader_parameter("energy_color", glow)
	var portal := SectorVisuals.mesh(root,aperture,Vector3.ZERO,energy)
	portal.name = "Portal"
	portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Restrict the portal spill to gate armor; nearby ships and scenery keep their
	# existing lighting. Two soft lights make both approaches readable without bloom.
	for side in [-1,1]:
		var light := OmniLight3D.new()
		light.position = Vector3(0,0,side*5.0)
		light.light_color = glow
		light.light_energy = 5.0
		light.omni_range = 29
		light.omni_attenuation = 0.8
		light.light_cull_mask = 2
		root.add_child(light)
	var label := Label3D.new()
	label.text = gate_label(destination)
	label.position = Vector3(0, 27, 0)
	label.font_size = 40
	label.pixel_size = 0.08
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = MAPS[destination]["color"]
	root.add_child(label)
