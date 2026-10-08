extends "res://tests/hud_customization_test.gd"
## Actual GUI drags, input dispatch, local persistence and optional extras lifecycle.

var extra_calls := 0
var extra_enabled := false


func extra_state() -> Dictionary:
	return {"name": "Test CPU", "active": extra_enabled, "count": "ON" if extra_enabled else "OFF", "tooltip": "Test toggle", "available": true}


func extra_command() -> void:
	extra_calls += 1
	extra_enabled = not extra_enabled


func move_cursor(point: Vector2) -> void:
	if DisplayServer.get_name() != "headless":
		root.warp_mouse(point)
		await process_frame


func click(point: Vector2) -> void:
	await move_cursor(point)
	await super.click(point)


func find_drag_preview(node: Node) -> Control:
	if node.name == "QuickslotDragPreview":
		return node as Control
	for child: Node in node.get_children(true):
		var preview := find_drag_preview(child)
		if preview != null:
			return preview
	return null


func gui_drag(start: Vector2, finish: Vector2, source: QuickslotTile = null, screenshot: String = "") -> void:
	await move_cursor(start)
	var motion := InputEventMouseMotion.new()
	motion.position = start
	root.push_input(motion)
	await process_frame
	await pointer(start, true)
	for point: Vector2 in [start + Vector2(12, 0), finish - Vector2(100, 100), finish]:
		await move_cursor(point)
		motion = InputEventMouseMotion.new()
		motion.position = point
		motion.relative = point - start
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion)
		await process_frame
		if point == finish - Vector2(100, 100) and source != null:
			var preview := find_drag_preview(root)
			check(root.gui_is_dragging() and preview != null, "Actual GUI drag creates a complete tile preview")
			if preview != null:
				var tile := preview.get_child(0) as Button
				var rows := tile.get_child(0) as VBoxContainer
				var header := rows.get_child(0) as HBoxContainer
				check((rows.get_child(1) as TextureRect).texture == source.art.texture and (rows.get_child(2) as Label).text == source.amount.text, "Drag preview retains the item picture and quantity/status")
				check((header.get_child(0) as Label).text == source.key_label.text and (header.get_child(1) as Label).text == source.title.text, "Drag preview retains the shortcut and title")
				check(tile.get_global_rect().size.is_equal_approx(source.get_global_rect().size) and tile.get_theme_stylebox("normal") == source.get_theme_stylebox("normal"), "Drag preview retains the full tile size, scale and background")
				check(not preview.z_as_relative and preview.z_index > source.bar.picker.z_index, "Drag preview draws above the category picker")
			if not screenshot.is_empty():
				await capture(screenshot)
	await pointer(finish, false)
	await process_frame


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	await sync_physics()
	var bar := sector.hud.ammo_bar
	var layout := sector.hud.layout
	bar.config.save_path = "user://quickslots-test.cfg"
	layout.save_path = "user://quickslots-layout-test.cfg"
	bar.config.slots = Quickslots.DEFAULT_SLOTS.duplicate()
	bar.config.vertical = false
	layout.entries.clear()
	sector.settings.reset_controls()
	await process_frame
	check(bar.tiles.size() == 10 and bar.config.slots == Quickslots.DEFAULT_SLOTS, "First bar contains ten mixed default slots")
	check(GameSettings.binding_text("quickslot_10") == "0", "Tenth slot defaults to zero")
	await tap_key(KEY_3)
	check(sector.player.ammo_type == "x3" and not sector.auto_fire, "Quickslot selects ammunition without starting laser fire")
	bar.config.swap(0, 2)
	await tap_key(KEY_1)
	check(sector.player.ammo_type == "x3", "Rearranging contents keeps the key attached to the slot")
	sector.settings.rebind("quickslot_1", KEY_H)
	sector.player.ammo_type = "x1"
	await tap_key(KEY_1)
	check(sector.player.ammo_type == "x1", "Old slot key no longer activates its contents")
	await tap_key(KEY_H, false)
	check(sector.player.ammo_type == "x3" and bar.tiles[0].key_label.text == "H", "Rebound logical key and visible key label activate the moved item")
	sector.settings.rebind("fire", KEY_H)
	check(sector.settings.bindings.quickslot_1 == KEY_SPACE and sector.settings.bindings.fire == KEY_H, "Flight and quickslot binding conflicts swap")
	sector.settings.reset_controls()
	bar.config.reset_slots()
	layout.close_item("ammo")
	await tap_key(KEY_2)
	check(sector.player.ammo_type == "x2", "Hidden bar retains its keyboard shortcuts")
	layout.reopen("ammo")
	var target_before := sector.target
	sector.auto_fire = true
	sector.autopilot.enabled = true
	await click(bar.items_button.get_global_rect().get_center())
	await process_frame
	check(not layout.editing and not sector.paused and not layout.sidebar.visible and bar.slot_editing and bar.picker.visible, "Plus opens quickslot customization directly without entering HUD editing or pausing")
	check(sector.auto_fire and sector.autopilot.enabled, "Opening the quickslot picker does not cancel flight or laser fire")
	check(bar.picker.find_children("*", "Button", true, false).all(func(button: Button): return button.text != "Edit quickslots"), "Picker has no redundant edit quickslots button")
	sector.auto_fire = false
	sector.autopilot.enabled = false
	var original := layout.rect_for("ammo")
	layout.store_rect("ammo", Rect2(original.position, original.size * 0.8))
	await process_frame
	await process_frame
	var before := layout.rect_for("ammo")
	await gui_drag(bar.tiles[0].get_global_rect().get_center(), bar.tiles[2].get_global_rect().get_center(), bar.tiles[0], "quickslots-drag-1440")
	check(bar.config.slots[0] == "ammo:x3" and bar.config.slots[2] == "ammo:x1", "GUI drag swaps occupied quickslots")
	check(layout.rect_for("ammo") == before and sector.target == target_before and not sector.auto_fire, "Slot drag neither moves the bar nor targets or fires")
	layout.reset_layout()
	await process_frame
	await process_frame
	var source := bar.picker_tiles.filter(func(tile: QuickslotTile): return tile.action_id == "ammo:x4")[0] as QuickslotTile
	await gui_drag(source.get_global_rect().get_center(), bar.tiles[9].get_global_rect().get_center(), source)
	check(bar.config.slots[9] == "ammo:x4", "GUI drag from picker assigns an empty slot")
	await click(bar.tiles[9].get_global_rect().get_center())
	bar.clear_button.pressed.emit()
	check(bar.config.slots[9].is_empty(), "Selected slot can be explicitly cleared")
	await click(bar.tiles[0].get_global_rect().get_center())
	await click(source.get_global_rect().get_center())
	check(bar.config.slots[0] == "ammo:x4", "Click slot then picker item assigns without dragging")
	await tap_key(KEY_1)
	check(sector.player.ammo_type == "x4" and not sector.paused, "Quickslot keys remain usable while the picker is open")
	bar.register_extra("test-cpu", extra_state, extra_command)
	bar.config.assign(9, "extra:test-cpu")
	await process_frame
	await gui_drag(bar.tiles[9].get_global_rect().get_center(), Vector2(1000, 550), bar.tiles[9])
	check(extra_calls == 0 and bar.config.slots[9] == "extra:test-cpu" and sector.target == target_before, "Cancelled extra drag preserves assignment without activating or targeting")
	bar.tabs.current_tab = 1
	await process_frame
	var unassigned := bar.picker_tiles.filter(func(tile: QuickslotTile): return tile.action_id == "ammo:plt-2021")[0] as QuickslotTile
	await click(unassigned.get_global_rect().get_center())
	check(sector.player.rockets.single_type == "plt-2021" and not bar.config.slots.has("ammo:plt-2021"), "Flight picker selects ammunition that is not assigned to any slot")
	await click(bar.items_button.get_global_rect().get_center())
	check(not bar.picker.visible and not bar.slot_editing and not layout.editing, "Plus closes customization without entering HUD editing")
	bar.tabs.current_tab = 0
	await tap_key(KEY_0)
	check(extra_calls == 1 and extra_enabled and bar.tiles[9].button_pressed, "Usable extra executes once and shows its live toggle state")
	var repeat := InputEventKey.new()
	repeat.keycode = KEY_0
	repeat.pressed = true
	repeat.echo = true
	root.push_input(repeat)
	await process_frame
	check(extra_calls == 1, "Key repeat does not repeatedly toggle an extra")
	bar.unregister_extra("test-cpu")
	await process_frame
	await tap_key(KEY_0)
	check(extra_calls == 1 and bar.config.slots[9] == "extra:test-cpu" and bar.tiles[9].disabled, "Missing extra retains its assignment and cannot activate")
	bar.register_extra("test-cpu", extra_state, extra_command)
	await tap_key(KEY_0)
	check(extra_calls == 2 and not extra_enabled, "Restored extra reuses the saved assignment")
	sector.set_paused(true)
	bar.activate("extra:test-cpu")
	check(extra_calls == 2, "Menu blocks click activation")
	sector.set_paused(false)
	bar.begin_editing()
	bar.toggle_orientation()
	await process_frame
	check(bar.config.vertical and Rect2(Vector2.ZERO, layout.size).encloses(layout.rect_for("ammo")), "Vertical orientation keeps the whole bar on screen")
	for tile: QuickslotTile in bar.tiles:
		check(bar.get_global_rect().encloses(tile.get_global_rect()), "Vertical tile stays inside instrument")
		check(tile.get_global_rect().encloses((tile.get_child(0) as Control).get_global_rect()), "Compact vertical contents fit their tile")
	await gui_drag(bar.tiles[0].get_global_rect().get_center(), bar.tiles[2].get_global_rect().get_center(), bar.tiles[0])
	bar.config.swap(0, 2)
	await capture("quickslots-vertical-1440")
	var saved := bar.config.slots.duplicate()
	var fresh := Quickslots.new()
	fresh.save_path = bar.config.save_path
	fresh.load_from()
	check(fresh.slots == saved and fresh.vertical, "Assignments and orientation survive a fresh configuration instance")
	layout.reset_layout()
	check(bar.config.slots == saved, "Reset layout leaves slot assignments intact")
	bar.config.reset_slots()
	check(bar.config.slots == Quickslots.DEFAULT_SLOTS and bar.config.vertical, "Reset slots preserves orientation")
	bar.toggle_orientation()
	layout.reset_layout()
	for pixels in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		root.size = pixels
		root.content_scale_size = pixels
		DisplayServer.window_set_size(pixels)
		await sync_physics()
		await process_frame
		await process_frame
		check(Rect2(Vector2.ZERO, layout.size).encloses(bar.get_global_rect()) and Rect2(Vector2.ZERO, layout.size).encloses(bar.picker.get_global_rect()), "Bar and picker fit at %s" % pixels)
		check(not bar.get_global_rect().intersects(sector.hud.ship_rect()) and not bar.get_global_rect().intersects(sector.hud.target_rect()), "Bar clears status cards at %s" % pixels)
		check(not bar.get_global_rect().intersects(bar.picker.get_global_rect()), "Default picker does not cover quickslots at %s" % pixels)
		for tile: QuickslotTile in bar.tiles:
			check(tile.get_global_rect().encloses((tile.get_child(0) as Control).get_global_rect()), "Horizontal contents fit their tile at %s" % pixels)
		for tile: QuickslotTile in bar.picker_tiles:
			if tile.action_id in ["ammo:x1", "ammo:x2", "ammo:x3", "ammo:x4"]:
				var clip := (bar.tabs.get_current_tab_control() as Control).get_global_rect()
				check(clip.encloses(tile.get_global_rect()), "Picker shows the complete ammo tile and count at %s: %s / %s" % [pixels, clip, tile.get_global_rect()])
		await capture("quickslots-editor-%d" % pixels.x)
	bar.close_picker()
	await process_frame
	check(not bar.picker.visible and not bar.slot_editing and not sector.paused, "Closing the picker finishes customization without pausing")
	await capture("quickslots-flight-1920")
	bar.begin_editing()
	layout.set_editing(true)
	await process_frame
	await process_frame
	check(not bar.picker.visible and not bar.slot_editing and bar.items_button.disabled, "HUD placement mode closes customization and retains whole-bar dragging")
	layout.set_editing(false)
	await process_frame
	var malformed := ConfigFile.new()
	malformed.set_value("bar", "slots", ["bad", "", 5, {}, "ammo:r-310", "ammo:eco-10", "rocket:single", "rocket:launcher", "extra:missing", ""])
	malformed.set_value("bar", "vertical", "yes")
	malformed.save("user://quickslots-malformed.cfg")
	fresh.save_path = "user://quickslots-malformed.cfg"
	fresh.load_from()
	check(fresh.slots[0] == "ammo:x1" and fresh.slots[1].is_empty() and fresh.slots[2] == "ammo:x3" and not fresh.vertical, "Malformed entries keep defaults while explicit empty slots remain empty")
	check(fresh.slots[8] == "extra:missing", "Unknown future action IDs remain saved")
	var legacy := ConfigFile.new()
	legacy.set_value("bindings", "fire", KEY_5)
	legacy.save("user://quickslots-legacy-controls.cfg")
	var settings := GameSettings.new()
	settings.load_from("user://quickslots-legacy-controls.cfg")
	check(settings.bindings.fire == KEY_5 and settings.bindings.quickslot_5 == KEY_SPACE, "Legacy occupied digit binding is preserved with a usable swapped slot key")
	settings.rebind("quickslot_1", KEY_H)
	settings.save("user://quickslots-saved-controls.cfg")
	var restored := GameSettings.new()
	restored.load_from("user://quickslots-saved-controls.cfg")
	check(restored.bindings == settings.bindings, "Quickslot and legacy control bindings survive save and reload")
	sector.settings.configure_input()
	for field: String in ["preflight", "paused"]:
		sector.set(field, true)
		bar.activate("extra:test-cpu")
		check(extra_calls == 2, "%s blocks quickslot activation" % field)
		sector.set(field, false)
	sector.player.alive = false
	bar.activate("extra:test-cpu")
	check(extra_calls == 2, "Destroyed ship cannot activate a quickslot")
	sector.player.alive = true
	sector.client_only = true
	bar.activate("extra:test-cpu")
	check(extra_calls == 2, "Disconnected client cannot activate a quickslot")
	sector.queue_free()
	await process_frame
	print("Quickslots: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
