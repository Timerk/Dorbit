extends "res://tests/encounter_test.gd"
## Real preview input, world isolation, material maps and idle rendering lifecycle.

var preview: ShipHangarPreview


func settle_preview() -> void:
	for frame in range(24):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func capture_preview(label: String) -> void:
	await settle_preview()
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build/validation")
		check(preview.stage.get_texture().get_image().save_png("res://build/validation/" + label + ".png") == OK, "Save " + label)


func run() -> void:
	root.size = Vector2i(1200, 800)
	preview = ShipHangarPreview.new()
	preview.size = Vector2(1200, 800)
	root.add_child(preview)
	preview.set_model("liberator")
	check(preview.stage.own_world_3d and preview.stage.find_world_3d() != root.find_world_3d(), "Hangar lighting stays isolated from the sector")
	check(preview.hull.find_children("*", "MeshInstance3D", true, false).size() == 1, "Preview uses the exported flight mesh")
	await capture_preview("liberator-hangar")
	check(preview.stage.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Idle preview stops drawing after its initial frames")
	var rotation := preview.camera.rotation
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(600, 400)
	root.push_input(down)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(740, 380)
	motion.relative = Vector2(140, -20)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion)
	await process_frame
	down.pressed = false
	root.push_input(down)
	check(not preview.camera.rotation.is_equal_approx(rotation), "Mouse drag orbits the preview camera")
	check(preview.stage.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Camera movement refreshes the cached preview")
	await capture_preview("liberator-hangar-orbit")
	var old_distance := preview.distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(600, 400)
	root.push_input(wheel)
	await process_frame
	check(preview.distance < old_distance, "Mouse wheel zooms the hull")
	preview.yaw = -2.48
	preview.pitch = .32
	preview.distance = 7.5
	preview.update_camera()
	await capture_preview("liberator-hangar-detail")
	preview.hide()
	check(preview.stage.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden preview renders no frames")
	preview.show()
	check(preview.stage.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Reopening the preview refreshes it")
	preview.set_model("phoenix")
	check(preview.hull.name == "PreviewHull" and preview.room.find_children("PreviewHull", "Node3D", true, false).size() == 1, "Hull switching replaces the preview without duplicates")
	preview.set_model("liberator")
	preview.yaw = -2.48
	preview.pitch = .55
	preview.distance = 9.2
	preview.update_camera()
	await capture_preview("liberator-hangar")
	# Optional comparison against the untextured GLB saved before this material pass.
	var baseline := "res://build/validation/liberator-before-materials.glb"
	if FileAccess.file_exists(baseline) and DisplayServer.get_name() != "headless":
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		check(document.append_from_file(ProjectSettings.globalize_path(baseline), state) == OK, "Load optional material comparison")
		preview.room.remove_child(preview.hull)
		preview.hull.queue_free()
		preview.hull = document.generate_scene(state)
		preview.room.add_child(preview.hull)
		preview.request_render()
		await capture_preview("liberator-hangar-before-materials")
	preview.free()
	print("Hangar checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
