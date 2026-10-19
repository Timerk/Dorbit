extends SceneTree
## Rendered review of story objective visuals: waypoint gate, scan field, recorder and burst.

var sector: Sector
var camera: Camera3D
var output := "res://build/validation/objective-review"


func _initialize() -> void:
	run.call_deferred()


func frames(count: int = 24) -> void:
	for frame in range(count):
		await process_frame


func capture(name: String, position: Vector3, focus: Vector3) -> void:
	camera.position = position
	camera.look_at(focus)
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))


func show_step(index: int, progress: float = 0.0) -> Vector3:
	var sites := sector.story_sites
	var step: Dictionary = Story.STEPS[index]
	var location := Story.site_position(step)
	var scanning: bool = step["type"] == "scan"
	sites.site.show()
	sites.site.position = location
	sites.gate.visible = not scanning
	sites.field.visible = scanning
	sites.recorder.visible = step["type"] == "recover"
	sites.field.scale = Vector3.ONE * float(step["radius"])
	sites.field_material.set_shader_parameter("progress", progress)
	var extent: float = StorySites.RECORDER_GATE_RADIUS if sites.recorder.visible else float(step["radius"])
	sites.gate.scale = Vector3.ONE * extent * StorySites.GATE_SCALE
	(sites.beam.material_override as ShaderMaterial).set_shader_parameter("gap", extent * 1.1 / StorySites.BEAM_HALF_HEIGHT)
	return location


func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--art-output="):
			output = argument.trim_prefix("--art-output=")
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	DisplayServer.window_set_title("Dorbit — story objective review")
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.offline = true
	sector.client_only = false
	root.add_child(sector)
	sector.session.launch()
	sector.set_physics_process(false)
	sector.session.menu.hide()
	sector.set_paused(false)
	sector.hud.hide()
	sector.player.model.hide()
	# Drive the sites directly; offline sessions have no saved chapter.
	sector.story_sites.set_process(false)
	camera = Camera3D.new()
	camera.fov = 60
	camera.far = 8500
	sector.add_child(camera)
	camera.current = true
	await frames(60)
	var gate := show_step(0)
	await capture("gate-far", gate + Vector3(30, 12, 190), gate)
	await capture("gate-near", gate + Vector3(10, 4, 48), gate)
	var field := show_step(2, 0.6)
	await capture("field-outside", field + Vector3(-70, 35, 120), field)
	show_step(2, 0.3)
	await capture("field-inside", field + Vector3(0, -8, 20), field + Vector3(0, 6, -60))
	var recorder := show_step(5)
	await capture("recorder", recorder + Vector3(10, 5, 26), recorder)
	sector.story_sites.site.hide()
	var flash := sector.story_sites.effect(StorySites.GATE_SHADER, sector.story_sites)
	flash.position = gate
	flash.scale = Vector3.ONE * 25.0 * StorySites.GATE_SCALE
	flash.set_instance_shader_parameter("burst", 0.3)
	await capture("burst", gate + Vector3(10, 4, 70), gate)
	print("Captured story objective gate, field, recorder and completion burst.")
	quit()
