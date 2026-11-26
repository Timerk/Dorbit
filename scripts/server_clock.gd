class_name ServerClock
extends RefCounted
## Client estimate of the server's simulation time, and the render time remote
## entities are drawn at (see SnapshotBuffer).
##
## Each world snapshot carries the server tick it was sent on. Its offset
## sample is `tick / 60 - local arrival time`: late packets give smaller
## offsets, and the least-delayed packets the largest. The clock uses the
## median sample of the last OFFSET_WINDOW seconds, so single late or early
## packets barely move it, while lasting latency changes and clock drift are
## followed within one window. Estimated server time is local time plus that
## offset: the server's clock as seen through a typical recent packet. (The
## largest sample would follow the fastest path instead, but it is set by
## outliers, including frame and tick timing, and left less buffer for typical
## packets in measurements.)
##
## The render time trails it by INTERPOLATION_DELAY. advance() moves it by each
## physics tick's delta, so remote entities step in time with the local ship
## and camera, and time-scales it by at most MAX_SLEW to close any error over
## about CORRECTION_TIME. Only an error above SNAP_ERROR (connect, a stall or a
## large route change) jumps.

## Server simulation ticks per second.
const TICK_RATE := 60.0
## How far behind the estimated server time remote entities are drawn, in
## seconds: two snapshot intervals, so one lost or late snapshot still leaves
## a sample to interpolate toward. A playtesting setting.
const INTERPOLATION_DELAY := 0.1
## Seconds of offset samples the median is taken from.
const OFFSET_WINDOW := 2.0
## Largest time-scale change used to correct the render time (±5%).
const MAX_SLEW := 0.05
## Seconds over which a render time error is closed, before the slew limit.
const CORRECTION_TIME := 1.0
## Render time errors larger than this (seconds) snap instead of slewing.
const SNAP_ERROR := 0.25
## Time constant (seconds) of the low-pass filter on the render time error.
## Physics ticks run at frame boundaries, so each tick's wall-clock time is
## off by up to a frame; filtering keeps that noise out of the time-scale,
## where it would shake remote entities' drawn velocity.
const ERROR_SMOOTHING := 0.5

var synced: bool = false
## Server seconds minus local seconds: the median sample in the window.
var offset: float = 0.0
## Recent offset samples and their local arrival times, oldest first. Float64:
## server and client uptimes can be large.
var window_offsets := PackedFloat64Array()
var window_times := PackedFloat64Array()
## Render time on the server's timeline, in seconds.
var render_time: float = 0.0
## Newest server tick received.
var latest_tick: int = -1
## Latest render-time error (target minus render time) and time-scale, for stats.
var error: float = 0.0
## Low-pass filtered render time error, which sets the time-scale.
var filtered_error: float = 0.0
var time_scale: float = 1.0
var snaps: int = 0
var delay: float = INTERPOLATION_DELAY


func reset() -> void:
	synced = false
	offset = 0.0
	window_offsets.clear()
	window_times.clear()
	render_time = 0.0
	latest_tick = -1
	error = 0.0
	filtered_error = 0.0
	time_scale = 1.0
	snaps = 0


static func now_seconds() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


## Records a snapshot sent on server `tick` arriving at local time `now`.
func observe(tick: int, now: float = now_seconds()) -> void:
	latest_tick = maxi(latest_tick, tick)
	var sample := tick / TICK_RATE - now
	window_offsets.append(sample)
	window_times.append(now)
	var expired := 0
	while expired < window_times.size() - 1 and window_times[expired] < now - OFFSET_WINDOW:
		expired += 1
	if expired > 0:
		window_offsets = window_offsets.slice(expired)
		window_times = window_times.slice(expired)
	var sorted := window_offsets.duplicate()
	sorted.sort()
	offset = sorted[sorted.size() / 2]
	if not synced:
		synced = true
		render_time = now + offset - delay


## Estimated current server time, in seconds.
func server_time(now: float = now_seconds()) -> float:
	return now + offset


## Advances the render time by one physics tick of `delta` seconds.
func advance(delta: float, now: float = now_seconds()) -> void:
	if not synced:
		return
	var target := server_time(now) - delay
	error = target - (render_time + delta)
	if absf(error) > SNAP_ERROR:
		render_time = target
		time_scale = 1.0
		snaps += 1
		error = 0.0
		filtered_error = 0.0
		return
	filtered_error = lerpf(filtered_error, error, 1.0 - exp(-delta / ERROR_SMOOTHING))
	time_scale = 1.0 + clampf(filtered_error / CORRECTION_TIME, -MAX_SLEW, MAX_SLEW)
	render_time += delta * time_scale


func render_tick() -> float:
	return render_time * TICK_RATE


## How far the newest received snapshot is ahead of the render time, in seconds.
func buffer_depth() -> float:
	return latest_tick / TICK_RATE - render_time if synced else 0.0
