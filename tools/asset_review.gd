extends SceneTree
## Paired native-renderer captures and monitor samples. Run with an isolated APPDATA.
## --review-output=res://build/asset-review/before (then after reimport, /after).

var sector: Sector
var camera: Camera3D
var output := "res://build/asset-review/before"
var samples: Array[Dictionary] = []
var retained: Array[Resource] = []
var mesh_inventory: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func frames(count: int = 30) -> void:
	for index in count:
		await process_frame

func capture(label: String, eye: Vector3, focus: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(focus)
	await frames()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.save_png(output.path_join(label + ".png")) != OK:
		push_error("Cannot save " + label)
		quit(1)
	var primitives: Array[float] = []
	for index in 30:
		await process_frame
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	primitives.sort()
	samples.append({"view": label, "eye": str(eye), "focus": str(focus),
		"primitives": primitives[15], "primitives_min": primitives[0], "primitives_max": primitives[29],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"buffer_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)})
	print(JSON.stringify(samples.back()))

func model(path: String, parent: Node3D, at: Vector3) -> Node3D:
	var instance := (load(path) as PackedScene).instantiate() as Node3D
	parent.add_child(instance)
	instance.position = at
	if not mesh_inventory.any(func(entry: Dictionary) -> bool: return entry.path == path):
		var triangles := 0
		var materials := {}
		var textures := {}
		for mesh: MeshInstance3D in instance.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				triangles += mesh.mesh.surface_get_array_index_len(surface) / 3
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				if material == null:
					continue
				materials[material.get_instance_id()] = true
				for channel in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
					var texture := material.get_texture(channel)
					if texture != null:
						var image := texture.get_image()
						textures[texture.get_instance_id()] = {"channel": channel, "width": texture.get_width(), "height": texture.get_height(), "compressed": image.is_compressed(), "format": image.get_format(), "mipmaps": image.has_mipmaps()}
		mesh_inventory.append({"path": path, "triangles": triangles, "materials": materials.size(), "textures": textures.values()})
	return instance

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Asset review requires a rendered window")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):
			output = argument.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	seed(12345)
	sector = load("res://scenes/sector.tscn").instantiate()
	sector.offline = true
	sector.client_only = false
	root.add_child(sector)
	sector.session.launch()
	sector.session.menu.hide()
	sector.set_paused(false)
	sector.settings = GameSettings.new()
	sector.apply_graphics(false)
	await frames(2)
	# Freeze simulation and HUD state. Shader TIME remains cosmetic.
	sector.process_mode = Node.PROCESS_MODE_DISABLED
	sector.player.model.hide()
	for enemy: Alien in sector.world_aliens.values():
		enemy.position = SectorMaps.origin(enemy.map_id) + Vector3((enemy.alien_id % 5 - 2) * 20, 0, -180)
	for label: Label3D in sector.find_children("*", "Label3D", true, false):
		label.hide()
	camera = Camera3D.new()
	root.add_child(camera)
	camera.fov = 60
	camera.far = 16000
	camera.current = true
	await frames(90)
	await capture("station-near", Sector.STATION_POSITION + Vector3(150, 110, 230), Sector.STATION_POSITION + Vector3(0, 100, 0))
	await capture("station-far", Sector.STATION_POSITION + Vector3(400, 250, 800), Sector.STATION_POSITION + Vector3(0, 100, 0))
	# Every playable hull uses its actual imported materials and normal maps.
	var lineup := Node3D.new()
	sector.add_child(lineup)
	for index in 12:
		var hull: String = ["aegis", "bigboy", "defcom", "goliath", "leonov", "liberator", "nostromo", "phoenix", "piranha", "spearhead", "vengeance", "yamato"][index]
		model("res://assets/ships/%s.glb" % hull, lineup, Vector3((index % 4 - 1.5) * 11, (index / 4 - 1) * 10, 0))
	await capture("ships-near", Vector3(0, 18, 55), Vector3.ZERO)
	await capture("ships-far", Vector3(0, 50, 180), Vector3.ZERO)
	lineup.hide()
	for map in 4:
		sector.player.map_id = map
		sector.activate_map(map)
		var origin := SectorMaps.origin(map)
		var planet: Vector3 = origin + SectorBackdrop.THEMES[map]["planet"]
		var direction := (planet - origin).normalized()
		await capture("planet-%d-near" % (map + 1), origin + direction * 1050, planet)
		await capture("planet-%d-far" % (map + 1), origin - direction * 500, planet)
		if map == 1:
			var gate := SectorMaps.gate_position(1, 0)
			await capture("gate-near", gate + Vector3(28, 9, 65), gate)
			await capture("gate-far", gate + Vector3(100, 45, 350), gate)
	# Controlled busy scene: all three gates, ten pilots and five aliens remain
	# in view at both distances; no simulation, visibility ranges or occlusion.
	sector.hide()
	sector.hud.hide()
	var busy := Node3D.new()
	root.add_child(busy)
	for index in 3:
		model("res://assets/sector/transit-gate.glb", busy, Vector3((index - 1) * 100, 0, 0))
	var pilots := Node3D.new()
	busy.add_child(pilots)
	for index in 10:
		model("res://assets/ships/%s.glb" % ("goliath" if index % 2 else "liberator"), pilots, Vector3((index % 5 - 2) * 35, 65 + (index / 5) * 25, 0))
	for index in 5:
		model("res://assets/aliens/%s.glb" % ("raider" if index > 2 else "skirmisher"), pilots, Vector3((index - 2) * 35, -65, 0))
	root.mesh_lod_threshold = 1.0
	await capture("busy-near-lod", Vector3(0, 20, 400), Vector3(0, 20, 0))
	await capture("busy-far-lod", Vector3(0, 20, 2000), Vector3(0, 20, 0))
	root.mesh_lod_threshold = 0.0
	await capture("busy-far-base", Vector3(0, 20, 2000), Vector3(0, 20, 0))
	pilots.hide()
	root.mesh_lod_threshold = 1.0
	await capture("three-gates-near-lod", Vector3(0, 0, 400), Vector3.ZERO)
	await capture("three-gates-far-lod", Vector3(0, 0, 2000), Vector3.ZERO)
	root.mesh_lod_threshold = 0.0
	await capture("three-gates-far-base", Vector3(0, 0, 2000), Vector3.ZERO)
	pilots.show()
	# Load every PNG as a second, explicit inventory measurement. Keep references
	# alive so on-demand menu images cannot make before/after residency differ.
	var inventory: Array[Dictionary] = []
	load_pngs("res://assets", inventory)
	await capture("all-pngs-resident", Vector3(0, 20, 2000), Vector3(0, 20, 0))
	var report := {"engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "resolution": "1440x900", "msaa": root.msaa_3d,
		"note": "Frozen offline sector and controlled busy lineup; not a multiplayer FPS benchmark. Monitor video memory is engine accounting, not total driver VRAM.",
		"samples": samples, "png_inventory": inventory, "mesh_inventory": mesh_inventory}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	quit()

func load_pngs(directory: String, inventory: Array[Dictionary]) -> void:
	for filename in DirAccess.get_files_at(directory):
		if filename.ends_with(".png"):
			var path := directory.path_join(filename)
			var texture := load(path) as Texture2D
			retained.append(texture)
			var image := texture.get_image()
			inventory.append({"path": path, "width": texture.get_width(), "height": texture.get_height(), "format": image.get_format(), "mipmaps": image.has_mipmaps(), "data_bytes": image.get_data_size()})
	for child in DirAccess.get_directories_at(directory):
		load_pngs(directory.path_join(child), inventory)
