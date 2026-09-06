extends SceneTree
## Bundle the engine and dependency notices with the Windows executable.


func _initialize() -> void:
	var path := "res://build/windows/THIRD_PARTY_NOTICES.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write third-party notices")
		quit(1)
		return
	file.store_string("Godot Engine\n\n" + Engine.get_license_text())
	file.store_string("\n\nThird-party components\n\n" + JSON.stringify(Engine.get_copyright_info(), "  "))
	file.store_string("\n\nLicense texts\n\n" + JSON.stringify(Engine.get_license_info(), "  "))
	file.close()
	quit()
