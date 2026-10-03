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
	check(shop.selected_model == "laser" and shop.cards.values().all(func(card: Button): return card.visible), "All equipment opens with the laser selected")
	await click(client, shop.cargo_button)
	check(shop.cargo_page.visible and not shop.equipment_page.visible and shop.sells.size() == 7, "Trading navigation opens all seven ore cards without overlapping the equipment catalog")
	check(Rect2(Vector2.ZERO, Vector2(960, 600)).encloses(shop.get_global_rect()), "Trading fits the minimum viewport with category-shop navigation")
	await capture(client, "shop-cargo")
	await click(client, shop.catalog_button)
	check(shop.equipment_page.visible and not shop.cargo_page.visible and shop.selected_model == "laser", "Equipment navigation restores the selected catalog item")
	check(client.credits == 12000 and combat.inventory["revision"] == 0, "Switching shop pages sends no purchase or sale")
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		await settle()
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(shop.get_global_rect()), "Shop stays inside %s" % dimensions)
		for model: String in shop.cards:
			check(shop.get_global_rect().encloses(shop.cards[model].get_global_rect()), "Card %s fits at %s" % [model, dimensions])
		check(shop.get_global_rect().encloses(shop.buys[shop.selected_model].get_global_rect()), "Buy control fits at %s" % dimensions)
		if dimensions.x == 960:
			await capture(client, "shop-960")
	await capture(client, "shop-1440")
	client.get_viewport().size = Vector2i(960, 600)
	for category: String in ["weapons", "generators", "shields", "engines"]:
		shop.categories[category].pressed.emit()
		await settle()
		var expected: Array = {"weapons": ["laser"], "generators": ["shield", "engine"], "shields": ["shield"], "engines": ["engine"]}[category]
		check(shop.cards.keys().filter(func(model: String): return shop.cards[model].visible) == expected, "Category %s filters the catalog" % category)
		check(shop.selected_model in expected and shop.buys[shop.selected_model].visible, "Category %s selects a purchasable item" % category)
	shop.categories["generators"].pressed.emit()
	await settle()
	await click(client, shop.cards["shield"])
	await settle()
	check(shop.product_title.text == "Shield generator" and shop.price.text == "2,400 CR" and shop.bonus.text.contains("70"), "Selecting a card changes the preview, price and bonus together")
	await capture(client, "shop-generators")
	await press(client, KEY_I)
	check(client.equipment_menu.visible and not shop.visible and client.paused, "I switches to the separate equipment screen")
	await press(client, KEY_B)
	check(shop.visible and not client.equipment_menu.visible and shop.selected_model == "shield", "B returns to the selected shop item")
	shop.equipment_button.pressed.emit()
	await settle()
	check(client.equipment_menu.visible and not shop.visible, "Shop navigation opens equipment without overlapping panels")
	await press(client, KEY_B)
	var before: Dictionary = combat.inventory.duplicate(true)
	shop.buys["shield"].pressed.emit()
	check(combat.station_pending and shop.buys["shield"].disabled, "Purchase disables immediately while waiting for the server")
	shop.buys["shield"].pressed.emit()
	await settle()
	await replicate(server)
	check(client.credits == 9600 and combat.inventory["items"].size() == before["items"].size() + 1, "A double click sends one committed purchase")
	check(combat.inventory["items"]["purchase-1"] == {"model": "shield", "ship": "", "slot": ""}, "Bought equipment goes into storage")
	check(Equipment.stats(combat.inventory) == Equipment.stats(before), "Buying never installs equipment or changes ship stats")
	check(shop.ownership.text.contains("OWNED 2") and shop.ownership.text.contains("1 in storage"), "Server inventory refreshes the displayed ownership count")
	shop.categories["ships"].pressed.emit()
	await settle()
	check(shop.selected_model.is_empty() and shop.empty_catalog.visible and not shop.grid.visible and shop.buys.values().all(func(buy: Button): return not buy.visible), "Ships is an empty category with no stale purchase control")
	await capture(client, "shop-ships")
	shop.categories["weapons"].pressed.emit()
	check(server.session.store.commit({"pilot0": 500}), "Set a low wallet through persistence")
	server.session.combat.records[client.multiplayer.get_unique_id()]["credits"] = 500
	await replicate(server)
	await settle()
	check(shop.buys["laser"].disabled and shop.availability.text == "Need 2,500 more CR", "Insufficient funds disable buying and show the shortfall")
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
