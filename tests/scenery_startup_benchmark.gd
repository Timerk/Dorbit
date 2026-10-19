extends SceneTree
## Run in separate rendered-client and headless --server processes with fresh profiles.

var started := Time.get_ticks_usec()


func _initialize() -> void:
	run.call_deferred()


func sample(label: String) -> Dictionary:
	return {"label": label, "static_bytes": OS.get_static_memory_usage(),
		"static_peak_bytes": OS.get_static_memory_peak_usage(),
		"video_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"texture_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"buffer_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)}


func run() -> void:
	var sector := load("res://scenes/sector.tscn").instantiate() as Sector
	root.add_child(sector)
	var ready_ms := (Time.get_ticks_usec() - started) / 1000.0
	var engine_ready_ms := Time.get_ticks_usec() / 1000.0
	sector.set_physics_process(false)
	if not sector.dedicated_server:
		sector.session.menu.hide()
	for frame in range(10):
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	var result := sample("startup")
	result["ready_ms"] = ready_ms
	result["engine_ready_ms"] = engine_ready_ms
	result["settled_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	result["engine_settled_ms"] = Time.get_ticks_usec() / 1000.0
	result["dedicated"] = sector.dedicated_server
	result["renderer"] = RenderingServer.get_video_adapter_name()
	result["scenery_maps"] = sector.map_scenery.keys()
	print("SCENERY_BENCHMARK=" + JSON.stringify(result))
	if sector.dedicated_server:
		sector.session.disconnect_session("Benchmark complete")
	sector.free()
	quit()
