class_name NetSimulator
extends RefCounted
## Debug UDP relay that degrades one client's connection to a server.
##
## The client's ENet socket talks to `listen_port` on 127.0.0.1; the relay
## forwards each datagram to the real server and back after applying the
## conditions of its direction. Because it works on raw datagrams below ENet,
## ENet's own acknowledgements, resends, ordering and throttling react to the
## loss exactly as on a real network.
##
## Conditions are per direction (UP is client to server, DOWN is server to
## client) and can change while the relay runs:
## - latency_ms: one-way delay added to every datagram.
## - jitter_ms: each datagram's delay varies uniformly by up to this many
##   milliseconds either way (never below zero). Jitter can reorder datagrams.
## - loss_percent: chance that a datagram is dropped.
## - duplicate_percent: chance that a datagram is delivered twice. The copy
##   draws its own jitter.
## `set_round_trip()` sets both directions from round-trip figures: half of the
## added round trip and half of its jitter each way, so "150 ± 30 ms" adds
## 75 ± 15 ms per direction.
##
## Timing does not depend on frames or on the OS sleep granularity (a 15.6 ms
## timer tick on some Windows systems): one thread per socket blocks until a
## datagram arrives and timestamps it. The delivery thread measures how long its
## 1 ms sleeps really take and spins instead of sleeping when the next datagram
## is due sooner than that. One relay serves one client.

const UP := 0
const DOWN := 1
const BOTH := -1
# Spin margin added to the measured sleep length.
const SPIN_USEC := 500
const MAX_QUEUE := 4096
const FLUSH := 9223372036854775807

## Port the client connects to on 127.0.0.1. Zero while stopped.
var listen_port: int = 0
var server_address: String = ""
var server_port: int = 0

# Guards everything below that more than one thread touches.
var _mutex := Mutex.new()
var _listeners: Array[Thread] = []
var _pump: Thread
var _running := false
var _pumping := false
var _rng := RandomNumberGenerator.new()
var _client := PacketPeerUDP.new()
var _upstream := PacketPeerUDP.new()
var _waker := PacketPeerUDP.new()
var _client_port := 0
var _conditions: Array[Dictionary] = [blank_conditions(), blank_conditions()]
var _stats: Array[Dictionary] = [blank_stats(), blank_stats()]
# Pending datagrams per direction, sorted by due time; equal times keep arrival order.
var _due: Array[Array] = [[], []]
var _packets: Array[Array] = [[], []]


static func blank_conditions() -> Dictionary:
	return {"latency_ms": 0.0, "jitter_ms": 0.0, "loss_percent": 0.0, "duplicate_percent": 0.0}


static func blank_stats() -> Dictionary:
	# received: datagrams entering the relay; forwarded: datagrams sent on,
	# including duplicates; dropped: simulated losses (plus queue overflow).
	return {"received_packets": 0, "received_bytes": 0, "forwarded_packets": 0, "forwarded_bytes": 0,
		"dropped_packets": 0, "duplicated_packets": 0, "queued_packets": 0}


## Starts relaying to `address`:`port`, listening on 127.0.0.1:`bind_port`
## (0 picks a free port; read `listen_port` afterwards).
func start(address: String, port: int, bind_port: int = 0) -> Error:
	if is_running():
		return ERR_ALREADY_IN_USE
	if port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	var resolved := address if address.is_valid_ip_address() else IP.resolve_hostname(address)
	if resolved.is_empty():
		return ERR_CANT_RESOLVE
	_client = PacketPeerUDP.new()
	_upstream = PacketPeerUDP.new()
	_waker = PacketPeerUDP.new()
	var error := _client.bind(bind_port, "127.0.0.1")
	if error == OK:
		error = _upstream.bind(0, "*")
	if error == OK:
		error = _upstream.set_dest_address(resolved, port)
	if error == OK:
		error = _waker.bind(0, "127.0.0.1")
	if error != OK:
		_client.close()
		_upstream.close()
		_waker.close()
		return error
	server_address = resolved
	server_port = port
	listen_port = _client.get_local_port()
	_client_port = 0
	_mutex.lock()
	_due = [[], []]
	_packets = [[], []]
	_stats = [blank_stats(), blank_stats()]
	_running = true
	_pumping = true
	_mutex.unlock()
	_listeners = [Thread.new(), Thread.new()]
	_listeners[UP].start(_listen.bind(UP))
	_listeners[DOWN].start(_listen.bind(DOWN))
	_pump = Thread.new()
	_pump.start(_deliver_loop)
	return OK


## Stops the relay. Datagrams already received, including ones still delayed,
## are delivered immediately first, so a disconnect notice sent just before
## stopping still reaches the server.
func stop() -> void:
	if _pump == null:
		return
	_mutex.lock()
	_running = false
	_mutex.unlock()
	# Wake the blocked receivers; they skip these datagrams.
	_waker.set_dest_address("127.0.0.1", listen_port)
	_waker.put_packet(PackedByteArray([0]))
	_waker.set_dest_address("127.0.0.1", _upstream.get_local_port())
	_waker.put_packet(PackedByteArray([0]))
	for listener in _listeners:
		listener.wait_to_finish()
	_listeners.clear()
	_mutex.lock()
	_pumping = false
	_mutex.unlock()
	_pump.wait_to_finish()
	_pump = null
	_client.close()
	_upstream.close()
	_waker.close()
	listen_port = 0


func is_running() -> bool:
	return _pump != null


## Seeds loss, duplication and jitter decisions. Call before start() for a
## repeatable sequence of decisions on the same traffic.
func set_seed(value: int) -> void:
	_mutex.lock()
	_rng.seed = value
	_mutex.unlock()


## Sets one direction (UP, DOWN) or both (BOTH) to the given one-way conditions.
func configure(direction: int, latency_ms: float, jitter_ms: float = 0.0, loss_percent: float = 0.0, duplicate_percent: float = 0.0) -> void:
	var values := {
		"latency_ms": clampf(latency_ms, 0.0, 5000.0), "jitter_ms": clampf(jitter_ms, 0.0, 5000.0),
		"loss_percent": clampf(loss_percent, 0.0, 100.0), "duplicate_percent": clampf(duplicate_percent, 0.0, 100.0),
	}
	_mutex.lock()
	for index in ([UP, DOWN] if direction == BOTH else [direction]):
		_conditions[index] = values.duplicate()
	_mutex.unlock()


## Adds `round_trip_ms` ± `jitter_ms` of round trip, split evenly between the
## directions, with the same loss and duplication chance each way.
func set_round_trip(round_trip_ms: float, jitter_ms: float = 0.0, loss_percent: float = 0.0, duplicate_percent: float = 0.0) -> void:
	configure(BOTH, round_trip_ms * 0.5, jitter_ms * 0.5, loss_percent, duplicate_percent)


## One-way conditions of a direction, as in blank_conditions().
func conditions(direction: int) -> Dictionary:
	_mutex.lock()
	var result := _conditions[direction].duplicate()
	_mutex.unlock()
	return result


## Whether both directions currently use the same conditions.
func symmetric() -> bool:
	return conditions(UP) == conditions(DOWN)


## Copies of the counters as {"up": blank_stats(), "down": blank_stats()}.
func stats() -> Dictionary:
	_mutex.lock()
	var result := {"up": _stats[UP].duplicate(), "down": _stats[DOWN].duplicate()}
	_mutex.unlock()
	return result


func reset_stats() -> void:
	_mutex.lock()
	for direction in 2:
		_stats[direction] = blank_stats()
		_stats[direction]["queued_packets"] = _due[direction].size()
	_mutex.unlock()


## Applies `--netsim`, `--netsim-rtt=MS`, `--netsim-jitter=MS` (± round trip),
## `--netsim-loss=PERCENT`, `--netsim-duplicate=PERCENT` and `--netsim-seed=N`.
## Returns whether any of them asked to route connections through the relay.
func configure_from_args(args: PackedStringArray) -> bool:
	var enabled := false
	var values := {"rtt": 0.0, "jitter": 0.0, "loss": 0.0, "duplicate": 0.0}
	for argument in args:
		if argument == "--netsim":
			enabled = true
		elif argument.begins_with("--netsim-seed="):
			set_seed(int(argument.trim_prefix("--netsim-seed=")))
		else:
			for key: String in values:
				var prefix := "--netsim-%s=" % key
				if argument.begins_with(prefix) and argument.trim_prefix(prefix).is_valid_float():
					values[key] = float(argument.trim_prefix(prefix))
					enabled = true
	set_round_trip(values["rtt"], values["jitter"], values["loss"], values["duplicate"])
	return enabled


# Receiver thread: blocks on one socket and schedules each datagram on arrival.
func _listen(direction: int) -> void:
	var socket := _client if direction == UP else _upstream
	var waker_port := _waker.get_local_port()
	while true:
		if socket.wait() != OK:
			OS.delay_usec(1000)
		var now := Time.get_ticks_usec()
		while socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()
			if socket.get_packet_error() != OK:
				continue
			if socket.get_packet_port() == waker_port and socket.get_packet_ip() in ["127.0.0.1", "::ffff:127.0.0.1"]:
				continue
			if direction == UP and socket.get_packet_port() != _client_port:
				# Follow the client's socket, including after it reconnects.
				_mutex.lock()
				_client_port = socket.get_packet_port()
				_client.set_dest_address(socket.get_packet_ip(), _client_port)
				_mutex.unlock()
			_schedule(direction, now, packet)
		_mutex.lock()
		var running := _running
		_mutex.unlock()
		if not running:
			return


func _schedule(direction: int, now: int, packet: PackedByteArray) -> void:
	_mutex.lock()
	var settings := _conditions[direction]
	var counters := _stats[direction]
	counters["received_packets"] += 1
	counters["received_bytes"] += packet.size()
	var copies := 1
	if _rng.randf() * 100.0 < settings["loss_percent"]:
		copies = 0
		counters["dropped_packets"] += 1
	elif _rng.randf() * 100.0 < settings["duplicate_percent"]:
		copies = 2
		counters["duplicated_packets"] += 1
	var dues: Array = _due[direction]
	for _copy in copies:
		if dues.size() >= MAX_QUEUE:
			counters["dropped_packets"] += 1
			continue
		var jitter: float = settings["jitter_ms"]
		var delay := maxf(0.0, settings["latency_ms"] + _rng.randf_range(-jitter, jitter))
		var due := now + int(delay * 1000.0)
		var index := dues.bsearch(due, false)
		dues.insert(index, due)
		_packets[direction].insert(index, packet)
	counters["queued_packets"] = dues.size()
	_mutex.unlock()


# Delivery thread: sends datagrams when due; a final pass flushes the queues.
func _deliver_loop() -> void:
	# Longest recent sleep, decaying so a single stall does not cause spinning forever.
	var sleep_usec := 2000.0
	while true:
		_mutex.lock()
		var pumping := _pumping
		_mutex.unlock()
		var now := Time.get_ticks_usec() if pumping else FLUSH
		var next := FLUSH
		for direction in 2:
			next = mini(next, _deliver(direction, now))
		if not pumping:
			return
		var before := Time.get_ticks_usec()
		if next - before > sleep_usec + SPIN_USEC:
			OS.delay_usec(1000)
			sleep_usec = maxf(sleep_usec * 0.999, Time.get_ticks_usec() - before)


# Sends what is due in one direction; returns the next due time, or FLUSH.
func _deliver(direction: int, now: int) -> int:
	_mutex.lock()
	var dues: Array = _due[direction]
	var count := 0
	while count < dues.size() and dues[count] <= now:
		count += 1
	var ready: Array = _packets[direction].slice(0, count)
	if count > 0:
		_due[direction] = dues.slice(count)
		_packets[direction] = _packets[direction].slice(count)
	var next: int = _due[direction][0] if not _due[direction].is_empty() else FLUSH
	# Server replies before the client's first datagram have nowhere to go.
	var socket := _upstream if direction == UP else (_client if _client_port != 0 else null)
	var sent := 0
	var bytes := 0
	if socket != null:
		for packet: PackedByteArray in ready:
			if socket.put_packet(packet) == OK:
				sent += 1
				bytes += packet.size()
	_stats[direction]["forwarded_packets"] += sent
	_stats[direction]["forwarded_bytes"] += bytes
	_stats[direction]["queued_packets"] = _due[direction].size()
	_mutex.unlock()
	return next
