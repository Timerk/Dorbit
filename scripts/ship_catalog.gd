class_name ShipCatalog
extends RefCounted
## Shared hull data also used by the offline provisioning tool.

const URIDIUM_TO_CREDITS: int = 100
# DarkOrbit map units are adapted to this sector's meter scale.
const SPEED_SCALE: float = 0.1
const BOOST_BONUS: float = 42.0
static var MODELS: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ships/catalog.json"))


static func canonical(model: String) -> String:
	# Retain saved starter IDs and item/cargo locations from earlier releases.
	return "liberator" if model == "pathfinder" else model


static func info(model: String) -> Dictionary:
	return MODELS[canonical(model)]


static func price(model: String) -> int:
	var entry := info(model)
	return int(entry["price"]) * (URIDIUM_TO_CREDITS if entry["currency"] == "uridium" else 1)


static func owned_id(data: Dictionary, model: String) -> String:
	for id: String in data.get("ships", {}):
		if canonical(data["ships"][id]) == canonical(model):
			return id
	return ""


static func slots(model: String) -> Dictionary:
	var entry := info(model)
	var result := {}
	result["launcher1"] = "launcher"
	for kind: String in ["laser", "generator", "extra"]:
		for index in range(1, int(entry[{"laser": "lasers", "generator": "generators", "extra": "extras"}[kind]]) + 1):
			result[kind + str(index)] = kind
	return result


static func model_scene(model: String) -> Node3D:
	var scene: PackedScene = load("res://assets/ships/%s.glb" % canonical(model))
	return scene.instantiate()
