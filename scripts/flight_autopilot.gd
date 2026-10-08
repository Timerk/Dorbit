class_name FlightAutopilot
extends RefCounted
## Local flight assistance produces ordinary movement commands; the server still simulates flight.

const CLEARANCE := 5.2 # 2.2 m ship collider plus room for steering and network correction.
const RING_STEPS := 16
# Time is checked between work units; a single visibility test may overrun it.
const PLANNING_BUDGET_USEC := 1500
const PLANNING_WORK_LIMIT := 64


class PlanningJob extends RefCounted:
	var points: Array[Vector3] = []
	var included: Dictionary[int, bool] = {}
	var visibility: Dictionary[Vector2i, bool] = {}
	var costs: Dictionary[int, float] = {}
	var previous: Dictionary[int, int] = {}
	var open: Array[int] = []
	var closed: Dictionary[int, bool] = {}
	var current := -1
	var neighbor := 1
	var obstacle_index := 0
	var selecting := true
	var direct_only := true
	var expanded := false
	var best_length := INF
	var result: Array[Vector3] = []
	var done := false
	var visibility_checks := 0
	var cache_hits := 0

	func restart_search() -> void:
		costs = {0: 0.0}
		previous.clear()
		open = [0]
		closed.clear()
		current = -1
		selecting = false
		direct_only = false

	func step(planner: FlightAutopilot) -> void:
		if selecting:
			if obstacle_index == planner.obstacles.size():
				if expanded:
					restart_search()
				else:
					done = true
				return
			var index := obstacle_index
			obstacle_index += 1
			if included.has(index):
				return
			var obstacle := planner.obstacles[index]
			# Start with direct blockers. Once a route exists, a candidate outside
			# its path-length ellipse cannot improve it (triangle inequality).
			if direct_only:
				if not planner.obstacle_blocks(points[0], points[1], obstacle):
					return
			elif best_length < INF:
				var center: Vector3 = obstacle.get("center", Vector3.ZERO)
				var radius: float = obstacle.get("radius", 0.0)
				if obstacle.has("box"):
					var box: AABB = obstacle["box"].grow(0.5)
					center = box.get_center()
					radius = box.size.length() * 0.5
				else:
					radius = (radius + 0.5) / cos(PI / RING_STEPS)
				if points[0].distance_to(center) + points[1].distance_to(center) - 2.0 * radius > best_length:
					return
			var candidates := planner.obstacle_points(obstacle, points[0], points[1])
			if best_length < INF and not candidates.any(func(point: Vector3): return points[0].distance_to(point) + points[1].distance_to(point) <= best_length + 0.001):
				return
			included[index] = true
			points.append_array(candidates)
			expanded = true
			return
		if current == -1:
			if open.is_empty():
				# A local graph may not connect around a cluster. Fall back to the
				# full graph, still in slices, before declaring the route blocked.
				if included.size() < planner.obstacles.size():
					selecting = true
					obstacle_index = 0
					expanded = true
					best_length = INF
				else:
					done = true
				return
			current = open[0]
			for index in open:
				if costs[index] + points[index].distance_to(points[1]) < costs[current] + points[current].distance_to(points[1]):
					current = index
			open.erase(current)
			if current == 1:
				result.clear()
				best_length = costs[1]
				while current != 0:
					result.push_front(points[current])
					current = previous[current]
				selecting = true
				obstacle_index = 0
				expanded = false
				return
			closed[current] = true
			neighbor = 1
			return
		if neighbor == points.size():
			current = -1
			return
		var next := neighbor
		neighbor += 1
		if next == current or closed.has(next):
			return
		var cost := costs[current] + points[current].distance_to(points[next])
		if cost >= costs.get(next, INF) or cost + points[next].distance_to(points[1]) > best_length + 0.001:
			return
		if not edge_clear(planner, current, next):
			return
		costs[next] = cost
		previous[next] = current
		if not next in open:
			open.append(next)

	func edge_clear(planner: FlightAutopilot, a: int, b: int) -> bool:
		var key := Vector2i(mini(a, b), maxi(a, b))
		if visibility.has(key):
			cache_hits += 1
			return visibility[key]
		visibility_checks += 1
		var clear := planner.segment_clear(points[a], points[b])
		visibility[key] = clear
		return clear


var sector: Sector
var enabled := false
var status := "OFF"
var route: Array[Vector3] = []
var obstacles: Array[Dictionary] = []
var goal := Vector3.INF
var destination_key := ""
var waypoint_key := ""
var planning: PlanningJob


func cancel(reason: String = "OFF") -> void:
	enabled = false
	status = reason
	route.clear()
	goal = Vector3.INF
	destination_key = ""
	waypoint_key = ""
	planning = null


func toggle() -> void:
	if enabled:
		cancel()
		return
	if sector.paused or not sector.player.alive or (sector.client_only and not sector.session.active):
		return
	sector.hud.navigation.sync_waypoint()
	waypoint_key = sector.hud.navigation.waypoint_key
	collect_obstacles()
	enabled = true
	status = "FLYING"
	sector.player.release_mouse()


func collect_obstacles() -> void:
	planning = null
	obstacles.clear()
	for collider in sector.find_children("*", "CollisionShape3D", true, false):
		if collider.disabled or not collider.get_parent() is StaticBody3D:
			continue
		if collider.shape is SphereShape3D:
			var radius: float = collider.shape.radius + CLEARANCE
			obstacles.append({"center": collider.global_position, "radius": radius,
				"bounds": AABB(collider.global_position - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)})
		elif collider.shape is BoxShape3D:
			var extent: Vector3 = collider.shape.size * 0.5 + Vector3.ONE * CLEARANCE
			var box := AABB(collider.global_position - extent, extent * 2)
			obstacles.append({"box": box, "bounds": box})


func segment_clear(start: Vector3, finish: Vector3) -> bool:
	# Native AABB broad phase skips exact visibility tests for distant obstacles.
	# Grow to include touching/zero-length segments; exact clearance stays below.
	var bounds := AABB(start.min(finish), (finish - start).abs()).grow(0.001)
	for obstacle in obstacles:
		if obstacle.has("bounds") and not (obstacle["bounds"] as AABB).intersects(bounds):
			continue
		if obstacle_blocks(start, finish, obstacle):
			return false
	return true


func obstacle_blocks(start: Vector3, finish: Vector3, obstacle: Dictionary) -> bool:
	var offset := finish - start
	if obstacle.has("radius"):
		var center: Vector3 = obstacle["center"]
		var fraction := clampf((center - start).dot(offset) / maxf(offset.length_squared(), 0.00001), 0, 1)
		var radius: float = obstacle["radius"]
		return (start + offset * fraction).distance_squared_to(center) < radius * radius
	else:
		var box: AABB = obstacle["box"]
		var near := 0.0
		var far := 1.0
		for axis in range(3):
			if absf(offset[axis]) < 0.00001:
				if start[axis] < box.position[axis] or start[axis] > box.end[axis]:
					return false
			else:
				var a: float = (box.position[axis] - start[axis]) / offset[axis]
				var b: float = (box.end[axis] - start[axis]) / offset[axis]
				near = maxf(near, minf(a, b))
				far = minf(far, maxf(a, b))
				if near > far:
					return false
		return near <= far


func plan(start: Vector3, finish: Vector3) -> Array[Vector3]:
	# Synchronous helper for fixtures/tools. Flight uses begin_plan/advance_plan.
	var job := begin_plan(start, finish)
	while not job.done:
		advance_plan(job)
	return job.result


func begin_plan(start: Vector3, finish: Vector3) -> PlanningJob:
	var job := PlanningJob.new()
	job.points = [start, finish]
	if not segment_clear(start, start) or not segment_clear(finish, finish):
		job.done = true
	elif segment_clear(start, finish):
		job.result = [finish]
		job.done = true
	return job


func advance_plan(job: PlanningJob, budget_usec: int = PLANNING_BUDGET_USEC, work_limit: int = PLANNING_WORK_LIMIT) -> void:
	var deadline := Time.get_ticks_usec() + budget_usec
	for work in range(work_limit):
		if job.done or Time.get_ticks_usec() >= deadline:
			break
		job.step(self)


func obstacle_points(obstacle: Dictionary, start: Vector3, finish: Vector3) -> Array[Vector3]:
	# A* finds the shortest visible polyline over sampled sphere rings and box corners.
	# Clear routes remain exact straight lines; curved obstacle routes are approximations.
	var points: Array[Vector3] = []
	if obstacle.has("radius"):
		var center: Vector3 = obstacle["center"]
		var axis := (start - center).normalized()
		if axis.length_squared() < 0.01:
			return points
		var normal := axis.cross(finish - center).normalized()
		if normal.length_squared() < 0.01:
			normal = axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		var side := normal.cross(axis).normalized()
		var radius := (float(obstacle["radius"]) + 0.5) / cos(PI / RING_STEPS)
		for step in range(RING_STEPS):
			var angle := step * TAU / RING_STEPS
			points.append(center + (axis * cos(angle) + side * sin(angle)) * radius)
	else:
		var box: AABB = obstacle["box"].grow(0.5)
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				for z in [box.position.z, box.end.z]:
					points.append(Vector3(x, y, z))
	return points


func command(delta: float) -> Vector3:
	var pilot := sector.player
	if sector.paused or not pilot.alive or (sector.client_only and not sector.session.active):
		cancel()
		return Vector3.ZERO
	sector.hud.navigation.sync_waypoint()
	# Losing a contact must not silently send the pilot back to the fallback outpost.
	if waypoint_key != sector.hud.navigation.waypoint_key:
		cancel("TARGET LOST")
		return Vector3.ZERO
	var selected := sector.hud.navigation.destination()
	var location: Vector3 = selected["position"]
	var offset := location - pilot.position
	var arrival_radius := 50.0 if selected["key"] == "station" else 20.0
	if selected["key"] == "safe":
		arrival_radius = 0.0
	if offset.length() <= arrival_radius + 1.0:
		if pilot.velocity.length() < 1.0:
			cancel("ARRIVED")
		return Vector3.ZERO
	var endpoint := location - offset.normalized() * arrival_radius
	if selected["key"] == "station":
		# The taller station can occupy the radial stopping point above/below
		# the service origin. Keep a chosen clear approach stable during detours.
		if destination_key == "station" and goal != Vector3.INF:
			endpoint = goal
		elif not segment_clear(endpoint, endpoint):
			var nearest := INF
			for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
				var candidate: Vector3 = location + direction * arrival_radius
				var distance_to_pilot := candidate.distance_squared_to(pilot.position)
				if distance_to_pilot < nearest and segment_clear(candidate, candidate):
					endpoint = candidate
					nearest = distance_to_pilot
	if goal == Vector3.INF or goal.distance_to(endpoint) > 8.0 or destination_key != selected["key"]:
		goal = endpoint
		destination_key = selected["key"]
		route.clear()
		planning = begin_plan(pilot.position, goal)
	if planning != null:
		advance_plan(planning)
		if not planning.done:
			status = "PLANNING"
			return Vector3.ZERO
		route = planning.result
		planning = null
		if route.is_empty():
			cancel("ROUTE BLOCKED")
			sector.notify("Autopilot: no clear route. Take manual control.")
			return Vector3.ZERO
		# Momentum/network correction may move the ship while it brakes during
		# planning. Validate the actual first leg before issuing any thrust.
		if not segment_clear(pilot.position, route[0]):
			route.clear()
			planning = begin_plan(pilot.position, goal)
			status = "PLANNING"
			return Vector3.ZERO
	if route.is_empty():
		planning = begin_plan(pilot.position, goal)
		status = "PLANNING"
		return Vector3.ZERO
	if segment_clear(route[-2] if route.size() > 1 else pilot.position, endpoint):
		# Follow small contact movements too, so the last waypoint cannot become a stale stopping point.
		goal = endpoint
		route[-1] = goal
	if route.size() > 1 and pilot.position.distance_to(route[0]) < 1.0 and pilot.velocity.length() < 1.5:
		route.pop_front()
	# Shortcut only after braking: existing sideways momentum can cut an otherwise clear corner.
	if route.size() > 1 and pilot.velocity.length() < 1.5 and segment_clear(pilot.position, goal):
		route = [goal]
	var direction := (route[0] - pilot.position).normalized()
	var distance := pilot.position.distance_to(route[0])
	var speed := minf(pilot.cruise_speed, minf(sqrt(2.0 * pilot.braking * maxf(distance - 0.5, 0.0)) * 0.65, distance * 2.0))
	var lateral := pilot.velocity - direction * pilot.velocity.dot(direction)
	var desired := (direction * speed - lateral * 2.0).limit_length(pilot.cruise_speed)
	# Face the route while applying world-space thrust, including destinations directly above/below.
	pilot.pending_look = Vector2.ZERO
	var yaw := atan2(-direction.x, -direction.z)
	var pitch := clampf(asin(clampf(direction.y, -1, 1)), -1.48, 1.48)
	pilot.rotation.y += clampf(angle_difference(pilot.rotation.y, yaw), -delta * 1.8, delta * 1.8)
	pilot.rotation.x = move_toward(pilot.rotation.x, pitch, delta * 1.8)
	status = "DETOUR" if route.size() > 1 else "FLYING"
	return pilot.global_basis.inverse() * desired / pilot.cruise_speed
