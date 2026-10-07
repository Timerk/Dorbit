extends "res://tests/shop_test.gd"
## Exercise actual --offline startup, local launch/return and development hosting.


func run() -> void:
	var client := make_sector("OfflinePilot")
	var menu := client.main_menu
	await settle()
	check(client.offline and client.preflight and client.paused and menu.home.visible, "--offline opens the main menu before flight")
	check(not client.session.active and not client.session.connecting and not menu.start_button.disabled, "Offline Start needs no server or snapshot")
	check(menu.connection.text.contains("OFFLINE") and menu.notice.text.contains("temporary"), "Offline console identifies temporary development progress")
	check(menu.ship_title.text == "LIBERATOR" and not menu.ship_stats.text.is_empty(), "Offline overview displays the starter ship")
	for page: String in ["shop", "hangar", "cargo", "quests"]:
		check(menu.navigation[page].disabled and menu.navigation[page].tooltip_text.contains("dedicated server"), "Offline %s explains its server requirement" % page)
	if DisplayServer.get_name() != "headless":
		client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var screen := TextureRect.new()
		screen.texture = client.get_viewport().get_texture()
		root.add_child(screen)
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		root.size = dimensions
		await settle()
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(menu.home.get_global_rect()), "Offline overview fits at %s" % dimensions)
		await capture(client, "offline-main-menu-%d" % dimensions.x)
	await click(client, menu.navigation["settings"])
	check(client.settings_menu.panel.visible, "Offline settings open from the main menu")
	client.settings_menu.close()
	await settle()
	check(menu.home.visible and client.paused, "Closing settings keeps the offline pilot in the main menu")
	await click(client, menu.navigation["connection"])
	check(client.session.menu.visible and client.session.host_button.visible, "Offline connection page retains development hosting")
	client.session.back_button.pressed.emit()
	await settle()
	check(menu.home.visible and not client.session.menu.visible and client.paused, "Connection Back returns to the offline overview")
	await press(client, KEY_M)
	check(not client.hud.navigation.overview.visible, "Offline preparation blocks the flight map")
	await click(client, menu.start_button)
	check(not client.preflight and not client.paused and not menu.visible and not client.session.active, "Offline Start enters solo flight")
	client.credits = 42
	client.player.hull -= 100
	var hull := client.player.hull
	client.select_target(client.alien)
	client.auto_fire = true
	client.autopilot.enabled = true
	await press(client, KEY_ESCAPE)
	check(client.settings_menu.main_menu_button.visible, "Offline flight pause includes Quit to main menu")
	await click(client, client.settings_menu.main_menu_button)
	check(client.preflight and client.paused and menu.home.visible, "Quit returns to the offline main menu")
	check(client.target == null and not client.auto_fire and not client.autopilot.enabled, "Offline return cancels targeting, fire and autopilot")
	await click(client, menu.start_button)
	check(client.credits == 42 and client.player.hull == hull, "Offline relaunch preserves the temporary wallet and health")
	check(not client.preflight and not menu.visible, "Offline relaunch leaves the main menu")
	client.player.take_damage(client.player.max_hull + client.player.max_shield + 1, client.alien)
	client.session.quit_to_menu()
	await settle()
	check(menu.start_button.disabled, "Offline launch waits for rescue")
	client._physics_process(3.1)
	await settle()
	check(client.player.alive and not menu.start_button.disabled and client.preflight, "Rescue completes while the offline main menu is open")
	await click(client, menu.navigation["connection"])
	check(client.session.host(24743) == OK, "Development host starts from the offline main menu")
	check(client.session.active and not client.preflight and not client.paused and not menu.visible, "Development hosting leaves the offline menu and enters flight")
	client.session.disconnect_session("Test complete")
	client.session.back_button.pressed.emit()
	await settle()
	check(client.preflight and client.paused and menu.home.visible and not client.session.active, "Leaving a development session returns to the offline main menu")
	finish()
