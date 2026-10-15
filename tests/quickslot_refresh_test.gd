extends "res://tests/encounter_test.gd"
## Quickslot tiles re-apply theme overrides and text only when their shown state changes.


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	await sync_physics()
	var bar := sector.hud.ammo_bar
	bar.config.save_path = "user://quickslot-refresh-test.cfg"
	bar.config.reset_slots()
	bar.set_process(false)
	var player := sector.player
	player.ammo["x2"] = 5000
	bar.refresh_tiles()
	var tile := bar.tiles[1]
	var notices := [0]
	tile.amount.theme_changed.connect(func(): notices[0] += 1)
	var styles := [0]
	tile.theme_changed.connect(func(): styles[0] += 1)
	for frame in 5:
		bar.refresh_tiles()
	check(notices[0] == 0 and styles[0] == 0, "Unchanged state does not re-apply the tile's theme overrides")
	check(tile.amount.text == "5,000" and tile.amount.get_theme_color("font_color") == FlightHud.INK, "Unchanged tile keeps its count and colour")

	player.ammo["x2"] = 4000
	bar.refresh_tiles()
	check(tile.amount.text == "4,000" and notices[0] == 0, "Count change with the same colour leaves the override alone")
	player.ammo["x2"] = 0
	bar.refresh_tiles()
	check(tile.amount.text == "0" and tile.amount.get_theme_color("font_color") == FlightHud.RED and notices[0] == 1, "Running out updates the count and colour once")

	player.ammo_type = "x2"
	bar.refresh_tiles()
	check(tile.button_pressed and tile.get_theme_stylebox("normal") == tile.selected_style, "Selected ammunition highlights its tile")
	player.ammo_type = "x1"
	bar.refresh_tiles()
	check(not tile.button_pressed and tile.get_theme_stylebox("normal") == tile.normal_style, "Deselected ammunition clears its highlight")
	tile.set_pressed_no_signal(true)
	bar.refresh_tiles()
	check(not tile.button_pressed, "A click toggle is corrected even when the shown state is unchanged")

	var single := bar.single_fire as QuickslotTile
	var cooldown_notices := [0]
	single.amount.theme_changed.connect(func(): cooldown_notices[0] += 1)
	player.rockets.single_cooldown = 1.23
	bar.refresh_tiles()
	check(single.amount.text == "1.2s", "Cooldown shows its remaining time")
	player.rockets.single_cooldown = 0.51
	bar.refresh_tiles()
	check(single.amount.text == "0.5s" and cooldown_notices[0] == 0, "Cooldown updates text without theme changes")
	player.rockets.single_cooldown = 0.0
	bar.refresh_tiles()
	check(single.amount.text == "FIRE", "Finished cooldown returns to FIRE")

	sector.settings.rebind("quickslot_2", KEY_H)
	bar.refresh_tiles()
	check(tile.key_label.text == "H", "Rebinding updates the key label")
	check(tile.get_tooltip(Vector2.ZERO).contains("rounds per volley") and tile.get_tooltip(Vector2.ZERO).contains("Press H"), "Tooltip is built on demand with the current binding")
	sector.settings.reset_controls()
	bar.refresh_tiles()

	var picker_tile: QuickslotTile = bar.picker_tiles.filter(func(entry: QuickslotTile): return entry.action_id == "ammo:x2")[0]
	var shown_before := picker_tile.amount.text
	player.ammo["x2"] = 777
	bar.refresh_tiles()
	check(picker_tile.amount.text == shown_before, "Hidden picker tiles are not refreshed")
	bar.begin_editing()
	check(picker_tile.amount.text == "777" and tile.amount.text == "777", "Opening the picker refreshes its tiles")
	bar.close_picker()
	bar.config.reset_slots()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bar.config.save_path))
	print("Quickslot refresh: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
