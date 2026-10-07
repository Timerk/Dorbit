extends "res://tests/shop_test.gd"
## Exercise actual --offline startup, local launch/return and development hosting.


func run() -> void:
	var client := make_sector("OfflinePilot")
	var menu := client.main_menu
	await settle()
	check(client.offline and client.preflight and client.paused and menu.home.visible, "--offline opens the main menu before flight")
	check(not client.session.active and not client.session.connecting and not menu.start_button.disabled, "Offline Start needs no server or snapshot")
	check(menu.ship_status.text == "OFFLINE PREVIEW" and menu.start_caption.text == "SOLO ENCOUNTER", "Offline overview identifies the preview and solo launch")
	check(menu.ship_title.text == "LIBERATOR" and menu.stat_values["damage"].text == "65", "Offline overview displays the starter ship and fitting")
	check(menu.exit_buttons[0].disabled and client.session.combat.inventory.is_empty(), "Offline preview does not create a server inventory or enable disconnect")
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
		for page: String in ["hangar", "shop", "cargo", "refining", "quests", "skylab", "gates"]:
			check(not menu.navigation[page].disabled, "Offline %s can be browsed" % page)
			await click(client, menu.navigation[page])
			var panel: Control = client.equipment_menu if page == "hangar" else (client.shop if page in ["shop", "cargo"] else (client.hud.contract_panel if page == "quests" else menu.placeholder))
			if page == "refining":
				panel = client.resource_workshop
			check(panel.is_visible_in_tree() and not menu.start_button.is_visible_in_tree() and not menu.specifications.is_visible_in_tree(), "Offline %s stays open without Overview footer" % page)
			check(Rect2(menu.content_rect().position - Vector2.ONE, menu.content_rect().size + Vector2.ONE * 2).encloses(panel.get_global_rect()), "Offline %s fits at %s" % [page, dimensions])
			await capture(client, "offline-%s-%d" % [page, dimensions.x])
			if page == "hangar":
				check(client.equipment_menu.specifications.is_visible_in_tree() and client.equipment_menu.stat_values["damage"].text == "65", "Offline Hangar has starter specifications")
				check(client.equipment_menu.activate_button.disabled and not client.equipment_menu.reason("starter-laser", "").is_empty(), "Offline activation and fitting are blocked")
				client.equipment_menu.move_item("starter-laser", "")
				check(client.equipment_menu.slots["laser1"]._get_drag_data(Vector2.ZERO) == null, "Offline installed items cannot start a fitting drag")
			elif page == "shop":
				client.shop.select_category("ships")
				client.shop.select_model("goliath")
				check(client.shop.product_title.text == "Goliath" and client.shop.buys["goliath"].disabled, "Offline ship catalog selection works while buying stays disabled")
				client.shop.purchase("goliath")
				client.shop.select_category("weapons")
				check(client.shop.buys[client.shop.selected_model].disabled, "Offline equipment purchases stay disabled")
			elif page == "cargo":
				check(client.shop.cargo_page.visible and client.shop.sell_all.disabled, "Offline cargo is viewable and Sell all is disabled")
				for resource: String in client.shop.sells:
					check(client.shop.sells[resource].disabled, "Offline %s sale is disabled" % resource)
			elif page == "refining":
				check(client.resource_workshop.refine_button.disabled, "Offline refining cannot spend cargo")
				client.resource_workshop.select_tab("update")
				await settle()
				check(client.resource_workshop.upgrade_button.disabled, "Offline resource upgrades remain unavailable")
				client.resource_workshop.select_tab("refining")
			elif page == "quests":
				client.hud.select_contract("heavy")
				check(client.hud.contract_title.text == "Heavy hunt" and client.hud.contract_accept.disabled, "Offline quest selection works while acceptance is disabled")
				client.hud.act_on_contract("accept")
				client.hud.filter_contracts(true)
				check(client.hud.contract_empty.visible, "Offline Active quests tab shows the empty state")
				client.hud.filter_contracts(false)
			check(not client.session.combat.station_pending and client.session.combat.inventory.is_empty() and client.active_contracts.is_empty(), "Offline %s browsing cannot mutate progression or request a transaction" % page)
			await click(client, menu.navigation["overview"])
			check(menu.home.visible and client.paused, "Offline %s returns to paused Overview" % page)
		await click(client, menu.navigation["settings"])
		check(client.settings_menu.binding_buttons.size() == GameSettings.ACTIONS.size(), "Offline Controls includes every current binding")
		for tab in 3:
			client.settings_menu.tabs.current_tab = tab
			await settle()
			check(client.settings_menu.panel.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(client.settings_menu.panel.get_global_rect()), "Offline Settings tab %d fits at %s" % [tab, dimensions])
			await capture(client, "offline-settings-%d-%d" % [tab, dimensions.x])
		await click(client, menu.navigation["connection"])
		check(client.session.menu.is_visible_in_tree(), "Offline Connection opens from Settings")
		await capture(client, "offline-connection-%d" % dimensions.x)
		await click(client, menu.navigation["overview"])
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
	client.player.position = Vector3(0, 100, -400)
	await check_flight_pages(client, "offline")
	check(not client.auto_fire and not client.autopilot.enabled, "Offline flight browsing cancels fire and autopilot")
	client.settings_menu.open()
	await settle()
	client.settings_menu.close()
	await settle()
	check(not client.paused and not menu.visible, "Closing flight Settings resumes the offline encounter")
	await press(client, KEY_ESCAPE)
	check(client.settings_menu.main_menu_button.visible, "Offline flight pause includes Quit to main menu")
	await check_flight_menu(client, "offline")
	await click(client, client.settings_menu.main_menu_button)
	check(client.preflight and client.paused and menu.home.visible, "Quit returns to the offline main menu")
	check(client.target == null and not client.auto_fire and not client.autopilot.enabled, "Offline return cancels targeting, fire and autopilot")
	await click(client, menu.navigation["hangar"])
	check(client.equipment_menu.visible, "Offline Hangar remains viewable after returning from a hunt away from the station")
	await click(client, menu.navigation["overview"])
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
	await press(client, KEY_ESCAPE)
	check(client.settings_menu.main_menu_button.is_visible_in_tree(), "Development flight exposes Quit to main menu")
	await check_flight_menu(client, "development-host")
	await click(client, client.settings_menu.main_menu_button)
	await settle()
	check(client.preflight and client.paused and menu.home.visible and not client.session.active and not client.session.menu.visible, "Quit stops development hosting and returns directly to the offline overview")
	check(not menu.start_button.disabled and client.session.combat.inventory.is_empty(), "Development return allows solo relaunch without retaining a host inventory")
	await click(client, menu.start_button)
	check(not client.preflight and not client.paused and not menu.visible, "Solo flight can restart after leaving development hosting")
	finish()


func check_flight_menu(client: Sector, mode: String) -> void:
	var initial := client.settings_menu.pause_panel.get_global_rect()
	check(initial.size.x >= 500 and initial.size.y <= 450, "%s flight menu opens readably before any window resize" % mode)
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		client.get_viewport().size = dimensions
		root.size = dimensions
		await settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		var pause := client.settings_menu.pause_panel.get_global_rect()
		check(bounds.encloses(pause) and pause.get_center().distance_to(bounds.get_center()) < 1.0, "%s flight menu stays centered at %s" % [mode, dimensions])
		check(pause.size.x >= 500 and pause.size.y <= 450 and client.settings_menu.resume_button.get_global_rect().size.y >= 36, "%s flight menu retains readable proportions at %s" % [mode, dimensions])
		await capture(client, "%s-flight-menu-%d" % [mode, dimensions.x])
