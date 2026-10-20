class_name SectorVisuals
extends RefCounted
## Presentation kept outside flight and combat simulation.

const EFFECT_LIMIT: int = 64
const DESTRUCTION_LIMIT: int = 80
const EXPLOSION_DURATION: float = 1.2
const LASER_LIGHT_LIMIT: int = 12 # Keeps busy fights within the renderer's light budget.
const GLOW_SHADER := preload("res://shaders/combat_glow.gdshader")
const SHIELD_SHADER := preload("res://shaders/shield_hit.gdshader")
const STREAK_SHADER := preload("res://shaders/combat_streak.gdshader")
const SPARK_HOT := Color("ffe2ac")
const SPARK_COOL := Color(1.0, 0.25, 0.03, 0.0)
const SUN_ROTATION := Vector3(-30, -35, 0)
const FIREBALL_SHADER := preload("res://shaders/explosion_fireball.gdshader")
const DEBRIS_SHADER := preload("res://shaders/explosion_debris.gdshader")

# Effects share unit meshes and materials; nodes scale them and set instance uniforms.
static var _effect_resources: Dictionary[String, Resource] = {}


static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = 0.55 if not glow else 0.0
	result.roughness = 0.55
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if glow:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		result.emission_enabled = true
		result.emission = color
	return result


static func mesh(parent: Node3D, shape: Mesh, position: Vector3, surface: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = surface
	if surface is BaseMaterial3D and surface.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = position
	parent.add_child(instance)
	return instance


static func box(parent: Node3D, position: Vector3, size: Vector3, surface: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, position, surface)


static func ship_model(hostile: bool) -> Node3D:
	var root := Node3D.new()
	var armor := material(Color("753a51") if hostile else Color("a6bbc9"))
	var dark := material(Color("172c43"))
	var light := material(Color("ff655d") if hostile else Color("58e2f1"), true)
	box(root, Vector3.ZERO, Vector3(1.6, 0.8, 4.7), armor)
	box(root, Vector3(0, 0.55, -0.3), Vector3(1.0, 0.45, 1.6), dark)
	box(root, Vector3(0, 0.8, -0.65), Vector3(0.72, 0.08, 0.95), light)
	for side in [-1.0, 1.0]:
		var wing := box(root, Vector3(side * 1.8, -0.15, 0.65), Vector3(2.6, 0.2, 1.7), armor)
		wing.rotation.y = side * -0.35
		box(root, Vector3(side * 2.5, 0, 0.3), Vector3(0.35, 0.4, 3.2), dark)
		box(root, Vector3(side * 2.5, 0, -1.35), Vector3(0.18, 0.2, 0.2), light)
		var engine := CylinderMesh.new()
		engine.top_radius = 0.42
		engine.bottom_radius = 0.32
		engine.height = 1.4
		mesh(root, engine, Vector3(side * 1.0, -0.05, 2.0), dark).rotation.x = PI / 2.0
		box(root, Vector3(side * 1.0, -0.05, 2.75), Vector3(0.48, 0.4, 0.06), light)
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.82
	nose.height = 2.1
	nose.radial_segments = 4
	mesh(root, nose, Vector3(0, 0, -3.0), armor).rotation.x = -PI / 2.0
	return root


static func station(parent: Node3D, location: Vector3, render: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Outpost01"
	root.position = location
	parent.add_child(root)
	if render:
		var model := (load("res://assets/sector/outpost-01.glb") as PackedScene).instantiate()
		for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for index in part.mesh.get_surface_count():
				var surface := part.mesh.surface_get_material(index) as BaseMaterial3D
				# Keep geometric recess shading without suppressing the sun highlights.
				surface.ao_light_affect = 0.2
				if surface.resource_name.begins_with("Cyan guidance"):
					# Keep the cyan hue readable in the linear Compatibility tonemapper.
					surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					surface.albedo_color = Color(0.02, 0.85, 1.0)
					surface.emission = Color(0.02, 0.4, 0.7)
					surface.emission_energy_multiplier = 0.6
				if surface.resource_name.begins_with("Cobalt armor") or surface.resource_name.begins_with("Blue secondary"):
					surface.clearcoat_enabled = true
					surface.clearcoat = 0.8
					surface.clearcoat_roughness = 0.12
		configure_texture_filtering(model)
		root.add_child(model)
	# Blender exports simple physics envelopes separately from the render mesh.
	# The same manifest is loaded by clients and servers; hangar throats stay open.
	var boxes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sector/outpost-01-collision.json"))
	for entry: Dictionary in boxes:
		var p: Array = entry["position"]
		var s: Array = entry["size"]
		add_box_collider(root, Vector3(p[0], p[1], p[2]), Vector3(s[0], s[1], s[2]))
	return root


static func add_box_collider(parent: Node3D, location: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = location
	body.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)


static func environment(parent: Node3D, render: bool = true) -> void:
	if render:
		var world := WorldEnvironment.new()
		world.name = "WorldEnvironment"
		var settings := Environment.new()
		settings.background_mode = Environment.BG_SKY
		settings.sky = Sky.new()
		settings.sky.process_mode = Sky.PROCESS_MODE_QUALITY
		settings.sky.radiance_size = Sky.RADIANCE_SIZE_512
		var sky_material := ShaderMaterial.new()
		sky_material.shader = preload("res://shaders/space.gdshader")
		sky_material.set_shader_parameter("nebula_panorama", preload("res://assets/sector/nebula-panorama.png"))
		settings.sky.sky_material = sky_material
		# A dim cool ambient keeps unlit sides readable while the sun shapes hulls and rock.
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		settings.ambient_light_color = Color("7f97b8")
		settings.ambient_light_energy = 0.3
		# Filmic rolls off sun highlights and effect cores instead of clipping them flat.
		settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		settings.tonemap_exposure = 1.25
		settings.tonemap_white = 6.0
		settings.glow_hdr_threshold = 0.9
		settings.glow_intensity = 0.45
		settings.glow_bloom = 0.04
		settings.ssao_radius = 3.0
		settings.ssao_intensity = 1.2
		world.environment = settings
		parent.add_child(world)
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = SUN_ROTATION
		sun.light_color = Color("ffdfbd")
		sun.light_energy = 2.1
		sun.light_specular = 0.8
		parent.add_child(sun)
		sky_material.set_shader_parameter("sun_direction", Basis.from_euler(SUN_ROTATION * PI / 180.0).z)
		sky_material.set_shader_parameter("sun_color", sun.light_color)
		var fill := DirectionalLight3D.new()
		fill.name = "Fill"
		fill.rotation_degrees = Vector3(25, 145, 0)
		fill.light_color = Color("6e9edb")
		fill.light_energy = 0.3
		fill.light_specular = 0.15
		parent.add_child(fill)
		SpaceDust.attach(parent)
		SunFlare.attach(parent)
		# Distant scenery sits beyond the safe sector and has no colliders.
		distant_scenery(parent)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301
	var rock_surface: StandardMaterial3D
	if render:
		rock_surface = asteroid_surface()
	for index in range(24):
		var body := StaticBody3D.new()
		body.name = "Asteroid%d" % index
		var side := -1.0 if index % 2 == 0 else 1.0
		body.position = Vector3(side * rng.randf_range(80, 280), rng.randf_range(-90, 90), rng.randf_range(-400, -70))
		var radius := rng.randf_range(4.0, 16.0)
		# Consume the same random values on clients and servers to preserve collision geometry.
		var angles := Vector3(rng.randf(), rng.randf(), rng.randf())
		if render:
			var rock := (load("res://assets/sector/asteroid-%d.glb" % (index % 3)) as PackedScene).instantiate() as Node3D
			rock.scale = Vector3.ONE * radius
			rock.rotation = angles
			apply_surface(rock, rock_surface)
			body.add_child(rock)
		var collider := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		collider.shape = shape
		body.add_child(collider)
		parent.add_child(body)


static func apply_surface(node: Node, surface: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = surface
	for child in node.get_children():
		apply_surface(child, surface)


static func texture_filtering_enabled(parent: Node) -> bool:
	while parent != null:
		if parent is Sector:
			return parent.settings.anisotropic_filtering > 0
		parent = parent.get_parent()
	return false


static func configure_texture_filtering(node: Node, enabled: bool = true) -> void:
	var filter_mode := BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if enabled else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if node is GeometryInstance3D and node.material_override is BaseMaterial3D:
		(node.material_override as BaseMaterial3D).texture_filter = filter_mode
	if node is MeshInstance3D and node.mesh != null:
		for index in range(node.mesh.get_surface_count()):
			var surface := node.get_active_material(index) as BaseMaterial3D
			if surface != null:
				surface.texture_filter = filter_mode
	for child in node.get_children():
		configure_texture_filtering(child, enabled)


static func apply_graphics(parent: Node3D, preferences: GameSettings) -> void:
	var world := parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null:
		return # Dedicated servers have no environment or presentation settings.
	# GLES3 ignores runtime Viewport strengths; the saved startup override
	# sets the maximum. Material samplers still switch filtering on/off live.
	configure_texture_filtering(parent, preferences.anisotropic_filtering > 0)
	for preview: ShipHangarPreview in parent.get_tree().get_nodes_in_group("graphics_previews"):
		if parent.is_ancestor_of(preview):
			preview.apply_graphics()
	world.environment.glow_enabled = preferences.bloom
	world.environment.ssao_enabled = preferences.ssao
	var sun := parent.get_node("Sun") as DirectionalLight3D
	sun.shadow_enabled = preferences.shadow_quality > 0
	if sun.shadow_enabled:
		RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][preferences.shadow_quality - 1], true)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if preferences.shadow_quality == 3 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = [180.0, 300.0, 500.0][preferences.shadow_quality - 1]
	if parent.get_meta("effects_quality", 2) != preferences.effects_quality:
		for effect in parent.get_tree().get_nodes_in_group("transient_feedback"):
			if parent.is_ancestor_of(effect):
				effect.queue_free()
	parent.set_meta("effects_quality", preferences.effects_quality)


static func effects_quality(parent: Node) -> int:
	while parent != null:
		if parent is Sector:
			return parent.settings.effects_quality
		parent = parent.get_parent()
	return 2


static func asteroid_surface() -> StandardMaterial3D:
	# Real asteroids are dark; a low albedo leaves room for a bright sunlit rim.
	var surface := material(Color("7a7774"))
	surface.metallic = 0.0
	surface.roughness = 1.0
	surface.albedo_texture = load("res://assets/sector/rock-albedo.png")
	surface.normal_enabled = true
	surface.normal_texture = load("res://assets/sector/rock-normal.png")
	surface.normal_scale = 1.1
	surface.uv1_triplanar = true
	surface.uv1_scale = Vector3.ONE * 2.5
	return surface


static func distant_scenery(parent: Node3D) -> void:
	SectorBackdrop.build(parent, 0)


static func effect_resource(key: String) -> Resource:
	var resource: Resource = _effect_resources.get(key)
	if resource == null:
		resource = _create_effect_resource(key)
		_effect_resources[key] = resource
	return resource


static func _create_effect_resource(key: String) -> Resource:
	match key:
		"beam_low", "beam_high":
			var beam := CylinderMesh.new()
			beam.top_radius = 0.055
			beam.bottom_radius = 0.055
			beam.height = 1.0
			beam.radial_segments = 4 if key == "beam_low" else 8
			return beam
		"spark":
			var spark := CylinderMesh.new()
			spark.top_radius = 0.015
			spark.bottom_radius = 0.045
			spark.height = 1.0
			spark.radial_segments = 4
			return spark
		"glow":
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			return quad
		"shell_low", "shell_high":
			var shell := SphereMesh.new()
			shell.radius = 1.0
			shell.height = 2.0
			shell.radial_segments = 16 if key == "shell_low" else 32
			shell.rings = 8 if key == "shell_low" else 16
			return shell
		"debris":
			var chunk := BoxMesh.new()
			chunk.size = Vector3.ONE
			return chunk
	var surface := ShaderMaterial.new()
	surface.shader = {"streak_material": STREAK_SHADER, "glow_material": GLOW_SHADER, "shield_material": SHIELD_SHADER, "fireball_material": FIREBALL_SHADER, "debris_material": DEBRIS_SHADER}[key]
	return surface


static func effect_mesh(parent: Node3D, shape: String, surface: String, location: Vector3, size: Vector3) -> MeshInstance3D:
	var instance := mesh(parent, effect_resource(shape), location, effect_resource(surface))
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.scale = size
	return instance


static func laser(parent: Node3D, start: Vector3, finish: Vector3, hostile: bool, ammo_type: String = "x1") -> void:
	sound(parent, "laser", start)
	if start.distance_squared_to(finish) < 0.01:
		return
	var direction := (finish - start).normalized()
	# Use the existing shot endpoints for presentation; no additional combat RPCs.
	var target := shot_target(parent, finish)
	var endpoint := finish
	if target != null:
		target.set_meta("visual_hit_direction", -direction)
		target.set_meta("visual_hit_time", Time.get_ticks_msec())
		var contact_radius := shield_radius(target) if target.shield > 0.0 else hull_contact(target, -direction).length()
		endpoint -= direction * minf(contact_radius, start.distance_to(finish) * 0.5)
	var effect := feedback_root(parent, start, 0.18)
	if effect == null:
		return
	effect.set_meta("laser", true)
	var quality := effects_quality(parent)
	var color: Color = Color("ff6245") if hostile else Ammunition.TYPES.get(ammo_type, Ammunition.TYPES["x1"])["color"]
	var length := start.distance_to(endpoint)
	var core := color.lerp(Color.WHITE, 0.35)
	var beam := effect_mesh(effect, "beam_low" if quality == 1 else "beam_high", "streak_material", (endpoint - start) * 0.5, Vector3(1.0, length, 1.0))
	beam.quaternion = Quaternion(Vector3.UP, direction)
	beam.set_instance_shader_parameter("tint", core)
	if quality > 1:
		# The beam's length scale also stretches its child aura.
		glow(beam, Vector3.ZERO, Vector2(0.95, 1.0), color, 0.18).set_instance_shader_parameter("beam", true)
	var tween := beam.create_tween().set_parallel(true)
	tween.tween_property(beam, "scale", Vector3(0.2, length, 0.2), 0.18)
	tween.tween_method(func(alpha: float): beam.set_instance_shader_parameter("tint", Color(core, alpha)), core.a, 0.0, 0.18)
	if quality > 1:
		glow(effect, Vector3.ZERO, Vector2.ONE * 2.4, color, 0.09)
		glow(effect, endpoint - start, Vector2.ONE * 2.0, color, 0.13)
		# Hits briefly light the target hull in the beam colour.
		if parent.get_tree().get_node_count_in_group("laser_lights") < LASER_LIGHT_LIMIT:
			var light := OmniLight3D.new()
			light.add_to_group("laser_lights")
			light.position = endpoint - start
			light.light_color = color
			light.omni_range = 12.0
			light.light_energy = 3.0
			effect.add_child(light)
			light.create_tween().tween_property(light, "light_energy", 0.0, 0.16)


static func explosion(parent: Node3D, location: Vector3, diameter: float = 9.7) -> void:
	sound(parent, "destruction", location)
	var effect := feedback_root(parent, location, EXPLOSION_DURATION, DESTRUCTION_LIMIT)
	if effect == null:
		return
	effect.add_to_group("destruction_feedback")
	var size := maxf(diameter, 1.0)
	var high := effects_quality(parent) > 1
	effect.set_meta("diameter", size)
	var flash := glow(effect, Vector3.ZERO, Vector2.ONE * size * 2.2, Color("ffc46e"), 0.55)
	effect.create_tween().tween_property(flash, "scale", flash.scale * 2.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Overlapping turbulent puffs burn out from white-hot to drifting smoke.
	for index in range(6 if high else 2):
		var offset := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).limit_length(1.0) * size * (0.0 if index == 0 else 0.3)
		var puff := effect_mesh(effect, "glow", "fireball_material", offset, Vector3.ONE * size * randf_range(0.9, 1.25))
		puff.set_instance_shader_parameter("seed", randf())
		puff.set_instance_shader_parameter("heat", 1.0 if index == 0 else randf_range(0.65, 0.95))
		var lifetime := randf_range(0.85, 1.1)
		var tween := puff.create_tween().set_parallel(true)
		tween.tween_method(func(value: float): puff.set_instance_shader_parameter("progress", value), 0.0, 1.0, lifetime)
		tween.tween_property(puff, "scale", puff.scale * 2.1, lifetime).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "position", offset * 2.2, lifetime).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# Spent puffs are transparent but still shade their large quads; the root keeps loot timing.
		tween.chain().tween_callback(puff.queue_free)
	if high:
		glow(effect, Vector3.ZERO, Vector2(size * 4.8, size * 0.24), Color("ffd598"), 0.5)
		var shockwave := glow(effect, Vector3.ZERO, Vector2.ONE * size, Color(1.0, 0.78, 0.55, 0.45), 0.5)
		shockwave.set_instance_shader_parameter("ring", true)
		effect.create_tween().tween_property(shockwave, "scale", Vector3(size * 4.5, size * 4.5, 1.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# The blast briefly lights nearby hulls, rock and station plating.
		var light := OmniLight3D.new()
		light.light_color = Color("ffa04a")
		light.omni_range = maxf(size * 6.0, 20.0)
		light.light_energy = 6.0
		effect.add_child(light)
		effect.create_tween().tween_property(light, "light_energy", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		debris(effect, size)
	sparks(effect, Vector3.ZERO, Vector3.ZERO, 4 if not high else 12, size * 0.55, 1.15)


static func debris(parent: Node3D, size: float) -> void:
	# Tumbling hull fragments glow hot, then cool to dark metal as they fly apart.
	for index in range(6):
		var chunk := effect_mesh(parent, "debris", "debris_material", Vector3.ZERO, Vector3(randf_range(0.6, 1.4), randf_range(0.25, 0.6), randf_range(0.4, 1.0)) * size * 0.09)
		var direction := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		chunk.set_instance_shader_parameter("heat", 1.0)
		var tween := chunk.create_tween().set_parallel(true)
		tween.tween_property(chunk, "position", direction * size * randf_range(1.6, 3.2), 1.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(chunk, "rotation", Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)), 1.15)
		tween.tween_method(func(value: float): chunk.set_instance_shader_parameter("heat", value), 1.0, 0.0, 0.9)


static func destruction_size(ship: SpaceShip) -> float:
	# Exported visual diameters are also available without loading server meshes.
	if ship is Pilot:
		return float(ShipCatalog.info(ship.ship_model).get("visual_diameter", 7.0))
	if ship is Alien:
		return float(Alien.VISUAL_DIAMETERS.get(ship.kind, 7.0 * ship.tuning()["scale"].length() / sqrt(3.0))) * float(Alien.VISUAL_SCALE[ship.kind])
	return Vector3(6.6253, 1.895, 6.83).length()


static func explosion_active(parent: Node3D, location: Vector3) -> bool:
	for effect: Node3D in parent.get_tree().get_nodes_in_group("destruction_feedback"):
		if effect.get_parent() == parent and effect.global_position.distance_squared_to(location) < 0.01:
			return true
	return false


static func sound(parent: Node, cue: String, location: Vector3) -> void:
	var audio := parent.get_tree().get_first_node_in_group("feedback_audio") as FeedbackAudio
	if audio != null:
		audio.play(cue, location)


static func impact(parent: Node3D, location: Vector3, shield_hit: bool, hull_hit: bool) -> void:
	# Parent effects to the sector so a destroyed ship cannot hide its final impact.
	var world := parent.get_parent() as Node3D
	if world == null or not (shield_hit or hull_hit):
		return
	sound(parent, "hull" if hull_hit else "shield", location)
	var effect := feedback_root(world, location, 0.38)
	if effect == null:
		return
	if parent is SpaceShip:
		effect.follow = weakref(parent)
	var camera := parent.get_viewport().get_camera_3d()
	var direction := (camera.global_position - location).normalized() if camera != null else Vector3.BACK
	if Time.get_ticks_msec() - int(parent.get_meta("visual_hit_time", -1000)) < 500:
		direction = parent.get_meta("visual_hit_direction", direction)
	var radius := shield_radius(parent)
	var quality := effects_quality(parent)
	if shield_hit:
		var pulse := effect_mesh(effect, "shell_low" if quality == 1 else "shell_high", "shield_material", Vector3.ZERO, Vector3.ONE * radius)
		pulse.set_instance_shader_parameter("hit_direction", direction)
		pulse.create_tween().tween_method(func(value: float): pulse.set_instance_shader_parameter("progress", value), 0.0, 1.0, 0.38)
		if quality > 1:
			glow(effect, direction * radius, Vector2.ONE * 2.8, Color("65dfff"), 0.14)
	if hull_hit:
		var contact := hull_contact(parent, direction)
		glow(effect, contact, Vector2.ONE * 3.2, Color("ffaf50"), 0.18)
		sparks(effect, contact, direction, 1 if quality == 1 else 6, 1.0, 0.35)


static func feedback_root(parent: Node3D, location: Vector3, duration: float, limit: int = EFFECT_LIMIT) -> CombatEffect:
	var quality := effects_quality(parent)
	if quality == 0:
		return null
	if quality == 1:
		limit = mini(limit, 32)
	if parent.get_tree().get_node_count_in_group("transient_feedback") >= limit:
		return null
	var effect := CombatEffect.new()
	parent.add_child(effect)
	effect.global_transform = Transform3D(Basis.IDENTITY, location)
	effect.add_to_group("transient_feedback")
	# The root owns every visual and tween; freeing it also cancels all child animations.
	effect.create_tween().tween_callback(effect.queue_free).set_delay(duration)
	return effect


static func glow(parent: Node3D, location: Vector3, size: Vector2, color: Color, duration: float) -> MeshInstance3D:
	var flash := effect_mesh(parent, "glow", "glow_material", location, Vector3(size.x, size.y, 1.0))
	flash.set_instance_shader_parameter("tint", color)
	flash.create_tween().tween_method(func(value: float): flash.set_instance_shader_parameter("opacity", value), 1.0, 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return flash


static func sparks(parent: Node3D, location: Vector3, normal: Vector3, count: int, size: float, duration: float) -> void:
	for index in range(count):
		var direction := (normal * 0.8 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
		var travel := direction * randf_range(2.0, 5.0) * size
		var spark := effect_mesh(parent, "spark", "streak_material", location, Vector3(size, randf_range(0.35, 0.9) * size, size))
		spark.quaternion = Quaternion(Vector3.UP, direction)
		spark.set_instance_shader_parameter("tint", SPARK_HOT)
		var tween := spark.create_tween().set_parallel(true)
		tween.tween_property(spark, "position", location + travel, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "scale", spark.scale * 0.1, duration)
		tween.tween_method(func(tint: Color): spark.set_instance_shader_parameter("tint", tint), SPARK_HOT, SPARK_COOL, duration)


static func shield_radius(ship: Node3D) -> float:
	if ship is Alien:
		return (4.8 if ship.kind == "Heavy" else 3.6) * float(Alien.VISUAL_SCALE[ship.kind])
	return 3.6


static func hull_contact(ship: Node3D, direction: Vector3) -> Vector3:
	# Visual mesh bounds approximate the surface, so sparks are not buried in long noses.
	# This ray never touches the physics world or participates in damage validation.
	var distance := 0.0
	if ship is SpaceShip and is_instance_valid(ship.model):
		var start := ship.global_position + direction * maxf(20.0, destruction_size(ship))
		if ship.hull_visuals.is_empty():
			# Assigning a new model clears this cache; later hits skip the scene search.
			ship.hull_visuals.assign(ship.model.find_children("*", "MeshInstance3D", true, false))
		for visual in ship.hull_visuals:
			if not is_instance_valid(visual):
				continue
			var hit: Variant = visual.get_aabb().intersects_segment(visual.to_local(start), visual.to_local(ship.global_position))
			if hit is Vector3:
				distance = maxf(distance, (visual.to_global(hit) - ship.global_position).dot(direction))
	return direction * (distance + 0.08 if distance > 0.0 else 2.4)


static func shot_target(parent: Node3D, endpoint: Vector3) -> SpaceShip:
	var closest: SpaceShip
	var distance := 36.0
	for child in parent.get_children():
		if child is SpaceShip and child.alive:
			var candidate: float = child.global_position.distance_squared_to(endpoint)
			if candidate < distance:
				distance = candidate
				closest = child
	return closest
