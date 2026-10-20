extends PilotStore
## Timing adapter used only by the separate-process benchmark.

var measuring := false
var reason := "other"
var samples: Dictionary = {}
var events: Array[Dictionary] = []
var counts: Dictionary = {}
var extras_pilots: int = 0


func _init() -> void:
	replacement_trace = trace_replacement


func trace_replacement(destination: String, marks: PackedInt64Array, succeeded: bool) -> void:
	if not measuring: return
	var kind := replacement_kind(destination)
	# Conversion is outside write timing; open, encode and all I/O remain visible.
	var stages := ["open", "encode", "write", "flush", "readback", "close", "rename"]
	var durations := {}
	for index in range(marks.size() - 1):
		var elapsed := float(marks[index + 1] - marks[index])
		durations[stages[index]] = elapsed
		record(kind + "_" + stages[index], marks[index], elapsed)
	events.append({"kind": kind, "reason": reason, "started_us": marks[0],
		"duration_us": marks[-1] - marks[0], "stages_us": durations, "succeeded": succeeded})


func replacement_kind(destination: String) -> String:
	return "replace_backup" if destination.ends_with(".bak") else ("replace_journal" if destination.ends_with(".combat") else "replace_primary")


func record(kind: String, before: int, elapsed: float = -1.0) -> void:
	if not measuring:
		return
	if elapsed < 0.0: elapsed = float(Time.get_ticks_usec() - before)
	if not samples.has(kind): samples[kind] = []
	samples[kind].append(elapsed)
	counts[kind] = int(counts.get(kind, 0)) + 1
	if kind == "checkpoint" or elapsed >= 1000.0 and kind == "journal":
		events.append({"kind": kind, "reason": reason, "started_us": before,
			"duration_us": elapsed, "snapshot_bytes": saved_bytes,
			"journal_bytes": journal_bytes})


func commit_combat(ammo: Dictionary, boosts: Dictionary = {}) -> bool:
	var before := Time.get_ticks_usec()
	var result := super.commit_combat(ammo, boosts)
	record("journal", before)
	return result


func persist(next: Dictionary) -> bool:
	var before := Time.get_ticks_usec()
	var result := super.persist(next)
	var elapsed := float(Time.get_ticks_usec() - before)
	record("checkpoint", before, elapsed)
	record("checkpoint_" + reason, before, elapsed)
	return result


func replace_file(destination: String, text: String) -> bool:
	var before := Time.get_ticks_usec()
	var result := super.replace_file(destination, text)
	var kind := replacement_kind(destination)
	record(kind, before)
	return result


func commit(balances: Dictionary, contracts: Dictionary = {}, cargo: Dictionary = {}, ammo: Dictionary = {}, boosts: Dictionary = {}, research: Dictionary = {}) -> bool:
	var previous := reason
	reason = "extras" if not ammo.is_empty() else ("loot" if balances.is_empty() and not cargo.is_empty() else "economy")
	var result := super.commit(balances, contracts, cargo, ammo, boosts, research)
	if measuring and reason == "extras" and result:
		extras_pilots += ammo.size()
	reason = previous
	return result


func advance_labs(at: int) -> bool:
	var previous := reason
	reason = "industry"
	var result := super.advance_labs(at)
	reason = previous
	return result
