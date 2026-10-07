class_name SectorVisuals
extends RefCounted
## Presentation kept outside flight and combat simulation.

const EFFECT_LIMIT: int = 64
const DESTRUCTION_LIMIT: int = 80
const EXPLOSION_DURATION: float = 1.2
const GLOW_SHADER := preload("res://shaders/combat_glow.gdshader")
const SHIELD_SHADER := preload("res://shaders/shield_hit.gdshader")


static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = 0.55 if not glow else 0.0
	result.roughness = 0.55
	if glow:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		result.emission_enabled = true
		result.emission = color
	return result


static func mesh(parent: Node3D, shape: Mesh, position: Vector3, surface: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = surface
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
	root.position = location
	parent.add_child(root)
	if render:
		root.add_child((load("res://assets/sector/outpost-01.glb") as PackedScene).instantiate())
	# Separate colliders preserve the open docking ring.
	for side in [-1.0, 1.0]:
		add_box_collider(root, Vector3(side * 14, 0, 0), Vector3(5, 27, 5))
		add_box_collider(root, Vector3(side * 28, 0, 0), Vector3(16, 3, 31))
	add_box_collider(root, Vector3(0, -19, 0), Vector3(27, 8, 11))
	add_box_collider(root, Vector3(0, 14, 0), Vector3(25, 4, 5))
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
		var settings := Environment.new()
		settings.background_mode = Environment.BG_SKY
		settings.sky = Sky.new()
		settings.sky.process_mode = Sky.PROCESS_MODE_QUALITY
		settings.sky.radiance_size = Sky.RADIANCE_SIZE_512
		var sky_material := ShaderMaterial.new()
		sky_material.shader = preload("res://shaders/space.gdshader")
		settings.sky.sky_material = sky_material
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		settings.ambient_light_color = Color("8ca6c4")
		settings.ambient_light_energy = 0.48
		settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		world.environment = settings
		parent.add_child(world)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-30, -35, 0)
		sun.light_color = Color("ffdfbd")
		sun.light_energy = 1.55
		parent.add_child(sun)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(25, 145, 0)
		fill.light_color = Color("6e9edb")
		fill.light_energy = 0.45
		parent.add_child(fill)
		var planet := SphereMesh.new()
		planet.radius = 600.0
		planet.height = 1200.0
		planet.radial_segments = 64
		planet.rings = 32
		var planet_surface := ShaderMaterial.new()
		planet_surface.shader = preload("res://shaders/planet.gdshader")
		mesh(parent, planet, Vector3(1350, 480, -2500), planet_surface)
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


static func asteroid_surface() -> StandardMaterial3D:
	var surface := material(Color.WHITE)
	surface.metallic = 0.05
	surface.roughness = 0.96
	surface.albedo_texture = load("res://assets/sector/rock-albedo.png")
	surface.normal_enabled = true
	surface.normal_texture = load("res://assets/sector/rock-normal.png")
	surface.normal_scale = 0.7
	surface.uv1_triplanar = true
	surface.uv1_scale = Vector3.ONE * 2.5
	return surface


static func distant_scenery(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "DistantScenery"
	parent.add_child(root)
	# Three derelict silhouettes frame the outer hunting grounds without fake service markers.
	for location in [Vector3(-800, -190, -840), Vector3(920, 110, -900), Vector3(-580, 360, 750)]:
		var wreck := (load("res://assets/sector/derelict.glb") as PackedScene).instantiate() as Node3D
		wreck.position = location * 1.7
		wreck.rotation_degrees = Vector3(12, 32, -18)
		root.add_child(wreck)
	# A distant belt adds scale and parallax for three draw calls, outside playable space.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4671
	var surface := asteroid_surface()
	for variant in range(3):
		var source := (load("res://assets/sector/asteroid-%d.glb" % variant) as PackedScene).instantiate()
		var shape := (source.find_children("*", "MeshInstance3D")[0] as MeshInstance3D).mesh
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = shape
		instances.instance_count = 20
		for index in range(instances.instance_count):
			var location := Vector3(rng.randf_range(-1600, 1600), rng.randf_range(-410, -200), rng.randf_range(-1800, -950)) * 1.7
			var radius := rng.randf_range(12, 38)
			var basis := Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf())).scaled(Vector3.ONE * radius)
			instances.set_instance_transform(index, Transform3D(basis, location))
		var belt := MultiMeshInstance3D.new()
		belt.multimesh = instances
		belt.material_override = surface
		root.add_child(belt)
		source.free()


static func laser(parent: Node3D, start: Vector3, finish: Vector3, hostile: bool) -> void:
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
	var color := Color("ff6245") if hostile else Color("46cfff")
	var length := start.distance_to(endpoint)
	var shape := CylinderMesh.new()
	shape.top_radius = 0.055
	shape.bottom_radius = 0.055
	shape.height = length
	shape.radial_segments = 8
	var surface := material(color.lerp(Color.WHITE, 0.85), true)
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var beam := mesh(effect, shape, (endpoint - start) * 0.5, surface)
	beam.quaternion = Quaternion(Vector3.UP, direction)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aura := glow(beam, Vector3.ZERO, Vector2(0.95, length), color, 0.18)
	(aura.material_override as ShaderMaterial).set_shader_parameter("beam", true)
	var tween := effect.create_tween().set_parallel(true)
	tween.tween_property(beam, "scale", Vector3(0.2, 1.0, 0.2), 0.18)
	tween.tween_property(surface, "albedo_color:a", 0.0, 0.18)
	glow(effect, Vector3.ZERO, Vector2.ONE * 2.4, color, 0.09)
	glow(effect, endpoint - start, Vector2.ONE * 2.0, color, 0.13)


static func explosion(parent: Node3D, location: Vector3, diameter: float = 9.7) -> void:
	sound(parent, "destruction", location)
	var effect := feedback_root(parent, location, EXPLOSION_DURATION, DESTRUCTION_LIMIT)
	if effect == null:
		return
	effect.add_to_group("destruction_feedback")
	var size := maxf(diameter, 1.0)
	effect.set_meta("diameter", size)
	var flash := glow(effect, Vector3.ZERO, Vector2.ONE * size * 2.6, Color("ffb453"), 0.85)
	effect.create_tween().tween_property(flash, "scale", Vector3.ONE * 2.4, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	glow(effect, Vector3.ZERO, Vector2(size * 4.8, size * 0.24), Color("ffd598"), 0.65)
	sparks(effect, Vector3.ZERO, Vector3.ZERO, 12, size * 0.55, 1.15)


static func destruction_size(ship: SpaceShip) -> float:
	# Player exports use the catalog diameter. Procedural alien bounds
	# include their type scale and the Heavy's lower armor, without loading server meshes.
	if ship is Pilot:
		return float(ShipCatalog.info(ship.ship_model).get("visual_diameter", 7.0))
	var bounds := Vector3(6.6253, 1.895, 6.83)
	if ship is Alien:
		if ship.kind == "Heavy":
			bounds.y = 2.075
		bounds *= ship.tuning()["scale"]
	return bounds.length()


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
	if shield_hit:
		var shell := SphereMesh.new()
		shell.radius = radius
		shell.height = radius * 2.0
		shell.radial_segments = 32
		shell.rings = 16
		var surface := ShaderMaterial.new()
		surface.shader = SHIELD_SHADER
		surface.set_shader_parameter("hit_direction", direction)
		var pulse := mesh(effect, shell, Vector3.ZERO, surface)
		pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effect.create_tween().tween_method(func(value: float): surface.set_shader_parameter("progress", value), 0.0, 1.0, 0.38)
		glow(effect, direction * radius, Vector2.ONE * 2.8, Color("65dfff"), 0.14)
	if hull_hit:
		var contact := hull_contact(parent, direction)
		glow(effect, contact, Vector2.ONE * 3.2, Color("ffaf50"), 0.18)
		sparks(effect, contact, direction, 6, 1.0, 0.35)


static func feedback_root(parent: Node3D, location: Vector3, duration: float, limit: int = EFFECT_LIMIT) -> CombatEffect:
	if parent.get_tree().get_nodes_in_group("transient_feedback").size() >= limit:
		return null
	var effect := CombatEffect.new()
	parent.add_child(effect)
	effect.global_transform = Transform3D(Basis.IDENTITY, location)
	effect.add_to_group("transient_feedback")
	# The root owns every visual and tween; freeing it also cancels all child animations.
	effect.create_tween().tween_callback(effect.queue_free).set_delay(duration)
	return effect


static func glow(parent: Node3D, location: Vector3, size: Vector2, color: Color, duration: float) -> MeshInstance3D:
	var shape := QuadMesh.new()
	shape.size = size
	var surface := ShaderMaterial.new()
	surface.shader = GLOW_SHADER
	surface.set_shader_parameter("tint", color)
	var flash := mesh(parent, shape, location, surface)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.create_tween().tween_method(func(value: float): surface.set_shader_parameter("opacity", value), 1.0, 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return flash


static func sparks(parent: Node3D, location: Vector3, normal: Vector3, count: int, size: float, duration: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for index in range(count):
		var direction := (normal * 0.8 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		var travel := direction * rng.randf_range(2.0, 5.0) * size
		var shape := CylinderMesh.new()
		shape.top_radius = 0.015 * size
		shape.bottom_radius = 0.045 * size
		shape.height = rng.randf_range(0.35, 0.9) * size
		shape.radial_segments = 4
		var surface := material(Color("ffe2ac"), true)
		surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		surface.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var spark := mesh(parent, shape, location, surface)
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.quaternion = Quaternion(Vector3.UP, direction)
		var tween := parent.create_tween().set_parallel(true)
		tween.tween_property(spark, "position", location + travel, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "scale", Vector3.ONE * 0.1, duration)
		tween.tween_property(surface, "albedo_color", Color(1.0, 0.25, 0.03, 0.0), duration)


static func shield_radius(ship: Node3D) -> float:
	return 4.8 if ship is Alien and ship.kind == "Heavy" else 3.6


static func hull_contact(ship: Node3D, direction: Vector3) -> Vector3:
	# Visual mesh bounds approximate the surface, so sparks are not buried in long noses.
	# This ray never touches the physics world or participates in damage validation.
	var distance := 0.0
	if ship is SpaceShip and is_instance_valid(ship.model):
		var start := ship.global_position + direction * 20.0
		for child in ship.model.find_children("*", "MeshInstance3D", true, false):
			var visual := child as MeshInstance3D
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
