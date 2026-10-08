extends SceneTree
## Capture the actual contract previews, plus rear views of the shared game meshes.


func _initialize() -> void:
	render_preview.call_deferred()


func render_preview() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Alien review rendering requires a graphics display.")
		quit(1)
		return
	root.size = Vector2i(1680, 1040)
	root.content_scale_size = root.size
	var backdrop := ColorRect.new()
	backdrop.color = Color("101b2b")
	backdrop.size = root.size
	root.add_child(backdrop)
	var previews: Array[ContractPreview] = []
	var column := 0
	for kind: String in Alien.TYPES:
		for row in 2:
			var label := Label.new()
			label.text = kind + (" · contract preview" if row == 0 else " · rear machinery")
			label.position = Vector2(column * 560 + 24, row * 520 + 18)
			label.add_theme_font_size_override("font_size", 23)
			root.add_child(label)
			var preview := ContractPreview.new()
			preview.position = Vector2(column * 560, row * 520 + 54)
			preview.size = Vector2(560, 460)
			root.add_child(preview)
			preview.show_kind(kind)
			if row == 1:
				preview.camera.position = Vector3(-8, 5, 10)
				preview.camera.look_at(Vector3.ZERO)
			previews.append(preview)
		column += 1
	for frame in 32:
		await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://build/validation")
	DirAccess.make_dir_recursive_absolute(directory)
	var error := root.get_texture().get_image().save_png(directory.path_join("alien-models-godot.png"))
	print("ALIEN_PREVIEWS ", root.size, " renderer=", RenderingServer.get_video_adapter_name(), " result=", error)
	quit(error)
