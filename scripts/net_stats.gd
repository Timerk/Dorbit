class_name NetStats
extends RefCounted
## Client-side netcode measurements fed by FlightSession, shown by the F8
## overlay and read by tests/netcode_benchmark.gd. Measuring never changes
## gameplay: the server stays authoritative.
##
## Metrics:
## - rtt_ms: ENet's smoothed round-trip time to the server peer
##   (ENetPacketPeer.PEER_ROUND_TRIP_TIME), sampled once per second.
## - up/down_bytes_per_second: UDP payload bytes the client's ENet host sent and
##   received over the last whole second (ENet headers included, IP/UDP not).
## - snapshot jitter: for each world snapshot, |time since the previous one -
##   50 ms|, as handled by the client (so it includes frame quantization). The
##   mean and maximum cover the last JITTER_WINDOW intervals.
## - error_m: simulation error at reconciliation: how far rewinding to the
##   authoritative state and replaying unacknowledged inputs moved the
##   predicted ship. Zero when the server simulated exactly what was predicted.
## - offset_m: the decaying visual offset that hides those corrections, sampled
##   once per physics tick: how far the drawn ship is from the simulated one.
## - replayed_ticks: unacknowledged inputs replayed at a reconciliation.
## - ack_lag_ticks: client ticks between sampling the newest acknowledged
##   input and its acknowledgement arriving (round trip plus server buffering).
## - server_input_depth: inputs the server had buffered for this pilot.
## - inputs_sent / input_packets_sent: inputs sampled and packets sent; each
##   packet repeats recent unacknowledged inputs.
## - server_inputs: the server's counters for this pilot's inputs (see
##   InputBuffer): applied, duplicates, late, lost, dropped and starved.

const SNAPSHOT_INTERVAL_MS := 50.0
const JITTER_WINDOW := 100
const SAMPLE_USEC := 1_000_000

var rtt_ms: float = 0.0
var up_bytes_per_second: float = 0.0
var down_bytes_per_second: float = 0.0
var up_packets_per_second: float = 0.0
var down_packets_per_second: float = 0.0
var total_up_bytes: int = 0
var total_down_bytes: int = 0
var snapshots_received: int = 0
## Recent snapshot inter-arrival times in milliseconds, oldest first.
var snapshot_intervals: PackedFloat32Array = []
var latest_error_m: float = 0.0
var max_error_m: float = 0.0
var latest_offset_m: float = 0.0
var max_offset_m: float = 0.0
var corrections: int = 0
var replayed_ticks: int = 0
var max_replayed_ticks: int = 0
var ack_lag_ticks: int = 0
var server_input_depth: int = -1
var unacked_inputs: int = 0
var server_tick: int = 0
var server_inputs: Dictionary = {}
## Last authoritative state of the local ship, for the server ghost.
var has_server_state: bool = false
var server_position: Vector3 = Vector3.ZERO
var server_rotation: Vector3 = Vector3.ZERO
var inputs_sent: int = 0
var input_packets_sent: int = 0
## When true, every error, correction and jitter sample is kept for percentiles.
var keep_samples: bool = false
var error_samples: PackedFloat32Array = []
var offset_samples: PackedFloat32Array = []
var replay_samples: PackedFloat32Array = []
var jitter_samples: PackedFloat32Array = []

var _last_arrival_usec: int = -1
var _sample_started_usec: int = -1
var _window_up_bytes: int = 0
var _window_down_bytes: int = 0
var _window_up_packets: int = 0
var _window_down_packets: int = 0


func reset() -> void:
	rtt_ms = 0.0
	up_bytes_per_second = 0.0
	down_bytes_per_second = 0.0
	up_packets_per_second = 0.0
	down_packets_per_second = 0.0
	total_up_bytes = 0
	total_down_bytes = 0
	snapshots_received = 0
	snapshot_intervals = PackedFloat32Array()
	has_server_state = false
	inputs_sent = 0
	input_packets_sent = 0
	unacked_inputs = 0
	server_tick = 0
	server_inputs = {}
	server_input_depth = -1
	ack_lag_ticks = 0
	_last_arrival_usec = -1
	_sample_started_usec = -1
	_window_up_bytes = 0
	_window_down_bytes = 0
	_window_up_packets = 0
	_window_down_packets = 0
	reset_extremes()


## Clears correction extremes and kept samples, keeping transport rates.
func reset_extremes() -> void:
	latest_error_m = 0.0
	max_error_m = 0.0
	latest_offset_m = 0.0
	max_offset_m = 0.0
	corrections = 0
	replayed_ticks = 0
	max_replayed_ticks = 0
	error_samples = PackedFloat32Array()
	offset_samples = PackedFloat32Array()
	replay_samples = PackedFloat32Array()
	jitter_samples = PackedFloat32Array()


func record_snapshot_arrival(now_usec: int = Time.get_ticks_usec()) -> void:
	snapshots_received += 1
	if _last_arrival_usec >= 0:
		var interval := (now_usec - _last_arrival_usec) / 1000.0
		snapshot_intervals.append(interval)
		if snapshot_intervals.size() > JITTER_WINDOW:
			snapshot_intervals = snapshot_intervals.slice(snapshot_intervals.size() - JITTER_WINDOW)
		if keep_samples:
			jitter_samples.append(absf(interval - SNAPSHOT_INTERVAL_MS))
	_last_arrival_usec = now_usec


## Returns Vector2(mean, max) of |interval - 50 ms| over the window, in ms.
func snapshot_jitter() -> Vector2:
	if snapshot_intervals.is_empty():
		return Vector2.ZERO
	var total := 0.0
	var largest := 0.0
	for interval in snapshot_intervals:
		var deviation := absf(interval - SNAPSHOT_INTERVAL_MS)
		total += deviation
		largest = maxf(largest, deviation)
	return Vector2(total / snapshot_intervals.size(), largest)


## Records one reconciliation of the local ship against authoritative state.
## `ack_lag` and `depth` are negative when unknown.
func record_reconciliation(error_m: float, replayed: int, ack_lag: int = -1, depth: int = -1) -> void:
	latest_error_m = error_m
	max_error_m = maxf(max_error_m, error_m)
	replayed_ticks = replayed
	max_replayed_ticks = maxi(max_replayed_ticks, replayed)
	unacked_inputs = replayed
	if ack_lag >= 0:
		ack_lag_ticks = ack_lag
	if depth >= 0:
		server_input_depth = depth
	corrections += 1
	if keep_samples:
		error_samples.append(error_m)
		replay_samples.append(replayed)


func record_visual_offset(offset_m: float) -> void:
	latest_offset_m = offset_m
	max_offset_m = maxf(max_offset_m, offset_m)
	if keep_samples:
		offset_samples.append(offset_m)


func record_server_state(position: Vector3, rotation: Vector3) -> void:
	has_server_state = true
	server_position = position
	server_rotation = rotation


## Reads RTT and host traffic from a client's ENet peer, at most once per
## second. Takes ENet's host counters (pop_statistic), so call it from one
## place per host. Returns whether the rates were refreshed.
func sample_transport(peer: MultiplayerPeer, now_usec: int = Time.get_ticks_usec()) -> bool:
	var enet := peer as ENetMultiplayerPeer
	if enet == null or enet.host == null:
		return false
	var host := enet.host
	var sent := host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var received := host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var sent_packets := host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var received_packets := host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	total_up_bytes += sent
	total_down_bytes += received
	_window_up_bytes += sent
	_window_down_bytes += received
	_window_up_packets += sent_packets
	_window_down_packets += received_packets
	if _sample_started_usec < 0:
		_sample_started_usec = now_usec
		_window_up_bytes = 0
		_window_down_bytes = 0
		_window_up_packets = 0
		_window_down_packets = 0
		return false
	var elapsed := now_usec - _sample_started_usec
	if elapsed < SAMPLE_USEC:
		return false
	var seconds := elapsed / 1_000_000.0
	up_bytes_per_second = _window_up_bytes / seconds
	down_bytes_per_second = _window_down_bytes / seconds
	up_packets_per_second = _window_up_packets / seconds
	down_packets_per_second = _window_down_packets / seconds
	_window_up_bytes = 0
	_window_down_bytes = 0
	_window_up_packets = 0
	_window_down_packets = 0
	_sample_started_usec = now_usec
	var server := enet.get_peer(1)
	if server != null:
		rtt_ms = server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	return true


## Value at `fraction` (0..1) of the sorted samples, or 0 without samples.
static func percentile(values: PackedFloat32Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(fraction * sorted.size())) - 1, 0, sorted.size() - 1)]


static func mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()
