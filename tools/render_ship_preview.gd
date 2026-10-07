extends SceneTree
## Rebuild the Liberator shop thumbnail using its actual Godot materials.


func _initialize() -> void:
	render_preview.call_deferred()


func render_preview() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Thumbnail rendering requires a graphics display.")
		quit(1)
		return
	var preview := ShipHangarPreview.new()
	preview.size = Vector2(400, 360)
	root.add_child(preview)
	preview.set_model("liberator")
	preview.stage.transparent_bg = true
	var world := preview.room.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
	world.environment.background_mode = Environment.BG_CLEAR_COLOR
	for node: Node in preview.room.find_children("*", "MeshInstance3D", true, false):
		if not preview.hull.is_ancestor_of(node):
			(node as MeshInstance3D).hide()
	preview.request_render()
	for frame in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := preview.stage.get_texture().get_image().save_png("res://assets/ui/ships/liberator.png")
	preview.free()
	quit(error)
