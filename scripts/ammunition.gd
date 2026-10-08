class_name Ammunition
extends RefCounted
## Pilot-wide shot inventory. Each fitted laser consumes one round per volley.

const BATCH_SIZE: int = 100
const MAX_PURCHASE_BATCHES: int = 10_000 # One million rounds per order.
const MAX_SHOTS: int = 2_000_000_000
const TYPES := {
	"x1": {"name": "x1 ammunition", "multiplier": 1, "price": 10, "color": Color("b7d7ef")},
	"x2": {"name": "x2 ammunition", "multiplier": 2, "price": 50, "color": Color("66e2ee")},
	"x3": {"name": "x3 ammunition", "multiplier": 3, "price": 100, "color": Color("ffbf66")},
	"x4": {"name": "x4 ammunition", "multiplier": 4, "price": 0, "color": Color("c69bff")},
}
# Absolute damage, in Dorbit metres. These are game balancing defaults, not exact
# DarkOrbit mechanics. Launcher damage is fixed average damage unless varied.
const ROCKETS := {
	"r-310": {"name": "R-310", "damage": 1000.0, "range": 120.0, "accuracy": 0.70, "speed": 150.0, "cooldown": 2.0, "minimum": 0.80, "maximum": 1.0, "price": 100 * BATCH_SIZE, "launcher": false},
	"plt-2026": {"name": "PLT-2026", "damage": 2000.0, "range": 170.0, "accuracy": 0.80, "speed": 170.0, "cooldown": 2.0, "minimum": 0.80, "maximum": 1.0, "price": 500 * BATCH_SIZE, "launcher": false},
	"plt-2021": {"name": "PLT-2021", "damage": 4000.0, "range": 240.0, "accuracy": 0.90, "speed": 190.0, "cooldown": 2.0, "minimum": 0.80, "maximum": 1.0, "price": 5 * Equipment.URIDIUM_TO_CREDITS * BATCH_SIZE, "launcher": false},
	"plt-3030": {"name": "PLT-3030", "damage": 6000.0, "range": 240.0, "accuracy": 0.65, "speed": 190.0, "cooldown": 2.0, "minimum": 0.80, "maximum": 1.0, "price": 7 * Equipment.URIDIUM_TO_CREDITS * BATCH_SIZE, "launcher": false},
	"eco-10": {"name": "ECO-10", "damage": 2000.0, "range": 200.0, "accuracy": 1.0, "speed": 170.0, "minimum": 1.0, "maximum": 1.0, "price": 1500 * BATCH_SIZE, "launcher": true},
	"hstrm-01": {"name": "HSTRM-01", "damage": 4000.0, "range": 200.0, "accuracy": 1.0, "speed": 170.0, "minimum": 1.0, "maximum": 1.0, "price": 25 * Equipment.URIDIUM_TO_CREDITS * BATCH_SIZE, "launcher": true},
}


static func types() -> Dictionary:
	var result := TYPES.duplicate()
	result.merge(ROCKETS)
	return result


static func starter() -> Dictionary:
	var result := {"x1": 10000, "x2": 0, "x3": 0, "x4": 0}
	for kind: String in ROCKETS:
		result[kind] = 100 if kind == "r-310" else 0
	return result


static func valid(value: Variant, legacy: bool = false) -> bool:
	var catalog := TYPES if legacy else types()
	if not value is Dictionary or value.size() != catalog.size():
		return false
	for kind: String in catalog:
		var amount: Variant = value.get(kind)
		if not (amount is int or amount is float) or not is_finite(amount) or amount != floor(amount) or amount < 0 or amount > MAX_SHOTS:
			return false
	return true


static func purchase_blocker(kind: String) -> String:
	if not types().has(kind):
		return "Unknown ammunition type."
	return "x4 is reserved for future quests and special rewards." if kind == "x4" else ""
