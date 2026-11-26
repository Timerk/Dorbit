extends SceneTree
## SnapshotBuffer bracketing, ordering, extrapolation cap and reset, and
## ServerClock stability under ±30 ms arrival jitter.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	run()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func at(x: float) -> Vector3:
	return Vector3(x, 0, 0)


func run() -> void:
	# Bracketing: samples every 3 ticks, rendered between them.
	var buffer := SnapshotBuffer.new()
	check(buffer.sample(10.0).is_empty() and buffer.mode == SnapshotBuffer.Mode.EMPTY, "An empty buffer draws nothing")
	buffer.push(30, at(30), Vector3(0, 3.0, 0))
	buffer.push(33, at(33), Vector3(0, -3.0, 0))
	var middle := buffer.sample(31.5)
	check(middle["position"].is_equal_approx(at(31.5)) and middle["mode"] == SnapshotBuffer.Mode.INTERPOLATED, "Positions interpolate between the bracketing ticks")
	# 3.0 to -3.0 rad is 0.28 rad the short way, across ±PI.
	check(absf(angle_difference(middle["rotation"].y, PI)) < 0.01, "Angles interpolate along the shortest path (%.3f)" % middle["rotation"].y)
	check(buffer.sample(29.0)["position"].is_equal_approx(at(30)), "Render times before the oldest sample hold it")

	# Out-of-order and duplicate ticks.
	buffer = SnapshotBuffer.new()
	for tick in [6, 0, 3, 3, 9]:
		buffer.push(tick, at(tick), Vector3.ZERO)
	check(buffer.samples.size() == 4 and buffer.samples.map(func(entry: Dictionary): return entry["tick"]) == [0, 3, 6, 9], "Samples stay in tick order and duplicates are ignored")
	check(not buffer.push(6, at(99), Vector3.ZERO) and buffer.push(6, at(6.5), Vector3.ZERO, true) and buffer.samples[2]["position"] == at(6.5), "A duplicate tick is ignored unless a newer packet replaces it")
	buffer.sample(7.0)
	check(not buffer.push(5, at(5), Vector3.ZERO), "Ticks the render time already passed are stale")
	check(buffer.push(8, at(8), Vector3.ZERO) and buffer.sample(8.0)["position"].is_equal_approx(at(8)), "A late tick still ahead of the render time fills the gap")
	buffer = SnapshotBuffer.new()
	for tick in range(0, 300, 3):
		buffer.push(tick, at(tick), Vector3.ZERO)
	check(buffer.samples.size() == SnapshotBuffer.CAPACITY, "The buffer keeps at most %d samples" % SnapshotBuffer.CAPACITY)

	# Extrapolation from the newest two samples, capped, then held.
	buffer = SnapshotBuffer.new()
	buffer.push(0, at(0), Vector3(0, 0, 0))
	buffer.push(3, at(3), Vector3(0, 0.3, 0))
	buffer.sample(2.0)
	var ahead := buffer.sample(9.0)
	check(ahead["mode"] == SnapshotBuffer.Mode.EXTRAPOLATED and ahead["position"].is_equal_approx(at(9)) and is_equal_approx(ahead["rotation"].y, 0.9), "A dry buffer extrapolates the last motion")
	check(buffer.underruns == 1, "Running past the newest sample counts one underrun")
	var cap := 3 + SnapshotBuffer.MAX_EXTRAPOLATION_TICKS
	var held := buffer.sample(cap + 30.0)
	check(held["mode"] == SnapshotBuffer.Mode.HELD and held["position"].is_equal_approx(at(cap)), "Extrapolation stops after 250 ms and holds")
	check(buffer.sample(cap + 60.0)["position"].is_equal_approx(at(cap)) and buffer.underruns == 1, "A held entity stays put without counting new underruns")
	buffer.push(40, at(40), Vector3.ZERO)
	buffer.push(43, at(43), Vector3.ZERO)
	check(buffer.sample(41.0)["mode"] == SnapshotBuffer.Mode.INTERPOLATED, "Fresh samples resume interpolation")
	var single := SnapshotBuffer.new()
	single.push(10, at(10), Vector3.ZERO)
	check(single.sample(20.0)["position"].is_equal_approx(at(10)), "One sample cannot extrapolate and holds")

	# Reset at a discontinuity: nothing blends across it.
	buffer.clear()
	check(buffer.is_empty() and buffer.push(44, at(500), Vector3.ZERO), "Clearing accepts a new motion at any tick")
	check(buffer.sample(41.0)["position"].is_equal_approx(at(500)), "After a reset the new state is held, not blended with the old motion")

	check_clock()
	if failures == 0:
		print("Snapshot buffer tests passed: %d checks." % checks)
	quit(1 if failures > 0 else 0)


## Snapshots every 3 server ticks with a 75 ± 30 ms one-way delay and 5% loss.
## The render time must advance smoothly (no snaps, bounded time-scale) and
## stay close to the server time of a typical path minus the delay.
func check_clock() -> void:
	var clock := ServerClock.new()
	var random := RandomNumberGenerator.new()
	random.seed = 7
	var arrivals: Array[Vector2] = [] # (local arrival time, tick)
	var base := 0.075
	for tick in range(0, 60 * 40, 3):
		if random.randf() < 0.05:
			continue
		arrivals.append(Vector2(tick / 60.0 + base + random.randf_range(-0.03, 0.03), tick))
	arrivals.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	var next := 0
	var largest_step := 0.0
	var smallest_step := INF
	var largest_error := 0.0
	var previous := -INF
	var backwards := false
	var step := 1.0 / 60.0
	for frame in range(60 * 40):
		var now := frame * step
		while next < arrivals.size() and arrivals[next].x <= now:
			clock.observe(int(arrivals[next].y), arrivals[next].x)
			next += 1
		clock.advance(step, now)
		if not clock.synced:
			continue
		if frame > 60 * 10:
			var advanced := clock.render_time - previous
			largest_step = maxf(largest_step, advanced)
			smallest_step = minf(smallest_step, advanced)
			backwards = backwards or advanced < 0.0
			# Server time over a typical (median) path is now - base.
			var ideal := now - base - ServerClock.INTERPOLATION_DELAY
			largest_error = maxf(largest_error, absf(clock.render_time - ideal))
		previous = clock.render_time
	check(clock.snaps == 0, "Jitter never snaps the render clock")
	check(not backwards and smallest_step >= step * (1.0 - ServerClock.MAX_SLEW) - 1e-6 and largest_step <= step * (1.0 + ServerClock.MAX_SLEW) + 1e-6,
		"The render time advances every tick within ±5%% (%.4f..%.4f s per %.4f s)" % [smallest_step, largest_step, step])
	check(largest_error < 0.03, "The render time stays within 30 ms of a typical path minus the delay (%.1f ms)" % (largest_error * 1000.0))

	# A lasting latency increase is followed gently; a stall snaps once.
	var later := ServerClock.new()
	later.observe(0, 0.05)
	for frame in range(1, 600):
		var now := frame * step
		if frame % 3 == 0:
			later.observe(frame, now + (0.05 if frame < 300 else 0.15))
		later.advance(step, now)
	check(later.snaps == 0 and later.time_scale >= 1.0 - ServerClock.MAX_SLEW, "A lasting 100 ms latency rise is absorbed by slewing, not snapping")
	later.advance(step, 60.0)
	check(later.snaps == 1, "A long stall snaps the render clock once")
