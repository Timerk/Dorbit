extends SceneTree
## Run against the exported main pack to catch missing dynamically loaded assets.

func _initialize() -> void:
	if ShipCatalog.MODELS.size() != 12:
		push_error("Exported ship catalog must contain twelve hulls.")
		quit(1)
		return
	for id: String in ShipCatalog.MODELS:
		var hull := ShipCatalog.model_scene(id)
		if hull == null or StationUi.texture(id) == null:
			push_error("Missing packaged ship assets for " + id)
			quit(1)
			return
		hull.free()
	print("Packaged ship assets: 12 models, 12 previews and catalog loaded")
	quit()
