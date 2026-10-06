class_name Equipment
extends RefCounted
## Owned instances have one location: storage or a slot on an owned ship.

# Provisional economy and bonuses; see GAME_PLAN.md.
const MODELS := {
	"laser": {"name": "Pulse laser", "kind": "laser", "price": 3000, "damage": 65.0, "shield": 0.0, "speed": 0.0},
	"shield": {"name": "Shield generator", "kind": "generator", "price": 2400, "damage": 0.0, "shield": 1000.0, "absorption": 0.4, "speed": 0.0},
	"engine": {"name": "Ion engine", "kind": "generator", "price": 2400, "damage": 0.0, "shield": 0.0, "speed": 8.0},
}
# Keep the persisted pathfinder model ID so existing ownership and cargo stay valid.
const STARTER_HULL: float = 116000.0


static func starter() -> Dictionary:
	return {"revision": 0, "active_ship": "starter", "ships": {"starter": "pathfinder"}, "items": {
		"starter-laser": {"model": "laser", "ship": "starter", "slot": "laser1"},
		"starter-shield": {"model": "shield", "ship": "starter", "slot": "generator1"},
		"starter-engine": {"model": "engine", "ship": "starter", "slot": "generator2"},
	}}


static func valid(data: Variant) -> bool:
	if not data is Dictionary or not data.get("ships") is Dictionary or not data.get("items") is Dictionary:
		return false
	var revision: Variant = data.get("revision")
	if not (revision is int or revision is float) or not is_finite(revision) or revision < 0 or revision > PilotStore.MAX_CREDITS or revision != floor(revision):
		return false
	if not data.get("active_ship") is String or not data["ships"].has(data["active_ship"]) or data["ships"].is_empty():
		return false
	for id: Variant in data["ships"]:
		if not id is String or not PilotStore.valid_id(id) or not data["ships"][id] is String or not ShipCatalog.MODELS.has(ShipCatalog.canonical(data["ships"][id])):
			return false
	var occupied: Dictionary = {}
	for id: Variant in data["items"]:
		var item: Variant = data["items"][id]
		if not id is String or not PilotStore.valid_id(id) or not item is Dictionary:
			return false
		if not item.get("model") is String or not MODELS.has(item["model"]) or not item.get("ship") is String or not item.get("slot") is String:
			return false
		if item["ship"] == "" and item["slot"] == "":
			continue
		if not data["ships"].has(item["ship"]):
			return false
		var ship_slots := slots(data, item["ship"])
		if not ship_slots.has(item["slot"]) or ship_slots[item["slot"]] != MODELS[item["model"]]["kind"]:
			return false
		var location: String = item["ship"] + "/" + item["slot"]
		if occupied.has(location):
			return false
		occupied[location] = true
	return true


static func fitting_blocker(data: Dictionary, item_id: String, ship: String, slot: String) -> String:
	if not data["items"].has(item_id):
		return "You do not own that item."
	if ship == "" and slot == "":
		return "Already in storage." if data["items"][item_id]["ship"] == "" else ""
	if not data["ships"].has(ship):
		return "You do not own that ship."
	var ship_slots := slots(data, ship)
	if ship_slots.get(slot) == "extra":
		return "Extra slots are reserved for future equipment."
	if not ship_slots.has(slot) or ship_slots[slot] != MODELS[data["items"][item_id]["model"]]["kind"]:
		return "Incompatible slot. Lasers need laser slots; shields and engines share generator slots."
	for item: Dictionary in data["items"].values():
		if item["ship"] == ship and item["slot"] == slot:
			return "Slot occupied. Remove its item first."
	return ""


static func slots(data: Dictionary, ship: String = "") -> Dictionary:
	return ShipCatalog.slots(data["ships"][data["active_ship"] if ship.is_empty() else ship])


static func stats(data: Dictionary, ship: String = "") -> Dictionary:
	if ship.is_empty():
		ship = data["active_ship"]
	var model: String = ShipCatalog.canonical(data["ships"][ship])
	var hull := ShipCatalog.info(model)
	var speed: float = hull["speed"] * ShipCatalog.SPEED_SCALE
	var result := {"model": model, "hull": float(hull["hull"]), "damage": 0.0, "shield": 0.0, "absorption": 0.0, "speed": speed, "boost": speed + ShipCatalog.BOOST_BONUS}
	for item: Dictionary in data["items"].values():
		if item["ship"] != ship:
			continue
		var item_model: Dictionary = MODELS[item["model"]]
		for stat in ["damage", "shield", "speed"]:
			result[stat] += item_model[stat]
		result["boost"] += item_model["speed"]
		# Weight by capacity, rather than adding percentages for multiple generators.
		result["absorption"] += item_model["shield"] * item_model.get("absorption", 0.0)
	if result["shield"] > 0.0:
		result["absorption"] /= result["shield"]
	return result


static func apply_stats(ship: Pilot, values: Dictionary) -> void:
	if values.has("model"):
		ship.set_ship_model(values["model"])
	if values.has("hull"):
		ship.max_hull = values["hull"]
		ship.hull = minf(ship.hull, ship.max_hull)
	ship.laser_damage = values["damage"]
	ship.max_shield = values["shield"]
	ship.shield_absorption = values["absorption"]
	ship.cruise_speed = values["speed"]
	ship.boost_speed = values["boost"]
	# Capacity increases stay empty; decreases discard excess charge. Never reset combat state.
	ship.shield = minf(ship.shield, ship.max_shield)
