extends "res://tests/encounter_test.gd"
## Measures steady-flight HUD cost: process time and engine objects created per frame.
## Uses only existing game APIs, so the same script measures older builds.
## Run with a renderer: --path . --script res://tests/hud_redraw_benchmark.gd

const FRAMES := 900
const CALLS := 2000


func created_objects() -> int:
	# ObjectDB IDs carry a validator that increases with every created object.
	var probe := Object.new()
	var id := probe.get_instance_id()
	probe.free()
	return id >> 24


func measure(label: String) -> void:
	var player := sector.player
	for frame in range(60):
		player.rotation.y += 0.002
		await process_frame
	var first := created_objects()
	var times: Array[float] = []
	for frame in range(FRAMES):
		# Turning keeps every marker and radar contact moving between frames.
		player.rotation.y += 0.002
		await process_frame
		times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	var created := created_objects() - first - 1
	times.sort()
	print("HUD BENCHMARK %s: median %.3f ms process / %.2f objects created per frame" % [label, times[FRAMES / 2], float(created) / FRAMES])


func time_calls(label: String, callable: Callable) -> void:
	var start := Time.get_ticks_usec()
	for call in range(CALLS):
		callable.call()
	print("HUD BENCHMARK %s: %.2f us per call" % [label, float(Time.get_ticks_usec() - start) / CALLS])


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	sector.settings.configure_input()
	sector.show_performance = false
	sector.toast_time = 0
	await sync_physics()
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	var player := sector.player
	player.position = Vector3(500, 350, 600)
	player.rotation = Vector3(0.1, 0.5, 0)
	sector.aliens[1].position = Vector3(600, 440, 320)
	sector.select_target(sector.aliens[1])
	sector.session.active = true
	for kind: String in HuntingContracts.OFFERS:
		sector.active_contracts[kind] = HuntingContracts.accept(kind)
	var navigation := sector.hud.navigation
	time_calls("contacts()", func(): navigation.contacts())
	time_calls("destination()", func(): navigation.destination())
	time_calls("binding_text()", func(): GameSettings.binding_text("jump_gate"))
	sector.hud.visible = false
	await measure("hud hidden")
	sector.hud.visible = true
	await measure("flight")
	navigation.open_overview()
	await measure("overview")
	navigation.close_overview()
	sector.session.active = false
	quit(0 if failures == 0 else 1)
