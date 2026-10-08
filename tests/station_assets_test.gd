extends SceneTree
## Source/pack smoke check for the portable station finish and shared physics data.


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var room := Node3D.new()
	root.add_child(room)
	var station := SectorVisuals.station(room, Vector3.ZERO)
	var parts := station.find_children("*", "MeshInstance3D", true, false)
	if parts.size() != 1:
		fail("Station must export one mesh without a Blender studio.")
		return
	var shape := (parts[0] as MeshInstance3D).mesh
	if shape.get_surface_count() != 8 or shape.get_aabb().size.y < 250:
		fail("Station must preserve its tall silhouette and eight material surfaces.")
		return
	for surface in shape.get_surface_count():
		var mat := shape.surface_get_material(surface) as BaseMaterial3D
		if mat == null or mat.ao_texture == null:
			fail("Station surface is missing its material or portable occlusion map.")
			return
		var arrays := shape.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		# Godot can remap AO to UV1 on plain/emissive surfaces with no other map.
		var ao_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2 if mat.ao_on_uv2 else Mesh.ARRAY_TEX_UV]
		if ao_uv.size() != vertices.size():
			fail("Station surface %s is missing occlusion data (map=%s, uv2=%s, coordinates=%d/%d)." % [mat.resource_name, mat.ao_texture, mat.ao_on_uv2, ao_uv.size(), vertices.size()])
			return
		for vertex in vertices:
			if not vertex.is_finite():
				fail("Station has invalid vertex coordinates.")
				return
		if mat.resource_name.begins_with("Cobalt armor") or mat.resource_name.begins_with("Blue secondary"):
			if mat.albedo_texture == null or mat.normal_texture == null or not mat.clearcoat_enabled:
				fail("Station armor is missing its panel/normal maps or coated finish.")
				return
	if station.find_children("*", "CollisionShape3D", true, false).size() != 53:
		fail("Station collision manifest is missing from the pack.")
		return
	room.free()
	print("Station assets: one tall mesh, eight portable finishes, baked recess maps and 53 collision boxes.")
	quit()


func fail(message: String) -> void:
	push_error(message)
	quit(1)
