extends SceneTree
## Source and exported-client checks for the shared textured encounter models.

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func run() -> void:
	# Before any presentation factory runs, server-side enemies must not load art.
	for kind: String in Alien.TYPES:
		var server_alien := Alien.new()
		server_alien.kind = kind
		server_alien.render_enabled = false
		root.add_child(server_alien)
		check(server_alien.model == null and server_alien.get_child_count() == 1,
			kind + " server creates only the gameplay collider")
		check(not ResourceLoader.has_cached("res://assets/aliens/%s.glb" % kind.to_lower()),
			kind + " server does not load a visual asset")
		var diameter := SectorVisuals.destruction_size(server_alien)
		check(diameter > 0 and (not Alien.VISUAL_DIAMETERS.has(kind)
			or is_equal_approx(diameter, float(Alien.VISUAL_DIAMETERS[kind]) * float(Alien.VISUAL_SCALE[kind]))),
			kind + " server knows the visual destruction size without a mesh")
		server_alien.free()
	var preview := ContractPreview.new()
	root.add_child(preview)
	var sizes: Array[float] = []
	for kind: String in Alien.VISUAL_DIAMETERS:
		var alien := Alien.new()
		alien.kind = kind
		alien.home_position = Vector3.ZERO
		root.add_child(alien)
		var meshes := alien.model.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() == 1, kind + " uses one imported textured mesh")
		check(alien.model.find_children("*", "Camera3D", true, false).is_empty()
			and alien.model.find_children("*", "CollisionShape3D", true, false).is_empty(),
			kind + " model brings no studio or new physics geometry")
		if meshes.size() != 1:
			alien.free()
			continue
		var instance := meshes[0] as MeshInstance3D
		var mesh := instance.mesh as ArrayMesh
		var bounds := mesh.get_aabb()
		var diameter := float(Alien.VISUAL_DIAMETERS[kind])
		sizes.append(bounds.size.length())
		check(bounds.get_center().length() < .001 and absf(bounds.size.length() - diameter) < .001,
			kind + " is centered at its existing size tier")
		check(instance.transform.is_equal_approx(Transform3D.IDENTITY)
			and alien.model.scale.is_equal_approx(Vector3.ONE * float(Alien.VISUAL_SCALE[kind])),
			kind + " retains its baked orientation with presentation scaling")
		var collision := alien.get_child(0) as CollisionShape3D
		check(collision.shape is SphereShape3D and is_equal_approx(collision.shape.radius, float(Alien.TYPES[kind].get("radius", 2.2))),
			kind + " keeps its configured collision sphere")
		check(alien.hull == Alien.TYPES[kind]["hull"] and alien.shield == Alien.TYPES[kind]["shield"]
			and alien.laser_damage == Alien.TYPES[kind]["damage"], kind + " keeps combat tuning")
		check_finish(kind, mesh)
		preview.show_kind(kind)
		var preview_mesh := preview.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		check(preview_mesh.mesh == mesh, kind + " preview shares the actual encounter mesh")
		check(preview.model.scale == alien.model.scale and preview.camera.size >= diameter * float(Alien.VISUAL_SCALE[kind]) * 0.7,
			kind + " preview frames the same enlarged model")
		check(preview.camera.position.length() > diameter * float(Alien.VISUAL_SCALE[kind]),
			kind + " preview camera stays outside the enlarged hull")
		alien.take_damage(alien.max_hull + alien.max_shield + 1, null)
		check(not alien.alive and not alien.visible and alien.collision_layer == 0,
			kind + " destruction still hides the model and disables collision")
		alien.reset_health()
		check(alien.alive and alien.visible and alien.collision_layer == 2,
			kind + " respawn restores visibility and collision")
		alien.free()
	# Gate aliens without authored art use colored placeholder models.
	var placeholders: Array = Alien.TYPES.keys().filter(func(kind: String): return not Alien.VISUAL_DIAMETERS.has(kind))
	check(sizes.size() == Alien.TYPES.size() - placeholders.size() and sizes[0] < sizes[1] and sizes[1] < sizes[2],
		"Scout, Sentinel and Heavy retain increasing visual size")
	check(Alien.VISUAL_DIAMETERS.size() == Alien.TYPES.size() - placeholders.size() and placeholders.all(func(kind: String): return not Alien.VISUAL_DIAMETERS.has(kind)),
		"Every authored encounter type has an imported model and a mesh-free server diameter")
	check_vashar()
	for gate_id: String in GalaxyGates.ORDER:
		var faction: Array = GalaxyGates.info(gate_id)["pool"].keys()
		if faction.all(func(kind: String): return kind in placeholders):
			check_placeholders(faction)
	# Gate rosters are their own faction progressions, checked separately.
	var roster: Array = Alien.TYPES.keys().filter(func(kind: String): return not kind in GalaxyGates.arena_kinds())
	roster.sort_custom(func(a: String, b: String): return Alien.TYPES[a]["hull"] < Alien.TYPES[b]["hull"])
	var previous_diameter := 0.0
	for kind: String in roster:
		var alien := Alien.new()
		alien.kind = kind
		root.add_child(alien)
		var bounds := AABB()
		var first := true
		for part: MeshInstance3D in alien.model.find_children("*", "MeshInstance3D", true, false):
			for corner in range(8):
				var point := alien.to_local(part.to_global(part.get_aabb().get_endpoint(corner)))
				bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
				first = false
		var diameter := bounds.size.length()
		check(not first and diameter > previous_diameter, kind + " is visually larger than every weaker alien")
		previous_diameter = diameter
		check(is_equal_approx((alien.get_child(0) as CollisionShape3D).shape.radius, 2.2)
			and alien.hull == Alien.TYPES[kind]["hull"] and alien.shield == Alien.TYPES[kind]["shield"]
			and alien.laser_damage == Alien.TYPES[kind]["damage"], kind + " enlargement preserves collider and combat tuning")
		if kind in ["Marauder", "Warden"]:
			check(diameter >= 20.0, kind + " M3 silhouette spans at least 20 m")
		elif kind in ["Ravager", "Overlord"]:
			check(diameter >= 35.0, kind + " M4 silhouette spans at least 35 m")
		print("ALIEN_SIZE %s diameter=%.2f m" % [kind, diameter])
		alien.free()
	preview.free()
	print("Alien asset checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


func check_finish(kind: String, mesh: ArrayMesh) -> void:
	var textures := {}
	var painted := false
	var luminous := false
	var forward_optics := false
	var rear_exhaust := false
	var lod_count := 0
	var triangles := 0
	var bounds := mesh.get_aabb()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		check(not vertices.is_empty() and uv.size() == vertices.size() and normals.size() == vertices.size(),
			kind + " surface preserves geometry, UVs and normals")
		var finite := true
		for vertex in vertices:
			finite = finite and vertex.is_finite()
		check(finite, kind + " surface positions are finite")
		triangles += indices.size() / 3
		var data := RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
		lod_count += data.get("lods", []).size()
		for channel in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
			var texture := material.get_texture(channel)
			check(texture != null and texture.get_size() == Vector2(2048, 2048), kind + " has a 2K runtime atlas")
			if texture != null:
				textures[texture.get_instance_id()] = true
		check(material.get_texture(BaseMaterial3D.TEXTURE_METALLIC) == material.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS),
			kind + " shares metallic and roughness maps")
		if material.resource_name.ends_with("coated armor"):
			painted = material.clearcoat_enabled
			# Vashar armor keeps a low lift so near-black crystal contrasts with its violet seams.
			var minimum_lift := 2.0 if kind in ["Scout", "Sentinel", "Heavy"] else (0.1 if kind in GalaxyGates.arena_kinds() else 0.3)
			check(material.emission_enabled and material.emission == Color.WHITE
				and material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY
				and material.emission_energy_multiplier >= minimum_lift
				and material.emission_texture == material.albedo_texture,
				kind + " textured armor remains visible without direct light or bloom")
		elif material.resource_name.ends_with("sensor emission") and material.emission_enabled:
			luminous = true
			for vertex in vertices:
				forward_optics = forward_optics or vertex.z < bounds.position.z + .04
				rear_exhaust = rear_exhaust or vertex.z > bounds.end.z - bounds.size.length() * .08
	check(textures.size() == 3 and painted and luminous, kind + " retains three shared maps, coated armor and emission")
	# Vashar crystals are deliberately low-poly faceted hulls without forward optics.
	var vashar := kind in GalaxyGates.arena_kinds()
	check(vashar or (forward_optics and rear_exhaust), kind + " cannons face -Z and exhausts face +Z")
	check(lod_count > 0 and triangles > (1500 if vashar else 30000), kind + " retains detailed geometry and generated distance LODs")
	print("ALIEN_GEOMETRY %s triangles=%d lod_levels=%d" % [kind, triangles, lod_count])


func check_vashar() -> void:
	var previous := 0.0
	for kind: String in GalaxyGates.info("vashar")["pool"]:
		var alien := Alien.new()
		alien.kind = kind
		root.add_child(alien)
		var instance := alien.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var diameter := instance.mesh.get_aabb().size.length() * float(Alien.VISUAL_SCALE[kind])
		check(diameter > previous, kind + " is larger than the previous Vashar tier")
		check(is_equal_approx(SectorVisuals.destruction_size(alien), float(Alien.VISUAL_DIAMETERS[kind]) * float(Alien.VISUAL_SCALE[kind])), kind + " destruction size matches its exported model")
		previous = diameter
		print("ALIEN_SIZE %s diameter=%.2f m" % [kind, diameter])
		alien.free()


func check_placeholders(kinds: Array) -> void:
	var previous := 0.0
	for kind: String in kinds:
		var alien := Alien.new()
		alien.kind = kind
		root.add_child(alien)
		var diameter := SectorVisuals.destruction_size(alien)
		check(not alien.model.find_children("*", "MeshInstance3D", true, false).is_empty(), kind + " has a placeholder model")
		check(diameter > previous, kind + " placeholder is larger than the previous tier of its faction")
		check(is_equal_approx((alien.get_child(0) as CollisionShape3D).shape.radius, float(Alien.TYPES[kind].get("radius", 2.2))), kind + " uses its configured collider")
		previous = diameter
		alien.free()
