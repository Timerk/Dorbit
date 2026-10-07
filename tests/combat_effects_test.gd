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
	await create_timer(0.8).timeout
	check(get_nodes_in_group("transient_feedback").is_empty(), "Saturated effects and destruction expire without leaked nodes")
	ship.render_enabled = false
	ship.present_impact(true, true)
	check(get_nodes_in_group("transient_feedback").is_empty(), "Non-rendering ships do not allocate hit presentation")
	world.free()
	print("Combat effect checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
