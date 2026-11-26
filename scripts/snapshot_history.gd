class_name SnapshotHistory
extends RefCounted
## One viewer's packed snapshot states, scoped to its map visit. Both ends
## retain a 32-snapshot window (1.6 s at 20 Hz). A ring slot always names its
## exact sequence, so loss, reordering and slot reuse cannot substitute a base.

const CAPACITY := 32

var acknowledged := 0
var visit := -1
var map := -1
var newest := 0
var frames: Dictionary[int, Dictionary] = {}


func set_scope(next_visit: int, next_map: int) -> void:
	if visit == next_visit and map == next_map:
		return
	visit = next_visit
	map = next_map
	acknowledged = 0
	newest = 0
	frames.clear()


func find(sequence: int) -> Dictionary:
	if sequence <= 0 or newest - sequence >= CAPACITY:
		return {}
	var frame: Dictionary = frames.get(sequence % CAPACITY, {})
	return frame if frame.get("sequence") == sequence else {}


func remember_sent(sequence: int, entries: Dictionary) -> void:
	frames[sequence % CAPACITY] = {"sequence": sequence, "visit": visit, "entries": entries}
	newest = sequence


func acknowledge(sequence: int) -> void:
	if sequence > acknowledged and not find(sequence).is_empty():
		acknowledged = sequence


func baseline_for(sequence: int) -> Dictionary:
	var age := sequence - acknowledged
	if age <= 0 or age >= CAPACITY:
		return {}
	return find(acknowledged)


func receive(packet: PackedByteArray, header: Dictionary) -> Dictionary:
	if header.is_empty() or header["visit"] != visit:
		return {}
	var sequence: int = header["sequence"]
	var part: int = header["part"]
	if newest - sequence >= CAPACITY:
		return {}
	var frame := find(sequence)
	if not frame.is_empty() and (frame["received"].has(part) or frame["parts"] != header["parts"]
			or frame["tick"] != header["tick"] or frame["baseline"] != header["baseline"]):
		return {}
	var baseline := find(header["baseline"])
	if header["baseline"] != 0 and (baseline.is_empty() or baseline["received"].size() != baseline["parts"]):
		return {}
	var world := SnapshotCodec.decode_world(packet, baseline)
	if world.is_empty():
		return {}
	world["first_part"] = frame.is_empty()
	if frame.is_empty():
		frame = header.duplicate()
		frame["received"] = {}
		frame["entries"] = {}
	for key: Vector2i in world["entries"]:
		if frame["entries"].has(key):
			return {}
	frame["entries"].merge(world["entries"])
	frame["received"][part] = true
	frames[sequence % CAPACITY] = frame
	newest = maxi(newest, sequence)
	if frame["received"].size() == frame["parts"]:
		acknowledged = maxi(acknowledged, sequence)
	return world
