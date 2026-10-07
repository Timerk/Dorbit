extends "res://tests/encounter_test.gd"
## Visual upgrades must not change authoritative obstacles or add server rendering.


func run() -> void:
	var client := Node3D.new()
	var server := Node3D.new()
	root.add_child(client)
	root.add_child(server)
	SectorVisuals.environment(client, true)
	SectorVisuals.environment(server, false)
	SectorVisuals.station(client, Sector.STATION_POSITION, true)
	SectorVisuals.station(server, Sector.STATION_POSITION, false)
	var graphics := GameSettings.new()
	graphics.bloom = true
	graphics.ssao = true
	graphics.shadow_quality = 3
	graphics.effects_quality = 0
	SectorVisuals.apply_graphics(server, graphics)
	var client_shapes := collision_manifest(client)
	var server_shapes := collision_manifest(server)
	check(client_shapes == server_shapes, "Rendered and dedicated sectors have identical obstacle geometry")
	check(client_shapes.size() == 30, "Original 24 asteroids and six station colliders remain")
	check(render_nodes(server) == 0, "Dedicated server creates no meshes, lights or environment")
	check(client.get_node_or_null("DistantScenery") != null, "Client has distant scenery")
	check(server.get_node_or_null("DistantScenery") == null, "Server skips distant scenery")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301
	for index in range(24):
		var side := -1.0 if index % 2 == 0 else 1.0
		var expected := Vector3(side * rng.randf_range(80, 280), rng.randf_range(-90, 90), rng.randf_range(-400, -70))
		var radius := rng.randf_range(4.0, 16.0)
		var _angles := Vector3(rng.randf(), rng.randf(), rng.randf())
		var rock := server.get_node("Asteroid%d" % index) as StaticBody3D
		check(rock.position.is_equal_approx(expected), "Asteroid %d preserves its original position" % index)
		check(is_equal_approx((rock.get_child(0).shape as SphereShape3D).radius, radius), "Asteroid %d preserves its original radius" % index)
	await sync_physics()
	var space := server.get_world_3d().direct_space_state
	var center := Sector.STATION_POSITION
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(0, 0, 20), center - Vector3(0, 0, 20), 1)).is_empty(), "Station docking aperture remains physically open")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(14, 0, 20), center + Vector3(14, 0, -20), 1)).is_empty(), "Station structure still blocks weapons and ships")
	client.free()
	server.free()
	print("Sector visual checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


func collision_manifest(node: Node) -> Array:
	var result: Array = []
	if node is CollisionShape3D:
		var shape := node.shape as Shape3D
		result.append([node.global_transform, shape.get_class(), shape.radius if shape is SphereShape3D else shape.size])
	for child in node.get_children():
		result.append_array(collision_manifest(child))
	return result


func render_nodes(node: Node) -> int:
	var count := 1 if node is VisualInstance3D or node is WorldEnvironment else 0
	for child in node.get_children():
		count += render_nodes(child)
	return count
