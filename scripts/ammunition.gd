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


static func starter() -> Dictionary:
	return {"x1": 10000, "x2": 0, "x3": 0, "x4": 0}


static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != TYPES.size():
		return false
	for kind: String in TYPES:
		var amount: Variant = value.get(kind)
		if not (amount is int or amount is float) or not is_finite(amount) or amount != floor(amount) or amount < 0 or amount > MAX_SHOTS:
			return false
	return true


static func purchase_blocker(kind: String) -> String:
	if not TYPES.has(kind):
		return "Unknown ammunition type."
	return "x4 is reserved for future quests and special rewards." if kind == "x4" else ""
