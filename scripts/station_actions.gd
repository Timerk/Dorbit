class_name StationActions
extends RefCounted
## Economy rules for one station action, applied to the copied pilot record of
## a PilotStore transaction. The store owns sequencing, validation and saving.

# A purchase ID collision means the ledger is inconsistent; the store fails on it.
const ITEM_ID_CONFLICT := "Equipment item ID conflicts with its transaction sequence."


# Returns a blocker, or an empty string after changing `pilot`. `previous` is the
# saved record, unchanged. A blocked action may leave `pilot` partly changed.
static func apply(pilot: Dictionary, previous: Dictionary, sequence: int, action: String,
		subject: String, ship: String, slot: String) -> String:
	match action:
		"buy_ammo": return buy_ammo(pilot, subject, ship, slot)
		"buy": return buy(pilot, sequence, subject, ship, slot)
		"buy_ship": return buy_ship(pilot, sequence, subject, ship, slot)
		"switch_ship": return switch_ship(pilot, subject, ship, slot)
		"test_credits": return test_credits(pilot, subject, ship, slot)
		"test_research": return test_research(pilot, subject, ship, slot)
		"sell": return sell(pilot, subject, ship, slot)
		"refine", "boost", "replace_boost": return refine_or_boost(pilot, action, subject, ship, slot)
		"fit": return fit(pilot, previous, subject, ship, slot)
		"research": return research(pilot, subject, ship, slot)
		"research_reset": return research_reset(pilot, subject, ship, slot)
		"story_deliver", "story_skip": return story(pilot, action, subject, ship, slot)
		"configure_extra": return configure_extra(pilot, subject, ship, slot)
	return "Unknown station action."


# The confirmation for an action that `apply` accepted and the store saved.
static func result(pilot: Dictionary, action: String, subject: String, previous_credits: int,
		previous_points: int, previous_story: Dictionary = {}) -> String:
	var equipment: Dictionary = pilot["equipment"]
	if action in ["story_deliver", "story_skip"]:
		var step := Story.current(previous_story)
		var reward := Story.advance(previous_story, "deliver", step["required"]) if action == "story_deliver" else Story.skip(previous_story)
		var notice := "Delivered %s." % CargoResources.describe({step["resource"]: step["required"]}) if action == "story_deliver" else "Prologue skipped."
		return "%s %s." % [notice, Story.reward_text(reward["credits"], reward["research"])]
	if action == "test_credits":
		return "Preview: added %d test credits." % (pilot["credits"] - previous_credits)
	if action == "test_research":
		return "Preview: added %d research points." % (int(Research.state(equipment)["points"]) - previous_points)
	if action == "configure_extra":
		return "Extra settings saved."
	if action == "research":
		return "%s researched to level %d." % [Research.SKILLS[subject]["name"], Research.level(Research.state(equipment), subject)]
	if action == "research_reset":
		return "Skill tree reset. Research points refunded; %d available." % Research.state(equipment)["points"]
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


static func buy_ammo(pilot: Dictionary, subject: String, ship: String, slot: String) -> String:
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
	var price: int = Ammunition.types()[kind]["price"] * batches
	if pilot["credits"] < price:
		return "Insufficient credits. Need %d CR." % price
	if shots > Ammunition.MAX_SHOTS - int(pilot["ammo"][kind]):
		return "Ammunition limit reached."
	pilot["ammo"][kind] += shots
	pilot["credits"] -= price
	return ""


static func buy(pilot: Dictionary, sequence: int, subject: String, ship: String, slot: String) -> String:
	var equipment: Dictionary = pilot["equipment"]
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
			return ITEM_ID_CONFLICT
		equipment["items"][identifier] = {"model": model, "ship": "", "slot": ""}
	pilot["credits"] -= price
	return ""


static func buy_ship(pilot: Dictionary, sequence: int, subject: String, ship: String, slot: String) -> String:
	var equipment: Dictionary = pilot["equipment"]
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
	return ""


static func switch_ship(pilot: Dictionary, subject: String, ship: String, slot: String) -> String:
	var equipment: Dictionary = pilot["equipment"]
	if not equipment["ships"].has(subject) or not ship.is_empty() or not slot.is_empty():
		return "You do not own that ship."
	if equipment["active_ship"] == subject:
		return "Ship is already active."
	equipment["active_ship"] = subject
	return ""


static func test_credits(pilot: Dictionary, subject: String, ship: String, slot: String) -> String:
	if not subject.is_empty() or not ship.is_empty() or not slot.is_empty():
		return "Invalid test credit request."
	if pilot["credits"] == PilotStore.MAX_CREDITS:
		return "Credit limit reached."
	pilot["credits"] = mini(PilotStore.MAX_CREDITS, pilot["credits"] + PilotStore.PREVIEW_CREDIT_GRANT)
	return ""


static func test_research(pilot: Dictionary, subject: String, ship: String, slot: String) -> String:
	var equipment: Dictionary = pilot["equipment"]
	if not subject.is_empty() or not ship.is_empty() or not slot.is_empty():
		return "Invalid test research request."
	if int(Research.state(equipment)["points"]) == Research.MAX_POINTS:
		return "Research point limit reached."
	Research.add_points(equipment, PilotStore.PREVIEW_RESEARCH_GRANT)
	return ""


static func sell(pilot: Dictionary, subject: String, ship: String, slot: String) -> String:
	var equipment: Dictionary = pilot["equipment"]
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
	if proceeds > PilotStore.MAX_CREDITS - pilot["credits"]:
		return "Sale exceeds the credit limit. Free wallet space first."
	pilot["credits"] += proceeds
	for sold_resource: String in sold:
		hold[sold_resource] -= sold[sold_resource]
		if hold[sold_resource] == 0:
			hold.erase(sold_resource)
	return ""


static func refine_or_boost(pilot: Dictionary, action: String, subject: String, ship: String, slot: String) -> String:
	var equipment: Dictionary = pilot["equipment"]
	var parts := subject.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int() or parts[1].length() > 4 or not slot.is_empty():
		return "Invalid resource quantity."
	var amount := parts[1].to_int()
	var hold: Dictionary = pilot["cargo"][equipment["active_ship"]]
	if action == "refine":
		if not ship.is_empty():
			return "Invalid refining request."
		return ResourceBoosts.refine(hold, parts[0], amount)
	var boosts: Dictionary = pilot["boosts"][equipment["active_ship"]]
	return ResourceBoosts.apply(hold, boosts, ship, parts[0], amount, action == "replace_boost")


static func fit(pilot: Dictionary, previous: Dictionary, subject: String, ship: String, slot: String) -> String:
	var equipment: Dictionary = pilot["equipment"]
	var blocker := Equipment.fitting_blocker(equipment, subject, ship, slot)
	if not blocker.is_empty():
		return blocker
	Equipment.move(equipment, subject, ship, slot)
	if not CargoResources.valid(pilot["cargo"], equipment):
		return "Sell excess cargo before removing cargo capacity. No items were moved."
	# Only a hull that loses capacity must fit its cargo; compare the saved fitting.
	for cargo_ship: String in equipment["ships"]:
		var capacity := CargoResources.capacity(equipment, cargo_ship)
		var reduced := capacity < CargoResources.capacity(previous["equipment"], cargo_ship)
		if reduced and CargoResources.units(pilot["cargo"][cargo_ship]) > capacity:
			return "Sell excess cargo before removing cargo capacity. No items were moved."
	if not Skylab.valid(pilot["skylab"], equipment):
		return "Wait for the Skylab shipment before removing cargo capacity. No items were moved."
	return ""


static func research(pilot: Dictionary, subject: String, ship: String, slot: String) -> String:
	if not ship.is_empty() or not slot.is_empty():
		return "Invalid research request."
	return Research.learn(pilot["equipment"], pilot["skylab"]["inventory"], subject)


static func research_reset(pilot: Dictionary, subject: String, ship: String, slot: String) -> String:
	var equipment: Dictionary = pilot["equipment"]
	if not subject.is_empty() or not ship.is_empty() or not slot.is_empty():
		return "Invalid research reset."
	var state := Research.state(equipment)
	if Research.spent(state) == 0:
		return "No skills to reset."
	var price := Research.reset_price(state)
	if pilot["credits"] < price:
		return "Insufficient credits. Need %d CR." % price
	# Reset first, then check capacity: a blocker discards the whole copied record.
	Research.reset(equipment)
	pilot["credits"] -= price
	for cargo_ship: String in equipment["ships"]:
		if CargoResources.units(pilot["cargo"][cargo_ship]) > CargoResources.capacity(equipment, cargo_ship):
			return "Sell excess cargo before resetting Cargo Compression. Skills unchanged."
	if not Skylab.valid(pilot["skylab"], equipment):
		return "Wait for the Skylab shipment before resetting Cargo Compression. Skills unchanged."
	return ""


static func story(pilot: Dictionary, action: String, subject: String, ship: String, slot: String) -> String:
	if not subject.is_empty() or not ship.is_empty() or not slot.is_empty():
		return "Invalid story request."
	var equipment: Dictionary = pilot["equipment"]
	var state := Story.state(equipment)
	var step := Story.current(state)
	var reward := Story.skip(state)
	if step.is_empty():
		return "Prologue already complete."
	if action == "story_deliver":
		if step["type"] != "deliver":
			return "Nothing to deliver for this step."
		var hold: Dictionary = pilot["cargo"][equipment["active_ship"]]
		var resource: String = step["resource"]
		var amount: int = step["required"]
		if int(hold.get(resource, 0)) < amount:
			return "Need %s in your active ship's cargo." % CargoResources.describe({resource: amount})
		hold[resource] -= amount
		if hold[resource] == 0:
			hold.erase(resource)
		reward = Story.advance(state, "deliver", amount)
	if reward["credits"] > PilotStore.MAX_CREDITS - pilot["credits"]:
		return "Reward exceeds the credit limit. Free wallet space first."
	pilot["credits"] += reward["credits"]
	Research.add_points(equipment, reward["research"])
	equipment["story"] = reward["story"]
	return ""

static func configure_extra(pilot: Dictionary, subject: String, ship: String, slot: String) -> String:
	var item: Dictionary = pilot["equipment"]["items"].get(subject, {})
	var configurable: bool = not item.is_empty() and Equipment.MODELS[item["model"]].get("family", "") in ["ammo", "generators", "repair-auto"]
	if not configurable or not ship in ["on", "off"]:
		return "Invalid extra configuration."
	if (item["model"] == "ammo-cpu" and not slot in ["x1", "x2", "x3"]) or (item["model"] != "ammo-cpu" and not slot.is_empty()):
		return "Invalid automatic ammunition type."
	item["enabled"] = ship == "on"
	if item["model"] == "ammo-cpu":
		item["ammo_type"] = slot
	return ""
