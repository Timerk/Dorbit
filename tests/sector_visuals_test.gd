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
	check(client_shapes.size() == 77, "All 24 asteroids and 53 simple station collision shapes are present")
	check(render_nodes(server) == 0, "Dedicated server creates no meshes, lights or environment")
	check(client.get_node_or_null("DistantScenery") != null, "Client has distant scenery")
	check(server.get_node_or_null("DistantScenery") == null, "Server skips distant scenery")
	space_dust_checks(client, server)
	await sync_physics()
	await sun_flare_checks(client)
	check(client.get_node_or_null("SunFlare") is SunFlare and server.get_node_or_null("SunFlare") == null, "Only rendering clients create the sun flare")
	var clouds := client.get_node_or_null("DistantScenery/NebulaClouds") as MultiMeshInstance3D
	check(clouds != null and clouds.multimesh.instance_count == SectorBackdrop.CLOUD_COUNT, "Nebula wisps share one instanced draw")
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
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(0, 0, 45), center, 1)).is_empty(), "Lowest hangar has an open approach to the station service point")
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Sector.SPAWN_POSITION, Sector.SPAWN_POSITION + Vector3(0, 0, -10), 1)).is_empty(), "Launch and rescue spawn remain clear of the larger structure")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(center, center + Vector3(0, 0, -30), 1)).is_empty(), "Hangar rear bulkhead blocks weapons and ships")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(14, 0, 30), center + Vector3(14, 0, -20), 1)).is_empty(), "Hangar jamb blocks weapons and ships")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(60, -28, 30), center + Vector3(60, -28, -30), 1)).is_empty(), "Large docking blade has collision")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(0, 162, 40), center + Vector3(0, 162, -40), 1)).is_empty(), "Command crown has collision")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(0, -63, 30), center + Vector3(0, -63, -30), 1)).is_empty(), "Underside reactor has collision")
	client.free()
	server.free()
	await check_campaign_backdrops()
	print("Sector visual checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


func check_campaign_backdrops() -> void:
	var flight := preload("res://scenes/sector.tscn").instantiate() as Sector
	flight.offline = true
	root.add_child(flight)
	flight.set_physics_process(false)
	var authority := preload("res://scenes/sector.tscn").instantiate() as Sector
	authority.dedicated_server = true
	authority.server_port = preload("res://tests/network_test.gd").free_udp_port(24967 + int(OS.get_environment("DORBIT_TEST_PORT_OFFSET")))
	var previous_directory := OS.get_environment("DORBIT_DATA_DIR")
	var directory := ProjectSettings.globalize_path("user://backdrop-server-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	var ledger := FileAccess.open(directory.path_join("pilots.json"),FileAccess.WRITE)
	ledger.store_string(JSON.stringify({"version":1,"pilots":{"backdrop":{"verifier":"backdrop-test-token".sha256_text(),"credits":0}}}))
	ledger.close()
	OS.set_environment("DORBIT_DATA_DIR",directory)
	root.add_child(authority)
	authority.set_physics_process(false)
	var client_obstacles := static_obstacles(flight)
	check(client_obstacles == static_obstacles(authority) and client_obstacles.size() == 173, "All four rendered maps and the gate arena retain identical server obstacles")
	check(render_nodes(authority) == 0, "Four-map server creates no campaign planets, machines or sky")
	check(flight.map_scenery.keys() == [0], "Startup builds only the current map's scenery")
	check(authority.map_scenery.is_empty(), "Dedicated startup has no visual map cache")
	for map: int in SectorMaps.MAPS:
		if map != 0:
			check(flight.get_node_or_null("Map%dBackdrop" % (map+1)) == null and flight.get_node_or_null("Map%dGates" % (map+1)) == null and flight.get_node_or_null("Map%dRocks" % (map+1)) == null, "Unvisited map has no backdrop, gate or asteroid visuals")
			check(flight.map_terrain[map].get_child_count() == 24 and render_nodes(flight.map_terrain[map]) == 0, "Unvisited terrain contains all 24 physical obstacles without meshes")
		flight.map_id = map
		flight.autopilot.collect_obstacles()
		check(flight.autopilot.obstacles.size() == (77 if map == 0 else 24), "Autopilot sees every map's obstacles before its scenery exists")
		var enemy: Alien = authority.map_rosters[map].values()[0]
		if SectorMaps.MAPS[map].get("instance", false):
			check(not enemy.alive and not enemy.visible, "Gate arena aliens stay dormant until a run spawns them")
		else:
			check(authority.alien_home_clear(enemy.home_position, enemy), "Alien relocation uses complete startup collision and gate data")
		flight.player.map_id = map
		for destination: int in SectorMaps.links(map):
			flight.player.position = SectorMaps.gate_position(map, destination)
			check(SectorMaps.protected(flight.player), "Unvisited gate protection is available at startup")
			check(SectorMaps.arrival(map, destination).distance_to(flight.player.position) <= SectorMaps.JUMP_RADIUS, "Unvisited reciprocal spawn stays inside the gate trigger range")
	flight.player.map_id = 0
	flight.player.position = Sector.SPAWN_POSITION
	flight.map_id = 0
	for map: int in SectorMaps.MAPS:
		var before_count := flight.map_scenery.size()
		var was_built := flight.map_scenery.has(map)
		flight.activate_map(map)
		check(flight.map_scenery.has(map) and flight.map_scenery.size() == before_count + (0 if was_built else 1), "Entering a map builds only that map's visuals")
		check(static_obstacles(flight) == client_obstacles, "First visit preserves every collider's dimensions and transform")
		if map != 0:
			var rocks := flight.get_node("Map%dRocks" % (map+1))
			for index in range(24):
				var body := flight.map_terrain[map].get_child(index) as StaticBody3D
				var model := rocks.get_child(index) as Node3D
				check(model.global_position.is_equal_approx(body.global_position) and is_equal_approx(model.scale.x, body.get_child(0).shape.radius), "Lazy asteroid visuals align with their existing collider")
		for destination: int in SectorMaps.links(map):
			var gate := flight.get_node("Map%dGates/GateToM%d" % [map+1,destination+1]) as Node3D
			check(gate.global_position.is_equal_approx(SectorMaps.gate_position(map,destination)), "Detailed gate retains its authoritative travel position")
			check(gate.find_children("*","CollisionObject3D",true,false).is_empty(), "Transit armor and portal add no collision bodies")
			check(gate.global_basis.z.dot((gate.global_position-SectorMaps.origin(map)).normalized()) > 0.99, "Transit gate aperture faces the local sector")
			var parts := gate.find_children("*","MeshInstance3D",true,false)
			var surfaces := 0
			for part: MeshInstance3D in parts:
				surfaces += part.mesh.get_surface_count()
				check((part.transform*part.get_aabb()).size.length() < SectorMaps.PROTECTION_RADIUS, "Gate presentation stays within its protected approach")
			check(surfaces <= 6, "Shared detailed gate uses at most six mesh surfaces including the portal")
			var portal := gate.get_node("Portal") as MeshInstance3D
			check((portal.material_override as ShaderMaterial).get_shader_parameter("turbulence") is Texture2D, "Animated portal has its packaged turbulence texture")
		var backdrop_name := "DistantScenery" if map == 0 else "Map%dBackdrop" % (map+1)
		var backdrop := flight.get_node(backdrop_name) as Node3D
		check(backdrop.is_visible_in_tree() and backdrop.position == SectorMaps.origin(map), "Current map backdrop follows its sector origin")
		check(backdrop.find_children("*", "CollisionObject3D", true, false).is_empty(), "Background landmarks add no collision or targeting bodies")
		var planet := backdrop.get_node("ColonyPlanet") as MeshInstance3D
		check(planet.position.length()-(planet.mesh as SphereMesh).radius > Sector.MAP_RADIUS, "Colony planet is outside the entire flight volume")
		var planet_material := planet.material_override as ShaderMaterial
		var surface_map := planet_material.get_shader_parameter("surface_map") as Texture2D
		check(surface_map != null and surface_map.get_width() >= 1700 and surface_map.get_width() == surface_map.get_height()*2, "Planet has its complete spherical surface texture")
		check(surface_map.resource_path.ends_with("colony-surface-war.png" if map == 0 else "mineral-surface.png"), "Only the home colony uses the revised war-damage surface")
		check(planet_material.get_shader_parameter("war_damage") == (1.0 if map == 0 else 0.0), "Burned settlement light suppression applies only on M1")
		check(backdrop.get_node_or_null("Atmosphere") != null, "Planet has a separate atmosphere beyond the solid limb")
		var sky := (flight.get_node("WorldEnvironment") as WorldEnvironment).environment.sky.sky_material as ShaderMaterial
		var panorama := sky.get_shader_parameter("nebula_panorama") as Texture2D
		check(panorama != null and panorama.get_width() == panorama.get_height()*2, "Sky has its panoramic texture after map activation")
		check(sky.get_shader_parameter("nebula_warm") == SectorBackdrop.THEMES[map]["warm"], "Map transfer updates its nebula palette")
		for key: int in flight.map_scenery:
			for node: Node3D in flight.map_scenery[key]:
				check(node.visible == (key == map), "Map transfer hides all other maps' scenery")
		check_background_bounds(backdrop, SectorMaps.origin(map))
		# Enter and leave each map twice so a prior visit cannot leave a visible backdrop.
		flight.activate_map(0)
		flight.activate_map(map)
		check(backdrop.is_visible_in_tree(), "Revisited map restores its background")
		check(flight.get_node(backdrop_name) == backdrop, "Revisiting reuses the original scenery without duplicates")
		authority.activate_map(map)
		authority.build_map_visuals(map)
		check(authority.map_scenery.is_empty() and render_nodes(authority) == 0, "Dedicated map activation never creates visual scenery")
	authority.session.disconnect_session("Backdrop validation complete")
	if previous_directory.is_empty():
		OS.unset_environment("DORBIT_DATA_DIR")
	else:
		OS.set_environment("DORBIT_DATA_DIR",previous_directory)
	flight.free()
	authority.free()


func static_obstacles(node: Node) -> Array:
	var shapes: Array = []
	if node is StaticBody3D:
		for child: Node in node.get_children():
			if child is CollisionShape3D:
				shapes.append([child.global_transform, child.shape.get_class(), child.shape.radius if child.shape is SphereShape3D else child.shape.size])
	for child: Node in node.get_children():
		shapes.append_array(static_obstacles(child))
	return shapes


func check_background_bounds(node: Node, origin: Vector3) -> void:
	if node is MeshInstance3D:
		var bounds: AABB = node.global_transform * node.get_aabb()
		var nearest := Vector3(clampf(origin.x,bounds.position.x,bounds.end.x),clampf(origin.y,bounds.position.y,bounds.end.y),clampf(origin.z,bounds.position.z,bounds.end.z))
		check(nearest.distance_to(origin) > Sector.MAP_RADIUS, "Solid-looking decorative landmark stays outside safe space")
	# The dummy headless rendering server does not retain MultiMesh GPU transforms.
	if node is MultiMeshInstance3D and DisplayServer.get_name() != "headless":
		for index in node.multimesh.instance_count:
			var transform: Transform3D = node.global_transform * node.multimesh.get_instance_transform(index)
			var radius: float = node.multimesh.mesh.get_aabb().size.length()*transform.basis.get_scale().x*0.5
			check(transform.origin.distance_to(origin)-radius > Sector.MAP_RADIUS, "Instanced belt rock remains outside safe space")
	for child: Node in node.get_children():
		check_background_bounds(child, origin)


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


func space_dust_checks(client: Node3D, server: Node3D) -> void:
	var dust := client.get_node_or_null("SpaceDust") as SpaceDust
	check(dust != null and server.get_node_or_null("SpaceDust") == null, "Only rendering clients create space dust")
	if dust == null:
		return
	check(dust.multimesh.instance_count == SpaceDust.COUNT and dust.multimesh.use_custom_data, "Dust motes share one instanced draw with per-mote seeds")
	var camera := Camera3D.new()
	client.add_child(camera)
	camera.make_current()
	# Drive the tracker directly so the result does not depend on frame timing.
	dust._process(1.0 / 60.0)
	for index in range(30):
		camera.position += Vector3(0, 0, -41.0 / 60.0)
		dust._process(1.0 / 60.0)
	check(absf(dust.velocity.z + 41.0) < 1.0, "Dust streaks follow the camera's cruise velocity")
	camera.position += Vector3(0, 0, -5000)
	dust._process(1.0 / 60.0)
	check(dust.velocity == Vector3.ZERO, "Jumps and rescues reset dust streaks instead of smearing them")
	camera.position += Vector3(0, 0, -5.0)
	for index in range(30):
		camera.position += Vector3(0, 0, -5.0)
		dust._process(1.0 / 60.0)
	check(dust.velocity.length() <= SpaceDust.MAX_STREAK_SPEED + 0.01, "Fast camera motion cannot stretch streaks beyond the cap")
	camera.free()


func sun_flare_checks(client: Node3D) -> void:
	var flare := client.get_node("SunFlare") as SunFlare
	var camera := Camera3D.new()
	client.add_child(camera)
	camera.make_current()
	var sky := (client.get_node("WorldEnvironment") as WorldEnvironment).environment.sky.sky_material as ShaderMaterial
	var sun := (sky.get_shader_parameter("sun_direction") as Vector3).normalized()
	camera.global_position = Vector3(0, 0, 900)
	camera.look_at(camera.global_position + sun)
	check(flare.visibility() > 0.9, "Looking straight at an unobstructed sun shows the flare")
	camera.look_at(camera.global_position - sun)
	check(flare.visibility() == 0.0, "Facing away from the sun hides the flare")
	var rock := client.get_node("Asteroid4") as Node3D
	camera.global_position = rock.global_position - sun * 30.0
	camera.look_at(camera.global_position + sun)
	check(flare.visibility() == 0.0, "An asteroid between the camera and the sun blocks the flare")
	# Ships use collision layer 2, separate from obstacles.
	var ship := StaticBody3D.new()
	ship.collision_layer = 2
	var hull := CollisionShape3D.new()
	hull.shape = SphereShape3D.new()
	(hull.shape as SphereShape3D).radius = 3.0
	ship.add_child(hull)
	client.add_child(ship)
	camera.global_position = Vector3(0, 0, 900)
	ship.global_position = camera.global_position + sun * 20.0
	camera.look_at(camera.global_position + sun)
	await sync_physics()
	check(flare.visibility() == 0.0, "A ship between the camera and the sun blocks the flare")
	ship.free()
	camera.free()
