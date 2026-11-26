class_name FlightInput
extends RefCounted
## Compact flight input packets from a client to the server.
##
## A client samples one input per physics tick (60 Hz): a per-connection
## sequence number, its local tick, movement, boost and the facing it requests.
## Every packet repeats the most recent unacknowledged inputs, so a lost packet
## costs nothing while a later one arrives. Sequence numbers in a packet are
## consecutive, so only the first is sent.
##
## Layout (little endian):
##   u8 flags (FIRE), u32 life, i32 encounter, i32 target, u32 client tick of
##   the newest input, u32 first sequence, u8 count, then per input:
##   3 x i8 movement (axis * 127), u16 yaw, i16 pitch, u8 flags (BOOST).
## Movement and facing are quantized here, and clients predict with the
## quantized values, so the server and the client simulate the same numbers.

const FIRE := 1
const BOOST := 1
## Inputs per packet: at 30 packets per second (two inputs each) ten inputs
## cover a burst of four lost packets. A playtesting setting.
const REDUNDANCY := 10
const MAX_INPUTS := 16
const HEADER_SIZE := 22
const INPUT_SIZE := 8
const MOVEMENT_SCALE := 127.0
const YAW_SCALE := 65536.0 / TAU
const PITCH_SCALE := 20000.0
const PITCH_LIMIT := 1.48


static func quantize_movement(movement: Vector3) -> Vector3:
	var result := Vector3.ZERO
	for axis in 3:
		result[axis] = roundf(clampf(movement[axis], -1.0, 1.0) * MOVEMENT_SCALE) / MOVEMENT_SCALE
	return result


## Facing as the server decodes it: yaw wrapped to [-PI, PI), pitch clamped.
static func quantize_facing(angles: Vector3) -> Vector3:
	var yaw := posmod(roundi((wrapf(angles.y, -PI, PI) + PI) * YAW_SCALE), 65536)
	var pitch := roundi(clampf(angles.x, -PITCH_LIMIT, PITCH_LIMIT) * PITCH_SCALE)
	return Vector3(pitch / PITCH_SCALE, yaw / YAW_SCALE - PI, 0.0)


## `inputs` hold {seq, movement, boost, facing} with consecutive sequences.
static func encode(life: int, fire: bool, encounter: int, target: int, client_tick: int, inputs: Array) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_u8(FIRE if fire else 0)
	buffer.put_u32(life)
	buffer.put_32(encounter)
	buffer.put_32(target)
	buffer.put_u32(client_tick)
	buffer.put_u32(inputs[0]["seq"] if not inputs.is_empty() else 0)
	buffer.put_u8(inputs.size())
	for input: Dictionary in inputs:
		var movement: Vector3 = input["movement"]
		for axis in 3:
			buffer.put_8(roundi(clampf(movement[axis], -1.0, 1.0) * MOVEMENT_SCALE))
		var facing: Vector3 = input["facing"]
		buffer.put_u16(posmod(roundi((wrapf(facing.y, -PI, PI) + PI) * YAW_SCALE), 65536))
		buffer.put_16(roundi(clampf(facing.x, -PITCH_LIMIT, PITCH_LIMIT) * PITCH_SCALE))
		buffer.put_u8(BOOST if input["boost"] else 0)
	return buffer.data_array


## Returns {fire, life, encounter, target, tick, inputs: [{seq, movement,
## boost, facing}]}, or {} for a malformed packet. Values are always finite
## and in range, whatever the sender wrote.
static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.size() < HEADER_SIZE:
		return {}
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = packet
	var result := {"fire": buffer.get_u8() & FIRE != 0, "life": buffer.get_u32(), "encounter": buffer.get_32(),
		"target": buffer.get_32(), "tick": buffer.get_u32(), "inputs": []}
	var first := buffer.get_u32()
	var count := buffer.get_u8()
	if count < 1 or count > MAX_INPUTS or packet.size() != HEADER_SIZE + count * INPUT_SIZE:
		return {}
	for index in count:
		var movement := Vector3.ZERO
		for axis in 3:
			movement[axis] = clampi(buffer.get_8(), -127, 127) / MOVEMENT_SCALE
		var yaw := buffer.get_u16()
		var pitch := clampi(buffer.get_16(), -roundi(PITCH_LIMIT * PITCH_SCALE), roundi(PITCH_LIMIT * PITCH_SCALE))
		result["inputs"].append({"seq": first + index, "movement": movement,
			"facing": Vector3(pitch / PITCH_SCALE, yaw / YAW_SCALE - PI, 0.0),
			"boost": buffer.get_u8() & BOOST != 0})
	return result
