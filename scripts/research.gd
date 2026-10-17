class_name Research
extends RefCounted
## Personal skill tree. Points come from quests; each level also consumes Skylab stock.
## Values follow the DarkOrbit skill tree; costs, caps and rewards are provisional.

const MAX_LEVEL := 5
# Researched levels at once. The tree holds 50, so pilots must specialize.
const SPENT_CAP := 30
const MAX_POINTS := 1_000_000
const RESET_BASE_CREDITS := 100_000
# Skills unlock left to right within a row once the previous skill is complete.
const ROWS := {
	"defense": ["ship_hull_1", "shield_engineering", "engineering", "shield_mechanics", "ship_hull_2"],
	"economy": ["logistics", "tractor_beam", "greed"],
	"offense": ["alien_hunter", "heat_seeking", "rocket_fusion"],
}
const ROW_NAMES := {"defense": "Defense", "economy": "Economy", "offense": "Offense"}
# Cumulative values at levels 1-5. Percentages are fractions; hull is flat.
const SKILLS := {
	"ship_hull_1": {"name": "Ship Hull I", "effect": "hull", "values": [5000.0, 10000.0, 15000.0, 25000.0, 50000.0], "text": "+%s max hull"},
	"shield_engineering": {"name": "Shield Engineering", "effect": "shield", "values": [0.04, 0.08, 0.12, 0.18, 0.25], "text": "+%s shield capacity"},
	"engineering": {"name": "Engineering", "effect": "repair", "values": [0.05, 0.10, 0.15, 0.20, 0.30], "text": "+%s repair robot speed"},
	"shield_mechanics": {"name": "Shield Mechanics", "effect": "absorption", "values": [0.02, 0.04, 0.06, 0.08, 0.12], "text": "+%s shield absorption"},
	"ship_hull_2": {"name": "Ship Hull II", "effect": "hull", "values": [5000.0, 10000.0, 15000.0, 25000.0, 50000.0], "text": "+%s max hull"},
	"logistics": {"name": "Logistics", "effect": "cargo", "values": [0.04, 0.08, 0.12, 0.16, 0.25], "text": "+%s cargo capacity"},
	"tractor_beam": {"name": "Tractor Beam", "effect": "loot", "values": [0.02, 0.06, 0.10, 0.15, 0.20], "text": "+%s resources from loot boxes"},
	"greed": {"name": "Greed", "effect": "credits", "values": [0.04, 0.08, 0.12, 0.18, 0.25], "text": "+%s credits per alien kill"},
	"alien_hunter": {"name": "Alien Hunter", "effect": "alien_damage", "values": [0.02, 0.04, 0.06, 0.08, 0.12], "text": "+%s laser damage against aliens"},
	"heat_seeking": {"name": "Heat-Seeking Missiles", "effect": "rocket_accuracy", "values": [0.01, 0.02, 0.04, 0.06, 0.10], "text": "+%s rocket hit chance"},
	"rocket_fusion": {"name": "Rocket Fusion", "effect": "rocket_damage", "values": [0.02, 0.04, 0.06, 0.08, 0.15], "text": "+%s rocket damage"},
}
# Lab stock consumed by the next level, indexed by the current level.
const LEVEL_COSTS := [
	{"prometid": 50, "duranium": 50},
	{"prometid": 100, "duranium": 100, "promerium": 10},
	{"promerium": 25},
	{"promerium": 50, "seprom": 2},
	{"promerium": 80, "seprom": 5},
]
const EFFECTS := ["hull", "shield", "repair", "absorption", "cargo", "loot", "credits", "alien_damage", "rocket_accuracy", "rocket_damage"]


static func empty() -> Dictionary:
	return {"points": 0, "skills": {}, "resets": 0}


# Pilots without a saved tree have nothing researched; no save migration is needed.
static func state(equipment: Dictionary) -> Dictionary:
	return equipment.get("research", empty())


static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or not value.get("skills") is Dictionary:
		return false
	if not Skylab.integer(value.get("points"), 0, MAX_POINTS) or not Skylab.integer(value.get("resets"), 0, 64):
		return false
	var spent := 0
	for id: Variant in value["skills"]:
		if not id is String or not SKILLS.has(id) or not Skylab.integer(value["skills"][id], 1, MAX_LEVEL):
			return false
		var previous := previous_skill(id)
		if not previous.is_empty() and int(value["skills"].get(previous, 0)) < MAX_LEVEL:
			return false
		spent += int(value["skills"][id])
	return spent <= SPENT_CAP


static func normalize(value: Dictionary) -> void:
	value["points"] = int(value["points"])
	value["resets"] = int(value["resets"])
	for id: String in value["skills"]:
		value["skills"][id] = int(value["skills"][id])


static func row(id: String) -> String:
	for key: String in ROWS:
		if id in ROWS[key]:
			return key
	return ""


static func previous_skill(id: String) -> String:
	var skills: Array = ROWS.get(row(id), [])
	var index := skills.find(id)
	return skills[index - 1] if index > 0 else ""


static func level(research: Dictionary, id: String) -> int:
	return int(research["skills"].get(id, 0))


static func spent(research: Dictionary) -> int:
	var total := 0
	for value: Variant in research["skills"].values():
		total += int(value)
	return total


static func cost(research: Dictionary, id: String) -> Dictionary:
	var current := level(research, id)
	return LEVEL_COSTS[current] if current < MAX_LEVEL else {}


static func learn_blocker(research: Dictionary, id: String, stock: Dictionary) -> String:
	if not SKILLS.has(id):
		return "Unknown skill."
	if level(research, id) >= MAX_LEVEL:
		return "Skill fully researched."
	var previous := previous_skill(id)
	if not previous.is_empty() and level(research, previous) < MAX_LEVEL:
		return "Complete %s first." % SKILLS[previous]["name"]
	if spent(research) >= SPENT_CAP:
		return "Research limit reached (%d levels). Reset the tree to specialize differently." % SPENT_CAP
	if int(research["points"]) < 1:
		return "Need 1 research point. Complete quests to earn more."
	var needs := cost(research, id)
	for resource: String in needs:
		if int(stock.get(resource, 0)) < needs[resource]:
			return "Need %s in Skylab stock." % CargoResources.describe(needs)
	return ""


# Spend one point and the level's lab stock. Callers persist both together.
static func learn(equipment: Dictionary, stock: Dictionary, id: String) -> String:
	var research := state(equipment).duplicate(true)
	var blocker := learn_blocker(research, id, stock)
	if not blocker.is_empty():
		return blocker
	var needs := cost(research, id)
	for resource: String in needs:
		stock[resource] -= needs[resource]
	research["points"] -= 1
	research["skills"][id] = level(research, id) + 1
	equipment["research"] = research
	return ""


static func reset_price(research: Dictionary) -> int:
	return mini(PilotStore.MAX_CREDITS, RESET_BASE_CREDITS * int(pow(2, int(research["resets"]))))


# Refund every point. Consumed lab stock is not returned.
static func reset(equipment: Dictionary) -> void:
	var research := state(equipment).duplicate(true)
	research["points"] = mini(MAX_POINTS, int(research["points"]) + spent(research))
	research["skills"] = {}
	research["resets"] = mini(64, int(research["resets"]) + 1)
	equipment["research"] = research


static func add_points(equipment: Dictionary, amount: int) -> void:
	var research := state(equipment).duplicate(true)
	research["points"] = mini(MAX_POINTS, int(research["points"]) + amount)
	equipment["research"] = research


static func bonuses(equipment: Dictionary) -> Dictionary:
	var result := {}
	for effect: String in EFFECTS:
		result[effect] = 0.0
	var research := state(equipment)
	for id: String in research["skills"]:
		result[SKILLS[id]["effect"]] += SKILLS[id]["values"][int(research["skills"][id]) - 1]
	return result


static func bonus(equipment: Dictionary, effect: String) -> float:
	return bonuses(equipment)[effect]


static func format_value(id: String, value: float) -> String:
	return StationShop.credits_text(int(value)) if SKILLS[id]["effect"] == "hull" else "%d%%" % roundi(value * 100.0)


static func describe(id: String, current: int) -> String:
	var skill: Dictionary = SKILLS[id]
	if current == 0:
		return "Not researched. Level 1: " + skill["text"] % format_value(id, skill["values"][0])
	var text: String = skill["text"] % format_value(id, skill["values"][current - 1])
	if current < MAX_LEVEL:
		text += "  /  Next: " + skill["text"] % format_value(id, skill["values"][current])
	return text
