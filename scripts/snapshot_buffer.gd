class_name SnapshotBuffer
extends RefCounted
## Client-side interpolation buffer for one remote entity (a pilot or an alien).
##
## Holds the entity's recent authoritative transforms keyed by the server tick
## they were simulated on, oldest first. sample() returns the transform at a
## fractional render tick: it interpolates along a smooth curve between the two
## samples that bracket it, extrapolates from the newest two for at most
## MAX_EXTRAPOLATION_TICKS when the buffer runs dry, and then holds. Callers clear() it at every
## discontinuity (spawn, new life, map visit, dock or launch, alien reset), so
## samples never blend across a teleport.

enum Mode { EMPTY, INTERPOLATED, EXTRAPOLATED, HELD }

## Samples kept: 1.6 s of 20 Hz snapshots, far more than the render delay needs.
const CAPACITY := 32
## Extrapolation cap: 250 ms of server ticks past the newest sample. After that
## the entity holds still until fresh state arrives. A playtesting setting.
const MAX_EXTRAPOLATION_TICKS := 15
## Samples further apart than this (1 s) are not treated as one motion.
const MAX_VELOCITY_GAP_TICKS := 60

## Samples, oldest first: {tick: int, position: Vector3, rotation: Vector3}.
var samples: Array[Dictionary] = []
## Mode of the latest sample() call.
var mode: int = Mode.EMPTY
## Times sample() ran past the newest sample after interpolating (underruns).
var underruns: int = 0
## Ticks already rendered past; samples at or before it are stale.
var rendered_tick: float = -INF


func clear() -> void:
	samples.clear()
	mode = Mode.EMPTY
	rendered_tick = -INF


func is_empty() -> bool:
	return samples.is_empty()


func newest_tick() -> int:
	return samples[-1]["tick"] if not samples.is_empty() else -1


func newest_position() -> Vector3:
	return samples[-1]["position"] if not samples.is_empty() else Vector3.ZERO


## Adds a sample, keeping tick order so out-of-order arrivals still fill gaps.
## Returns false for ticks already rendered past and for duplicates of a held
## tick. `replace` marks state from a newer packet: it overwrites a sample with
## the same tick (only scripted tests resend a tick with different state).
func push(tick: int, position: Vector3, rotation: Vector3, replace: bool = false) -> bool:
	if tick <= rendered_tick and not replace and not samples.is_empty():
		return false
	var index := samples.size()
	while index > 0 and int(samples[index - 1]["tick"]) >= tick:
		index -= 1
	var sample := {"tick": tick, "position": position, "rotation": rotation}
	if index < samples.size() and int(samples[index]["tick"]) == tick:
		if not replace:
			return false
		samples[index] = sample
		return true
	samples.insert(index, sample)
	if samples.size() > CAPACITY:
		samples.pop_front()
	return true


## The transform at `render_tick`: {position, rotation, mode}. Empty buffers
## return {} so the caller leaves the entity where it is.
func sample(render_tick: float) -> Dictionary:
	if samples.is_empty():
		mode = Mode.EMPTY
		return {}
	# Drop samples the render time has passed, keeping two at or before it:
	# the bracket's older sample and its predecessor, for the curve's tangent.
	while samples.size() > 3 and float(samples[2]["tick"]) <= render_tick:
		samples.pop_front()
	var previous := mode
	var result: Dictionary
	var first: Dictionary = samples[0]
	var last: Dictionary = samples[-1]
	if render_tick <= float(first["tick"]) or samples.size() == 1:
		# Before the oldest sample (just after a reset) or a single sample: hold it.
		var held: Dictionary = first if render_tick <= float(first["tick"]) else last
		result = {"position": held["position"], "rotation": held["rotation"]}
		mode = Mode.INTERPOLATED if render_tick <= float(last["tick"]) else Mode.HELD
	elif render_tick <= float(last["tick"]):
		var index := 0
		while float(samples[index + 1]["tick"]) < render_tick:
			index += 1
		result = interpolate(index, render_tick)
		mode = Mode.INTERPOLATED
	else:
		var older: Dictionary = samples[-2]
		var gap := int(last["tick"]) - int(older["tick"])
		var ahead := render_tick - float(last["tick"])
		if gap > MAX_VELOCITY_GAP_TICKS:
			result = {"position": last["position"], "rotation": last["rotation"]}
			mode = Mode.HELD
		else:
			# blend() with a weight above 1 continues the last motion linearly.
			result = blend(older, last, 1.0 + minf(ahead, MAX_EXTRAPOLATION_TICKS) / gap)
			mode = Mode.EXTRAPOLATED if ahead <= MAX_EXTRAPOLATION_TICKS else Mode.HELD
	if mode != Mode.INTERPOLATED and previous == Mode.INTERPOLATED:
		underruns += 1
	rendered_tick = maxf(rendered_tick, minf(render_tick, float(last["tick"])))
	result["mode"] = mode
	return result


## Position on a cubic Hermite curve between samples `index` and `index + 1`,
## with each tangent the slope across that sample's neighbours (one-sided at
## the ends), so drawn velocity stays continuous where linear interpolation
## would change it abruptly at every snapshot. Angles interpolate linearly.
func interpolate(index: int, render_tick: float) -> Dictionary:
	var older: Dictionary = samples[index]
	var newer: Dictionary = samples[index + 1]
	var span := float(int(newer["tick"]) - int(older["tick"]))
	var weight := (render_tick - float(older["tick"])) / span
	var result := blend(older, newer, weight)
	var start := slope(index)
	var finish := slope(index + 1)
	var squared := weight * weight
	var cubed := squared * weight
	result["position"] = (older["position"] as Vector3) * (2.0 * cubed - 3.0 * squared + 1.0) \
		+ start * span * (cubed - 2.0 * squared + weight) \
		+ (newer["position"] as Vector3) * (-2.0 * cubed + 3.0 * squared) \
		+ finish * span * (cubed - squared)
	return result


## Velocity in metres per tick at sample `index`, across its neighbours.
func slope(index: int) -> Vector3:
	var before: Dictionary = samples[maxi(0, index - 1)]
	var after: Dictionary = samples[mini(samples.size() - 1, index + 1)]
	var ticks := int(after["tick"]) - int(before["tick"])
	if ticks <= 0 or ticks > MAX_VELOCITY_GAP_TICKS:
		return Vector3.ZERO
	return ((after["position"] as Vector3) - (before["position"] as Vector3)) / ticks


## Position lerp and shortest-path angle lerp per axis. Weights above 1
## extrapolate.
static func blend(older: Dictionary, newer: Dictionary, weight: float) -> Dictionary:
	var from: Vector3 = older["rotation"]
	var to: Vector3 = newer["rotation"]
	var rotation := Vector3(
		from.x + angle_difference(from.x, to.x) * weight,
		from.y + angle_difference(from.y, to.y) * weight,
		from.z + angle_difference(from.z, to.z) * weight)
	return {"position": (older["position"] as Vector3).lerp(newer["position"], weight), "rotation": rotation}
