extends SceneTree
## Run against source or the exported main pack to catch missing ship finishes.

const PAINT := ["Blue grey armor", "Muted green grey armor", "Cobalt enamel",
	"Aegis green enamel", "Defcom green enamel", "Phoenix red enamel"]


func _initialize() -> void:
	if ShipCatalog.MODELS.size() != 12:
		fail("Exported ship catalog must contain twelve hulls.")
		return
	for id: String in ShipCatalog.MODELS:
		var hull := ShipCatalog.model_scene(id)
		if hull == null or StationUi.texture(id) == null:
			fail("Missing packaged ship assets for " + id)
			return
		var meshes := hull.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() != 1 or not hull.find_children("*", "Camera3D", true, false).is_empty() or not hull.find_children("*", "Light3D", true, false).is_empty():
			fail("Ship export must contain one mesh and no studio: " + id)
			return
		var mesh := (meshes[0] as MeshInstance3D).mesh
		var bounds := mesh.get_aabb()
		if absf(bounds.size.length() - 7.0) > 0.01 or bounds.get_center().length() > 0.01:
			fail("Ship export must preserve its centered 7 m bounding diameter: " + id)
			return
		if not check_finish(id, mesh):
			return
		hull.free()
	print("Packaged ship assets: 12 centered 7 m hulls with finite geometry, previews and no studio")
	print("Roster finish: every hull retains UVs, 3 shared PBR atlases, coated paint and distinct smooth cockpit glass")
	quit()


func check_finish(id: String, mesh: Mesh) -> bool:
	var textures := {}
	var glass: Array[Color] = []
	var brightest_armor := 0.0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if vertices.is_empty() or material == null or uv.size() != vertices.size():
			return fail("Missing geometry, material or UVs: " + id)
		for vertex in vertices:
			if not vertex.is_finite():
				return fail("Non-finite exported geometry: " + id)
		for channel in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_NORMAL]:
			var texture := material.get_texture(channel)
			if texture == null or texture.get_size() != Vector2(2048, 2048):
				return fail("Missing full-resolution PBR atlas: " + id)
			textures[texture.get_instance_id()] = true
		if material.get_texture(BaseMaterial3D.TEXTURE_METALLIC) != material.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS):
			return fail("Metal and roughness must share the ORM map: " + id)
		var color := surface_texel(mesh, surface, BaseMaterial3D.TEXTURE_ALBEDO)
		var orm := surface_texel(mesh, surface, BaseMaterial3D.TEXTURE_ROUGHNESS)
		var glazing := material.resource_name.to_lower().contains("glass") or material.resource_name.to_lower().contains("glazing")
		if glazing:
			glass.append(color)
			if color.get_luminance() > .18 or orm.g > .14 or orm.b > .05:
				return fail("Cockpit glass must retain a dark, smooth dielectric finish: " + id)
		elif PAINT.has(material.resource_name):
			brightest_armor = maxf(brightest_armor, color.get_luminance())
			if not material.clearcoat_enabled or orm.b > .25 or orm.g < .20:
				return fail("Colored armor must retain coated paint rather than bare metal: " + id)
		if material.resource_name in ["Ion blue", "Green reactor lens"] and not material.emission_enabled:
			return fail("Ship lights must preserve emission: " + id)
	if textures.size() != 3 or glass.is_empty():
		return fail("Each hull must share three atlases and retain cockpit glass: " + id)
	for color in glass:
		if brightest_armor > 0 and color.get_luminance() >= brightest_armor * .65:
			return fail("Cockpit glazing must contrast with colored armor: " + id)
	print("FINISH ", id, ": ", mesh.get_surface_count(), " surfaces, 3 shared maps, ", glass.size(), " glass materials")
	return true


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


func fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
