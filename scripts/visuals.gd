class_name SectorVisuals
extends RefCounted
## Procedural placeholder art, kept outside flight and combat simulation.


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


static func station(parent: Node3D, location: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = location
	parent.add_child(root)
	var armor := material(Color("8b9bad"))
	var dark := material(Color("182d43"))
	var glow := material(Color("5af4cf"), true)
	var ring := TorusMesh.new()
	ring.inner_radius = 12.0
	ring.outer_radius = 15.5
	mesh(root, ring, Vector3.ZERO, armor).rotation.x = PI / 2.0
	var inner := TorusMesh.new()
	inner.inner_radius = 11.6
	inner.outer_radius = 12.1
	mesh(root, inner, Vector3(0, 0, 0.9), glow).rotation.x = PI / 2.0
	for side in [-1.0, 1.0]:
		box(root, Vector3(side * 24, 0, 0), Vector3(20, 2, 2), armor)
		box(root, Vector3(side * 28, 0, 0), Vector3(13, 0.7, 30), dark)
		for offset in range(-6, 7):
			box(root, Vector3(side * 28, 0.42, offset * 2.0), Vector3(12.5, 0.05, 0.06), glow)
		box(root, Vector3(side * 10.0, -14.0, 0), Vector3(5, 7, 8), dark)
	box(root, Vector3(0, -20, 0), Vector3(25, 5, 10), armor)
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


static func environment(parent: Node3D) -> void:
	var world := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	settings.sky = Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/space.gdshader")
	settings.sky.sky_material = sky_material
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("91a5d0")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = settings
	parent.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -35, 0)
	sun.light_color = Color("c5deff")
	sun.light_energy = 1.8
	parent.add_child(sun)
	var planet := SphereMesh.new()
	planet.radius = 440.0
	planet.height = 880.0
	planet.radial_segments = 64
	planet.rings = 32
	mesh(parent, planet, Vector3(900, 310, -2200), material(Color("284762")))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301
	var rock_surface := material(Color("4b5063"))
	for index in range(24):
		var body := StaticBody3D.new()
		var side := -1.0 if index % 2 == 0 else 1.0
		body.position = Vector3(side * rng.randf_range(80, 280), rng.randf_range(-90, 90), rng.randf_range(-400, -70))
		var radius := rng.randf_range(4.0, 16.0)
		var rock := SphereMesh.new()
		rock.radius = radius
		rock.height = radius * 1.6
		rock.radial_segments = 7
		rock.rings = 4
		mesh(body, rock, Vector3.ZERO, rock_surface).rotation = Vector3(rng.randf(), rng.randf(), rng.randf())
		var collider := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		collider.shape = shape
		body.add_child(collider)
		parent.add_child(body)


static func laser(parent: Node3D, start: Vector3, finish: Vector3, hostile: bool) -> void:
	var shape := CylinderMesh.new()
	shape.top_radius = 0.10
	shape.bottom_radius = 0.10
	shape.height = start.distance_to(finish)
	shape.radial_segments = 6
	var surface := material(Color("ff675b") if hostile else Color("74f3ff"), true)
	var beam := mesh(parent, shape, (start + finish) * 0.5, surface)
	beam.quaternion = Quaternion(Vector3.UP, (finish - start).normalized())
	var tween := parent.create_tween()
	tween.tween_property(beam, "scale", Vector3(0.01, 1.0, 0.01), 0.13)
	tween.tween_callback(beam.queue_free)


static func explosion(parent: Node3D, location: Vector3) -> void:
	var shape := SphereMesh.new()
	shape.radius = 1.0
	shape.height = 2.0
	var surface := material(Color("ffb96c"), true)
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var burst := mesh(parent, shape, location, surface)
	var tween := parent.create_tween().set_parallel(true)
	tween.tween_property(burst, "scale", Vector3.ONE * 9.0, 0.45)
	tween.tween_property(surface, "albedo_color:a", 0.0, 0.45)
	tween.chain().tween_callback(burst.queue_free)
