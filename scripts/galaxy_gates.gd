class_name GalaxyGates
extends RefCounted
## Galaxy gate parts, signal operations and gate definitions.
## The occupying aliens ferry gate parts through the reclaimed maps so they can
## summon allied factions. Pilots capture the parts, assemble a faction's gate
## themselves and strike its staging fleet before it comes through.
## Part counts, chances, waves, lives and rewards are provisional playtesting values.

const MAX_PARTS := 99
# Pilots counted when locking a wave's size. Each additional pilot adds half the base count.
const SCALED_PILOTS := 4
const WAVE_DELAY := 8.0
const FIRST_WAVE_DELAY := 12.0
# A run with nobody inside the gate for this long collapses.
const ABANDON_TIME := 120.0
# Pilots left inside after a victory are returned home after this long.
const VICTORY_TIME := 90.0
const ESCORT_INTERVAL := 25.0
const ESCORTS := 2
const SIGNAL_STATES := ["available", "active", "done"]
# Display and lookup order. Each gate has its own arena map, entry portal near
# Outpost 01, parts, operation, alien pool, waves and rewards.
const ORDER := ["vashar", "korrath"]
const GATES := {
	"vashar": {
		"name": "Vashar Gate", "faction": "Vashar", "arena": "Vashar Rift", "map": 4, "glow": Color("c86bff"),
		"portal": Vector3(320, 40, -300), "parts_required": 20, "lives": 3,
		"summary": "The occupying aliens are smuggling gate parts through our sectors to summon their Vashar allies. Capture enough parts and assemble the gate ourselves: it opens near Outpost 01 and leads straight into the Vashar staging fleet. Destroy the mothership to set back their invasion.",
		# Chance that an alien carries one part in its loot box. Home-map aliens carry none.
		"part_chance": {"Skirmisher": 0.08, "Raider": 0.12, "Marauder": 0.12, "Warden": 0.16, "Ravager": 0.16, "Overlord": 0.2},
		# Each qualifying kill on the signal map guarantees a part while the operation is active.
		"signal": {
			"title": "Signal Anomaly", "contact": "sato", "map": 1, "required": 8, "parts": 4, "credits": 10000, "research": 2,
			"objective": "Recover Vashar gate parts from aliens in M2 / Outer Patrol",
			"briefing": "Pilot, Sato here. I have isolated an anomaly in the alien traffic through Outer Patrol. Their couriers are hauling segments of a jump gate, and the signature is not theirs. It belongs to the Vashar, an allied faction they are trying to summon. Destroy the couriers in M2 and recover the parts before anyone can assemble that gate.",
			"done": "That is enough to decode the courier manifest. I have located their cache and added its parts to your stock. Keep collecting: once the gate is complete, we can turn it on the Vashar ourselves.",
		},
		# Every participant: credits, research points and x4 rounds, plus a chance at an item.
		"reward": {"credits": 150000, "research": 6, "x4": 15000, "item": "lf-4", "item_chance": 0.2},
		"boss": "Mothership", "boss_title": "VASHAR MOTHERSHIP", "escort": "Shardling",
		"victory": "Vashar mothership destroyed. Their invasion is set back.",
		# Arena alien pool, in stable ID order. Waves activate subsets; nothing respawns by itself.
		"pool": {"Shardling": 8, "Spireguard": 4, "Mothership": 1},
		"waves": [
			{"Shardling": 3},
			{"Shardling": 5},
			{"Shardling": 4, "Spireguard": 1},
			{"Shardling": 5, "Spireguard": 2},
			{"Shardling": 6, "Spireguard": 2},
			{"Shardling": 5, "Spireguard": 3},
			{"Mothership": 1, "Shardling": 4, "Spireguard": 2},
		],
	},
	"korrath": {
		"name": "Korrath Gate", "faction": "Korrath", "arena": "Korrath Bastion", "map": 5, "glow": Color("ff8a3d"),
		"portal": Vector3(-340, -30, -330), "parts_required": 24, "lives": 3,
		"summary": "The Korrath are siege engineers: armored hulks that crack planetary defenses. The occupiers are dragging Korrath gate segments through the deep sectors. Assemble the gate, break into their staging bastion and destroy the Siegebreaker before it is turned on Outpost 01.",
		"part_chance": {"Marauder": 0.08, "Warden": 0.12, "Ravager": 0.12, "Overlord": 0.16},
		"signal": {
			"title": "Siege Manifest", "contact": "brell", "map": 2, "required": 10, "parts": 5, "credits": 25000, "research": 3,
			"objective": "Recover Korrath gate parts from aliens in M3 / Debris Fields",
			"briefing": "Brell here. I pulled a cargo manifest out of a Warden wreck in the Debris Fields. The aliens are hauling heavy gate segments through there, built for something called the Korrath. Siege engineers, by the look of the tooling. Knock out the haulers in M3 and bring me those segments before they finish another gate.",
			"done": "That manifest pointed straight at a segment depot. I cracked it open and added the parts to your stock. Finish the gate and we hit their bastion before they hit us.",
		},
		"reward": {"credits": 300000, "research": 10, "x4": 25000, "item": "sg3n-b00", "item_chance": 0.2},
		"boss": "Siegebreaker", "boss_title": "KORRATH SIEGEBREAKER", "escort": "Husk",
		"victory": "The Korrath Siegebreaker is wrecked. Their siege is set back.",
		"pool": {"Husk": 10, "Bulwark": 5, "Siegebreaker": 1},
		"waves": [
			{"Husk": 4},
			{"Husk": 6},
			{"Husk": 4, "Bulwark": 1},
			{"Husk": 6, "Bulwark": 2},
			{"Bulwark": 3},
			{"Husk": 8, "Bulwark": 2},
			{"Husk": 6, "Bulwark": 3},
			{"Siegebreaker": 1, "Husk": 4, "Bulwark": 2},
		],
	},
}


static func info(gate: String) -> Dictionary:
	return GATES[gate]


## The gate whose arena is `map`, or an empty string for normal maps.
static func for_map(map: int) -> String:
	for gate: String in ORDER:
		if int(GATES[gate]["map"]) == map:
			return gate
	return ""


static func is_arena(map: int) -> bool:
	return not for_map(map).is_empty()


static func pool_kinds(gate: String) -> Array[String]:
	var kinds: Array[String] = []
	for kind: String in GATES[gate]["pool"]:
		for index in range(GATES[gate]["pool"][kind]):
			kinds.append(kind)
	return kinds


## Every alien kind fought inside any gate arena.
static func arena_kinds() -> Array[String]:
	var kinds: Array[String] = []
	for gate: String in ORDER:
		for kind: String in GATES[gate]["pool"]:
			kinds.append(kind)
	return kinds


static func empty() -> Dictionary:
	return {"parts": 0, "signal": "available", "progress": 0}


## Saved progress for every gate. Pilots without saved progress start empty.
static func states(equipment: Dictionary) -> Dictionary:
	return equipment.get("gates", {})


static func state(equipment: Dictionary, gate: String) -> Dictionary:
	return states(equipment).get(gate, empty())


static func valid(value: Variant, gate: String) -> bool:
	if not value is Dictionary or value.size() != 3 or not Skylab.integer(value.get("parts"), 0, MAX_PARTS):
		return false
	if not value.get("signal") is String or not value["signal"] in SIGNAL_STATES:
		return false
	return Skylab.integer(value.get("progress"), 0, int(GATES[gate]["signal"]["required"]) - 1 if value["signal"] == "active" else 0)


## Saved gate progress: a dictionary keyed by known gate IDs.
static func valid_collection(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for gate: Variant in value:
		if not gate is String or not GATES.has(gate) or not valid(value[gate], gate):
			return false
	return true


static func normalize(value: Dictionary) -> void:
	for gate: String in value:
		value[gate]["parts"] = int(value[gate]["parts"])
		value[gate]["progress"] = int(value[gate]["progress"])


static func signal_active(gates: Dictionary) -> bool:
	return gates.get("signal", "") == "active"


## Parts carried by one destroyed alien, per gate. `guaranteed` lists gates whose
## active operation guarantees a part for this kill.
static func roll_parts(kind: String, rng: RandomNumberGenerator, guaranteed: Array) -> Dictionary:
	var parts := {}
	for gate: String in ORDER:
		var count := 1 if gate in guaranteed else 0
		if rng.randf() < float(GATES[gate]["part_chance"].get(kind, 0.0)):
			count += 1
		if count > 0:
			parts[gate] = count
	return parts


## Adds collected parts. `qualifying` of them came from the operation's map and
## count toward an active signal operation. Returns the next state with any reward.
static func collect(gates: Dictionary, gate: String, amount: int, qualifying: int) -> Dictionary:
	var operation: Dictionary = GATES[gate]["signal"]
	var next := gates.duplicate()
	var result := {"gates": next, "credits": 0, "research": 0, "completed": false}
	next["parts"] = mini(MAX_PARTS, int(next["parts"]) + amount)
	if not signal_active(next) or qualifying <= 0:
		return result
	var progress := int(next["progress"]) + qualifying
	if progress < int(operation["required"]):
		next["progress"] = progress
		return result
	next["signal"] = "done"
	next["progress"] = 0
	next["parts"] = mini(MAX_PARTS, int(next["parts"]) + int(operation["parts"]))
	result["credits"] = operation["credits"]
	result["research"] = operation["research"]
	result["completed"] = true
	return result


static func accept_blocker(gates: Dictionary, gate: String) -> String:
	match gates["signal"]:
		"active": return "%s is already active." % GATES[gate]["signal"]["title"]
		"done": return "Assemble the %s before tracing another lead." % GATES[gate]["name"]
	return ""


static func assemble_blocker(gates: Dictionary, gate: String) -> String:
	if int(gates["parts"]) < int(GATES[gate]["parts_required"]):
		return "Need %d gate parts; %d collected." % [GATES[gate]["parts_required"], int(gates["parts"])]
	return ""


## Consumes one gate's parts. A finished signal operation becomes available again.
static func assemble(gates: Dictionary, gate: String) -> Dictionary:
	var next := gates.duplicate()
	next["parts"] = int(next["parts"]) - int(GATES[gate]["parts_required"])
	if next["signal"] == "done":
		next["signal"] = "available"
	return next


## Alien counts for one wave, locked when it starts. The boss never scales, and
## a boss wave leaves enough dormant escorts for the boss to launch.
static func wave_counts(gate: String, wave: int, pilots: int) -> Dictionary:
	var counts := {}
	var definition: Dictionary = GATES[gate]
	var extra := clampi(pilots, 1, SCALED_PILOTS) - 1
	var boss_wave: bool = definition["waves"][wave].has(definition["boss"])
	for kind: String in definition["waves"][wave]:
		var base := int(definition["waves"][wave][kind])
		var limit := int(definition["pool"][kind]) - (ESCORTS if boss_wave and kind == definition["escort"] else 0)
		counts[kind] = base if kind == definition["boss"] else mini(limit, base + int(base * extra / 2.0))
	return counts


static func signal_objective(gates: Dictionary, gate: String) -> String:
	var operation: Dictionary = GATES[gate]["signal"]
	return "%s  %d / %d" % [operation["objective"], int(gates["progress"]), int(operation["required"])]


static func item_name(gate: String) -> String:
	return Equipment.MODELS[GATES[gate]["reward"]["item"]]["name"]


static func reward_text(gate: String, item: bool) -> String:
	var reward: Dictionary = GATES[gate]["reward"]
	var text := "%s and +%s x4 shots" % [Story.reward_text(reward["credits"], reward["research"]), StationShop.credits_text(reward["x4"])]
	return text + (" and an %s (in storage)" % item_name(gate) if item else "")
