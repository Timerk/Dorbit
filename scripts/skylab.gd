class_name Skylab
extends RefCounted
## Server-time industry. Ore settles at fixed UTC minute boundaries, independent of reads.
## Timers/robot bonuses are integrated at their actual event timestamps between boundaries.

const RESOURCES := ["prometium", "endurium", "terbium", "prometid", "duranium", "xenomit", "promerium", "seprom"]
const MODULES := {
	"basic": "Basic", "solar": "Solar", "storage": "Storage", "transport": "Transport",
	"prometiumCollector": "Prometium Collector", "enduriumCollector": "Endurium Collector", "terbiumCollector": "Terbium Collector",
	"prometidRefinery": "Prometid Refinery", "duraniumRefinery": "Duranium Refinery", "promeriumRefinery": "Promerium Refinery",
	"xeno": "Xeno", "sepromRefinery": "Seprom Refinery",
}
const COLLECTORS := {"prometiumCollector": "prometium", "enduriumCollector": "endurium", "terbiumCollector": "terbium"}
const RECIPES := {
	"prometidRefinery": {"prometium": 20, "endurium": 10},
	"duraniumRefinery": {"endurium": 10, "terbium": 20},
	"promeriumRefinery": {"prometid": 10, "duranium": 10},
	"sepromRefinery": {"promerium": 10},
}
const OUTPUT := {"prometidRefinery": "prometid", "duraniumRefinery": "duranium", "promeriumRefinery": "promerium", "sepromRefinery": "seprom"}
const LIMIT := 2_000_000_000
const ROBOT_LIFETIME := 172800
const ROBOT_SLOTS := 12
static var balance: Dictionary = {}


static func data() -> Dictionary:
	if balance.is_empty():
		balance = JSON.parse_string(FileAccess.get_file_as_string("res://assets/skylab/balance-v1.json"))
		var policies: Dictionary = balance["policies"]
		# Named v1 simulation choices. Alternate algorithms require a versioned engine change.
		assert(policies["tick_seconds"] == 60 and policies["infrastructure_retains_service"] and not policies["disable_pauses_construction"])
		assert(policies["construction_power"] == "completed_level" and policies["robot_stacking"] == "additive")
		assert(policies["catalyst_priority"] == "virtual_first" and policies["shipment_recipient"] == "dispatch_ship")
	return balance


static func now() -> int:
	return int(Time.get_unix_time_from_system())


static func table(id: String, level: int) -> Dictionary:
	if level == 0:
		return {"power": 0, "rate_per_hour": 0.0, "solar_capacity": 0, "capacities": {}}
	return data()["modules"][id][level - 1]


static func bootstrap(at: int) -> Dictionary:
	var lab := {"version": 1, "balance_version": 1, "lastSimulatedAt": at, "inventory": {}, "modules": {}, "carry": {}, "robots": {}, "shipment": null, "fair_turn": 0, "last_outputs": {}, "last_net": {}}
	for resource: String in RESOURCES:
		lab["inventory"][resource] = int(data()["bootstrap"]["raw_stock"]) if resource in COLLECTORS.values() else 0
		lab["last_net"][resource] = 0
	for id: String in MODULES:
		lab["modules"][id] = {"level": int(data()["bootstrap"]["levels"][id]), "enabled": true, "upgrade": null}
		lab["carry"][id] = 0.0
		lab["last_outputs"][id] = 0
	for id: String in COLLECTORS:
		lab["robots"][id] = {"active": [], "credit": 0, "advanced": 0}
	return lab


static func integer(value: Variant, lower: int = 0, upper: int = LIMIT) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= lower and value <= upper and value == floor(value)


static func migrate_credits(pilot: Dictionary) -> bool:
	if not integer(pilot.get("uridium")) or not pilot.get("skylab") is Dictionary:
		return false
	var converted := int(pilot["credits"]) + int(pilot["uridium"]) * 100
	if converted > LIMIT: return false
	var lab: Dictionary = pilot["skylab"].duplicate(true)
	if not lab.get("robots") is Dictionary: return false
	for robots: Variant in lab["robots"].values():
		if not robots is Dictionary or not integer(robots.get("uridium")) or robots.has("advanced") or not robots.get("active") is Array:
			return false
		robots["advanced"] = robots["uridium"]
		robots.erase("uridium")
		for robot: Variant in robots["active"]:
			if not robot is Dictionary or robot.get("kind") not in ["credit", "uridium"]: return false
			if robot["kind"] == "uridium": robot["kind"] = "advanced"
	if not valid(lab, pilot["equipment"]): return false
	pilot["skylab"] = lab
	pilot["credits"] = converted
	pilot.erase("uridium")
	return true


static func valid(lab: Variant, equipment: Dictionary) -> bool:
	if not lab is Dictionary or lab.get("version") != 1 or lab.get("balance_version") != 1 or not integer(lab.get("lastSimulatedAt"), 0, 10_000_000_000) or not integer(lab.get("fair_turn"), 0, 1):
		return false
	for field in ["inventory", "modules", "carry", "robots", "last_outputs", "last_net"]:
		if not lab.get(field) is Dictionary:
			return false
	if lab["inventory"].size() != RESOURCES.size() or lab["modules"].size() != MODULES.size() or lab["carry"].size() != MODULES.size() or lab["robots"].size() != COLLECTORS.size():
		return false
	for resource: String in RESOURCES:
		if not integer(lab["inventory"].get(resource)) or not integer(lab["last_net"].get(resource), -LIMIT):
			return false
	for id: String in MODULES:
		var module: Variant = lab["modules"].get(id)
		if not module is Dictionary or not integer(module.get("level"), 0, 1 if id == "transport" else 20) or not module.get("enabled") is bool:
			return false
		if id == "basic" and (not module["enabled"] or module["level"] < 1):
			return false
		var progress: Variant = lab["carry"].get(id)
		if not (progress is int or progress is float) or not is_finite(progress) or progress < 0 or progress > (2 if id == "xeno" else 1) + float(table(id, int(module["level"]))["rate_per_hour"]) * 1.48 / 60:
			return false
		if not integer(lab["last_outputs"].get(id)):
			return false
		var job: Variant = module.get("upgrade")
		if job != null:
			if id == "transport" or not job is Dictionary or not integer(job.get("targetLevel"), 1, 20) or job["targetLevel"] != module["level"] + 1:
				return false
			if not integer(job.get("startedAt"), 0, 10_000_000_000) or not integer(job.get("finishesAt"), 0, 10_000_000_000) or job["finishesAt"] <= job["startedAt"]:
				return false
			if id != "basic" and job["targetLevel"] > lab["modules"]["basic"]["level"]:
				return false
	for id: String in COLLECTORS:
		var robots: Variant = lab["robots"].get(id)
		if not robots is Dictionary or not robots.get("active") is Array or robots["active"].size() > ROBOT_SLOTS or not integer(robots.get("credit")) or not integer(robots.get("advanced")):
			return false
		for robot: Variant in robots["active"]:
			if not robot is Dictionary or robot.get("kind") not in ["credit", "advanced"] or not integer(robot.get("startedAt"), 0, 10_000_000_000) or not integer(robot.get("expiresAt"), 0, 10_000_000_000) or robot["expiresAt"] - robot["startedAt"] != ROBOT_LIFETIME:
				return false
	var shipment: Variant = lab.get("shipment")
	if shipment != null:
		if not shipment is Dictionary or not shipment.get("id") is String or not equipment["ships"].has(shipment.get("recipientId")) or not shipment.get("manifest") is Dictionary or shipment["manifest"].is_empty():
			return false
		for resource: Variant in shipment["manifest"]:
			if resource not in RESOURCES or not integer(shipment["manifest"][resource], 1):
				return false
		if CargoResources.units(shipment["manifest"]) > CargoResources.capacity(equipment, shipment["recipientId"]):
			return false
		if not integer(shipment.get("dispatchedAt"), 0, 10_000_000_000) or not integer(shipment.get("arrivesAt"), 0, 10_000_000_000) or shipment["arrivesAt"] < shipment["dispatchedAt"] or not shipment.get("delivered") is bool or shipment["delivered"]:
			return false
	return true


static func capacities(lab: Dictionary) -> Dictionary:
	var result := {}
	var configured: Dictionary = table("storage", int(lab["modules"]["storage"]["level"]))["capacities"]
	for resource: String in RESOURCES:
		result[resource] = int(configured.get(resource, 0))
	return result


static func normalize(lab: Dictionary) -> void:
	# Godot's JSON parser represents all numbers as doubles. Restore integer economy fields.
	for key in ["version", "balance_version", "lastSimulatedAt", "fair_turn"]: lab[key] = int(lab[key])
	for field in ["inventory", "last_outputs", "last_net"]:
		for key: String in lab[field]: lab[field][key] = int(lab[field][key])
	for module: Dictionary in lab["modules"].values():
		module["level"] = int(module["level"])
		if module["upgrade"] != null:
			for key in ["targetLevel", "startedAt", "finishesAt"]: module["upgrade"][key] = int(module["upgrade"][key])
	for robots: Dictionary in lab["robots"].values():
		robots["credit"] = int(robots["credit"])
		robots["advanced"] = int(robots["advanced"])
		for robot: Dictionary in robots["active"]:
			robot["startedAt"] = int(robot["startedAt"])
			robot["expiresAt"] = int(robot["expiresAt"])
	if lab["shipment"] != null:
		for key in ["dispatchedAt", "arrivesAt"]: lab["shipment"][key] = int(lab["shipment"][key])
		for resource: String in lab["shipment"]["manifest"]: lab["shipment"]["manifest"][resource] = int(lab["shipment"]["manifest"][resource])


static func power(lab: Dictionary) -> Dictionary:
	var solar: Dictionary = lab["modules"]["solar"]
	var capacity: int = int(table("solar", int(solar["level"]))["solar_capacity"]) if solar["enabled"] else 0
	var result := {"capacity": capacity, "demand": 0, "used": 0, "admitted": {}, "missing": {}}
	for id: String in data()["policies"]["power_priority"]:
		var module: Dictionary = lab["modules"][id]
		var demand: int = int(table(id, int(module["level"]))["power"]) if module["enabled"] else 0
		result["demand"] += demand
		result["admitted"][id] = module["enabled"] and demand <= capacity - result["used"]
		result["missing"][id] = maxi(0, demand - (capacity - result["used"]))
		if result["admitted"][id]:
			result["used"] += demand
	return result


static func robot_bonus(lab: Dictionary, id: String) -> float:
	var bonus := 1.0
	for robot: Dictionary in lab["robots"][id]["active"]:
		bonus += 0.04 if robot["kind"] == "advanced" else 0.01
	return bonus


static func rates(lab: Dictionary) -> Dictionary:
	var budget := power(lab)
	var result := {}
	for id: String in MODULES:
		var module: Dictionary = lab["modules"][id]
		result[id] = float(table(id, int(module["level"]))["rate_per_hour"]) * (robot_bonus(lab, id) if COLLECTORS.has(id) else 1.0) if module["level"] > 0 and module["enabled"] and module["upgrade"] == null and budget["admitted"][id] else 0.0
	return result


static func refill_robots(lab: Dictionary, at: int) -> void:
	for id: String in COLLECTORS:
		var robots: Dictionary = lab["robots"][id]
		robots["active"] = robots["active"].filter(func(robot: Dictionary): return robot["expiresAt"] > at)
		while robots["active"].size() < ROBOT_SLOTS and (robots["advanced"] > 0 or robots["credit"] > 0):
			var kind := "advanced" if robots["advanced"] > 0 else "credit"
			robots[kind] -= 1
			robots["active"].append({"kind": kind, "startedAt": at, "expiresAt": at + ROBOT_LIFETIME})


static func events(pilot: Dictionary, at: int) -> void:
	var lab: Dictionary = pilot["skylab"]
	for module: Dictionary in lab["modules"].values():
		var job: Variant = module["upgrade"]
		if job != null and job["finishesAt"] <= at:
			module["level"] = int(job["targetLevel"])
			module["upgrade"] = null
	refill_robots(lab, at)
	var shipment: Variant = lab["shipment"]
	if shipment != null and shipment["arrivesAt"] <= at:
		var hold: Dictionary = pilot["cargo"][shipment["recipientId"]]
		for resource: String in shipment["manifest"]:
			hold[resource] = int(hold.get(resource, 0)) + int(shipment["manifest"][resource])
		lab["shipment"] = null # Removal and cargo are committed in the same pilot transaction.


static func next_event(lab: Dictionary, target: int) -> int:
	var result := target
	for module: Dictionary in lab["modules"].values():
		if module["upgrade"] != null:
			result = mini(result, int(module["upgrade"]["finishesAt"]))
	for robots: Dictionary in lab["robots"].values():
		for robot: Dictionary in robots["active"]:
			result = mini(result, int(robot["expiresAt"]))
	if lab["shipment"] != null:
		result = mini(result, int(lab["shipment"]["arrivesAt"]))
	return result


static func advance(pilot: Dictionary, target: int) -> void:
	var lab: Dictionary = pilot["skylab"]
	var at := int(lab["lastSimulatedAt"])
	target = maxi(target, at) # Backwards server clock changes cannot replay earned work.
	events(pilot, at)
	var tick_seconds := int(data()["policies"]["tick_seconds"])
	while at < target:
		var boundary := (int(at / tick_seconds) + 1) * tick_seconds
		var end := mini(boundary, next_event(lab, target))
		var gross := rates(lab)
		for id: String in MODULES:
			lab["carry"][id] += gross[id] * float(end - at) / 3600.0
		at = end
		if at == boundary:
			settle_tick(lab)
		events(pilot, at)
		# At a fully blocked fixed point, skip empty minute ticks up to the next event.
		# Capacity/input shortages discard unearned work rather than banking a burst.
		if at == boundary and quiescent(lab):
			var stop := next_event(lab, target)
			var skipped := int(stop / tick_seconds) * tick_seconds
			if skipped > at:
				at = skipped
				events(pilot, at)
	lab["lastSimulatedAt"] = target


static func max_output(lab: Dictionary, id: String, desired: int, caps: Dictionary, ignore_endurium: bool = false) -> int:
	var inventory: Dictionary = lab["inventory"]
	var result := mini(desired, maxi(0, caps[OUTPUT[id]] - inventory[OUTPUT[id]]))
	for resource: String in RECIPES[id]:
		if ignore_endurium and resource == "endurium":
			continue
		result = mini(result, int(inventory[resource] / RECIPES[id][resource]))
	return result


static func produce(lab: Dictionary, id: String, count: int) -> void:
	for resource: String in RECIPES[id]:
		lab["inventory"][resource] -= RECIPES[id][resource] * count
	lab["inventory"][OUTPUT[id]] += count
	lab["last_outputs"][id] = count


static func settle_tick(lab: Dictionary) -> void:
	var inventory: Dictionary = lab["inventory"]
	var before := inventory.duplicate()
	var caps := capacities(lab)
	for id: String in MODULES:
		lab["last_outputs"][id] = 0
	var wants := {}
	for id: String in MODULES:
		wants[id] = floori(float(lab["carry"][id]) + 0.00000001)
	for id: String in COLLECTORS:
		var resource: String = COLLECTORS[id]
		var count := mini(wants[id], maxi(0, caps[resource] - inventory[resource]))
		inventory[resource] += count
		lab["last_outputs"][id] = count
	var feasible := {
		"prometidRefinery": max_output(lab, "prometidRefinery", 1, caps) > 0,
		"duraniumRefinery": max_output(lab, "duraniumRefinery", 1, caps) > 0,
	}
	var first := max_output(lab, "prometidRefinery", wants["prometidRefinery"], caps, true)
	var second := max_output(lab, "duraniumRefinery", wants["duraniumRefinery"], caps, true)
	var available := int(inventory["endurium"] / 10)
	if first + second > available:
		var first_share := float(available) * first / (first + second)
		var second_share := float(available) * second / (first + second)
		first = floori(first_share)
		second = floori(second_share)
		if first + second < available:
			var a := first_share - first
			var b := second_share - second
			if a > b + 0.000001 or (is_equal_approx(a, b) and lab["fair_turn"] == 0):
				first += 1
			else:
				second += 1
			if is_equal_approx(a, b):
				lab["fair_turn"] = 1 - int(lab["fair_turn"])
	produce(lab, "prometidRefinery", first)
	produce(lab, "duraniumRefinery", second)
	feasible["promeriumRefinery"] = max_output(lab, "promeriumRefinery", 1, caps) > 0 and (rates(lab)["xeno"] > 0 or inventory["xenomit"] > 0)
	var promerium := max_output(lab, "promeriumRefinery", wants["promeriumRefinery"], caps)
	var virtual := mini(promerium, wants["xeno"])
	promerium = mini(promerium, virtual + int(inventory["xenomit"]))
	virtual = mini(promerium, virtual)
	inventory["xenomit"] -= promerium - virtual
	produce(lab, "promeriumRefinery", promerium)
	lab["last_outputs"]["xeno"] = virtual
	feasible["sepromRefinery"] = max_output(lab, "sepromRefinery", 1, caps) > 0
	produce(lab, "sepromRefinery", max_output(lab, "sepromRefinery", wants["sepromRefinery"], caps))
	for id: String in MODULES:
		# Keep at most one catalyst allowance to bridge differently paced integer outputs.
		# This is bounded simulator progress, never Xenomit stock or ship cargo.
		if id == "xeno":
			var remaining := maxf(0.0, float(lab["carry"][id]) - virtual)
			# Discard spare whole allowances, preserving fractional throughput progress.
			lab["carry"][id] = minf(1.0, floor(remaining)) + fmod(remaining, 1.0)
		else:
			lab["carry"][id] = maxf(0.0, float(lab["carry"][id]) - wants[id])
		if COLLECTORS.has(id) and inventory[COLLECTORS[id]] >= caps[COLLECTORS[id]]:
			lab["carry"][id] = 0.0
		# Judge blockage before competing consumers ran. Otherwise a faster refinery
		# erases its slower neighbor's fractional work each time it drains shared ore.
		elif RECIPES.has(id) and not feasible[id]:
			lab["carry"][id] = 0.0
	# Virtual catalyst is an interval allowance, never a transferable inventory.
	if max_output(lab, "promeriumRefinery", 1, caps) == 0 or not lab["modules"]["promeriumRefinery"]["enabled"] or lab["modules"]["promeriumRefinery"]["upgrade"] != null:
		lab["carry"]["xeno"] = 0.0
	for resource: String in RESOURCES:
		lab["last_net"][resource] = inventory[resource] - before[resource]


static func quiescent(lab: Dictionary) -> bool:
	for value: Variant in lab["carry"].values():
		if absf(float(value)) > 0.0000001:
			return false
	for value: Variant in lab["last_outputs"].values():
		if value > 0:
			return false
	var gross := rates(lab)
	var caps := capacities(lab)
	for id: String in COLLECTORS:
		if gross[id] > 0 and lab["inventory"][COLLECTORS[id]] < caps[COLLECTORS[id]]:
			return false
	for id: String in RECIPES:
		if gross[id] > 0 and max_output(lab, id, 1, caps) > 0:
			if id != "promeriumRefinery" or gross["xeno"] > 0 or lab["inventory"]["xenomit"] > 0:
				return false
	return true


static func upgrade_blocker(lab: Dictionary, id: String) -> String:
	if not MODULES.has(id): return "Unknown module."
	if id == "transport": return "Transport stays at level 1."
	var module: Dictionary = lab["modules"][id]
	if module["upgrade"] != null: return "This module is already upgrading."
	if module["level"] >= 20: return "Maximum level reached."
	if id != "basic" and module["level"] + 1 > lab["modules"]["basic"]["level"]: return "Upgrade Basic first."
	return ""


static func speed_price(job: Dictionary, base: int, at: int) -> int:
	return ceili(float(base) * maxi(0, int(job["finishesAt"]) - at) / (job["finishesAt"] - job["startedAt"]))


static func command(pilot: Dictionary, sequence: int, action: String, payload: Dictionary, at: int) -> String:
	var lab: Dictionary = pilot["skylab"]
	at = maxi(at, int(lab["lastSimulatedAt"]))
	var id: Variant = payload.get("module", "")
	match action:
		"enable":
			if not id is String or not MODULES.has(id) or not payload.get("enabled") is bool: return "Invalid module control."
			if id == "basic": return "Basic cannot be switched off."
			if lab["modules"][id]["level"] == 0: return "Build this module first."
			lab["modules"][id]["enabled"] = payload["enabled"]
			if not payload["enabled"]: lab["carry"][id] = 0.0
			return "Module enabled." if payload["enabled"] else "Module disabled."
		"upgrade", "build_instant":
			if not id is String: return "Unknown module."
			var blocker := upgrade_blocker(lab, id)
			if not blocker.is_empty(): return blocker
			var entry := table(id, int(lab["modules"][id]["level"]) + 1)
			for resource: String in entry["ores"]:
				if lab["inventory"][resource] < entry["ores"][resource]: return "Insufficient %s." % CargoResources.TYPES[resource]["name"]
			var instant: int = int(entry["instant_credits"]) if action == "build_instant" else 0
			if pilot["credits"] < int(entry["credits"]) + instant: return "Insufficient credits."
			pilot["credits"] -= int(entry["credits"]) + instant
			for resource: String in entry["ores"]:
				lab["inventory"][resource] -= int(entry["ores"][resource])
			var module: Dictionary = lab["modules"][id]
			lab["carry"][id] = 0.0
			if action == "build_instant":
				module["level"] += 1
			else:
				module["upgrade"] = {"targetLevel": module["level"] + 1, "startedAt": at, "finishesAt": at + int(entry["duration"])}
			return "Upgrade completed." if action == "build_instant" else "Upgrade started."
		"cancel", "finish_upgrade":
			if not id is String or not MODULES.has(id) or lab["modules"][id]["upgrade"] == null: return "No active upgrade."
			var module: Dictionary = lab["modules"][id]
			var job: Dictionary = module["upgrade"]
			if action == "finish_upgrade":
				var price := speed_price(job, int(table(id, int(job["targetLevel"]))["instant_credits"]), at)
				if pilot["credits"] < price: return "Insufficient credits."
				pilot["credits"] -= price
				module["level"] = int(job["targetLevel"])
			module["upgrade"] = null
			return "Upgrade canceled. Paid credits and ore are forfeited." if action == "cancel" else "Upgrade completed."
		"ship", "ship_instant":
			if lab["shipment"] != null: return "A shipment is already in flight."
			if not payload.get("manifest") is Dictionary or payload["manifest"].is_empty(): return "Enter a positive shipment amount."
			var manifest: Dictionary = payload["manifest"]
			var total := 0
			for resource: Variant in manifest:
				if resource not in RESOURCES or not integer(manifest[resource], 1): return "Invalid shipment manifest."
				if manifest[resource] > lab["inventory"][resource]: return "Insufficient lab stock."
				total += int(manifest[resource])
				if total > LIMIT: return "Shipment too large."
			var equipment: Dictionary = pilot["equipment"]
			var ship: String = equipment["active_ship"]
			if total > CargoResources.capacity(equipment) - CargoResources.units(pilot["cargo"][ship]): return "Not enough free ship cargo."
			var budget := power(lab)
			if not lab["modules"]["transport"]["enabled"] or not budget["admitted"]["transport"] or lab["modules"]["transport"]["level"] < 1: return "Transport must be enabled and powered."
			var instant_price := int(data()["policies"]["instant_shipment_credits"]) if action == "ship_instant" else 0
			if pilot["credits"] < instant_price: return "Insufficient credits."
			pilot["credits"] -= instant_price
			for resource: String in manifest:
				lab["inventory"][resource] -= int(manifest[resource])
			var policies: Dictionary = data()["policies"]
			var duration := maxi(int(policies["minimum_shipment_seconds"]), total * int(policies["seconds_per_cargo_unit"]))
			if pilot["premium"]: duration = ceili(duration * 0.5)
			lab["shipment"] = {"id": "shipment-%d" % sequence, "recipientId": ship, "manifest": manifest.duplicate(true), "dispatchedAt": at, "arrivesAt": at + duration, "delivered": false}
			if action == "ship_instant":
				lab["shipment"]["arrivesAt"] = at
				events(pilot, at)
				return "Shipment delivered instantly."
			return "Shipment dispatched to %s." % ShipCatalog.info(equipment["ships"][ship])["name"]
		"finish_shipment":
			if lab["shipment"] == null: return "No active shipment."
			var price := int(data()["policies"]["instant_shipment_credits"])
			if pilot["credits"] < price: return "Insufficient credits."
			pilot["credits"] -= price
			lab["shipment"]["arrivesAt"] = at
			events(pilot, at)
			return "Shipment delivered."
		"robots":
			if not id is String or not COLLECTORS.has(id) or lab["modules"][id]["level"] < 1 or payload.get("kind") not in ["credit", "advanced"] or not integer(payload.get("amount"), 1, 1000000): return "Invalid robot purchase."
			var kind: String = payload["kind"]
			var amount := int(payload["amount"])
			var robots: Dictionary = lab["robots"][id]
			if robots[kind] > LIMIT - amount: return "Robot queue limit reached."
			var price := amount * int(data()["policies"]["robot_credit_price" if kind == "credit" else "robot_advanced_price"])
			if pilot["credits"] < price: return "Insufficient credits."
			pilot["credits"] -= price
			robots[kind] += amount
			refill_robots(lab, at)
			return "Collector robots purchased."
	return "Unknown Skylab command."


static func snapshot(pilot: Dictionary, at: int) -> Dictionary:
	var lab: Dictionary = pilot["skylab"]
	var budget := power(lab)
	var gross := rates(lab)
	var caps := capacities(lab)
	var modules := {}
	for id: String in MODULES:
		var module: Dictionary = lab["modules"][id].duplicate(true)
		var flags: Array[String] = []
		if module["level"] == 0: flags.append("unbuilt")
		if module["upgrade"] != null: flags.append("upgrading")
		if not module["enabled"]: flags.append("disabled")
		if module["enabled"] and not budget["admitted"][id]: flags.append("blocked-no-power")
		if COLLECTORS.has(id) and lab["inventory"][COLLECTORS[id]] >= caps[COLLECTORS[id]]: flags.append("blocked-output-full")
		if RECIPES.has(id):
			if lab["inventory"][OUTPUT[id]] >= caps[OUTPUT[id]]: flags.append("blocked-output-full")
			for resource: String in RECIPES[id]:
				if lab["inventory"][resource] < RECIPES[id][resource]:
					flags.append("blocked-input")
					break
			if id == "promeriumRefinery" and gross["xeno"] <= 0 and lab["inventory"]["xenomit"] < 1 and "blocked-input" not in flags: flags.append("blocked-input")
		module.merge({"state": "running" if flags.is_empty() else flags[0], "blockers": flags, "power": int(table(id, int(module["level"]))["power"]) if module["enabled"] else 0, "missing_power": budget["missing"][id], "nominal_per_hour": gross[id], "gross_per_hour": lab["last_outputs"][id] * 60.0})
		module["productivity"] = clampf(module["gross_per_hour"] / gross[id] * 100.0, 0, 100) if gross[id] > 0 and flags.is_empty() else 0.0
		module["upgrade_blocker"] = upgrade_blocker(lab, id)
		module["next"] = table(id, int(module["level"]) + 1).duplicate(true) if id != "transport" and module["level"] < 20 else {}
		if module["upgrade"] != null:
			module["speed_price"] = speed_price(module["upgrade"], int(table(id, int(module["upgrade"]["targetLevel"]))["instant_credits"]), at)
		modules[id] = module
	var net := {}
	for resource: String in RESOURCES:
		net[resource] = lab["last_net"][resource] * 60.0
	return {"server_time": at, "inventory": lab["inventory"].duplicate(), "capacities": caps, "modules": modules, "power": budget, "robots": lab["robots"].duplicate(true), "shipment": lab["shipment"].duplicate(true) if lab["shipment"] != null else null, "net_per_hour": net, "credits": pilot["credits"], "premium": pilot["premium"], "revision": pilot["equipment"]["revision"], "balance_label": data()["label"]}


static func screenshot_fixture(at: int) -> Dictionary:
	var lab := bootstrap(at)
	var levels := {"basic": 9, "solar": 8, "storage": 8, "transport": 1, "prometiumCollector": 7, "enduriumCollector": 7, "terbiumCollector": 7, "prometidRefinery": 6, "duraniumRefinery": 6, "promeriumRefinery": 4, "xeno": 5, "sepromRefinery": 3}
	for id: String in levels:
		lab["modules"][id]["level"] = levels[id]
		if id in ["prometidRefinery", "duraniumRefinery", "sepromRefinery"]: lab["modules"][id]["enabled"] = false
		if id in COLLECTORS or id == "promeriumRefinery": lab["modules"][id]["upgrade"] = {"targetLevel": levels[id] + 1, "startedAt": at, "finishesAt": at + 3600}
	lab["inventory"] = {"prometium": 0, "endurium": 0, "terbium": 1, "prometid": 103077, "duranium": 105424, "xenomit": 0, "promerium": 1194, "seprom": 578}
	return lab


static func screenshot_snapshot(at: int) -> Dictionary:
	# Fixture capacities are reference data only, not fitted into development level curves.
	var pilot := {"equipment": Equipment.starter(), "cargo": {"starter": {}}, "credits": 19000, "premium": false, "skylab": screenshot_fixture(at)}
	var result := snapshot(pilot, at)
	result["capacities"] = {"prometium": 4018569, "endurium": 4018569, "terbium": 4018569, "prometid": 200928, "duranium": 200928, "xenomit": 20093, "promerium": 20093, "seprom": 1827}
	return result
