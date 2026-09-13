extends "res://tests/server_workload.gd"
## Render one workload client. Run alongside the server and nine headless workload clients.

var frame_ms: Array[float] = []
var frames_started := 0
var render_complete := false
var previous_frame_us := 0
var captured_entry := false
var captured_combat := false


func run() -> void:
	await super.run()
	if sector.dedicated_server:
		return
	var viewport := sector.get_viewport() as SubViewport
	viewport.size = Vector2i(1440, 900)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.size = viewport.size
	root.add_child(display)
	DisplayServer.window_set_size(viewport.size)
	DisplayServer.window_set_title("Dorbit alien variety validation")
	sector.show_performance = true


func _process(_delta: float) -> bool:
	if not is_instance_valid(sector) or sector.dedicated_server or render_complete:
		return false
	if sector.session.alien_sequences.size() == sector.aliens.size() and not captured_entry:
		captured_entry = true
		save_frame.call_deferred("hunting-entry.png")
	for id: int in sector.session.goals:
		if sector.session.ships.has(id) and sector.session.ships[id] != sector.player:
			sector.session.ships[id].position = sector.session.goals[id]["position"]
			sector.session.ships[id].rotation = sector.session.goals[id]["rotation"]
	if sector.session.received_snapshot:
		sector.set_paused(false)
		var enemy := sector.aliens[int(options.get("index", "0")) % sector.aliens.size()]
		if enemy.available() and sector.target != enemy:
			sector.select_target(enemy)
		sector.auto_fire = enemy.available()
		sector.player.look_at(enemy.position, Vector3.UP)
		sector.weapon_status = sector.player.firing_blocker(sector.target)
	if options.has("output") and FileAccess.file_exists(options["output"].path_join("start.json")):
		var now := Time.get_ticks_usec()
		if frames_started == 0:
			frames_started = now
		if previous_frame_us > 0:
			frame_ms.append((now - previous_frame_us) / 1000.0)
		previous_frame_us = now
		if frame_ms.size() >= 600 and not captured_combat:
			captured_combat = true
			save_frame.call_deferred("hunting-combat.png")
		if FileAccess.file_exists(options["output"].path_join("server.json")):
			render_complete = true
			var elapsed := (Time.get_ticks_usec() - frames_started) / 1000000.0
			write_json("rendered-client.json", {
				"frames": frame_ms.size(), "elapsed_seconds": elapsed,
				"average_fps": frame_ms.size() / elapsed, "frame_ms": distribution(frame_ms),
				"resolution": "1440x900", "msaa": "4x", "renderer": "GL Compatibility",
				"adapter": RenderingServer.get_video_adapter_name(), "os": OS.get_name(),
				"notes": "One rendered scripted client plus nine headless clients and a dedicated server on one Windows machine; no input prediction."
			})
			save_frame.call_deferred("rendered-sector.png")
	return false


func save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	sector.get_viewport().get_texture().get_image().save_png(options["output"].path_join(filename))
