class_name GalaxyGates
extends RefCounted
## Galaxy gate parts, the signal operation and the Vashar Gate run.
## The occupying aliens ferry gate parts through the reclaimed maps so they can
## summon their Vashar allies. Pilots capture the parts, assemble the gate
## themselves and strike the Vashar staging fleet before it comes through.
## Part counts, chances, waves, lives and rewards are provisional playtesting values.

const NAME := "Vashar Gate"
# Faction violet for gate UI, loot and labels.
const GLOW := Color("c86bff")
const FACTION := "Vashar"
const MAP := 4
const PARTS_REQUIRED := 20
const MAX_PARTS := 99
# Chance that an alien carries one part in its loot box. Home-map aliens carry none.
const PART_CHANCE := {"Skirmisher": 0.08, "Raider": 0.12, "Marauder": 0.12, "Warden": 0.16, "Ravager": 0.16, "Overlord": 0.2}
# Each qualifying kill on the signal map guarantees a part while the operation is active.
const SIGNAL := {
	"title": "Signal Anomaly", "contact": "sato", "map": 1, "required": 8, "parts": 4, "credits": 10000, "research": 2,
	"objective": "Recover gate parts from aliens in M2 / Outer Patrol",
	"briefing": "Pilot, Sato here. I have isolated an anomaly in the alien traffic through Outer Patrol. Their couriers are hauling segments of a jump gate, and the signature is not theirs. It belongs to the Vashar, an allied faction they are trying to summon. Destroy the couriers in M2 and recover the parts before anyone can assemble that gate.",
	"done": "That is enough to decode the courier manifest. I have located their cache and added its parts to your stock. Keep collecting: once the gate is complete, we can turn it on the Vashar ourselves.",
}
const LIVES := 3
# Every participant: credits, research points and x4 rounds, plus a chance at an LF-4 laser.
const REWARD := {"credits": 150000, "research": 6, "x4": 15000, "item": "lf-4", "item_chance": 0.2}
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
# Arena alien pool, in stable ID order. Waves activate subsets; nothing respawns by itself.
const POOL := {"Shardling": 8, "Spireguard": 4, "Mothership": 1}
const WAVES: Array[Dictionary] = [
	{"Shardling": 3},
	{"Shardling": 5},
	{"Shardling": 4, "Spireguard": 1},
	{"Shardling": 5, "Spireguard": 2},
	{"Shardling": 6, "Spireguard": 2},
	{"Shardling": 5, "Spireguard": 3},
	{"Mothership": 1, "Shardling": 4, "Spireguard": 2},
]
const SIGNAL_STATES := ["available", "active", "done"]


static func pool_kinds() -> Array[String]:
	var kinds: Array[String] = []
	for kind: String in POOL:
		for index in range(POOL[kind]):
			kinds.append(kind)
	return kinds


static func empty() -> Dictionary:
	return {"parts": 0, "signal": "available", "progress": 0}


# Pilots without saved gate progress start empty; no save migration is needed.
static func state(equipment: Dictionary) -> Dictionary:
	return equipment.get("gates", empty())


static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or not Skylab.integer(value.get("parts"), 0, MAX_PARTS):
		return false
	if not value.get("signal") is String or not value["signal"] in SIGNAL_STATES:
		return false
	return Skylab.integer(value.get("progress"), 0, int(SIGNAL["required"]) - 1 if value["signal"] == "active" else 0)


static func normalize(value: Dictionary) -> void:
	value["parts"] = int(value["parts"])
	value["progress"] = int(value["progress"])


static func signal_active(gates: Dictionary) -> bool:
	return gates.get("signal", "") == "active"


## Parts carried by one destroyed alien. `guaranteed` adds the signal operation's part.
static func roll_parts(kind: String, rng: RandomNumberGenerator, guaranteed: bool) -> int:
	var parts := 1 if guaranteed else 0
	if rng.randf() < float(PART_CHANCE.get(kind, 0.0)):
		parts += 1
	return parts


## Adds collected parts. `qualifying` of them came from the operation's map and
## count toward an active signal operation. Returns the next state with any reward.
static func collect(gates: Dictionary, amount: int, qualifying: int) -> Dictionary:
	var next := gates.duplicate()
	var result := {"gates": next, "credits": 0, "research": 0, "completed": false}
	next["parts"] = mini(MAX_PARTS, int(next["parts"]) + amount)
	if not signal_active(next) or qualifying <= 0:
		return result
	var progress := int(next["progress"]) + qualifying
	if progress < int(SIGNAL["required"]):
		next["progress"] = progress
		return result
	next["signal"] = "done"
	next["progress"] = 0
	next["parts"] = mini(MAX_PARTS, int(next["parts"]) + int(SIGNAL["parts"]))
	result["credits"] = SIGNAL["credits"]
	result["research"] = SIGNAL["research"]
	result["completed"] = true
	return result


static func accept_blocker(gates: Dictionary) -> String:
	match gates["signal"]:
		"active": return "Signal Anomaly is already active."
		"done": return "Assemble the %s before tracing another signal." % NAME
	return ""


static func assemble_blocker(gates: Dictionary) -> String:
	if int(gates["parts"]) < PARTS_REQUIRED:
		return "Need %d gate parts; %d collected." % [PARTS_REQUIRED, int(gates["parts"])]
	return ""


## Consumes one gate's parts. A finished signal operation becomes available again.
static func assemble(gates: Dictionary) -> Dictionary:
	var next := gates.duplicate()
	next["parts"] = int(next["parts"]) - PARTS_REQUIRED
	if next["signal"] == "done":
		next["signal"] = "available"
	return next


## Alien counts for one wave, locked when it starts. The boss never scales, and
## a boss wave leaves enough dormant Shardlings for the mothership's escorts.
static func wave_counts(wave: int, pilots: int) -> Dictionary:
	var counts := {}
	var extra := clampi(pilots, 1, SCALED_PILOTS) - 1
	var boss_wave: bool = WAVES[wave].has("Mothership")
	for kind: String in WAVES[wave]:
		var base := int(WAVES[wave][kind])
		var limit := int(POOL[kind]) - (ESCORTS if boss_wave and kind == "Shardling" else 0)
		counts[kind] = base if kind == "Mothership" else mini(limit, base + int(base * extra / 2.0))
	return counts


static func signal_objective(gates: Dictionary) -> String:
	return "%s  %d / %d" % [SIGNAL["objective"], int(gates["progress"]), int(SIGNAL["required"])]


static func reward_text(item: bool) -> String:
	var text := "%s and +%s x4 shots" % [Story.reward_text(REWARD["credits"], REWARD["research"]), StationShop.credits_text(REWARD["x4"])]
	return text + (" and an %s laser (in storage)" % Equipment.MODELS[REWARD["item"]]["name"] if item else "")
