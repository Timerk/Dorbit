extends SceneTree
## Render actual game finishes: shop thumbnails, optional hangar and six views.

const VIEWS := {"perspective": Vector2(-2.48, .55), "front": Vector2(PI, 0),
	"rear": Vector2(0, 0), "side": Vector2(-PI / 2, 0),
	"top": Vector2(PI, PI / 2 - .001), "underside": Vector2(PI, -PI / 2 + .001)}


func _initialize() -> void:
	render_preview.call_deferred()


func render_preview() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Thumbnail rendering requires a graphics display.")
		quit(1)
		return
	var arguments := OS.get_cmdline_user_args()
	var review := "--review" in arguments
	var models: Array[String] = []
	for argument in arguments:
		if argument != "--review":
			if not ShipCatalog.MODELS.has(argument):
				push_error("Unknown ship: " + argument)
				quit(1)
				return
			models.append(argument)
	if models.is_empty():
		models.assign(ShipCatalog.MODELS.keys())
	for model in models:
		var preview := ShipHangarPreview.new()
		preview.size = Vector2(900, 600) if review else Vector2(400, 360)
		root.add_child(preview)
		preview.set_model(model)
		var directory := "res://art/ship-review/materials/" + model
		if review:
			DirAccess.make_dir_recursive_absolute(directory)
			if not await save_view(preview, directory + "/hangar.png"):
				return
		preview.stage.transparent_bg = true
		var world := preview.room.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
		world.environment.background_mode = Environment.BG_CLEAR_COLOR
		for node: Node in preview.room.find_children("*", "MeshInstance3D", true, false):
			if not preview.hull.is_ancestor_of(node):
				(node as MeshInstance3D).hide()
		preview.size = Vector2(400, 360)
		preview.update_size()
		if not await save_view(preview, "res://assets/ui/ships/" + model + ".png"):
			return
		if review:
			# Technical angles need readable undersides as well as the lit upper hull.
			# This studio fill is only for review images, after the game thumbnail.
			var studio_sky := ProceduralSkyMaterial.new()
			studio_sky.sky_top_color = Color(.18, .23, .31)
			studio_sky.sky_horizon_color = Color(.48, .55, .63)
			studio_sky.ground_bottom_color = Color(.24, .28, .34)
			studio_sky.ground_horizon_color = Color(.34, .39, .46)
			world.environment.sky = Sky.new()
			world.environment.sky.sky_material = studio_sky
			var lower_fill := DirectionalLight3D.new()
			lower_fill.rotation_degrees = Vector3(60, 40, 0)
			lower_fill.light_energy = .8
			preview.room.add_child(lower_fill)
			preview.size = Vector2(600, 540)
			preview.update_size()
			preview.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			preview.camera.size = 7.8
			preview.distance = 12.0
			for view in VIEWS:
				var angles: Vector2 = VIEWS[view]
				preview.yaw = angles.x
				preview.pitch = angles.y
				preview.update_camera()
				if not await save_view(preview, directory + "/" + view + ".png"):
					return
		preview.free()
		print("RENDERED ", model, " shop thumbnail", " and seven review views" if review else "")
	quit()


func save_view(preview: ShipHangarPreview, path: String) -> bool:
	preview.request_render()
	for frame in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := preview.stage.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save " + path)
		quit(error)
	return error == OK
