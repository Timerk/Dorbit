class_name ResourceBoosts
extends RefCounted
## One resource per equipment group, per hull. Duration is server-simulated online time.

const RECIPES := {
	"prometid": {"prometium": 20, "endurium": 10},
	"duranium": {"endurium": 10, "terbium": 20},
	"promerium": {"prometid": 10, "duranium": 10},
}
const BONUSES := {
	"prometid": {"lasers": 0.15, "rockets": 0.15},
	"duranium": {"shields": 0.10, "engines": 0.10},
	"promerium": {"lasers": 0.30, "rockets": 0.30, "shields": 0.20, "engines": 0.20},
	"seprom": {"lasers": 0.60, "rockets": 0.60, "shields": 0.40},
}
const GROUPS := {"lasers": "Lasers", "rockets": "Rockets", "shields": "Shields", "engines": "Engines"}
const ROUNDS_PER_UNIT := 10
const SECONDS_PER_UNIT := 600
const MAX_RESERVE := 2_000_000_000


static func empty_holds(equipment: Dictionary) -> Dictionary:
	return CargoResources.empty_holds(equipment)


static func valid(holds: Variant, equipment: Dictionary) -> bool:
	if not holds is Dictionary or holds.size() != equipment["ships"].size():
		return false
	for ship: Variant in holds:
		if not ship is String or not equipment["ships"].has(ship) or not holds[ship] is Dictionary:
			return false
		for group: Variant in holds[ship]:
			var entry: Variant = holds[ship][group]
			if not group is String or not GROUPS.has(group) or not entry is Dictionary or entry.size() != 2:
				return false
			var resource: Variant = entry.get("resource")
			var remaining: Variant = entry.get("remaining")
			if not resource is String or not BONUSES.get(resource, {}).has(group) or not (remaining is int or remaining is float):
				return false
			if not is_finite(remaining) or remaining <= 0 or remaining > MAX_RESERVE or (group in ["lasers", "rockets"] and remaining != floor(remaining)):
				return false
	return true


static func remaining(boosts: Dictionary, group: String) -> float:
	return maxf(0.0, boosts.get(group, {}).get("remaining", 0.0))


static func bonus(boosts: Dictionary, group: String) -> float:
	return BONUSES.get(boosts.get(group, {}).get("resource", ""), {}).get(group, 0.0) if remaining(boosts, group) > 0 else 0.0


static func maximum(hold: Dictionary, output: String) -> int:
	if not RECIPES.has(output):
		return 0
	var amount := MAX_RESERVE
	for ingredient: String in RECIPES[output]:
		amount = mini(amount, int(int(hold.get(ingredient, 0)) / int(RECIPES[output][ingredient])))
	return amount


static func spend(hold: Dictionary, resource: String, amount: int) -> void:
	hold[resource] -= amount
	if hold[resource] == 0:
		hold.erase(resource)


static func refine(hold: Dictionary, output: String, amount: int) -> String:
	if not RECIPES.has(output):
		return "This resource cannot be refined on the ship."
	if amount < 1 or amount > maximum(hold, output):
		return "Not enough ingredients for that refining amount."
	for ingredient: String in RECIPES[output]:
		spend(hold, ingredient, amount * int(RECIPES[output][ingredient]))
	hold[output] = int(hold.get(output, 0)) + amount
	return ""


static func apply(hold: Dictionary, boosts: Dictionary, group: String, resource: String, amount: int, replace: bool) -> String:
	if not BONUSES.get(resource, {}).has(group):
		return "That resource does not boost this equipment."
	if group == "rockets":
		return "Rocket boosts will be available when rocket weapons are implemented."
	if amount < 1 or amount > int(hold.get(resource, 0)):
		return "Not enough resources for that boost amount."
	var current := remaining(boosts, group)
	var same: bool = boosts.get(group, {}).get("resource", "") == resource
	if current > 0 and not same and not replace:
		return "Confirm replacement of the remaining boost first."
	var reserve := (current if same else 0.0) + amount * (ROUNDS_PER_UNIT if group == "lasers" else SECONDS_PER_UNIT)
	if reserve > MAX_RESERVE:
		return "Boost reserve limit reached."
	spend(hold, resource, amount)
	boosts[group] = {"resource": resource, "remaining": int(reserve) if group == "lasers" else reserve}
	return ""


static func stats(base: Dictionary, boosts: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	result["shield"] *= 1.0 + bonus(boosts, "shields")
	for key in ["speed", "boost"]:
		result[key] *= 1.0 + bonus(boosts, "engines")
	return result


# The stable fitting order determines which lasers receive the last partial volley.
static func laser_damage(lasers: Array, against_alien: bool, boosts: Dictionary) -> float:
	var rounds := int(remaining(boosts, "lasers"))
	var multiplier := bonus(boosts, "lasers")
	var damage := 0.0
	for index in range(lasers.size()):
		var laser: Dictionary = lasers[index]
		var base: float = laser["damage"] + (laser["npc_damage"] if against_alien else 0.0)
		damage += base * (1.0 + multiplier if index < rounds else 1.0)
	return damage
