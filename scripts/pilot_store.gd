class_name PilotStore
extends RefCounted
## One server-owned ledger for the private group. Never creates or repairs saves implicitly.

const MAX_CREDITS: int = 2_000_000_000
const PREVIEW_CREDIT_GRANT: int = 100_000_000
# Enough to fill the research spending cap once; resets refund spent points.
const PREVIEW_RESEARCH_GRANT: int = Research.SPENT_CAP
const PREVIEW_LAB_ACTIONS := ["test_skylab_max", "test_skylab_reset"]
# Live journal verification reads only the header and this many final bytes.
const JOURNAL_TAIL_BYTES: int = 512
var path: String
var error: String = ""
var pilots: Dictionary = {}
var saved_text: String
var saved_modified_time: int = 0
var saved_bytes: int = -1
var locked: bool = false
var failed: bool = false
var next_lab_due: int = 0
var journal_metadata: Dictionary = {}
var journal_header: PackedByteArray
var journal_tail: PackedByteArray
var journal_sequence: int = 0
var checkpoint_sequence: int = 0
var journal_file: FileAccess
var journal_modified_time: int = 0
var journal_bytes: int = 0
var combat_tick_active: bool = false
var combat_tick_verified: bool = false
# Optional benchmark observer. Normal sessions take no clocks or timing samples.
var replacement_trace: Callable


static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 32:
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true


# Economy actions check the acting wallet before saving so open() can always reload it.
static func valid_credits(value: Variant) -> bool:
	return value is int and value >= 0 and value <= MAX_CREDITS


static func valid_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


func open(directory: String) -> bool:
	if failed: return false
	if locked: return fail("Pilot store already owns a ledger lock.")
	journal_sequence = 0
	checkpoint_sequence = 0
	if directory.is_empty() or not directory.is_absolute_path():
		return fail("DORBIT_DATA_DIR must be an absolute path to a provisioned directory.")
	path = directory.path_join("pilots.json")
	if DirAccess.make_dir_absolute(path + ".lock") != OK:
		return fail("Cannot acquire pilots.json.lock. Check permissions or recover a stale lock while the server is stopped.")
	locked = true
	for temporary in [path + ".tmp", path + ".bak.tmp", path + ".combat.tmp"]:
		if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary):
			return fail("Interrupted save found: " + temporary + ". Preserve and recover it before starting.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fail("Cannot read pilots.json. Provision or recover it before starting.")
	saved_text = file.get_as_text()
	file.close()
	remember_snapshot()
	var json := JSON.new()
	var data: Variant = json.data if json.parse(saved_text) == OK else null
	if not data is Dictionary or not Skylab.integer(data.get("version"), 1, 8) or not data.get("pilots") is Dictionary or data["pilots"].is_empty():
		return fail("Invalid pilots.json schema. Original file preserved.")
	if data["version"] < 8 and (FileAccess.file_exists(path + ".combat") or DirAccess.dir_exists_absolute(path + ".combat")):
		return fail("Unexpected combat journal beside a legacy ledger. Preserve and recover both files.")
	if data["version"] == 8 and not CombatJournal.valid_metadata(data.get("combat_journal")):
		return fail("Invalid combat journal metadata. Original file preserved.")
	for id: Variant in data["pilots"]:
		var pilot: Variant = data["pilots"][id]
		if not id is String or not valid_id(id) or not pilot is Dictionary:
			return fail("Invalid pilot record. Original file preserved.")
		var verifier: Variant = pilot.get("verifier")
		var credits: Variant = pilot.get("credits")
		if not verifier is String or not valid_hex(verifier):
			return fail("Invalid pilot verifier. Original file preserved.")
		if not (credits is float or credits is int) or not is_finite(credits) or credits < 0 or credits > MAX_CREDITS or credits != floor(credits):
			return fail("Invalid pilot credits. Original file preserved.")
		pilot["credits"] = int(credits)
		var contracts: Variant = pilot.get("contracts", {})
		if pilot.has("contract"):
			var legacy: Variant = pilot["contract"]
			if pilot.has("contracts") or not HuntingContracts.valid(legacy):
				return fail("Invalid legacy hunting contract. Original file preserved.")
			if not legacy.is_empty():
				contracts = {legacy["type"]: legacy}
		if not HuntingContracts.valid_collection(contracts):
			return fail("Invalid hunting contracts. Original file preserved.")
		for contract: Dictionary in contracts.values():
			for field in ["required", "reward", "progress", "research"]:
				if contract.has(field):
					contract[field] = int(contract[field])
		pilot.erase("contract")
		pilot["contracts"] = contracts
		if data["version"] == 1:
			if pilot.has("equipment"):
				return fail("Unexpected equipment in legacy save. Original file preserved.")
			pilot["equipment"] = Equipment.starter()
		elif not Equipment.valid(pilot.get("equipment")):
			return fail("Invalid pilot equipment. Original file preserved.")
		pilot["equipment"]["revision"] = int(pilot["equipment"]["revision"])
		if pilot["equipment"].has("research"):
			Research.normalize(pilot["equipment"]["research"])
		if pilot["equipment"].has("story"):
			Story.normalize(pilot["equipment"]["story"])
		if pilot["equipment"].has("gates"):
			GalaxyGates.normalize(pilot["equipment"]["gates"])
		if data["version"] < 3:
			if pilot.has("cargo"):
				return fail("Unexpected cargo in legacy save. Original file preserved.")
			pilot["cargo"] = CargoResources.empty_holds(pilot["equipment"])
		elif not CargoResources.valid(pilot.get("cargo"), pilot["equipment"]):
			return fail("Invalid pilot cargo. Original file preserved.")
		for hold: Dictionary in pilot["cargo"].values():
			for resource: String in hold:
				hold[resource] = int(hold[resource])
		# Schema 4 existed with ammunition or resource boosts on separate branches.
		if data["version"] == 4 and not pilot.has("ammo") and not pilot.has("boosts"):
			return fail("Missing schema-4 progression. Original file preserved.")
		if data["version"] < 4 and pilot.has("ammo"):
			return fail("Unexpected ammunition in legacy save. Original file preserved.")
		if not pilot.has("ammo") and data["version"] < 5:
			pilot["ammo"] = Ammunition.starter()
		elif not Ammunition.valid(pilot.get("ammo")) and not (data["version"] < 7 and Ammunition.valid(pilot.get("ammo"), true)):
			return fail("Invalid pilot ammunition. Original file preserved.")
		if data["version"] < 7 and pilot["ammo"].size() == Ammunition.TYPES.size():
			for kind: String in Ammunition.ROCKETS:
				pilot["ammo"][kind] = Ammunition.starter()[kind]
		for kind: String in pilot["ammo"]:
			pilot["ammo"][kind] = int(pilot["ammo"][kind])
		if not pilot.has("boosts") and data["version"] < 6:
			pilot["boosts"] = ResourceBoosts.empty_holds(pilot["equipment"])
		elif not ResourceBoosts.valid(pilot.get("boosts"), pilot["equipment"]):
			return fail("Invalid pilot resource boosts. Original file preserved.")
		if data["version"] < 7:
			# Accept either schema-6 branch layout. Convert only older industry wallets.
			if pilot.has("skylab"):
				if data["version"] < 6 and not Skylab.migrate_credits(pilot): return fail("Invalid legacy Skylab or credit conversion overflow. Original file preserved.")
			else:
				if pilot.has("uridium") or pilot.has("premium"): return fail("Unexpected industry fields. Original file preserved.")
				pilot["skylab"] = Skylab.bootstrap(Skylab.now())
				pilot["premium"] = false
		if pilot.has("uridium") or not pilot.get("premium") is bool or not Skylab.valid(pilot.get("skylab"), pilot["equipment"]):
			return fail("Invalid pilot Skylab state. Original file preserved.")
		Skylab.normalize(pilot["skylab"])
	pilots = data["pilots"]
	if data["version"] == 8:
		journal_metadata = data["combat_journal"]
		checkpoint_sequence = int(journal_metadata["sequence"])
		# Take the time before reading, so a concurrent edit fails the first check.
		var modified_time := FileAccess.get_modified_time(path + ".combat")
		var journal := FileAccess.get_file_as_bytes(path + ".combat")
		journal_sequence = CombatJournal.replay(journal.get_string_from_utf8(), journal_metadata, pilots)
		if journal_sequence < 0: return fail("Missing, mismatched or damaged combat journal. Preserve and recover both files.")
		remember_journal(journal, modified_time)
	else:
		journal_metadata = {"id": Crypto.new().generate_random_bytes(16).hex_encode(), "sequence": 0}
		var header := CombatJournal.header(journal_metadata)
		if not replace_file(path + ".combat", header): return false
		remember_journal(header.to_utf8_buffer(), FileAccess.get_modified_time(path + ".combat"))
		if data["version"] == 7:
			for pilot: Dictionary in pilots.values(): Skylab.advance(pilot, Skylab.now())
		if not persist(pilots): return false
		# Newly bootstrapped labs have no earlier industry to catch up. Keep the
		# migration backup intact until the first normal command or scheduled tick.
		schedule_labs(Skylab.now())
		return true
	return advance_labs(Skylab.now())


# Flush and verify one small transaction before the caller changes ammo or damage.
# Equipment, cargo, wallets and industry are neither copied nor serialized here.
func commit_combat(ammo: Dictionary, boosts: Dictionary = {}) -> bool:
	if failed or not locked: return false
	if not CombatJournal.valid_updates(pilots, ammo, boosts): return fail("Invalid server combat update.")
	if journal_sequence >= CombatJournal.MAX_SEQUENCE: return fail("Combat journal sequence exhausted.")
	var entry := CombatJournal.record(journal_sequence + 1, ammo, boosts)
	var entry_bytes := entry.to_utf8_buffer()
	# Bound replay and live verification cost. Ordinary economy/industry saves
	# also checkpoint pending combat; this limit covers extended quiet sessions.
	if journal_bytes + entry_bytes.size() > CombatJournal.MAX_BYTES:
		if not persist(pilots): return false
	# All pilot volleys in one synchronous physics pass share the integrity read.
	# Every individual debit still writes, flushes and verifies before its damage.
	if not combat_tick_active or not combat_tick_verified:
		if not unchanged_files(): return false
		combat_tick_verified = combat_tick_active
	var file := journal_file
	# Keep one handle between debits. Reopening a recently written file took
	# 8–20 ms in the Windows benchmark, versus fractions of a ms for flush.
	file.seek_end()
	var start := file.get_position()
	if start != journal_bytes: return fail("Combat journal changed or became unreadable while running. Stop and recover both files.")
	file.store_string(entry)
	file.flush()
	var result := file.get_error()
	file.seek(start)
	var verified := file.get_buffer(entry_bytes.size()).get_string_from_utf8() == entry
	if result != OK or not verified: return fail("Combat journal write failed. Files preserved for recovery.")
	journal_modified_time = FileAccess.get_modified_time(path + ".combat")
	journal_tail.append_array(entry_bytes)
	journal_tail = journal_tail.slice(-JOURNAL_TAIL_BYTES)
	journal_bytes += entry_bytes.size()
	journal_sequence += 1
	CombatJournal.apply_updates(pilots, ammo, boosts)
	return true


func begin_combat_tick() -> void:
	combat_tick_active = true
	combat_tick_verified = false


func end_combat_tick() -> void:
	combat_tick_active = false
	combat_tick_verified = false


func verifies(id: String, nonce: PackedByteArray, proof: PackedByteArray) -> bool:
	if failed or not pilots.has(id) or nonce.size() != 32 or proof.size() != 32:
		return false
	var expected := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, str(pilots[id]["verifier"]).hex_decode(), nonce)
	return Crypto.new().constant_time_compare(expected, proof)


# Commit all shares of a kill together, before combat publishes the new balances.
# Research holds points earned by each pilot in this transaction; stories hold
# each pilot's next chapter position; gates hold each pilot's galaxy gate parts.
func commit(balances: Dictionary, contracts: Dictionary = {}, cargo: Dictionary = {}, ammo: Dictionary = {}, boosts: Dictionary = {}, research: Dictionary = {}, stories: Dictionary = {}, gates: Dictionary = {}) -> bool:
	if failed or not locked:
		return false
	var next := pilots.duplicate(true)
	for id: String in balances:
		var amount: Variant = balances[id]
		if not next.has(id) or not amount is int or amount < 0 or amount > MAX_CREDITS:
			return fail("Invalid server wallet update.")
		next[id]["credits"] = amount
	for id: String in contracts:
		if not next.has(id) or not HuntingContracts.valid_collection(contracts[id]):
			return fail("Invalid server contract update.")
		next[id]["contracts"] = contracts[id].duplicate(true)
	for id: String in cargo:
		if not next.has(id) or not CargoResources.valid(cargo[id], next[id]["equipment"]):
			return fail("Invalid server cargo update.")
		next[id]["cargo"] = cargo[id].duplicate(true)
	for id: String in ammo:
		if not next.has(id) or not Ammunition.valid(ammo[id]):
			return fail("Invalid server ammunition update.")
		next[id]["ammo"] = ammo[id].duplicate(true)
	for id: String in boosts:
		if not next.has(id) or not ResourceBoosts.valid(boosts[id], next[id]["equipment"]):
			return fail("Invalid server boost update.")
		next[id]["boosts"] = boosts[id].duplicate(true)
	for id: String in research:
		var earned: Variant = research[id]
		if not next.has(id) or not earned is int or earned < 0 or earned > 1000:
			return fail("Invalid server research update.")
		Research.add_points(next[id]["equipment"], earned)
	for id: String in stories:
		if not next.has(id) or not Story.valid(stories[id]):
			return fail("Invalid server story update.")
		next[id]["equipment"]["story"] = stories[id].duplicate()
	for id: String in gates:
		if not next.has(id) or not GalaxyGates.valid(gates[id]):
			return fail("Invalid server gate update.")
		next[id]["equipment"]["gates"] = gates[id].duplicate()
	return persist(next)


# Victory rewards for one gate run, saved together for every winner. Each reward
# holds credits, research points, x4 shots and an optional storage item model.
func reward_gate(rewards: Dictionary) -> bool:
	if failed or not locked:
		return false
	var next := pilots.duplicate(true)
	for id: String in rewards:
		var reward: Dictionary = rewards[id]
		if not next.has(id):
			return fail("Invalid server gate reward.")
		var pilot: Dictionary = next[id]
		pilot["credits"] = mini(MAX_CREDITS, int(pilot["credits"]) + int(reward["credits"]))
		Research.add_points(pilot["equipment"], int(reward["research"]))
		pilot["ammo"]["x4"] = mini(Ammunition.MAX_SHOTS, int(pilot["ammo"]["x4"]) + int(reward["x4"]))
		if not str(reward["item"]).is_empty():
			var item_id := "gate-" + Crypto.new().generate_random_bytes(8).hex_encode()
			if pilot["equipment"]["items"].has(item_id):
				return fail("Gate reward item ID conflict.")
			pilot["equipment"]["items"][item_id] = {"model": reward["item"], "ship": "", "slot": ""}
		if not Equipment.valid(pilot["equipment"]) or not Ammunition.valid(pilot["ammo"]):
			return fail("Invalid server gate reward.")
	return persist(next)


# The persisted sequence rejects every old request, including after a reconnect or restart.
# Only successful changes advance it; distinct station actions use the next sequence.
# StationActions owns the per-action economy rules and result messages.
func transact(id: String, sequence: int, action: String, subject: String, ship: String, slot: String,
		allow_preview_tools: bool = false, active_boosts: Variant = null) -> String:
	if failed or not locked or not pilots.has(id):
		return "Persistence unavailable."
	if not advance_lab(id, Skylab.now()):
		return "Persistence unavailable."
	if action == "test_credits" and not allow_preview_tools:
		return "Test credits are unavailable for this pilot on this server."
	if action == "test_research" and not allow_preview_tools:
		return "Test research points are unavailable for this pilot on this server."
	var next := pilots.duplicate(true)
	var pilot: Dictionary = next[id]
	var previous_credits: int = pilot["credits"]
	var previous_story := Story.state(pilot["equipment"]).duplicate()
	var equipment: Dictionary = pilot["equipment"]
	var previous_points := int(Research.state(equipment)["points"])
	if active_boosts != null:
		pilot["boosts"][equipment["active_ship"]] = active_boosts.duplicate(true)
		if not ResourceBoosts.valid(pilot["boosts"], equipment):
			fail("Invalid server boost transaction.")
			return "Persistence unavailable."
	if sequence <= equipment["revision"]:
		return "Request already processed. Inventory refreshed."
	if sequence != equipment["revision"] + 1 or sequence > MAX_CREDITS:
		return "Inventory changed. Review it and try again."
	var blocker := StationActions.apply(pilot, pilots[id], sequence, action, subject, ship, slot)
	if blocker == StationActions.ITEM_ID_CONFLICT:
		fail(blocker)
		return "Persistence unavailable."
	if not blocker.is_empty():
		return blocker
	equipment["revision"] = sequence
	if not valid_credits(pilot["credits"]):
		push_error("Rejected %s: credits %s outside the wallet range." % [action, pilot["credits"]])
		return "Transaction rejected. Credits unchanged."
	if not persist(next):
		return "Persistence unavailable."
	return StationActions.result(pilot, action, subject, previous_credits, previous_points, previous_story)


func advance_lab(id: String, at: int) -> bool:
	if failed or not locked or not pilots.has(id):
		return false
	var next := pilots.duplicate(true)
	Skylab.advance(next[id], at)
	if next != pilots and not persist(next):
		return false
	schedule_labs(at)
	return true


func advance_labs(at: int) -> bool:
	if failed or not locked:
		return false
	var next := pilots.duplicate(true)
	for pilot: Dictionary in next.values():
		Skylab.advance(pilot, at)
	if next != pilots and not persist(next):
		return false
	schedule_labs(at)
	return true


func schedule_labs(at: int) -> void:
	next_lab_due = (int(at / 60) + 1) * 60
	for pilot: Dictionary in pilots.values():
		next_lab_due = mini(next_lab_due, Skylab.next_event(pilot["skylab"], next_lab_due))


# Godot executes these commands synchronously on the server thread under its ledger lock.
# The existing persisted inventory sequence is the request ID across all economy actions.
func transact_lab(id: String, sequence: int, action: String, payload: Dictionary, at: int, allow_preview_tools: bool = false) -> String:
	if not advance_lab(id, at):
		return "Persistence unavailable."
	if action == "snapshot":
		return ""
	if action in PREVIEW_LAB_ACTIONS and not allow_preview_tools:
		return "Skylab preview tools are unavailable for this pilot on this server."
	var revision := int(pilots[id]["equipment"]["revision"])
	if sequence <= revision:
		return "Request already processed. Skylab refreshed."
	if sequence != revision + 1 or sequence > MAX_CREDITS:
		return "Inventory changed. Review it and try again."
	var next := pilots.duplicate(true)
	var result: String
	if action == "test_skylab_max":
		Skylab.preview_max(next[id]["skylab"])
		result = "Preview: Skylab maxed with full storage."
	elif action == "test_skylab_reset":
		next[id]["skylab"] = Skylab.preview_reset(next[id]["skylab"], at)
		result = "Preview: Skylab reset to starting levels."
	else:
		result = Skylab.command(next[id], sequence, action, payload, at)
	if next[id] != pilots[id]:
		next[id]["equipment"]["revision"] = sequence
		if not valid_credits(next[id]["credits"]) or not Skylab.valid(next[id]["skylab"], next[id]["equipment"]) or not CargoResources.valid(next[id]["cargo"], next[id]["equipment"]):
			fail("Invalid server Skylab update.")
			return "Persistence unavailable."
		if not persist(next):
			return "Persistence unavailable."
	schedule_labs(at)
	return result


# Preview pilots start each session with a maxed Skylab. No request sequence is consumed.
func preview_max_lab(id: String, at: int) -> bool:
	if not advance_lab(id, at):
		return false
	var next := pilots.duplicate(true)
	Skylab.preview_max(next[id]["skylab"])
	if next != pilots and not persist(next):
		return false
	schedule_labs(at)
	return true


func persist(next: Dictionary) -> bool:
	combat_tick_verified = false
	if failed or not locked:
		return false
	close_journal()
	if not unchanged_files(): return false
	close_journal() # Release the append handle before any atomic replacement.
	var metadata := {"id": journal_metadata["id"], "sequence": journal_sequence}
	var text := JSON.stringify({"version": 8, "combat_journal": metadata, "pilots": next}, "\t") + "\n"
	# The backup must include every flushed combat debit, even when the primary
	# snapshot predates them. Preserve the original bytes during legacy migration.
	var backup := saved_text if checkpoint_sequence == journal_sequence else JSON.stringify({"version": 8, "combat_journal": metadata, "pilots": pilots}, "\t") + "\n"
	if not replace_file(path + ".bak", backup) or not replace_file(path, text): return false
	pilots = next
	saved_text = text
	remember_snapshot()
	journal_metadata = metadata
	checkpoint_sequence = journal_sequence
	var compacted := CombatJournal.header(metadata)
	# Replace only after the snapshot is safe. Old records are harmless on replay
	# if a process stops between these two replacements.
	var compacted_bytes := compacted.to_utf8_buffer()
	if journal_bytes == journal_header.size() and journal_header == compacted_bytes: return true
	if not replace_file(path + ".combat", compacted): return false
	remember_journal(compacted_bytes, FileAccess.get_modified_time(path + ".combat"))
	return true


func unchanged_files() -> bool:
	for temporary in [path + ".tmp", path + ".bak.tmp", path + ".combat.tmp"]:
		if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary):
			return fail("Interrupted save found: " + temporary + ". Preserve and recover it before saving.")
	# Reopening a just-replaced snapshot took 2.5–3.5 ms in the Windows benchmark.
	# Compare contents only when its size or modification second has changed.
	if FileAccess.get_modified_time(path) != saved_modified_time or FileAccess.get_size(path) != saved_bytes:
		var current := FileAccess.open(path, FileAccess.READ_WRITE)
		if current == null or current.get_as_text() != saved_text:
			return fail("pilots.json changed or became unreadable while running. Save preserved; stop and recover.")
		current.close()
		remember_snapshot()
	# Reopening keeps the baseline from the last known contents: a reset here
	# would accept same-size edits made while the handle was closed.
	if journal_file == null:
		journal_file = FileAccess.open(path + ".combat", FileAccess.READ_WRITE)
	if journal_file == null: return fail("Combat journal became unreadable while running. Stop and recover both files.")
	if not FileAccess.file_exists(path + ".combat") or FileAccess.get_modified_time(path + ".combat") != journal_modified_time:
		return fail("Combat journal changed or disappeared while running. Stop and recover both files.")
	# Constant cost regardless of journal size: compare the length, the header and
	# the final bytes. Appends, truncation and rewrites change at least one of
	# them; every record is also checksummed for replay at startup.
	if FileAccess.get_size(path + ".combat") != journal_bytes or journal_file.get_length() != journal_bytes:
		return fail("Combat journal changed or became unreadable while running. Stop and recover both files.")
	journal_file.seek(0)
	var header := journal_file.get_buffer(journal_header.size())
	journal_file.seek(journal_bytes - journal_tail.size())
	if header != journal_header or journal_file.get_buffer(journal_tail.size()) != journal_tail:
		return fail("Combat journal changed or became unreadable while running. Stop and recover both files.")
	return true


# The header is the first line; the tail is a bounded suffix checked live.
func remember_journal(bytes: PackedByteArray, modified_time: int) -> void:
	journal_modified_time = modified_time
	journal_bytes = bytes.size()
	journal_header = bytes.slice(0, bytes.find(10) + 1)
	journal_tail = bytes.slice(-JOURNAL_TAIL_BYTES)


func remember_snapshot() -> void:
	saved_modified_time = FileAccess.get_modified_time(path)
	saved_bytes = FileAccess.get_size(path)


func close_journal() -> void:
	if journal_file != null:
		journal_file.close()
		journal_file = null


func replace_file(destination: String, text: String) -> bool:
	var temporary := destination + ".tmp"
	# A leftover temporary file is evidence of an interrupted save, for operator recovery.
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary):
		return fail("Save temporary path already exists: " + temporary)
	var tracing := replacement_trace.is_valid()
	var marks: PackedInt64Array
	if tracing: marks.append(Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE_READ)
	if tracing: marks.append(Time.get_ticks_usec())
	if file == null:
		return fail("Cannot write save temporary file: " + temporary)
	var bytes := text.to_utf8_buffer()
	if tracing: marks.append(Time.get_ticks_usec())
	file.store_buffer(bytes)
	if tracing: marks.append(Time.get_ticks_usec())
	file.flush()
	var result := file.get_error()
	if tracing: marks.append(Time.get_ticks_usec())
	# Read back through the same handle. Reopening a just-written file took
	# 3–5 ms per replacement in the Windows benchmark, most of a checkpoint.
	file.seek(0)
	var verified := file.get_length() == bytes.size() and file.get_buffer(bytes.size()) == bytes
	if tracing: marks.append(Time.get_ticks_usec())
	file.close()
	if tracing: marks.append(Time.get_ticks_usec())
	if result != OK or not verified:
		if tracing: replacement_trace.call(destination, marks, false)
		return fail("Save write failed. Original and temporary files preserved.")
	var renamed := DirAccess.rename_absolute(temporary, destination)
	if tracing:
		marks.append(Time.get_ticks_usec())
		replacement_trace.call(destination, marks, renamed == OK)
	if renamed != OK:
		return fail("Save replacement failed. Original and temporary files preserved.")
	return true


func fail(message: String) -> bool:
	combat_tick_verified = false
	error = message
	failed = true
	return false


func close() -> bool:
	end_combat_tick()
	if locked:
		if not failed and journal_sequence > checkpoint_sequence and not persist(pilots): push_error(error)
		close_journal()
		DirAccess.remove_absolute(path + ".lock")
		locked = false
	return not failed
