extends SceneTree
## Render real sector views with an isolated profile; capture evidence and frame timings.

var sector: Sector
var output := "res://build/validation/sector-art"


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--art-output="):
			output = argument.trim_prefix("--art-output=")
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create sector review directory: " + output)
		quit(1)
		return
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.offline = true
	sector.client_only = false
	root.add_child(sector)
	sector.session.launch()
	sector.set_physics_process(false)
	sector.session.menu.hide()
	sector.set_paused(false)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_title("Dorbit - sector art review")
	await frames(60)
	await capture("station-approach", Vector3(0, 0, 45), Sector.STATION_POSITION)
	await capture("hunting-lane", Vector3(0, 0, 45), Vector3(0, 8, -440))
	await capture("outer-sector", Vector3(280, 40, -260), Vector3(1350, 480, -2500))
	# Inspect the imported shape and texture near an actual obstacle.
	var rock := sector.get_node("Asteroid4") as StaticBody3D
	await capture("asteroid-detail", rock.position + Vector3(22, 9, 35), rock.position)
	await capture("dock-interior", Sector.STATION_POSITION + Vector3(0, 0, 22), Sector.STATION_POSITION + Vector3(0, 0, -20))
	await capture("reverse-view", Vector3(0, 0, -250), Vector3(-500, 120, 1000))
	var map_reports: Array[Dictionary] = []
	for map: int in SectorMaps.MAPS:
		sector.player.map_id = map
		sector.activate_map(map)
		var origin := SectorMaps.origin(map)
		await capture("m%d-flight" % (map+1), origin+Vector3(0,0,100), origin+Vector3(0,300,-3400))
		sector.hud.hide()
		await capture("m%d-background" % (map+1), origin+Vector3(0,0,-450), origin+Vector3(0,300,-3400))
		sector.hud.show()
		await capture("m%d-planet" % (map+1), origin+Vector3(0,80,-280), origin+SectorBackdrop.THEMES[map]["planet"])
		await capture("m%d-reverse" % (map+1), origin+Vector3(0,0,-200), origin+Vector3(0,100,2400))
		var forward: Vector3 = SectorBackdrop.THEMES[map]["planet"].normalized()
		await capture("m%d-boundary" % (map+1), origin+forward*1100.0, origin+SectorBackdrop.THEMES[map]["planet"])
		var intervals: Array[float] = []
		var previous_frame := Time.get_ticks_usec()
		for frame in range(120):
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append((now-previous_frame)/1000.0)
			previous_frame = now
		intervals.sort()
		var total := 0.0
		for interval in intervals:
			total += interval
		map_reports.append({"map": map+1, "average_ms": total/intervals.size(), "p95_ms": intervals[int(intervals.size()*0.95)], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
	sector.player.map_id = 0
	sector.activate_map(0)
	sector.player.position = Sector.SPAWN_POSITION
	sector.player.rotation = Vector3.ZERO
	# Leave aliens running while sampling rendered frame intervals.
	var timings: Array[float] = []
	var previous := Time.get_ticks_usec()
	for index in range(240):
		for enemy: Alien in sector.aliens.values():
			enemy.fly(1.0/60.0, null, Sector.STATION_POSITION)
		await process_frame
		var now := Time.get_ticks_usec()
		timings.append((now - previous) / 1000.0)
		previous = now
	timings.sort()
	var sum := 0.0
	for value in timings:
		sum += value
	var report := {"resolution": str(root.get_texture().get_size()), "renderer": "GL Compatibility", "msaa": "4x", "vsync": "disabled", "frames": timings.size(), "average_fps": 1000.0 / (sum / timings.size()), "p95_ms": timings[int(timings.size()*0.95)], "adapter": RenderingServer.get_video_adapter_name(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "maps": map_reports, "note": "Single local rendered sector; five patrolling aliens. Map samples use 120 frames after each boundary view. Not a multiplayer capacity benchmark."}
	var report_file := FileAccess.open(output.path_join("render-report.json"), FileAccess.WRITE)
	if report_file == null:
		push_error("Cannot write sector frame report: " + output)
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit()


func frames(count: int) -> void:
	for index in range(count):
		await process_frame


func capture(label: String, position: Vector3, focus: Vector3) -> void:
	sector.set_paused(false)
	sector.player.position = position
	sector.player.look_at(focus)
	await frames(20)
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(label + ".png")) != OK:
		push_error("Cannot save sector review capture: " + label)
		quit(1)
