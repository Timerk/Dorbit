class_name Quickslots
extends RefCounted
## Device-local shortcuts refer to actions, never inventory instances or quantities.

signal changed

const PATH := "user://quickslots.cfg"
const DEFAULT_SLOTS: Array[String] = [
	"ammo:x1", "ammo:x2", "ammo:x3", "ammo:x4", "ammo:r-310",
	"ammo:eco-10", "rocket:single", "rocket:launcher", "rocket:unload", "",
]
var slots: Array[String] = DEFAULT_SLOTS.duplicate()
var vertical := false
var save_path := PATH


static func valid_id(value: Variant) -> bool:
	if not value is String or value.length() > 80:
		return false
	if value.is_empty():
		return true
	var parts: PackedStringArray = value.split(":")
	if parts.size() != 2 or parts[0] not in ["ammo", "rocket", "extra"] or parts[1].is_empty():
		return false
	for character: String in parts[1]:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			return false
	return true


func assign(index: int, action: String) -> void:
	if index < 0 or index >= slots.size() or not valid_id(action):
		return
	slots[index] = action
	changed.emit()


func swap(first: int, second: int) -> void:
	if first < 0 or first >= slots.size() or second < 0 or second >= slots.size():
		return
	var previous := slots[first]
	slots[first] = slots[second]
	slots[second] = previous
	changed.emit()


func reset_slots() -> void:
	slots = DEFAULT_SLOTS.duplicate()
	changed.emit()


func save() -> bool:
	var config := ConfigFile.new()
	config.set_value("bar", "slots", slots)
	config.set_value("bar", "vertical", vertical)
	return config.save(save_path) == OK


func load_from() -> void:
	slots = DEFAULT_SLOTS.duplicate()
	vertical = false
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	var stored: Variant = config.get_value("bar", "slots", null)
	if stored is Array and stored.size() == DEFAULT_SLOTS.size():
		for index in slots.size():
			if valid_id(stored[index]):
				slots[index] = stored[index]
	var orientation: Variant = config.get_value("bar", "vertical", false)
	vertical = orientation is bool and orientation
