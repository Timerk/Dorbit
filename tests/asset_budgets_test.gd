extends SceneTree
## Catch import regressions using the actual generated textures, not source sizes.

var failures := 0
var count := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	count += 1
	if not ok:
		failures += 1
		push_error(message)

func inspect(directory: String) -> void:
	for filename in DirAccess.get_files_at(directory):
		if not filename.ends_with(".png"):
			continue
		var path := directory.path_join(filename)
		var config := ConfigFile.new()
		check(config.load(path + ".import") == OK, "Import settings exist: " + path)
		var texture := load(path) as Texture2D
		check(texture != null, "Imported texture loads: " + path)
		if texture == null:
			continue
		var image := texture.get_image()
		var longest := maxi(texture.get_width(), texture.get_height())
		if path.begins_with("res://assets/ui/"):
			check(config.get_value("params", "compress/mode") == 0, "UI stays lossless: " + path)
			var limit := 512
			if "/menu/ships/" in path:
				limit = 800
			elif filename == "equipment-atlas.png":
				limit = 1024
			elif "/maps/" in path or filename in ["station.png", "hangar-background.png"]:
				limit = 2048
			check(longest <= limit, "UI imported dimensions fit budget: " + path)
		else:
			check(config.get_value("params", "compress/mode") == 2, "3D uses VRAM compression: " + path)
			check(image.is_compressed(), "3D generated image is compressed: " + path)
			check(image.has_mipmaps(), "3D generated image includes mipmaps: " + path)
			check(longest <= 2048, "3D imported dimensions fit budget: " + path)
			if "normal" in filename.to_lower():
				check(config.get_value("params", "compress/normal_map") == 1, "Normal map compression is explicit: " + path)
	for child in DirAccess.get_directories_at(directory):
		inspect(directory.path_join(child))

func run() -> void:
	inspect("res://assets")
	print("Asset budgets: %d checks, %d failures" % [count, failures])
	quit(1 if failures else 0)
