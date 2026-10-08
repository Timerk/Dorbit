class_name PilotStore
extends RefCounted
## One server-owned ledger for the private group. Never creates or repairs saves implicitly.

const MAX_CREDITS: int = 2_000_000_000
const PREVIEW_CREDIT_GRANT: int = 100_000_000
var path: String
var error: String = ""
var pilots: Dictionary = {}
var saved_text: String
var locked: bool = false
var failed: bool = false
var next_lab_due: int = 0


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
	file.close()
	var json := JSON.new()
	var data: Variant = json.data if json.parse(saved_text) == OK else null
	if not data is Dictionary or not Skylab.integer(data.get("version"), 1, 6) or not data.get("pilots") is Dictionary or data["pilots"].is_empty():
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
			for field in ["required", "reward", "progress"]:
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
		elif not Ammunition.valid(pilot.get("ammo")):
			return fail("Invalid pilot ammunition. Original file preserved.")
		for kind: String in pilot["ammo"]:
			pilot["ammo"][kind] = int(pilot["ammo"][kind])
		if not pilot.has("boosts") and data["version"] < 6:
			pilot["boosts"] = ResourceBoosts.empty_holds(pilot["equipment"])
		elif not ResourceBoosts.valid(pilot.get("boosts"), pilot["equipment"]):
			return fail("Invalid pilot resource boosts. Original file preserved.")
		if data["version"] < 6:
			# Main's schema 5 contains boosts; the earlier Skylab preview's schema 5
			# contains industry. Preserve either layout and convert the retired wallet once.
			if pilot.has("skylab"):
				if not Skylab.migrate_credits(pilot): return fail("Invalid legacy Skylab or credit conversion overflow. Original file preserved.")
			else:
				if pilot.has("uridium") or pilot.has("premium"): return fail("Unexpected industry fields. Original file preserved.")
				pilot["skylab"] = Skylab.bootstrap(Skylab.now())
				pilot["premium"] = false
		if pilot.has("uridium") or not pilot.get("premium") is bool or not Skylab.valid(pilot.get("skylab"), pilot["equipment"]):
			return fail("Invalid pilot Skylab state. Original file preserved.")
		Skylab.normalize(pilot["skylab"])
	pilots = data["pilots"]
	if data["version"] < 6:
		if not persist(pilots): return false
		# Newly bootstrapped labs have no earlier industry to catch up. Keep the
		# migration backup intact until the first normal command or scheduled tick.
		schedule_labs(Skylab.now())
		return true
	return advance_labs(Skylab.now())


func verifies(id: String, nonce: PackedByteArray, proof: PackedByteArray) -> bool:
	if failed or not pilots.has(id) or nonce.size() != 32 or proof.size() != 32:
		return false
	var expected := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, str(pilots[id]["verifier"]).hex_decode(), nonce)
	return Crypto.new().constant_time_compare(expected, proof)


# Commit all shares of a kill together, before combat publishes the new balances.
func commit(balances: Dictionary, contracts: Dictionary = {}, cargo: Dictionary = {}, ammo: Dictionary = {}, boosts: Dictionary = {}) -> bool:
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
	return persist(next)


# The persisted sequence rejects every old request, including after a reconnect or restart.
# Only successful changes advance it; distinct station actions use the next sequence.
func transact(id: String, sequence: int, action: String, subject: String, ship: String, slot: String, allow_preview_credits: bool = false, active_boosts: Variant = null) -> String:
	if failed or not locked or not pilots.has(id):
		return "Persistence unavailable."
	if not advance_lab(id, Skylab.now()):
		return "Persistence unavailable."
	if action == "test_credits" and not allow_preview_credits:
		return "Test credits are unavailable for this pilot on this server."
	var next := pilots.duplicate(true)
	var pilot: Dictionary = next[id]
	var previous_credits: int = pilot["credits"]
	var equipment: Dictionary = pilot["equipment"]
	if active_boosts != null:
		pilot["boosts"][equipment["active_ship"]] = active_boosts.duplicate(true)
		if not ResourceBoosts.valid(pilot["boosts"], equipment):
			fail("Invalid server boost transaction.")
			return "Persistence unavailable."
	if sequence <= equipment["revision"]:
		return "Request already processed. Inventory refreshed."
	if sequence != equipment["revision"] + 1 or sequence > MAX_CREDITS:
		return "Inventory changed. Review it and try again."
	if action == "buy_ammo":
		var parts := subject.split(":")
		if parts.size() != 2 or not ship.is_empty() or not slot.is_empty() or parts[1].length() > 5 or not parts[1].is_valid_int():
			return "Invalid ammunition purchase."
		var kind: String = parts[0]
		var blocker := Ammunition.purchase_blocker(kind)
		if not blocker.is_empty():
			return blocker
		var batches := parts[1].to_int()
		if batches < 1 or batches > Ammunition.MAX_PURCHASE_BATCHES:
			return "Invalid ammunition quantity."
		var shots := batches * Ammunition.BATCH_SIZE
		var price: int = Ammunition.TYPES[kind]["price"] * batches
		if pilot["credits"] < price:
			return "Insufficient credits. Need %d CR." % price
		if shots > Ammunition.MAX_SHOTS - int(pilot["ammo"][kind]):
			return "Ammunition limit reached."
		pilot["ammo"][kind] += shots
		pilot["credits"] -= price
	elif action == "buy":
		# Legacy model-only requests buy one; model:quantity buys one atomic batch.
		var parts := subject.split(":")
		var model: String = parts[0]
		if parts.size() > 2 or not ship.is_empty() or not slot.is_empty():
			return "Invalid equipment purchase."
		var amount := 1
		if parts.size() == 2:
			if parts[1].length() > 3 or not parts[1].is_valid_int():
				return "Invalid purchase quantity."
			amount = parts[1].to_int()
			if amount < 1 or amount > Equipment.MAX_PURCHASE_QUANTITY:
				return "Invalid purchase quantity."
		var blocker := Equipment.purchase_blocker(model)
		if not blocker.is_empty():
			return blocker
		var price: int = Equipment.MODELS[model]["price"] * amount
		if pilot["credits"] < price:
			return "Insufficient credits. Need %d CR." % price
		for index in range(amount):
			var identifier := "purchase-%d" % sequence if index == 0 else "purchase-%d-%d" % [sequence, index + 1]
			if equipment["items"].has(identifier):
				fail("Equipment item ID conflicts with its transaction sequence.")
				return "Persistence unavailable."
			equipment["items"][identifier] = {"model": model, "ship": "", "slot": ""}
		pilot["credits"] -= price
	elif action == "buy_ship":
		if not ShipCatalog.MODELS.has(subject) or not ship.is_empty() or not slot.is_empty():
			return "Unknown ship model."
		if not ShipCatalog.owned_id(equipment, subject).is_empty():
			return "You already own this ship."
		var price := ShipCatalog.price(subject)
		if pilot["credits"] < price:
			return "Insufficient credits. Need %d CR." % price
		var identifier := "ship-%d" % sequence
		if equipment["ships"].has(identifier):
			return "Ship ID conflicts with its transaction sequence."
		pilot["credits"] -= price
		equipment["ships"][identifier] = subject
		pilot["cargo"][identifier] = {}
		pilot["boosts"][identifier] = {}
	elif action == "switch_ship":
		if not equipment["ships"].has(subject) or not ship.is_empty() or not slot.is_empty():
			return "You do not own that ship."
		if equipment["active_ship"] == subject:
			return "Ship is already active."
		equipment["active_ship"] = subject
	elif action == "test_credits":
		if not subject.is_empty() or not ship.is_empty() or not slot.is_empty():
			return "Invalid test credit request."
		if pilot["credits"] == MAX_CREDITS:
			return "Credit limit reached."
		pilot["credits"] = mini(MAX_CREDITS, pilot["credits"] + PREVIEW_CREDIT_GRANT)
	elif action == "sell":
		# A resource:quantity subject sells a selection; legacy subjects sell the whole type.
		var parts := subject.split(":")
		var resource: String = parts[0]
		if not ship.is_empty() or not slot.is_empty() or parts.size() > 2 or (resource != "all" and not CargoResources.TYPES.has(resource)):
			return "Unknown resource sale."
		var hold: Dictionary = pilot["cargo"][equipment["active_ship"]]
		var sold := hold.duplicate() if resource == "all" else ({resource: hold[resource]} if hold.has(resource) else {})
		if parts.size() == 2:
			if resource == "all" or not parts[1].is_valid_int() or parts[1].length() > 10:
				return "Invalid sale quantity."
			var amount := parts[1].to_int()
			if amount < 1 or amount > int(hold.get(resource, 0)):
				return "Invalid sale quantity."
			sold = {resource: amount}
		if sold.is_empty():
			return "No resources to sell."
		var proceeds := CargoResources.value(sold)
		if proceeds > MAX_CREDITS - pilot["credits"]:
			return "Sale exceeds the credit limit. Free wallet space first."
		pilot["credits"] += proceeds
		for sold_resource: String in sold:
			hold[sold_resource] -= sold[sold_resource]
			if hold[sold_resource] == 0:
				hold.erase(sold_resource)
	elif action in ["refine", "boost", "replace_boost"]:
		var parts := subject.split(":")
		if parts.size() != 2 or not parts[1].is_valid_int() or parts[1].length() > 4 or not slot.is_empty():
			return "Invalid resource quantity."
		var amount := parts[1].to_int()
		var hold: Dictionary = pilot["cargo"][equipment["active_ship"]]
		var blocker: String
		if action == "refine":
			if not ship.is_empty():
				return "Invalid refining request."
			blocker = ResourceBoosts.refine(hold, parts[0], amount)
		else:
			blocker = ResourceBoosts.apply(hold, pilot["boosts"][equipment["active_ship"]], ship, parts[0], amount, action == "replace_boost")
		if not blocker.is_empty():
			return blocker
	elif action == "fit":
		var blocker := Equipment.fitting_blocker(equipment, subject, ship, slot)
		if not blocker.is_empty():
			return blocker
		equipment["items"][subject]["ship"] = ship
		equipment["items"][subject]["slot"] = slot
	else:
		return "Unknown station action."
	equipment["revision"] = sequence
	if not persist(next):
		return "Persistence unavailable."
	if action == "test_credits":
		return "Preview: added %d test credits." % (pilot["credits"] - previous_credits)
	if action == "buy_ammo":
		return "Purchased %d %s shots." % [subject.get_slice(":", 1).to_int() * Ammunition.BATCH_SIZE, subject.get_slice(":", 0)]
	if action == "sell":
		return "Resources sold. +%d credits." % (pilot["credits"] - previous_credits)
	if action == "buy_ship":
		return "Ship purchased with an empty fitting. Activate it in Ship equipment."
	if action == "switch_ship":
		return "Ship activated. Equipment and cargo stay with their ships."
	if action == "refine":
		return "Refining complete. Ingredients consumed and output added to cargo."
	if action in ["boost", "replace_boost"]:
		return "Resource boost applied."
	if action == "buy" and subject.contains(":") and subject.get_slice(":", 1).to_int() > 1:
		return "Purchased %d items. Items are in storage." % subject.get_slice(":", 1).to_int()
	return "Purchased. Item is in storage." if action == "buy" else "Fitting saved."


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
func transact_lab(id: String, sequence: int, action: String, payload: Dictionary, at: int) -> String:
	if not advance_lab(id, at):
		return "Persistence unavailable."
	if action == "snapshot":
		return ""
	var revision := int(pilots[id]["equipment"]["revision"])
	if sequence <= revision:
		return "Request already processed. Skylab refreshed."
	if sequence != revision + 1 or sequence > MAX_CREDITS:
		return "Inventory changed. Review it and try again."
	var next := pilots.duplicate(true)
	var result := Skylab.command(next[id], sequence, action, payload, at)
	if next[id] != pilots[id]:
		next[id]["equipment"]["revision"] = sequence
		if not Skylab.valid(next[id]["skylab"], next[id]["equipment"]) or not CargoResources.valid(next[id]["cargo"], next[id]["equipment"]):
			fail("Invalid server Skylab update.")
			return "Persistence unavailable."
		if not persist(next):
			return "Persistence unavailable."
	schedule_labs(at)
	return result


func persist(next: Dictionary) -> bool:
	if failed or not locked:
		return false
	var current := FileAccess.open(path, FileAccess.READ)
	if current == null or current.get_as_text() != saved_text:
		return fail("pilots.json changed or became unreadable while running. Save preserved; stop and recover.")
	current.close()
	var text := JSON.stringify({"version": 6, "pilots": next}, "\t") + "\n"
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
