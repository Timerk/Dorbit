extends SceneTree
## Render the actual flight models close up and deployed over a Liberator.


func _initialize() -> void:
	render_preview.call_deferred()


func render_preview() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Repair bot review needs a graphics display.")
		quit(1)
		return
	root.size = Vector2i(1440, 1100)
	root.content_scale_size = root.size
	var background := ColorRect.new()
	background.color = Color("101823")
	background.size = root.size
	root.add_child(background)
	for column in 2:
		for row in 2:
			var label := Label.new()
			label.text = "REP-%d / %s" % [column + 1, "model detail" if row == 0 else "repairing in flight"]
			label.position = Vector2(column * 720 + 24, row * 550 + 16)
			label.add_theme_font_size_override("font_size", 24)
			root.add_child(label)
			var preview := ShipHangarPreview.new()
			preview.hull_only = true
			preview.position = Vector2(column * 720, row * 550 + 55)
			preview.size = Vector2(720, 495)
			root.add_child(preview)
			preview.stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			if row == 0:
				var scene := load("res://assets/extras/rep-%d.glb" % (column + 1)) as PackedScene
				preview.room.add_child(scene.instantiate())
				preview.camera.position = Vector3(2.8, 1.7, -4.6)
				preview.camera.look_at(Vector3(0, -.15, 0))
			else:
				var pilot := Pilot.new()
				pilot.simulation_authority = false
				preview.room.add_child(pilot)
				pilot.repair_seconds = 165.0 if column == 0 else 120.0
				pilot.robot_repairing = true
				pilot.hull = pilot.max_hull * .5
				pilot.set_process(false)
				var visual := RepairBotVisual.new()
				pilot.add_child(visual)
				visual._process(0.0)
				visual.set_process(false)
				preview.camera.position = Vector3(6.8, 6.0, 12)
				preview.camera.look_at(Vector3(0, 1.0, 0))
				preview.camera.current = true
	for frame in 32:
		await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://build/validation")
	DirAccess.make_dir_recursive_absolute(directory)
	var error := root.get_texture().get_image().save_png(directory.path_join("repair-bots-godot.png"))
	print("REPAIR_BOT_PREVIEW renderer=", RenderingServer.get_video_adapter_name(), " result=", error)
	quit(error)
