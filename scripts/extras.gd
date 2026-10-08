class_name Extras
extends RefCounted
## Utility behavior runs on the server; automatic costs commit before effects.


static func enabled(item: Dictionary) -> bool:
	return not item.is_empty() and item.get("enabled", item.get("model") == "repair-auto")


static func repair_blocker(ship: Pilot) -> String:
	if not ship.alive or ship.get_meta("docked", false):
		return "Launch a living ship to use its repair robot."
	if ship.repair_seconds <= 0.0:
		return "No repair robot fitted."
	if ship.hull >= ship.max_hull:
		return "Hull is already repaired."
	if ship.velocity.length() > 0.5:
		return "Stop moving to use the repair robot."
	if ship.time_since_hit < 5.0 or ship.time_since_attack < 5.0:
		return "Repair robot requires five seconds outside combat."
	return ""


static func tick_repair(ship: Pilot, delta: float, firing: bool) -> void:
	ship.time_since_attack += delta
	if firing or ship.velocity.length() > 0.5 or ship.time_since_hit < 5.0 or not ship.alive or ship.get_meta("docked", false):
		ship.repair_requested = false
	ship.robot_repairing = (ship.repair_requested or ship.repair_auto) and not firing and repair_blocker(ship).is_empty()
	if ship.robot_repairing:
		ship.hull = minf(ship.max_hull, ship.hull + delta * ship.max_hull / ship.repair_seconds)
		if ship.hull >= ship.max_hull:
			ship.repair_requested = false


static func automatic_update(pilot: Dictionary, live_boosts: Dictionary) -> bool:
	var equipment: Dictionary = pilot["equipment"]
	var changed := false
	var buyer := Equipment.extra(equipment, "ammo")
	if enabled(buyer):
		var kind: String = buyer.get("ammo_type", "x1")
		var price: int = int(Ammunition.TYPES[kind]["price"]) * 100
		if int(pilot["ammo"][kind]) < 1000 and int(pilot["ammo"][kind]) <= Ammunition.MAX_SHOTS - 10000 and int(pilot["credits"]) >= price:
			pilot["ammo"][kind] += 10000
			pilot["credits"] -= price
			changed = true
	if enabled(Equipment.extra(equipment, "generators")):
		var hold: Dictionary = pilot["cargo"][equipment["active_ship"]]
		for group: String in ["shields", "engines"]:
			if ResourceBoosts.remaining(live_boosts, group) > 0.0:
				continue
			# Do not consume a resource for an empty generator group.
			var stats := Equipment.stats(equipment)
			if (group == "shields" and stats["shield"] <= 0.0) or (group == "engines" and stats["speed"] <= ShipCatalog.info(stats["model"])["speed"] * ShipCatalog.SPEED_SCALE):
				continue
			for resource: String in (["seprom", "promerium", "duranium"] if group == "shields" else ["promerium", "duranium"]):
				if int(hold.get(resource, 0)) > 0:
					ResourceBoosts.apply(hold, live_boosts, group, resource, 1, false)
					changed = true
					break
	if changed:
		pilot["boosts"][equipment["active_ship"]] = live_boosts.duplicate(true)
	return changed
