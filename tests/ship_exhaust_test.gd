extends SceneTree
## Ion exhaust placement and its response to motion inferred from rendering.

const STEP: float = 1.0 / 60.0

var failures: int = 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)


func fly(pilot: Pilot, seconds: float, speed: Callable) -> void:
	# Drive the exhaust directly so the result does not depend on frame timing.
	var elapsed := 0.0
	while elapsed < seconds:
		elapsed += STEP
		pilot.global_position += -pilot.global_basis.z * float(speed.call(elapsed)) * STEP
		pilot.exhaust._process(STEP)


func run() -> void:
	for id: String in ShipCatalog.MODELS:
		var nozzles: Array = ShipCatalog.info(id).get("exhausts", [])
		check(not nozzles.is_empty(), id + " declares exhaust nozzles")
		var hull := ShipCatalog.model_scene(id)
		var bounds := (hull.find_children("*", "MeshInstance3D")[0] as MeshInstance3D).mesh.get_aabb()
		hull.free()
		for nozzle: Array in nozzles:
			var point := Vector3(nozzle[0], nozzle[1], nozzle[2])
			check(point.z > 0.0 and bounds.grow(0.01).has_point(point) and float(nozzle[3]) > 0.0, id + " nozzles sit aft, on the hull, with a radius")
	var world := Node3D.new()
	root.add_child(world)
	var pilot := Pilot.new()
	world.add_child(pilot)
	pilot.global_position = Vector3(0, 500, 0)
	pilot.set_process(false)
	var exhaust := pilot.exhaust
	exhaust.set_process(false)
	check(exhaust.get_parent() == pilot.model and exhaust.plumes.size() == 2, "Liberator exhaust banks with its model and has two plumes")
	fly(pilot, 0.5, func(_t: float) -> float: return 0.0)
	var idle := exhaust.throttle
	check(idle < 0.15, "Parked ships keep only a faint nozzle glow")
	var idle_length := exhaust.plumes[0].scale.y
	fly(pilot, 0.6, func(t: float) -> float: return 40.0 * t)
	check(exhaust.throttle > 0.8 and exhaust.boost < 0.05, "Accelerating forward lights the full plume without boost")
	check(exhaust.plumes[0].scale.y > idle_length * 3.0, "The plume stretches while accelerating")
	fly(pilot, 2.0, func(_t: float) -> float: return 41.0)
	check(exhaust.throttle > 0.2 and exhaust.throttle < 0.4, "Holding cruise speed sustains a short plume")
	fly(pilot, 1.0, func(t: float) -> float: return maxf(0.0, 41.0 - 60.0 * t))
	check(exhaust.throttle < 0.2, "Braking lets the plume die back")
	check(exhaust.engine_light.light_energy < 1.0, "An idle drive keeps only a faint engine light")
	pilot.boosting = true
	fly(pilot, 0.5, func(_t: float) -> float: return 0.0)
	check(exhaust.throttle > 0.9 and exhaust.boost > 0.9, "Boosting flares the plume and shifts its color")
	check(exhaust.engine_light != null and exhaust.engine_light.light_energy > 2.5, "Boosting brightens the engine light on the aft hull")
	pilot.boosting = false
	fly(pilot, 2.0, func(_t: float) -> float: return 0.0)
	pilot.global_position += Vector3(5000, 0, 0)
	pilot.exhaust._process(STEP)
	check(exhaust.throttle < 0.2, "Rescues and jumps do not flash the exhaust")
	pilot.set_ship_model("yamato")
	check(is_instance_valid(pilot.exhaust) and pilot.exhaust.get_parent() == pilot.model and pilot.exhaust.nozzles.size() == 4, "Changing hulls rebuilds the exhaust on the new nozzles")
	var server_pilot := Pilot.new()
	server_pilot.render_enabled = false
	world.add_child(server_pilot)
	check(server_pilot.exhaust == null, "Dedicated servers create no exhaust")
	world.free()
	print("Ship exhaust: %d failures" % failures)
	quit(1 if failures > 0 else 0)
