extends "res://tests/encounter_test.gd"
## Presentation lifecycle, contact direction, caps and unchanged combat state.


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	# A transformed sector must still display world-space shot endpoints correctly.
	world.position = Vector3(20, 10, -5)
	world.rotation.y = 0.4
	var ship := SpaceShip.new()
	world.add_child(ship)
	ship.global_position = Vector3(20, 10, -50)
	var health := Vector2(ship.shield, ship.hull)
	var nose_hit := SectorVisuals.hull_contact(ship, -ship.global_basis.z)
	check(nose_hit.length() > 4.0, "Hull sparks are placed outside the long visual nose instead of inside the physics sphere")
	var start := ship.global_position + Vector3(0, 0, 30)
	for kind: String in Ammunition.TYPES:
		SectorVisuals.laser(world, start, ship.global_position, false, kind)
		var effect: Node = get_nodes_in_group("transient_feedback")[-1]
		var mesh := effect.get_child(0) as MeshInstance3D
		var surface := mesh.material_override as StandardMaterial3D
		check(surface.albedo_color.is_equal_approx(Ammunition.TYPES[kind]["color"].lerp(Color.WHITE, 0.35)), kind + " beam uses its cartridge color")
		effect.free()
	SectorVisuals.laser(world, start, ship.global_position, true, "x4")
	var hostile_effect: Node = get_nodes_in_group("transient_feedback")[-1]
	var hostile_surface := (hostile_effect.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	check(hostile_surface.albedo_color.is_equal_approx(Color("ff6245").lerp(Color.WHITE, 0.35)), "Alien lasers retain hostile red")
	hostile_effect.free()
	SectorVisuals.laser(world, start, ship.global_position, false)
	check(ship.get_meta("visual_hit_direction") == Vector3.BACK, "Confirmed shot records the incoming surface direction")
	var beam := get_nodes_in_group("transient_feedback")[0] as CombatEffect
	check(beam.global_position.is_equal_approx(start) and beam.global_basis.is_equal_approx(Basis.IDENTITY), "Beam uses world-space endpoints under a transformed parent")
	SectorVisuals.impact(ship, ship.global_position, true, true)
	var hit := get_nodes_in_group("transient_feedback")[1] as CombatEffect
	ship.global_position += Vector3(5, 0, 0)
	await process_frame
	await process_frame
	check(hit.global_position.is_equal_approx(ship.global_position), "Shield ripple follows a moving ship")
	ship.alive = false
	ship.hide()
	var death_location := hit.global_position
	ship.global_position += Vector3(10, 0, 0)
	await process_frame
	await process_frame
	check(hit.global_position.is_equal_approx(death_location) and hit.is_visible_in_tree(), "Final impact remains visible at death instead of following a hidden rescue")
	check(Vector2(ship.shield, ship.hull) == health and ship.shot_cooldown == 0.0, "Presentation never changes health or weapon cooldown")
	await create_timer(0.5).timeout
	check(get_nodes_in_group("transient_feedback").is_empty(), "All hit and beam children are freed with their root")
	SectorVisuals.laser(world, start, start, true)
	SectorVisuals.impact(ship, ship.global_position, false, false)
	check(get_nodes_in_group("transient_feedback").is_empty(), "Empty hit and zero-length shot create no effects")
	for index in range(100):
		SectorVisuals.laser(world, start, start + Vector3.FORWARD * 50, index % 2 == 0)
		SectorVisuals.impact(ship, ship.global_position, true, true)
	check(get_nodes_in_group("transient_feedback").size() == SectorVisuals.EFFECT_LIMIT, "Mixed shield, hull and beam requests cannot exceed the ordinary effect cap")
	for index in range(30):
		SectorVisuals.explosion(world, ship.global_position)
	check(get_nodes_in_group("transient_feedback").size() == SectorVisuals.DESTRUCTION_LIMIT, "Destruction has a bounded reserve when ordinary effects are saturated")
	await create_timer(SectorVisuals.EXPLOSION_DURATION + 0.1).timeout
	check(get_nodes_in_group("transient_feedback").is_empty(), "Saturated effects and destruction expire without leaked nodes")
	ship.render_enabled = false
	ship.present_impact(true, true)
	check(get_nodes_in_group("transient_feedback").is_empty(), "Non-rendering ships do not allocate hit presentation")
	world.free()
	await destruction_checks()
	print("Combat effect checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


func destruction_checks() -> void:
	var pilot := Pilot.new()
	pilot.render_enabled = false
	pilot.ship_model = "phoenix"
	check(is_equal_approx(SectorVisuals.destruction_size(pilot), 3.5), "Phoenix destruction uses its smaller catalog diameter without rendering")
	pilot.ship_model = "liberator"
	check(is_equal_approx(SectorVisuals.destruction_size(pilot), 7.0), "Other player hulls retain the default exported diameter")
	pilot.free()
	var sizes: Array[float] = []
	for kind in ["Scout", "Sentinel", "Heavy"]:
		var alien := Alien.new()
		alien.kind = kind
		root.add_child(alien)
		var bounds := AABB()
		var first := true
		for child in alien.model.find_children("*", "MeshInstance3D", true, false):
			var visual := child as MeshInstance3D
			for corner in range(8):
				var point := alien.to_local(visual.to_global(visual.get_aabb().get_endpoint(corner)))
				bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
				first = false
		var diameter := SectorVisuals.destruction_size(alien)
		sizes.append(diameter)
		check(absf(diameter - bounds.size.length()) < 0.001, kind + " explosion size matches its actual scaled visual bounds")
		alien.free()
	check(sizes[0] < sizes[1] and sizes[1] < sizes[2], "Scout, Sentinel and Heavy destruction sizes increase with the modeled ship")
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	sector.player.position = Vector3(200, 100, 50)
	sector.alien.position = Vector3(200, 100, 0)
	sector.alien.home_position = sector.alien.position
	sector.alien.take_damage(sector.alien.max_hull + sector.alien.max_shield + 1, sector.player)
	var id := sector.loot.next_id
	check(sector.loot.drops.has(id) and not sector.loot.is_presented(id), "Actual death creates loot state but hides the box and caption during the explosion")
	var update: Dictionary = sector.loot.drops[id].duplicate(true)
	update["resources"] = {"prometium": 1}
	sector.loot.apply_drop(id, update)
	check(not sector.loot.is_presented(id), "Updating a drop during destruction does not expose its box early")
	sector.loot.apply_drop(999, {"position": sector.alien.position + Vector3(30, 0, 0), "resources": {"prometium": 1}, "ttl": 180.0})
	check(sector.loot.is_presented(999), "An explosion does not suppress unrelated nearby loot")
	await create_timer(SectorVisuals.EXPLOSION_DURATION + 0.1).timeout
	check(sector.loot.is_presented(id) and not SectorVisuals.explosion_active(sector, sector.alien.position), "Loot becomes visible only after the last explosion mesh is gone")
	sector.loot.apply_drop(id, {})
	await process_frame
	check(not sector.loot.meshes.has(id), "Removing a drop cannot resurrect its visual")
	sector.queue_free()
	await process_frame
