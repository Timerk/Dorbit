extends SceneTree
## Runtime values consumed by the Python provisioning parity guard.


func _initialize() -> void:
	var models := {}
	for id: String in Equipment.MODELS:
		var model: Dictionary = Equipment.MODELS[id]
		models[id] = {"kind": model["kind"], "family": model.get("family", "")}
	print("PROVISIONING_SCHEMA:", JSON.stringify({
		"models": models,
		"laser_ammo": Ammunition.TYPES.keys(),
		"rocket_ammo": Ammunition.ROCKETS.keys(),
		"starter_ammo": Ammunition.starter(),
	}))
	quit()
