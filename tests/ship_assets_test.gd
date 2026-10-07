extends SceneTree
## Run against the exported main pack to catch missing dynamically loaded assets.

func _initialize() -> void:
	if ShipCatalog.MODELS.size() != 12:
		push_error("Exported ship catalog must contain twelve hulls.")
		quit(1)
		return
	for id: String in ShipCatalog.MODELS:
		var hull := ShipCatalog.model_scene(id)
		if hull == null or StationUi.texture(id) == null:
			push_error("Missing packaged ship assets for " + id)
			quit(1)
			return
		var meshes := hull.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() != 1 or not hull.find_children("*", "Camera3D", true, false).is_empty() or not hull.find_children("*", "Light3D", true, false).is_empty():
			push_error("Ship export must contain one mesh and no studio: " + id)
			quit(1)
			return
		var instance := meshes[0] as MeshInstance3D
		var bounds := instance.mesh.get_aabb()
		if absf(bounds.size.length() - 7.0) > 0.01 or bounds.get_center().length() > 0.01:
			push_error("Ship export must preserve its centered 7 m bounding diameter: " + id)
			quit(1)
			return
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vertices.is_empty() or instance.mesh.surface_get_material(surface) == null:
				push_error("Empty geometry or missing PBR material: " + id)
				quit(1)
				return
			for vertex in vertices:
				if not vertex.is_finite():
					push_error("Non-finite exported geometry: " + id)
					quit(1)
					return
		hull.free()
	print("Packaged ship assets: 12 centered 7 m hulls with finite geometry, PBR materials, previews and no studio")
	quit()
