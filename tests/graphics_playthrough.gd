extends "res://tests/encounter_test.gd"
## Native Compatibility rendering and real keyboard interaction; isolated APPDATA.

const OUTPUT := "res://build/validation/graphics"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Graphics playthrough requires a rendered window")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	# Keep popup input inside the test viewport instead of relying on OS focus.
	root.gui_embed_subwindows = true
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	sector.settings = GameSettings.new()
	sector.apply_graphics(false)
	sector.session.menu.hide()
	sector.set_paused(false)
	await frames(40)
	var menu := sector.settings_menu
	menu.open()
	menu.tabs.current_tab = 2
	for pixels in [Vector2i(960, 600), Vector2i(1440, 900)]:
		DisplayServer.window_set_size(pixels)
		await frames(10)
		var scroll := menu.tabs.get_tab_control(2) as ScrollContainer
		scroll.scroll_vertical = 0
		await capture("menu-display-%d" % pixels.x)
		menu.graphics_options.render_scale.grab_focus()
		await frames(4)
		check(scroll.get_global_rect().encloses(menu.graphics_options.render_scale.get_global_rect()), "Keyboard scroll reaches render scale at %d pixels" % pixels.x)
		await capture("menu-quality-%d" % pixels.x)
		menu.graphics_options.effects_quality.grab_focus()
		await frames(4)
		check(scroll.get_global_rect().encloses(menu.graphics_options.effects_quality.get_global_rect()), "Keyboard scroll reaches the final effects option at %d pixels" % pixels.x)
		scroll.scroll_vertical = 100000
		await frames(4)
		await capture("menu-effects-%d" % pixels.x)
		check(root.get_visible_rect().encloses(menu.panel.get_global_rect()), "Graphics menu fits at %d pixels" % pixels.x)
	# Exercise the actual focus/input path, including dropdown popup navigation.
	for setting: String in menu.graphics_options:
		var choice := menu.graphics_options[setting]
		# Start from Off so navigation is independent of the existing High default.
		choice.select(0)
		choice.item_selected.emit(0)
		choice.grab_focus()
		await frames(4)
		await tap_key(KEY_SPACE)
		check(choice.get_popup().visible, "Keyboard opens %s popup" % setting)
		choice.get_popup().set_focused_item(choice.selected)
		for index in range(choice.item_count - 1):
			await popup_key(choice.get_popup(), KEY_DOWN)
		await popup_key(choice.get_popup(), KEY_ENTER)
		check(choice.selected == choice.item_count - 1, "Keyboard enables %s through its menu popup" % setting)
		await tap_key(KEY_SPACE)
		choice.get_popup().set_focused_item(choice.selected)
		for index in range(choice.item_count - 1):
			await popup_key(choice.get_popup(), KEY_UP)
		await popup_key(choice.get_popup(), KEY_ENTER)
		check(choice.selected == 0, "Keyboard switches %s off through its menu popup" % setting)
	for toggle: CheckButton in [menu.bloom, menu.ssao]:
		toggle.grab_focus()
		await frames(4)
		await tap_key(KEY_SPACE)
		check(toggle.button_pressed, "Keyboard enables %s" % toggle.text)
		await tap_key(KEY_SPACE)
		check(not toggle.button_pressed, "Keyboard disables %s" % toggle.text)
	menu.dismiss()
	sector.set_paused(false)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	sector.player.position = Vector3(0, 0, 45)
	sector.player.look_at(Sector.STATION_POSITION)
	await frames(20)
	var baseline := await capture("station-effects-off")
	sector.settings.bloom = true
	sector.apply_graphics(false)
	await frames(20)
	var bloom := await capture("station-bloom")
	check(world_pixels(baseline) != world_pixels(bloom), "Bloom changes rendered world pixels")
	sector.settings.bloom = false
	sector.settings.ssao = true
	sector.apply_graphics(false)
	await frames(20)
	var ssao := await capture("station-ssao")
	check(world_pixels(baseline) != world_pixels(ssao), "SSAO changes rendered world pixels")
	sector.settings.ssao = false
	sector.settings.shadow_quality = 3
	sector.apply_graphics(false)
	await frames(20)
	var shadows := await capture("station-shadows")
	check(world_pixels(baseline) != world_pixels(shadows), "Shadows change rendered world pixels")
	sector.settings.shadow_quality = 0
	sector.settings.render_scale = 0.5
	sector.apply_graphics(false)
	await frames(20)
	var scaled := await capture("station-scale-50")
	check(world_pixels(baseline) != world_pixels(scaled), "Render scaling changes rendered world pixels")
	check(root.get_texture().get_size() == Vector2(1440, 900), "Render scaling preserves the native output and HUD size")
	sector.settings.render_scale = 1.0
	sector.settings.anisotropic_filtering = 0
	sector.apply_graphics(false)
	var rock := sector.get_node("Asteroid4") as Node3D
	sector.player.position = rock.position + Vector3(22, 9, 35)
	sector.player.look_at(rock.position)
	await frames(20)
	var unfiltered := await capture("asteroid-filtering-off")
	sector.settings.anisotropic_filtering = 4
	sector.apply_graphics(false)
	await frames(20)
	var filtered := await capture("asteroid-filtering-16x")
	check(world_pixels(unfiltered) != world_pixels(filtered), "Anisotropic filtering changes textured asteroid pixels")
	check(SectorVisuals.asteroid_surface().albedo_texture.get_image().has_mipmaps(), "Asteroid texture imports include mipmaps required for filtering")
	sector.settings.bloom = true
	sector.settings.ssao = true
	sector.settings.shadow_quality = 3
	sector.settings.effects_quality = 2
	sector.apply_graphics(false)
	sector.player.position = Vector3(0, 0, 45)
	sector.player.look_at(Sector.STATION_POSITION)
	await frames(20)
	SectorVisuals.laser(sector, sector.player.position, Sector.STATION_POSITION, false)
	SectorVisuals.impact(sector.player, sector.player.position, true, true)
	SectorVisuals.explosion(sector, Sector.STATION_POSITION + Vector3(0, 0, 15))
	await capture("combat-effects-high")
	sector.settings.effects_quality = 1
	sector.apply_graphics(false)
	await frames(4)
	SectorVisuals.laser(sector, sector.player.position, Sector.STATION_POSITION, false)
	SectorVisuals.impact(sector.player, sector.player.position, true, true)
	SectorVisuals.explosion(sector, Sector.STATION_POSITION + Vector3(0, 0, 15))
	await capture("combat-effects-low")
	sector.settings.effects_quality = 0
	sector.apply_graphics(false)
	await frames(4)
	SectorVisuals.laser(sector, sector.player.position, Sector.STATION_POSITION, false)
	await capture("combat-effects-off")
	check(get_nodes_in_group("transient_feedback").is_empty(), "Rendered combat effects switch fully off")
	sector.settings = GameSettings.new()
	sector.settings.save()
	print("Rendered graphics checks: %d passed, %d failed; GPU=%s" % [checks - failures, failures, RenderingServer.get_video_adapter_name()])
	for voice in sector.audio.voices:
		voice.stop()
	await create_timer(0.1).timeout
	sector.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func frames(count: int) -> void:
	for index in range(count):
		await process_frame


func popup_key(_popup: PopupMenu, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await frames(2)


func capture(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png(OUTPUT.path_join(label + ".png"))
	return result


func world_pixels(image: Image) -> PackedByteArray:
	# Exclude the HUD to measure the 3D effect itself.
	return image.get_region(Rect2i(400, 280, 650, 340)).get_data()
