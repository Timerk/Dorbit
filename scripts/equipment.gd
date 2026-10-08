class_name Equipment
extends RefCounted
## Owned instances have one location: storage or a slot on an owned ship.

# Reference values and credit-only prices; see GAME_PLAN.md for sources.
const URIDIUM_TO_CREDITS: int = 100
const MAX_PURCHASE_QUANTITY: int = 999
const MODELS := {
	# Retain these persisted model IDs and the original starter engine's flight tuning.
	"laser": {"name": "LF-1", "kind": "laser", "price": 10000, "damage": 65.0, "shield": 0.0, "speed": 0.0},
	"mp-1": {"name": "MP-1", "kind": "laser", "price": 40000, "damage": 70.0, "shield": 0.0, "speed": 0.0},
	"lf-2": {"name": "LF-2", "kind": "laser", "price": 5000 * URIDIUM_TO_CREDITS, "damage": 140.0, "shield": 0.0, "speed": 0.0},
	"lf-3": {"name": "LF-3", "kind": "laser", "price": 10000 * URIDIUM_TO_CREDITS, "damage": 175.0, "npc_bonus": 0.15, "shield": 0.0, "speed": 0.0},
	"lf-4": {"name": "LF-4", "kind": "laser", "price": 0, "unavailable": "Unavailable until loot or assembly is added.", "damage": 200.0, "shield": 0.0, "speed": 0.0},
	"shield": {"name": "SG3N-A01", "kind": "generator", "price": 8000, "damage": 0.0, "shield": 1000.0, "absorption": 0.4, "speed": 0.0},
	"sg3n-a02": {"name": "SG3N-A02", "kind": "generator", "price": 16000, "damage": 0.0, "shield": 2000.0, "absorption": 0.5, "speed": 0.0},
	"fs-01": {"name": "FS-01", "kind": "generator", "price": 256000, "damage": 0.0, "shield": 3200.0, "absorption": 0.7, "regen_bonus": 0.0625, "speed": 0.0},
	"sg3n-a03": {"name": "SG3N-A03", "kind": "generator", "price": 128000, "damage": 0.0, "shield": 5000.0, "absorption": 0.6, "speed": 0.0},
	"sg3n-b00": {"name": "SG3N-B00", "kind": "generator", "price": 0, "unavailable": "Unavailable until assembly is added.", "damage": 0.0, "shield": 9000.0, "absorption": 0.7, "speed": 0.0},
	"sg3n-b01": {"name": "SG3N-B01", "kind": "generator", "price": 2500 * URIDIUM_TO_CREDITS, "damage": 0.0, "shield": 9500.0, "absorption": 0.7, "speed": 0.0},
	"sg3n-b02": {"name": "SG3N-B02", "kind": "generator", "price": 10000 * URIDIUM_TO_CREDITS, "damage": 0.0, "shield": 10000.0, "absorption": 0.8, "speed": 0.0},
	"g3n-1010": {"name": "G3N-1010", "kind": "generator", "price": 2000, "damage": 0.0, "shield": 0.0, "speed": 2.0},
	"g3n-2010": {"name": "G3N-2010", "kind": "generator", "price": 4000, "damage": 0.0, "shield": 0.0, "speed": 3.0},
	"g3n-3210": {"name": "G3N-3210", "kind": "generator", "price": 8000, "damage": 0.0, "shield": 0.0, "speed": 4.0},
	"g3n-3310": {"name": "G3N-3310", "kind": "generator", "price": 16000, "damage": 0.0, "shield": 0.0, "speed": 5.0},
	"g3n-6900": {"name": "G3N-6900", "kind": "generator", "price": 1000 * URIDIUM_TO_CREDITS, "damage": 0.0, "shield": 0.0, "speed": 7.0},
	"g3n-7900": {"name": "G3N-7900", "kind": "generator", "price": 2000 * URIDIUM_TO_CREDITS, "damage": 0.0, "shield": 0.0, "speed": 10.0},
	"engine": {"name": "Ion engine", "kind": "generator", "price": 0, "legacy": true, "unavailable": "Starter equipment only. Choose a G3N engine in the shop.", "damage": 0.0, "shield": 0.0, "speed": 8.0},
	"hst-1": {"name": "HST-1", "kind": "launcher", "capacity": 3, "price": 500000, "damage": 0.0, "shield": 0.0, "speed": 0.0},
	"hst-2": {"name": "HST-2", "kind": "launcher", "capacity": 5, "price": 15000 * URIDIUM_TO_CREDITS, "damage": 0.0, "shield": 0.0, "speed": 0.0},
}
# Keep the persisted pathfinder model ID so existing ownership and cargo stay valid.
const STARTER_HULL: float = 116000.0


static func category(model: String) -> String:
	var info: Dictionary = MODELS[model]
	return "weapons" if info["kind"] in ["laser", "launcher"] else ("shields" if info["shield"] > 0.0 else "engines")


static func catalog_models() -> Array[String]:
	var result: Array[String] = []
	for model: String in MODELS:
		if not MODELS[model].get("legacy", false):
			result.append(model)
	return result


static func purchase_blocker(model: String) -> String:
	if not MODELS.has(model):
		return "Unknown equipment model."
	return MODELS[model].get("unavailable", "")


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
		return "Incompatible slot. Lasers and launchers need their own slots; shields and engines share generator slots."
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
	var result := {"model": model, "hull": float(hull["hull"]), "damage": 0.0, "npc_damage": 0.0, "shield": 0.0, "absorption": 0.0, "regen_bonus": 0.0, "speed": speed, "boost": speed + ShipCatalog.BOOST_BONUS, "lasers": []}
	result["laser_count"] = 0
	result["launcher_capacity"] = 0
	var installed: Array = data["items"].values()
	installed.sort_custom(func(a: Dictionary, b: Dictionary): return a["slot"].naturalnocasecmp_to(b["slot"]) < 0)
	for item: Dictionary in installed:
		if item["ship"] != ship:
			continue
		var item_model: Dictionary = MODELS[item["model"]]
		if item_model["kind"] == "launcher":
			result["launcher_capacity"] = item_model["capacity"]
		if item_model["kind"] == "laser":
			result["laser_count"] += 1
			result["lasers"].append({"damage": item_model["damage"], "npc_damage": item_model["damage"] * item_model.get("npc_bonus", 0.0)})
		for stat in ["damage", "shield", "speed"]:
			result[stat] += item_model[stat]
		result["boost"] += item_model["speed"]
		# Apply each laser's NPC multiplier only to its own damage.
		result["npc_damage"] += item_model["damage"] * item_model.get("npc_bonus", 0.0)
		result["regen_bonus"] += item_model.get("regen_bonus", 0.0)
		# Weight by capacity, rather than adding percentages for multiple generators.
		result["absorption"] += item_model["shield"] * item_model.get("absorption", 0.0)
	if result["shield"] > 0.0:
		result["absorption"] /= result["shield"]
	return result


static func apply_stats(ship: Pilot, values: Dictionary) -> void:
	if values.has("launcher_capacity"):
		ship.rockets.equip(values["launcher_capacity"])
	if values.has("model"):
		ship.set_ship_model(values["model"])
	if values.has("hull"):
		ship.max_hull = values["hull"]
		ship.hull = minf(ship.hull, ship.max_hull)
	ship.laser_damage = values["damage"]
	if values.has("laser_count"):
		ship.laser_count = values["laser_count"]
	if values.has("lasers"):
		ship.laser_loadout = values["lasers"].duplicate(true)
	ship.npc_laser_damage = values["npc_damage"]
	ship.max_shield = values["shield"]
	ship.shield_absorption = values["absorption"]
	ship.shield_regen_bonus = values["regen_bonus"]
	ship.cruise_speed = values["speed"]
	ship.boost_speed = values["boost"]
	# Capacity increases stay empty; decreases discard excess charge. Never reset combat state.
	ship.shield = minf(ship.shield, ship.max_shield)
