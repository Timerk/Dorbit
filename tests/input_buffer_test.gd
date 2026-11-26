extends SceneTree
## InputBuffer ordering, deduplication, redundancy, starvation, catch-up and
## timeout, plus FlightInput packet round trips.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	run()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func input(seq: int, x: float = 0.0) -> Dictionary:
	return {"seq": seq, "movement": Vector3(x, 0, 0), "boost": false, "facing": Vector3.ZERO}


## Delivers what a client would send after sampling `newest`: the last
## FlightInput.REDUNDANCY inputs, oldest first.
func deliver(buffer: InputBuffer, newest: int) -> void:
	for seq in range(maxi(1, newest - FlightInput.REDUNDANCY + 1), newest + 1):
		buffer.receive(seq, input(seq, seq))


func applied_seq(result: Dictionary) -> int:
	return int(result["movement"].x) if not result.is_empty() else -1


func run() -> void:
	# Duplicates and reordering: each sequence is applied once, in order.
	var buffer := InputBuffer.new()
	for seq in [3, 1, 2, 2, 1, 3]:
		buffer.receive(seq, input(seq, seq))
	check(buffer.depth() == 3 and buffer.duplicates == 3, "Duplicates are discarded while buffered")
	var order: Array[int] = []
	for tick in 3:
		order.append(applied_seq(buffer.consume()))
	check(order == [1, 2, 3] and buffer.applied == 3, "Out-of-order inputs are applied once each, in sequence order")
	buffer.receive(2, input(2, 2))
	check(buffer.duplicates == 4 and buffer.late == 0 and buffer.depth() == 0, "An already applied input is a duplicate")

	# Redundancy: losing whole packets loses no inputs while a later packet arrives.
	buffer = InputBuffer.new()
	var sent := 0
	var packets := 0
	var lost_packets := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var applied: Array[int] = []
	var burst := 0
	for tick in range(1, 6001):
		sent = tick
		if tick % FlightPrediction.SEND_INTERVAL_TICKS == 0:
			packets += 1
			# 5% random loss plus a three-packet burst every 500 packets.
			var drop := rng.randf() < 0.05 or burst > 0
			if packets % 500 == 0:
				burst = 3
			if burst > 0:
				burst -= 1
			if drop:
				lost_packets += 1
			else:
				deliver(buffer, sent)
		# The server runs two ticks behind the client here.
		if tick > 2:
			var result := buffer.consume()
			if buffer.starved_ticks == 0 and not result.is_empty():
				applied.append(applied_seq(result))
	check(lost_packets > 150, "The redundancy scenario drops many packets (%d)" % lost_packets)
	check(buffer.lost == 0 and buffer.late == 0, "5%% loss and three-packet bursts lose no inputs (lost %d, late %d)" % [buffer.lost, buffer.late])
	var in_order := true
	for index in range(1, applied.size()):
		in_order = in_order and applied[index] == applied[index - 1] + 1
	check(in_order and applied.size() + buffer.dropped + buffer.depth() >= sent - 4, "Every input is applied once in order, apart from catch-up drops")

	# Gaps beyond the redundancy window are skipped and counted as lost; their
	# late arrival is recognized.
	buffer = InputBuffer.new()
	buffer.receive(1, input(1, 1))
	buffer.consume()
	buffer.receive(5, input(5, 5))
	check(applied_seq(buffer.consume()) == 5 and buffer.lost == 3, "A sequence gap is skipped and counted as lost")
	buffer.receive(3, input(3, 3))
	check(buffer.late == 1 and buffer.depth() == 0, "An input arriving after its slot was skipped is late, not applied")

	# Starvation reuses the last input without advancing; then the timeout idles.
	buffer = InputBuffer.new()
	check(buffer.consume().is_empty() and buffer.starved == 0, "A pilot without any input is idle, not starved")
	buffer.receive(1, input(1, 1))
	buffer.consume()
	var reused := 0
	for tick in InputBuffer.TIMEOUT_TICKS:
		if applied_seq(buffer.consume()) == 1:
			reused += 1
	check(reused == InputBuffer.TIMEOUT_TICKS and buffer.starved == InputBuffer.TIMEOUT_TICKS and buffer.last_seq == 1, "Starved ticks reuse the last input without advancing the sequence")
	check(buffer.consume().is_empty(), "After the tick timeout the pilot is idle")
	buffer.receive(2, input(2, 2))
	check(applied_seq(buffer.consume()) == 2 and buffer.starved_ticks == 0 and buffer.lost == 0, "A new input ends starvation without loss")

	# Catch-up: surplus depth held for a whole window is dropped down to the spare depth.
	buffer = InputBuffer.new()
	var next := 1
	for seq in range(1, 9):
		buffer.receive(seq, input(seq, seq))
		next = seq + 1
	for tick in InputBuffer.CATCH_UP_WINDOW:
		buffer.receive(next, input(next, next))
		next += 1
		buffer.consume()
	check(buffer.depth() == InputBuffer.SPARE_DEPTH and buffer.dropped == 8 - 1 - InputBuffer.SPARE_DEPTH + 1, "Persistent surplus is dropped to the spare depth (depth %d, dropped %d)" % [buffer.depth(), buffer.dropped])
	check(buffer.lost == 0, "Catch-up drops are not counted as lost inputs")
	# A burst beyond the hard bound is trimmed at once.
	for seq in range(next, next + InputBuffer.MAX_DEPTH + 6):
		buffer.receive(seq, input(seq, seq))
	buffer.consume()
	check(buffer.depth() == InputBuffer.MAX_DEPTH, "Buffered latency never exceeds MAX_DEPTH ticks")
	# Floods cannot grow the buffer without bound between ticks.
	for seq in range(next + 100, next + 200):
		buffer.receive(seq, input(seq, seq))
	check(buffer.depth() <= InputBuffer.MAX_DEPTH * 2, "A flood of inputs stays bounded")

	# A new life resynchronizes without counting the skipped sequences as lost.
	buffer = InputBuffer.new()
	buffer.receive(1, input(1, 1))
	buffer.consume()
	buffer.receive(2, input(2, 2))
	buffer.reset()
	check(buffer.depth() == 0 and buffer.consume().is_empty(), "Reset discards buffered inputs and the reused input")
	buffer.receive(40, input(40, 40))
	check(applied_seq(buffer.consume()) == 40 and buffer.lost == 0, "The first input after a reset starts a new run")
	buffer.receive(30, input(30, 30))
	check(buffer.depth() == 0, "Inputs from before the reset are never applied")

	# FlightInput packets round trip with quantized values.
	var inputs: Array = []
	for seq in range(100, 100 + FlightInput.REDUNDANCY):
		inputs.append({"seq": seq, "movement": Vector3(0.5, -1.0, 0.25), "boost": seq % 2 == 0, "facing": Vector3(1.2, -2.5, 0)})
	var packet := FlightInput.encode(7, true, 12, 3, 999, inputs, 4_000_000_000)
	check(packet.size() == FlightInput.HEADER_SIZE + inputs.size() * FlightInput.INPUT_SIZE and packet.size() <= 106, "Input packets with a snapshot acknowledgement stay compact (%d bytes)" % packet.size())
	var decoded := FlightInput.decode(packet)
	check(decoded["life"] == 7 and decoded["fire"] and decoded["encounter"] == 12 and decoded["target"] == 3 and decoded["tick"] == 999, "Packet header fields round trip")
	check(decoded["snapshot_ack"] == 4_000_000_000, "Flight packets carry the full unsigned snapshot acknowledgement")
	var exact := true
	for index in inputs.size():
		var original: Dictionary = inputs[index]
		var copy: Dictionary = decoded["inputs"][index]
		exact = exact and copy["seq"] == original["seq"] and copy["boost"] == original["boost"]
		exact = exact and copy["movement"] == FlightInput.quantize_movement(original["movement"]) and copy["facing"] == FlightInput.quantize_facing(original["facing"])
		exact = exact and copy["movement"].distance_to(original["movement"]) < 0.01 and copy["facing"].distance_to(original["facing"]) < 0.0002
	check(exact, "Decoded inputs equal the client's quantized prediction values exactly")
	check(is_equal_approx(FlightInput.quantize_facing(Vector3(9.0, 4.0, 0)).x, 1.48) and absf(FlightInput.quantize_facing(Vector3(0, 4.0, 0)).y - wrapf(4.0, -PI, PI)) < 0.0001, "Facing is clamped and wrapped like server validation")
	check(FlightInput.decode(packet.slice(0, packet.size() - 1)).is_empty() and FlightInput.decode(packet + PackedByteArray([0])).is_empty() and FlightInput.decode(PackedByteArray()).is_empty(), "Truncated or oversized packets are rejected")
	var empty := FlightInput.encode(1, false, 0, 0, 0, [])
	check(FlightInput.decode(empty).is_empty(), "Packets without inputs or a snapshot acknowledgement are rejected")
	var ack_only := FlightInput.decode(FlightInput.encode(1, false, -1, -1, 0, [], 42))
	check(ack_only.get("snapshot_ack") == 42 and ack_only["inputs"].is_empty(), "An idle pilot acknowledges snapshots without inputs")
	check(FlightInput.decode(FlightInput.encode(1, true, -1, -1, 0, [], 42)).is_empty(), "An acknowledgement alone cannot request fire")
	print("Input buffer checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
