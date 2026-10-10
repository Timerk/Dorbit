extends SceneTree
## Capture contract/rear previews, or use -- --sector for 25 m / 90 m visibility.


func _initialize() -> void:
	render_preview.call_deferred()


func render_preview() -> void:
	var sector_view := "--sector" in OS.get_cmdline_user_args()
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
			var caption := " · contract preview" if row == 0 else " · rear machinery"
			if sector_view:
				caption = " · 25 m" if row == 0 else " · 90 m"
			label.text = kind + caption
			label.position = Vector2(column * 560 + 24, row * 520 + 18)
			label.add_theme_font_size_override("font_size", 23)
			root.add_child(label)
			var preview := ContractPreview.new()
			preview.position = Vector2(column * 560, row * 520 + 54)
			preview.size = Vector2(560, 460)
			root.add_child(preview)
			preview.show_kind(kind)
			if sector_view:
				for child: Node in preview.viewport.get_children():
					if child is WorldEnvironment or child is Light3D:
						preview.viewport.remove_child(child)
						child.queue_free()
				var world := Node3D.new()
				preview.viewport.add_child(world)
				SectorVisuals.environment(world)
				preview.viewport.transparent_bg = false
				preview.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				preview.camera.fov = 60
				preview.camera.position = Vector3(0, 4, -25 if row == 0 else -90)
				preview.camera.look_at(Vector3.ZERO)
			elif row == 1:
				preview.camera.position = Vector3(-8, 5, 10)
				preview.camera.look_at(Vector3.ZERO)
			previews.append(preview)
		column += 1
	for frame in 32:
		await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://build/validation")
	DirAccess.make_dir_recursive_absolute(directory)
	var filename := "alien-visibility-sector.png" if sector_view else "alien-models-godot.png"
	var error := root.get_texture().get_image().save_png(directory.path_join(filename))
	print("ALIEN_PREVIEWS ", root.size, " renderer=", RenderingServer.get_video_adapter_name(), " result=", error)
	quit(error)
