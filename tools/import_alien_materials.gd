@tool
extends EditorScenePostImport
## Share the portable finish atlases across all seven alien material surfaces.


func _post_import(scene: Node) -> Object:
	var shared: Dictionary[int, Texture2D] = {}
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(surface) as BaseMaterial3D
			for channel in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC]:
				if channel == BaseMaterial3D.TEXTURE_METALLIC:
					material.set_texture(channel, shared[BaseMaterial3D.TEXTURE_ROUGHNESS])
				elif shared.has(channel):
					material.set_texture(channel, shared[channel])
				else:
					shared[channel] = material.get_texture(channel)
			if material.resource_name.ends_with("coated armor"):
				material.clearcoat_enabled = true
				material.clearcoat = .12
				material.clearcoat_roughness = .38
	return scene
