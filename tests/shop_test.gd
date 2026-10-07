extends "res://tests/dedicated_server_test.gd"
## Catalog navigation, real purchases and rendered layout at supported window sizes.


func press(client: Sector, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	client._unhandled_input(event)
	await settle()


func capture(client: Sector, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/validation")
	check(client.get_viewport().get_texture().get_image().save_png("res://build/validation/" + label + ".png") == OK, "Save rendered " + label)


func click(client: Sector, control: Control) -> void:
	# Route real mouse events through the card's image and nested controls.
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = control.get_global_rect().get_center()
		event.pressed = pressed
		client.get_viewport().push_input(event)
		await process_frame
	await settle()


func check_flight_pages(client: Sector, prefix: String) -> void:
	var menu := client.main_menu
	var position := client.player.position
	var hull := client.player.hull
	var credits := client.credits
	var inventory := client.session.combat.inventory.duplicate(true)
	client.set_paused(true)
	await settle()
	await click(client, client.settings_menu.ship_menus_button)
	check(menu.home.visible and menu.visible and not client.settings_menu.pause_panel.visible and not client.preflight, "%s Esc menu opens the shared flight Overview without docking" % prefix)
	await click(client, menu.resume_button)
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		client.get_viewport().size = dimensions
		root.size = dimensions
		await press(client, KEY_B)
		check(menu.visible and client.shop.visible and menu.selected_page == "shop", "%s B opens the shared Shop header and sidebar at %s" % [prefix, dimensions])
		await press(client, KEY_I)
		check(menu.visible and client.equipment_menu.visible and menu.selected_page == "hangar", "%s I opens the shared Hangar" % prefix)
		await press(client, KEY_C)
		check(menu.visible and client.hud.contract_panel.visible and menu.selected_page == "quests", "%s C opens the shared Quests" % prefix)
		await press(client, KEY_F7)
		check(client.session.menu.visible and menu.visible, "%s F7 opens Connection inside the shared shell" % prefix)
		for page: String in menu.navigation:
			await click(client, menu.navigation[page])
			var panel: Control
			match page:
				"overview": panel = menu.home
				"hangar": panel = client.equipment_menu
				"shop", "cargo": panel = client.shop
				"quests": panel = client.hud.contract_panel
				"settings": panel = client.settings_menu.panel
				"connection": panel = client.session.menu
				_: panel = menu.placeholder
			check(panel.is_visible_in_tree() and menu.selected_page == page and menu.resume_button.is_visible_in_tree(), "%s flight %s remains reachable at %s" % [prefix, page, dimensions])
			check(menu.content_rect().grow(1).encloses(panel.get_global_rect()), "%s flight %s fits beside the navigation at %s" % [prefix, page, dimensions])
			check(not client.preflight and client.paused and not client.settings_menu.pause_panel.visible and not menu.start_button.is_visible_in_tree(), "%s flight %s does not dock, launch or overlay the pause menu" % [prefix, page])
			if StationUi.offline_preview(client):
				if page == "hangar":
					check(client.equipment_menu.activate_button.disabled and not client.equipment_menu.reason("starter-laser", "").is_empty(), "Offline flight cannot activate or fit equipment")
				elif page == "shop":
					check(client.shop.buys[client.shop.selected_model].disabled, "Offline flight cannot purchase equipment")
				elif page == "cargo":
					check(client.shop.sell_all.disabled and client.shop.sells.values().all(func(button: Button): return button.disabled), "Offline flight cannot sell cargo")
				elif page == "quests":
					check(client.hud.contract_accept.disabled, "Offline flight cannot accept hunts")
			if page in ["hangar", "cargo"]:
				await capture(client, "%s-flight-%s-%d" % [prefix, page, dimensions.x])
		await click(client, menu.resume_button)
		check(not menu.visible and not client.paused and not client.session.menu.visible and not menu.placeholder.visible, "%s Resume closes the shell and its pages" % prefix)
		await press(client, KEY_I)
		await press(client, KEY_ESCAPE)
		check(not menu.visible and not client.equipment_menu.visible and not client.paused, "%s Esc closes the flight Hangar and resumes" % prefix)
	await press(client, KEY_F7)
	client.settings_menu.open(true)
	await settle()
	client.settings_menu.close()
	await settle()
	check(menu.visible and client.session.menu.visible and client.paused, "%s Connection Settings Back restores the shared Connection page" % prefix)
	await click(client, client.session.back_button)
	check(not client.paused and not menu.visible and not client.session.menu.visible, "%s Connection Back resumes flight" % prefix)
	check(client.player.position == position and client.player.hull == hull and client.credits == credits and client.session.combat.inventory == inventory and not client.session.combat.station_pending, "%s flight browsing preserves position, health, wallet and fitting without a station request" % prefix)


func run() -> void:
	var server := make_sector("ShopServer", true, 24735)
	check(server.session.store.commit({"pilot0": 12000}), "Seed a purchase budget")
	var client := make_sector("ShopPilot")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", 24735)
	await settle(0.5)
	await replicate(server)
	check(client.session.active, "Pilot authenticates")
	if not client.session.active:
		finish()
		return
	var combat := client.session.combat
	var shop := client.shop
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if DisplayServer.get_name() != "headless":
		var screen := TextureRect.new()
		screen.texture = client.get_viewport().get_texture()
		root.add_child(screen)
		root.size = Vector2i(960, 600)
	await press(client, KEY_B)
	check(shop.visible and client.paused and not client.settings_menu.pause_panel.visible, "B opens the shop and suppresses flight and pause controls")
	check(shop.selected_model == "laser" and shop.cards.keys().filter(func(model: String): return shop.cards[model].visible) == Equipment.catalog_models(), "All equipment opens with equipment only and the laser selected")
	await click(client, client.main_menu.navigation["cargo"])
	check(shop.cargo_page.visible and not shop.equipment_page.visible and shop.sells.size() == 7, "Trading navigation opens all seven ore cards without overlapping the equipment catalog")
	check(Rect2(Vector2.ZERO, Vector2(960, 600)).encloses(shop.get_global_rect()), "Trading fits the minimum viewport with category-shop navigation")
	await capture(client, "shop-cargo")
	await click(client, client.main_menu.navigation["shop"])
	check(shop.equipment_page.visible and not shop.cargo_page.visible and shop.selected_model == "laser", "Equipment navigation restores the selected catalog item")
	check(client.credits == 12000 and combat.inventory["revision"] == 0, "Switching shop pages sends no purchase or sale")
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		await settle()
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(shop.get_global_rect()), "Shop stays inside %s" % dimensions)
		var catalog_scroll := shop.grid.get_parent() as ScrollContainer
		check(shop.grid.size.x <= catalog_scroll.size.x, "Catalog fits horizontally at %s" % dimensions)
		catalog_scroll.scroll_vertical = 10000
		await settle()
		check(catalog_scroll.scroll_vertical > 0 and catalog_scroll.get_global_rect().encloses(shop.cards["g3n-7900"].get_global_rect()), "Catalog scroll reaches the last engine at %s" % dimensions)
		catalog_scroll.scroll_vertical = 0
		check(shop.get_global_rect().encloses(shop.buys[shop.selected_model].get_global_rect()), "Buy control fits at %s" % dimensions)
		if dimensions.x == 960:
			await capture(client, "shop-960")
	await capture(client, "shop-1440")
	client.get_viewport().size = Vector2i(960, 600)
	for category: String in ["weapons", "generators", "shields", "engines"]:
		shop.categories[category].pressed.emit()
		await settle()
		var expected: Array = {
			"weapons": ["laser", "mp-1", "lf-2", "lf-3", "lf-4"],
			"shields": ["shield", "sg3n-a02", "fs-01", "sg3n-a03", "sg3n-b00", "sg3n-b01", "sg3n-b02"],
			"engines": ["g3n-1010", "g3n-2010", "g3n-3210", "g3n-3310", "g3n-6900", "g3n-7900"],
			"generators": ["shield", "sg3n-a02", "fs-01", "sg3n-a03", "sg3n-b00", "sg3n-b01", "sg3n-b02", "g3n-1010", "g3n-2010", "g3n-3210", "g3n-3310", "g3n-6900", "g3n-7900"],
		}[category]
		check(shop.cards.keys().filter(func(model: String): return shop.cards[model].visible) == expected, "Category %s filters the catalog" % category)
		check(shop.selected_model in expected and shop.buys[shop.selected_model].visible, "Category %s selects a purchasable item" % category)
	shop.categories["generators"].pressed.emit()
	await settle()
	await click(client, shop.cards["shield"])
	await settle()
	check(shop.product_title.text == "SG3N-A01" and shop.price.text == "8,000 CR" and shop.bonus.text.contains("1000") and shop.bonus.text.contains("40%"), "Selecting a shield shows capacity and absorption with its price")
	await capture(client, "shop-generators")
	await press(client, KEY_I)
	check(client.equipment_menu.visible and not shop.visible and client.paused, "I switches to the separate equipment screen")
	await press(client, KEY_B)
	check(shop.visible and not client.equipment_menu.visible and shop.selected_model == "shield", "B returns to the selected shop item")
	await click(client, client.main_menu.navigation["hangar"])
	await settle()
	check(client.equipment_menu.visible and not shop.visible, "Shop navigation opens equipment without overlapping panels")
	await press(client, KEY_B)
	var before: Dictionary = combat.inventory.duplicate(true)
	shop.buys["shield"].pressed.emit()
	check(combat.station_pending and shop.buys["shield"].disabled, "Purchase disables immediately while waiting for the server")
	shop.buys["shield"].pressed.emit()
	await settle()
	await replicate(server)
	check(client.credits == 4000 and combat.inventory["items"].size() == before["items"].size() + 1, "A double click sends one committed purchase")
	check(combat.inventory["items"]["purchase-1"] == {"model": "shield", "ship": "", "slot": ""}, "Bought equipment goes into storage")
	check(Equipment.stats(combat.inventory) == Equipment.stats(before), "Buying never installs equipment or changes ship stats")
	check(shop.ownership.text.contains("OWNED 2") and shop.ownership.text.contains("1 in storage"), "Server inventory refreshes the displayed ownership count")
	shop.categories["ships"].pressed.emit()
	await settle()
	check(shop.models_in_category("ships").size() == 12 and shop.grid.visible and not shop.empty_catalog.visible, "Ships lists all twelve purchasable hulls")
	shop.select_model("liberator")
	check(shop.product_title.text == "Liberator" and shop.bonus.text.contains("116,000 hull") and shop.product_title.tooltip_text.contains("4 laser / 6 shared generator / 2 extra slots") and shop.buys["liberator"].disabled, "Owned Liberator shows its model and stats and blocks another purchase")
	await capture(client, "shop-ships")
	shop.categories["weapons"].pressed.emit()
	check(server.session.store.commit({"pilot0": 500}), "Set a low wallet through persistence")
	server.session.combat.records[client.multiplayer.get_unique_id()]["credits"] = 500
	await replicate(server)
	await settle()
	check(shop.buys["laser"].disabled and shop.availability.text == "Need 9,500 more CR", "Insufficient funds disable buying and show the shortfall")
	shop.buys["laser"].pressed.emit()
	await settle()
	check(not combat.station_pending and combat.inventory["revision"] == 1, "A disabled purchase cannot send an intent")
	await capture(client, "shop-insufficient")
	combat.preview_tools_available = true
	await settle()
	check(Rect2(Vector2.ZERO, Vector2(960, 600)).encloses(shop.get_global_rect()) and shop.get_global_rect().encloses(shop.test_credits_button.get_global_rect()), "Low-funds shop and preview tools fit at the minimum window size")
	combat.preview_tools_available = false
	check(server.session.store.commit({"pilot0": 12000}), "Restore wallet for station blocker checks")
	server.session.combat.records[client.multiplayer.get_unique_id()]["credits"] = 12000
	await replicate(server)
	client.player.time_since_hit = 0
	await settle()
	check(shop.buys["laser"].disabled and not shop.purchase_blocker("laser").is_empty(), "Damage while browsing disables purchases")
	client.player.time_since_hit = 5
	client.player.position = Vector3(0, 0, 400)
	await settle()
	check(shop.buys["laser"].disabled, "Leaving station range disables purchases")
	client.player.position = Sector.SPAWN_POSITION
	await press(client, KEY_C)
	check(client.hud.contract_panel.visible and not shop.visible and client.paused, "C switches to contracts without overlapping screens")
	await press(client, KEY_B)
	check(shop.visible and not client.hud.contract_panel.visible and client.paused, "B switches back to the shop")
	await press(client, KEY_ESCAPE)
	check(not shop.visible and not client.paused, "Esc resumes flight")
	await press(client, KEY_B)
	await press(client, KEY_F7)
	check(client.session.menu.visible and not shop.visible, "F7 closes the shop for the session menu")
	client.session.disconnect_session("Shop test complete")
	await settle()
	check(not shop.visible, "Disconnect closes the shop")
	finish()
