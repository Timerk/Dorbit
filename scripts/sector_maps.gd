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
	if ship.map_id == 0 and ship.position.distance_to(Sector.STATION_POSITION) <= PROTECTION_RADIUS:
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
	root.position = gate_position(map, destination)
	parent.add_child(root)
	root.look_at(origin(map), Vector3.UP)
	var armor := SectorVisuals.material(Color("506375"))
	var glow := SectorVisuals.material(MAPS[destination]["color"], true)
	for index in range(24):
		var angle := index * TAU / 24.0
		var rim := SectorVisuals.box(root, Vector3(cos(angle), sin(angle), 0) * 16.0, Vector3(3.0, 4.4, 3.0), armor)
		rim.rotation.z = angle
		var light := SectorVisuals.box(root, Vector3(cos(angle), sin(angle), -1.7) * Vector3(12.8, 12.8, 1), Vector3(0.6, 3.2, 0.4), glow)
		light.rotation.z = angle
	var label := Label3D.new()
	label.text = "GATE TO " + MAPS[destination]["name"]
	label.position = Vector3(0, 23, 0)
	label.font_size = 40
	label.pixel_size = 0.08
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = MAPS[destination]["color"]
	root.add_child(label)
