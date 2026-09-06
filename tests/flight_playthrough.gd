extends SceneTree
## Replays the hunt-and-repair loop with real input and simulation time.
## Run with a renderer for screenshots and local frame-time measurements.

var sector: Sector
var frame_times: Array[float] = []
var sampling: bool = false
var failures: int = 0
var rendered: bool


func _initialize() -> void:
	rendered = DisplayServer.get_name() != "headless"
	run.call_deferred()


func _process(delta: float) -> bool:
	if sampling:
		frame_times.append(delta * 1000.0)
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func press(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func snapshot(label: String) -> void:
	if rendered:
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://build/validation")
		DirAccess.make_dir_recursive_absolute(directory)
		root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func run() -> void:
	if rendered:
		root.content_scale_size = Vector2i(2560, 1440)
		root.size = Vector2i(2560, 1440)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	sector = preload("res://scenes/sector.tscn").instantiate()
	root.add_child(sector)
	current_scene = sector
	await create_timer(1.0).timeout
	sector.set_paused(false)
	sector.show_performance = true
	await snapshot("01-departure")
	sampling = true
	await press(KEY_TAB)
	await press(KEY_SPACE)
	Input.action_press("forward")
	await create_timer(3.4).timeout
	Input.action_release("forward")
	await create_timer(0.6).timeout
	await snapshot("02-combat")
	var deadline := Time.get_ticks_msec() + 25000
	while sector.kills == 0 and Time.get_ticks_msec() < deadline and sector.player.alive:
		await physics_frame
	check(sector.kills == 1, "Pilot can kill the first alien with target-lock lasers")
	check(sector.player.alive, "First encounter is survivable without upgrades")
	check(sector.credits == Sector.KILL_REWARD, "Combat reward arrives through the live encounter")
	await snapshot("03-reward")
	Input.action_press("backward")
	deadline = Time.get_ticks_msec() + 10000
	while sector.player.position.z < 30.0 and Time.get_ticks_msec() < deadline:
		await physics_frame
	Input.action_release("backward")
	await create_timer(1.0).timeout
	deadline = Time.get_ticks_msec() + 6000
	while sector.player.time_since_hit < 5.0 and Time.get_ticks_msec() < deadline:
		await physics_frame
	await press(KEY_R)
	await process_frame
	check(sector.objective_stage == 4, "Pilot returns to the station and completes repairs")
	check(sector.player.hull == sector.player.max_hull, "Station repair restores the ship")
	sampling = false
	await snapshot("04-repaired")
	if rendered and not frame_times.is_empty():
		var render_size := root.get_texture().get_size()
		check(render_size == Vector2(2560, 1440), "Rendered replay uses the full requested resolution")
		frame_times.sort()
		var total: float = frame_times.reduce(func(sum: float, value: float) -> float: return sum + value, 0.0)
		var average := total / frame_times.size()
		var p95 := frame_times[mini(frame_times.size() - 1, floori(frame_times.size() * 0.95))]
		print("Local render measurement: GPU=%s; render_size=%s; average=%.2f ms; p95=%.2f ms; frames=%d" % [RenderingServer.get_video_adapter_name(), render_size, average, p95, frame_times.size()])
	print("Flight playthrough: %d failures; credits=%d; objective=%d" % [failures, sector.credits, sector.objective_stage])
	sector.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
