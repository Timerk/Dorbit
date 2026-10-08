extends "res://tests/encounter_test.gd"
## Input-driven editor regression. Run rendered for visual captures in build/validation.


func _process(_delta: float) -> bool:
	# Ignore OS focus changes during this deterministic replay.
	if is_instance_valid(sector) and is_instance_valid(sector.hud):
		sector.set_paused(sector.hud.layout.editing or sector.hud.navigation.overview.visible)
	return false


func chord(pressed: bool = true, echo: bool = false, control_last: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_CTRL if control_last else KEY_ALT
	# Match Windows: the event excludes the modifier flag for its own key.
	event.ctrl_pressed = pressed and not control_last
	event.alt_pressed = pressed and control_last
	event.pressed = pressed
	event.echo = echo
	root.push_input(event)
	await process_frame


func pointer(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	root.push_input(event)
	await process_frame


func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
	await process_frame
	await pointer(point, true)
	await pointer(point, false)


func drag(start: Vector2, finish: Vector2) -> void:
	await pointer(start, true)
	var event := InputEventMouseMotion.new()
	event.position = finish
	event.relative = finish - start
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event)
	await process_frame
	await pointer(finish, false)


func capture(label: String) -> void:
	await create_timer(0.15).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://build/validation")
		DirAccess.make_dir_recursive_absolute(directory)
		root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	await sync_physics()
	var hud := sector.hud
	var layout := hud.layout
	var initial_performance := sector.settings.show_performance
	layout.save_path = "user://hud-customization-test.cfg"
	layout.entries.clear()
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_H
	shortcut.ctrl_pressed = true
	shortcut.alt_pressed = true
	shortcut.pressed = true
	root.push_input(shortcut)
	await process_frame
	check(not layout.editing, "Ctrl+Alt+letter events cannot accidentally start editing")
	shortcut.keycode = KEY_ALT
	shortcut.location = KEY_LOCATION_RIGHT
	root.push_input(shortcut)
	await process_frame
	check(not layout.editing, "Right Alt / AltGr cannot accidentally start editing")
	shortcut.pressed = false
	root.push_input(shortcut)
	sector.auto_fire = true
	sector.autopilot.enabled = true
	sector.player.steering = true
	await chord()
	check(layout.editing and layout.sidebar.visible and sector.paused, "Ctrl+Alt enters editor with a sidebar and suspended local controls")
	check(not sector.auto_fire and not sector.autopilot.enabled and not sector.player.steering, "Editing releases steering, fire and autopilot")
	await chord(true, true)
	check(layout.editing, "Key repeat cannot toggle the editor")
	await chord(false)
	await chord(true, false, true)
	check(not layout.editing, "Alt-then-Ctrl finishes editing with Windows modifier flags")
	await chord(false, false, true)
	await chord(true, false, true)
	check(layout.editing, "Alt-then-Ctrl enters editing with Windows modifier flags")
	await chord(false, false, true)
	await capture("hud-editor-1440")
	check(not sector.settings_menu.pause_panel.visible, "HUD editing never displays the pause menu")
	# A sidebar icon selects even a covered panel without altering its saved layout.
	await click(layout.buttons["ship"].get_global_rect().get_center())
	check(not layout.sidebar.visible and layout.rail_toggle.visible, "Selecting a covered panel exposes its handles by hiding the sidebar")
	layout.selected_id = "reticle"
	layout.entries["reticle"] = {"position": Vector2(0.1, 0.9), "scale": 1.2, "visible": true}
	var reticle := layout.rect_for("reticle")
	check(reticle.get_center().is_equal_approx(layout.size * 0.5), "Previously saved reticle positions are ignored")
	await drag(reticle.position + Vector2(20, -12), reticle.position + Vector2(200, 60))
	check(layout.rect_for("reticle") == reticle, "Dragging the reticle title cannot move or resize it")
	await drag(reticle.get_center(), reticle.get_center() + Vector2(100, 80))
	check(layout.rect_for("reticle") == reticle, "Dragging the reticle body cannot move it")
	await drag(reticle.end - Vector2(8, 8), reticle.end + Vector2(25, 10))
	reticle = layout.rect_for("reticle")
	check(reticle.size.x > layout.default_rect("reticle").size.x * 1.2 and reticle.get_center().is_equal_approx(layout.size * 0.5), "Reticle resizing grows around the screen center")
	check(not layout.entries["reticle"].has("position"), "Reticle customization saves only scale and visibility")
	layout.selected_id = "ship"
	var original := layout.rect_for("ship")
	await drag(original.position + Vector2(80, -12), original.position + Vector2(413, -225))
	var moved := layout.rect_for("ship")
	check(moved.position.distance_to(original.position) > 100 and moved.size.is_equal_approx(original.size), "Dragging a panel moves it without resizing")
	check(is_equal_approx(fmod(moved.position.x, HudLayout.GRID), 0), "Panel movement snaps to the visible grid")
	layout.snap = false
	await drag(moved.position + Vector2(80, -12), moved.position + Vector2(93, -5))
	check(layout.rect_for("ship").position.is_equal_approx(moved.position + Vector2(13, 7)), "Disabling grid snapping allows precise free placement")
	layout.snap = true
	moved = layout.rect_for("ship")
	var target_before := sector.target
	await click(moved.get_center())
	await tap_key(KEY_SPACE)
	await tap_key(KEY_M)
	check(sector.target == target_before and not sector.auto_fire and not hud.navigation.overview.visible, "Editor clicks and shortcuts cannot target, fire or open flight menus")
	await drag(moved.end - Vector2(8, 8), moved.end + Vector2(140, 90))
	var enlarged := layout.rect_for("ship")
	check(enlarged.size.x > moved.size.x and is_equal_approx(enlarged.size.x / enlarged.size.y, original.size.x / original.size.y), "Corner resizing grows the panel without distorting its content")
	await drag(enlarged.end - Vector2(8, 8), enlarged.end - Vector2(2000, 2000))
	var minimum := layout.rect_for("ship")
	check(minimum.size.is_equal_approx(original.size * HudLayout.MIN_SCALE), "Panels stop shrinking at the readable minimum")
	await drag(minimum.position + Vector2(50, -12), Vector2(5000, 5000))
	check(Rect2(Vector2.ZERO, layout.size).encloses(layout.rect_for("ship")), "Dragging cannot lose a panel outside the screen")
	var ship := layout.rect_for("ship")
	await click(Vector2(ship.end.x - 12, ship.position.y - 12))
	check(not layout.shown("ship"), "Window close control hides the panel")
	await click(layout.rail_toggle.get_global_rect().get_center())
	await click(layout.buttons["ship"].get_global_rect().get_center())
	check(layout.shown("ship"), "Sidebar icon reopens a closed panel")
	var ammo := hud.ammo_bar
	layout.selected_id = "ammo"
	var ammo_original := layout.rect_for("ammo")
	var ammo_type := sector.player.ammo_type
	check(ammo.visible and ammo.buttons["x1"].disabled, "Editor shows the ammo bar without enabling ammo selection")
	await drag(ammo.buttons["x2"].get_global_rect().get_center(), ammo.buttons["x2"].get_global_rect().get_center() + Vector2(0, -300))
	var ammo_moved := layout.rect_for("ammo")
	check(ammo_moved.position.y < ammo_original.position.y - 200 and sector.player.ammo_type == ammo_type, "Dragging an ammo tile moves the whole bar without changing ammunition")
	await drag(ammo_moved.end - Vector2(8, 8), ammo_moved.end - Vector2(2000, 2000))
	check(layout.rect_for("ammo").size.is_equal_approx(ammo_original.size * HudLayout.MIN_SCALE), "The entire ammo bar stops shrinking at the HUD minimum")
	var ammo_minimum := layout.rect_for("ammo")
	await drag(ammo_minimum.end - Vector2(8, 8), ammo_minimum.end + Vector2(120, 40))
	var ammo_enlarged := layout.rect_for("ammo")
	check(ammo_enlarged.size.x > ammo_original.size.x and is_equal_approx(ammo_enlarged.size.x / ammo_enlarged.size.y, ammo_original.size.x / ammo_original.size.y), "Resizing the ammo corner grows the whole horizontal bar proportionally")
	layout.store_rect("ammo", Rect2(Vector2(560, 510), ammo_original.size * 1.4))
	await process_frame
	check(ammo.get_global_rect().is_equal_approx(layout.rect_for("ammo")), "Ammo container follows the customized position and proportional scale")
	var previous_tile := Rect2()
	for kind: String in Ammunition.TYPES:
		var tile := ammo.buttons[kind].get_global_rect()
		check(ammo.get_global_rect().encloses(tile) and (previous_tile == Rect2() or tile.position.x > previous_tile.position.x and is_equal_approx(tile.position.y, previous_tile.position.y)), "The %s tile stays in the ordered horizontal bar" % kind)
		previous_tile = tile
	var ammo_rect := layout.rect_for("ammo")
	await click(Vector2(ammo_rect.end.x - 12, ammo_rect.position.y - 12))
	check(not ammo.visible and not layout.shown("ammo"), "Closing ammunition hides all tiles together")
	layout.sidebar.show()
	var ammo_scroll := layout.buttons["ammo"].get_parent().get_parent() as ScrollContainer
	ammo_scroll.ensure_control_visible(layout.buttons["ammo"])
	await process_frame
	await click(layout.buttons["ammo"].get_global_rect().get_center())
	check(ammo.visible and layout.shown("ammo"), "The sidebar ammunition icon restores the entire bar")
	# Keep the restored ship away from the radar under test.
	layout.store_rect("ship", Rect2(240, 600, 290, 174))
	var radar := layout.default_rect("radar")
	layout.store_rect("radar", Rect2(Vector2(800, 100), radar.size * 1.4))
	layout.close_item("target")
	await tap_key(KEY_ESCAPE)
	check(not layout.editing and not sector.paused and not layout.sidebar.visible, "Escape finishes editing without opening a pause menu")
	await process_frame
	var button := hud.navigation.range_more
	check(layout.rect_for("radar").encloses(button.get_global_rect()), "Resized radar controls stay inside the moved radar")
	check(button.get_global_rect().size.is_equal_approx(Vector2(26, 26) * 1.4), "Compact radar controls scale with the customized panel")
	check(button.get_global_rect().end.y <= layout.rect_for("radar").position.y + 34 * 1.4, "Customized radar controls retain the gap above the header divider")
	var previous_range := hud.navigation.range_index
	await click(button.get_global_rect().get_center())
	check(hud.navigation.range_index == previous_range + 1, "Radar button remains clickable after moving and resizing")
	await click(ammo.buttons["x3"].get_global_rect().get_center())
	check(sector.player.ammo_type == "x3" and ammo.buttons["x3"].button_pressed, "A moved and resized ammunition tile still selects ammo after editing")
	await capture("hud-customized-1440")
	var saved := layout.entries.duplicate(true)
	layout.entries.clear()
	layout.load_layout()
	check(layout.entries == saved, "Positions, scales and hidden state survive a fresh configuration load")
	await process_frame
	check(ammo.get_global_rect().is_equal_approx(layout.rect_for("ammo")), "Saved ammunition geometry is restored on the whole bar")
	check(layout.rect_for("reticle").get_center().is_equal_approx(layout.size * 0.5), "Reloading retains the centered, resized reticle")
	var fresh := HudLayout.new()
	fresh.save_path = layout.save_path
	fresh.load_layout()
	check(fresh.entries == saved, "A fresh layout instance restores the same saved preferences")
	fresh.free()
	for pixels in [Vector2i(960, 600), Vector2i(1920, 1080)]:
		root.size = pixels
		root.content_scale_size = pixels
		DisplayServer.window_set_size(pixels)
		await sync_physics()
		check(layout.rect_for("reticle").get_center().is_equal_approx(layout.size * 0.5), "Reticle stays centered when resizing the viewport")
		for id: String in HudLayout.ITEMS:
			check(Rect2(Vector2.ZERO, layout.size).encloses(layout.rect_for(id)), "Saved %s remains reachable at %d" % [id, pixels.x])
		await chord()
		await chord(false)
		await capture("hud-editor-%d" % pixels.x)
		await chord()
		await chord(false)
		check(not layout.editing, "Ctrl+Alt also finishes editing")
	var invalid := ConfigFile.new()
	invalid.set_value("ship", "position", Vector2(NAN, INF))
	invalid.set_value("ship", "scale", "invalid")
	invalid.set_value("target", "position", Vector2(-50, 500))
	invalid.set_value("target", "scale", -5.0)
	invalid.save(layout.save_path)
	layout.load_layout()
	check(layout.rect_for("ship") == layout.default_rect("ship"), "Invalid saved geometry falls back to the default panel")
	check(Rect2(Vector2.ZERO, layout.size).encloses(layout.rect_for("target")), "Out-of-range saved geometry is clamped safely")
	layout.set_editing(true)
	layout.reset_layout()
	check(layout.entries.is_empty() and layout.shown("target"), "Reset restores every default panel and visibility")
	# Every instrument uses the same editor lifecycle, including conditional ones.
	layout.sidebar.hide()
	layout.rail_toggle.hide()
	for id: String in HudLayout.ITEMS:
		layout.selected_id = id
		var rect := layout.rect_for(id)
		await click(Vector2(rect.end.x - 12, rect.position.y - 12))
		check(not layout.shown(id), "The %s instrument has a working close control" % id)
		layout.reopen(id)
		check(layout.shown(id), "The %s instrument can be restored" % id)
	layout.set_editing(false)
	layout.set_editing(true)
	sector.player.alive = false
	await process_frame
	check(not layout.editing, "Rescue automatically closes the editor")
	sector.player.reset_health()
	sector.preflight = true
	layout.set_editing(true)
	check(not layout.editing, "The customization shortcut is unavailable in the docked menu")
	sector.settings.show_performance = initial_performance
	sector.settings.save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(layout.save_path))
	print("HUD customization: %d passed, %d failed" % [checks - failures, failures])
	sector.free()
	quit(0 if failures == 0 else 1)
