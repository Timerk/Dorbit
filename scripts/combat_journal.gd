class_name CombatJournal
extends RefCounted
## Ordered, checksummed ammo/boost transactions paired with a schema-8 snapshot.
## Complete records are replayed; damaged or interrupted files require recovery.

const MAX_SEQUENCE: int = 9_007_199_254_740_991
const MAX_BYTES: int = 1_048_576


static func valid_metadata(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not value.get("id") is String or not Skylab.integer(value.get("sequence"), 0, MAX_SEQUENCE):
		return false
	var identifier: String = value["id"]
	return identifier.length() == 32 and PilotStore.valid_hex(identifier + identifier)


static func header(metadata: Dictionary) -> String:
	return JSON.stringify(metadata) + "\n"


static func record(sequence: int, ammo: Dictionary, boosts: Dictionary) -> String:
	var body := JSON.stringify({"sequence": sequence, "ammo": ammo, "boosts": boosts})
	return JSON.stringify([body, body.sha256_text()]) + "\n"


static func valid_updates(pilots: Dictionary, ammo: Variant, boosts: Variant) -> bool:
	if not ammo is Dictionary or not boosts is Dictionary or (ammo.is_empty() and boosts.is_empty()):
		return false
	for id: Variant in ammo:
		if not id is String or not pilots.has(id) or not Ammunition.valid(ammo[id]): return false
	for id: Variant in boosts:
		if not id is String or not pilots.has(id) or not ResourceBoosts.valid(boosts[id], pilots[id]["equipment"]): return false
	return true


static func apply_updates(pilots: Dictionary, ammo: Dictionary, boosts: Dictionary) -> void:
	for id: String in ammo:
		pilots[id]["ammo"] = ammo[id].duplicate(true)
		for kind: String in pilots[id]["ammo"]: pilots[id]["ammo"][kind] = int(pilots[id]["ammo"][kind])
	for id: String in boosts: pilots[id]["boosts"] = boosts[id].duplicate(true)


# The caller owns an unpublished ledger while replay runs. No files are modified.
static func replay(text: String, metadata: Dictionary, pilots: Dictionary) -> int:
	if not valid_metadata(metadata) or not text.ends_with("\n"): return -1
	var lines := text.trim_suffix("\n").split("\n")
	var base: Variant = JSON.parse_string(lines[0])
	if not valid_metadata(base) or base["id"] != metadata["id"] or base["sequence"] > metadata["sequence"]: return -1
	var sequence := int(base["sequence"])
	for index in range(1, lines.size()):
		var entry: Variant = JSON.parse_string(lines[index])
		if not entry is Array or entry.size() != 2 or not entry[0] is String or not entry[1] is String or entry[0].sha256_text() != entry[1]: return -1
		var body: Variant = JSON.parse_string(entry[0])
		if not body is Dictionary or body.size() != 3 or not Skylab.integer(body.get("sequence"), 1, MAX_SEQUENCE) or body["sequence"] != sequence + 1: return -1
		sequence += 1
		# A crash after snapshot replacement but before journal compaction leaves
		# already-checkpointed records. Never replay those over later purchases.
		if sequence <= metadata["sequence"]: continue
		if not valid_updates(pilots, body.get("ammo"), body.get("boosts")): return -1
		apply_updates(pilots, body["ammo"], body["boosts"])
	return sequence if sequence >= metadata["sequence"] else -1
