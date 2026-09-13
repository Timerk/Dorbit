class_name PilotStore
extends RefCounted
## One server-owned ledger for the private group. Never creates or repairs saves implicitly.

const MAX_CREDITS: int = 2_000_000_000
var path: String
var error: String = ""
var pilots: Dictionary = {}
var saved_text: String
var locked: bool = false
var failed: bool = false


static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 32:
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true


static func valid_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


func open(directory: String) -> bool:
	if directory.is_empty() or not directory.is_absolute_path():
		return fail("DORBIT_DATA_DIR must be an absolute path to a provisioned directory.")
	path = directory.path_join("pilots.json")
	if DirAccess.make_dir_absolute(path + ".lock") != OK:
		return fail("Cannot acquire pilots.json.lock. Check permissions or recover a stale lock while the server is stopped.")
	locked = true
	for temporary in [path + ".tmp", path + ".bak.tmp"]:
		if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary):
			return fail("Interrupted save found: " + temporary + ". Preserve and recover it before starting.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fail("Cannot read pilots.json. Provision or recover it before starting.")
	saved_text = file.get_as_text()
	var json := JSON.new()
	var data: Variant = json.data if json.parse(saved_text) == OK else null
	if not data is Dictionary or data.get("version") != 1 or not data.get("pilots") is Dictionary or data["pilots"].is_empty():
		return fail("Invalid pilots.json schema. Original file preserved.")
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
	pilots = data["pilots"]
	return true


func verifies(id: String, nonce: PackedByteArray, proof: PackedByteArray) -> bool:
	if failed or not pilots.has(id) or nonce.size() != 32 or proof.size() != 32:
		return false
	var expected := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, str(pilots[id]["verifier"]).hex_decode(), nonce)
	return Crypto.new().constant_time_compare(expected, proof)


# Commit all shares of a kill together, before combat publishes the new balances.
func commit(balances: Dictionary) -> bool:
	if failed or not locked:
		return false
	var next := pilots.duplicate(true)
	for id: String in balances:
		var amount: Variant = balances[id]
		if not next.has(id) or not amount is int or amount < 0 or amount > MAX_CREDITS:
			return fail("Invalid server wallet update.")
		next[id]["credits"] = amount
	var current := FileAccess.open(path, FileAccess.READ)
	if current == null or current.get_as_text() != saved_text:
		return fail("pilots.json changed or became unreadable while running. Save preserved; stop and recover.")
	current.close()
	var text := JSON.stringify({"version": 1, "pilots": next}, "\t") + "\n"
	if not replace_file(path + ".bak", saved_text) or not replace_file(path, text):
		return false
	pilots = next
	saved_text = text
	return true


func replace_file(destination: String, text: String) -> bool:
	var temporary := destination + ".tmp"
	# A leftover temporary file is evidence of an interrupted save, for operator recovery.
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary):
		return fail("Save temporary path already exists: " + temporary)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return fail("Cannot write save temporary file: " + temporary)
	file.store_string(text)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK or FileAccess.get_file_as_string(temporary) != text:
		return fail("Save write failed. Original and temporary files preserved.")
	if DirAccess.rename_absolute(temporary, destination) != OK:
		return fail("Save replacement failed. Original and temporary files preserved.")
	return true


func fail(message: String) -> bool:
	error = message
	failed = true
	return false


func close() -> void:
	if locked:
		DirAccess.remove_absolute(path + ".lock")
		locked = false
