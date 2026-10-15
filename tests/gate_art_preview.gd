extends SceneTree
## Real Compatibility-renderer model views, followed by clean sector thumbnails.

var sector: Sector
var camera: Camera3D
var output := "res://build/validation/gate-review"

func _initialize() -> void:
	run.call_deferred()

func frames(count: int = 24) -> void:
	for frame in range(count):
		await process_frame

func capture(name: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png(output.path_join(name+".png"))

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--art-output="):
			output = argument.trim_prefix("--art-output=")
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_size(Vector2i(1440,900))
	DisplayServer.window_set_title("Dorbit — transit gate review")
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
	for label: Label3D in sector.find_children("*","Label3D",true,false):
		label.hide()
	camera = Camera3D.new()
	camera.fov = 46
	camera.far = 8500
	sector.add_child(camera)
	camera.current = true
	await frames(60)
	var gate := SectorMaps.gate_position(0,1)
	camera.position = gate+Vector3(28,9,65)
	camera.look_at(gate)
	await capture("gate-hero")
	camera.position = gate+Vector3(-26,8,-65)
	camera.look_at(gate)
	await capture("gate-rear")
	camera.position = gate+Vector3(28,9,65)
	camera.look_at(gate)
	await capture("gate-flow-later")
	# Normal behind-the-ship view at jump range, with the actual HUD and gate cue.
	camera.current = false
	sector.player.camera.current = true
	sector.player.model.show()
	sector.hud.show()
	sector.player.position = gate+Vector3(0,0,44)
	sector.player.look_at(gate)
	await capture("gate-flight")
	if "--star-map" in OS.get_cmdline_user_args():
		var navigation := sector.hud.navigation
		navigation.open_overview()
		navigation.tabs.current_tab = 1
		await frames()
		var hover := InputEventMouseMotion.new()
		hover.position = navigation.network_plot.get_global_transform()*navigation.network_plot.map_rect(3).get_center()
		root.push_input(hover)
		await capture("star-system")
		navigation.close_overview()
	if "--thumbnails" in OS.get_cmdline_user_args():
		var directory := "res://assets/ui/maps"
		DirAccess.make_dir_recursive_absolute(directory)
		sector.hud.hide()
		sector.player.model.hide()
		camera.current = true
		camera.fov = 75
		for map: int in SectorMaps.MAPS:
			sector.player.map_id = map
			sector.activate_map(map)
			for group: Node3D in sector.map_scenery[map]:
				if group.name.ends_with("Gates"):
					group.hide()
			camera.position = SectorMaps.origin(map)+Vector3(0,0,-450)
			camera.look_at(SectorMaps.origin(map)+Vector3(0,300,-3400))
			await frames()
			await RenderingServer.frame_post_draw
			var picture := root.get_texture().get_image()
			picture.resize(720,450,Image.INTERPOLATE_LANCZOS)
			picture.save_png(directory.path_join("m%d.png" % (map+1)))
	print("Captured gate hero, reverse, animated flow and ordinary flight.")
	quit()
