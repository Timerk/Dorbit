extends SceneTree
## Run against the exported main pack to catch missing dynamically loaded assets.

func _initialize() -> void:
	var liberator_textures := {}
	var liberator_finish: Dictionary[String, Color] = {}
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
			if id == "liberator":
				var material := instance.mesh.surface_get_material(surface) as BaseMaterial3D
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				if uv.size() != vertices.size() or material == null or material.get_texture(BaseMaterial3D.TEXTURE_ALBEDO) == null or material.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS) == null or material.get_texture(BaseMaterial3D.TEXTURE_NORMAL) == null:
					push_error("Liberator must package UVs and its color, roughness and normal maps.")
					quit(1)
					return
				for channel in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_NORMAL]:
					liberator_textures[material.get_texture(channel).get_instance_id()] = true
				if material.resource_name == "Blue grey armor" and not material.clearcoat_enabled:
					push_error("Liberator's painted armor must retain its clearcoat.")
					quit(1)
					return
				if material.resource_name in ["Blue cockpit glazing", "Blue grey armor"]:
					liberator_finish[material.resource_name] = surface_texel(instance.mesh, surface, BaseMaterial3D.TEXTURE_ALBEDO)
					liberator_finish[material.resource_name + " ORM"] = surface_texel(instance.mesh, surface, BaseMaterial3D.TEXTURE_ROUGHNESS)
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
	if liberator_textures.size() != 3:
		push_error("Liberator's ten surfaces must share three atlas textures.")
		quit(1)
		return
	if not liberator_finish.has("Blue cockpit glazing") or not liberator_finish.has("Blue grey armor") or liberator_finish["Blue cockpit glazing"].get_luminance() >= liberator_finish["Blue grey armor"].get_luminance() * .55:
		push_error("Liberator cockpit glazing must remain visibly darker than the blue armor.")
		quit(1)
		return
	var glass_orm := liberator_finish["Blue cockpit glazing ORM"]
	if glass_orm.g >= liberator_finish["Blue grey armor ORM"].g or glass_orm.b > .05:
		push_error("Liberator glazing must be smoother than armor and retain a dielectric glass finish.")
		quit(1)
		return
	print("Packaged ship assets: 12 centered 7 m hulls with finite geometry, PBR materials, previews and no studio")
	print("Liberator finish: UVs, 3 shared PBR atlases, coated paint and distinct smooth cockpit glass retained")
	quit()


func surface_texel(mesh: Mesh, surface: int, channel: int) -> Color:
	var arrays := mesh.surface_get_arrays(surface)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var sample_uv := (uv[indices[0]] + uv[indices[1]] + uv[indices[2]]) / 3.0
	var material := mesh.surface_get_material(surface) as BaseMaterial3D
	var pixels := material.get_texture(channel).get_image()
	if pixels.is_compressed():
		pixels.decompress()
	return pixels.get_pixelv(Vector2i(sample_uv * Vector2(pixels.get_size())))
