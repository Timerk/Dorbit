class_name CargoResources
extends RefCounted
## Prices, loot and hold sizes are provisional playtesting values.

const TYPES := {
	"prometium": {"name": "Prometium", "price": 10, "color": Color("ef704b")},
	"endurium": {"name": "Endurium", "price": 20, "color": Color("b4d7e9")},
	"terbium": {"name": "Terbium", "price": 40, "color": Color("d6df56")},
	"prometid": {"name": "Prometid", "price": 80, "color": Color("f6a5d5")},
	"duranium": {"name": "Duranium", "price": 160, "color": Color("7be3b0")},
	"xenomit": {"name": "Xenomit", "price": 200, "color": Color("eee8d8")},
	"promerium": {"name": "Promerium", "price": 320, "color": Color("ffc55d")},
	"seprom": {"name": "Seprom", "price": 640, "color": Color("ab83ff")},
}
const LOOT := {
	"Scout": {"prometium": Vector2i(6, 10), "endurium": Vector2i(2, 4), "terbium": Vector2i(1, 2)},
	"Sentinel": {"prometium": Vector2i(10, 16), "endurium": Vector2i(6, 10), "terbium": Vector2i(4, 6), "prometid": Vector2i(2, 4), "duranium": Vector2i(1, 2)},
	"Heavy": {"prometium": Vector2i(18, 24), "endurium": Vector2i(12, 18), "terbium": Vector2i(8, 12), "prometid": Vector2i(6, 10), "duranium": Vector2i(4, 6), "xenomit": Vector2i(1, 3), "promerium": Vector2i(2, 4), "seprom": Vector2i(1, 2)},
}

static func capacity(equipment: Dictionary, ship: String = "") -> int:
	if ship.is_empty():
		ship = equipment["active_ship"]
	return int(ShipCatalog.info(equipment["ships"][ship])["cargo"]) * (2 if not Equipment.extra(equipment, "cargo", ship).is_empty() else 1)

static func empty_holds(equipment: Dictionary) -> Dictionary:
	var holds := {}
	for ship: String in equipment["ships"]:
		holds[ship] = {}
	return holds

static func units(amounts: Dictionary) -> int:
	var total := 0
	for amount: Variant in amounts.values():
		total += int(amount)
	return total

static func value(amounts: Dictionary) -> int:
	var total := 0
	for resource: String in amounts:
		total += int(amounts[resource]) * int(TYPES[resource]["price"])
	return total

static func valid(holds: Variant, equipment: Dictionary) -> bool:
	if not holds is Dictionary or holds.size() != equipment["ships"].size():
		return false
	for ship: Variant in holds:
		if not ship is String or not equipment["ships"].has(ship) or not holds[ship] is Dictionary:
			return false
		for resource: Variant in holds[ship]:
			var amount: Variant = holds[ship][resource]
			if not resource is String or not TYPES.has(resource) or not (amount is int or amount is float):
				return false
			# Delivery may overfill a hold. Bounds still reject corrupt or overflowing saves.
			if not is_finite(amount) or amount < 1 or amount > 2 * capacity(equipment, ship) or amount != floor(amount):
				return false
		# A single shipment can add at most one hold to cargo that filled during transit.
		if units(holds[ship]) > 2 * capacity(equipment, ship):
			return false
	return true

static func roll(kind: String) -> Dictionary:
	var result := {}
	for resource: String in LOOT.get(kind, {}):
		var quantity: Vector2i = LOOT[kind][resource]
		result[resource] = randi_range(quantity.x, quantity.y)
	return result

# Take valuable resources first when only part of a box fits. Leave every excess unit.
static func collect(hold: Dictionary, contents: Dictionary, limit: int) -> Dictionary:
	var room := maxi(0, limit - units(hold))
	var taken := {}
	var ordered := TYPES.keys()
	ordered.reverse()
	for resource: String in ordered:
		var count := mini(room, int(contents.get(resource, 0)))
		if count == 0:
			continue
		hold[resource] = int(hold.get(resource, 0)) + count
		contents[resource] -= count
		if contents[resource] == 0:
			contents.erase(resource)
		taken[resource] = count
		room -= count
	return taken

static func describe(amounts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for resource: String in TYPES:
		if amounts.has(resource):
			parts.append("%s x%d" % [TYPES[resource]["name"], amounts[resource]])
	return ", ".join(parts)
