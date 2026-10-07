class_name ResourceLoot
extends Node3D
## Server-owned boxes. Rendering has no authority over collection or cargo.

const PICKUP_RADIUS := 12.0
const LIFETIME := 180.0
const MAX_DROPS := 64
var sector: Sector
var drops: Dictionary[int, Dictionary] = {}
var meshes: Dictionary[int, MeshInstance3D] = {}
var next_id := 0
var collect_clock := 0.0

func clear() -> void:
	for id: int in drops.keys():
		apply_drop(id, {})
	collect_clock = 0.0

func spawn_drop(alien: Alien) -> void:
	if sector.session.active and not multiplayer.is_server():
		return
	if drops.size() >= MAX_DROPS:
		change(drops.keys()[0], {})
	next_id += 1
	change(next_id, {"position": alien.position, "resources": CargoResources.roll(alien.kind), "ttl": LIFETIME})

func change(id: int, data: Dictionary) -> void:
	apply_drop(id, data)
	if sector.session.active and multiplayer.is_server():
		sector.session.combat.loot_changed.rpc(id, data)

func apply_drop(id: int, data: Dictionary) -> void:
	if data.is_empty():
		drops.erase(id)
		if meshes.has(id):
			meshes[id].queue_free()
			meshes.erase(id)
		return
	drops[id] = data.duplicate(true)
	if sector.dedicated_server:
		return
	if not meshes.has(id):
		var mesh := MeshInstance3D.new()
		var shape := PrismMesh.new()
		shape.size = Vector3(3, 3, 3)
		mesh.mesh = shape
		add_child(mesh)
		meshes[id] = mesh
	var richest := "prometium"
	for resource: String in CargoResources.TYPES:
		if data["resources"].has(resource):
			richest = resource
	var material := StandardMaterial3D.new()
	material.albedo_color = CargoResources.TYPES[richest]["color"]
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 1.8
	meshes[id].material_override = material
	meshes[id].position = data["position"]
	meshes[id].visible = not SectorVisuals.explosion_active(sector, meshes[id].global_position)

func is_presented(id: int) -> bool:
	return meshes.has(id) and meshes[id].visible

func _process(delta: float) -> void:
	for id: int in meshes:
		var mesh := meshes[id]
		mesh.visible = not SectorVisuals.explosion_active(sector, mesh.global_position)
		mesh.rotate_y(delta * 0.7)

func tick(delta: float) -> void:
	for id: int in drops.keys():
		drops[id]["ttl"] -= delta
		if drops[id]["ttl"] <= 0:
			change(id, {})
	collect_clock += delta
	if collect_clock < 0.2 or drops.is_empty():
		return
	collect_clock = 0.0
	if sector.session.active:
		sector.session.combat.collect_loot()
	elif sector.player.alive:
		for id: int in drops.keys():
			if sector.player.position.distance_to(drops[id]["position"]) > PICKUP_RADIUS:
				continue
			var data := drops[id].duplicate(true)
			var taken := CargoResources.collect(sector.cargo, data["resources"], sector.cargo_capacity)
			if not taken.is_empty():
				sector.notify("Collected " + CargoResources.describe(taken))
				change(id, {} if data["resources"].is_empty() else data)
