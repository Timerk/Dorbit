extends "res://tests/dedicated_server_test.gd"
## Real authenticated RPCs, atomic disk changes, and the rendered fitting controls.


func request(client: Sector, sequence: int, action: String, subject: String, ship: String = "", slot: String = "", life: int = 0) -> void:
	client.session.combat.station_request.rpc_id(1, sequence, action, subject, ship, slot, life)
	await settle(0.1)


func press(client: Sector, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	client._unhandled_input(event)
	await settle()


func screenshot(client: Sector, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# This test advances simulation manually; finish interpolation before capturing the UI.
	client.session.combat.interpolate(1.0)
	client.weapon_status = client.player.firing_blocker(client.target)
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://build/validation")
	DirAccess.make_dir_recursive_absolute(directory)
	client.get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))


func drag(client: Sector, source: Control, target_control: Control) -> void:
	var viewport := client.get_viewport()
	var start := source.get_global_rect().get_center()
	var finish := target_control.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.position = start
	down.pressed = true
	viewport.push_input(down)
	await process_frame
	for point: Vector2 in [start + Vector2(20, 0), finish]:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.relative = point - start
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(motion)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = finish
	viewport.push_input(up)
	await settle()


func click_item(client: Sector, tile: Control, shift: bool = true, clicks: int = 1) -> void:
	var point := tile.get_global_rect().get_center()
	for click in range(clicks):
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			event.pressed = pressed
			event.shift_pressed = shift
			event.position = point
			client.get_viewport().push_input(event)
	await settle()


func check_inventory_layout(client: Sector) -> void:
	# Presentation-only fixture; real ownership transactions are exercised in run().
	var combat := client.session.combat
	var committed := combat.inventory.duplicate(true)
	var fixture := committed.duplicate(true)
	var models := ["laser", "shield", "engine", "lf-3", "fs-01", "g3n-7900", "mp-1", "sg3n-a03", "g3n-2010"]
	var expected_categories := {"laser": "weapon", "lf-3": "weapon", "mp-1": "weapon", "shield": "shield", "fs-01": "shield", "sg3n-a03": "shield", "engine": "engine", "g3n-7900": "engine", "g3n-2010": "engine"}
	for index in range(30):
		fixture["items"]["layout-%d" % index] = {"model": models[index % models.size()], "ship": "", "slot": ""}
	combat.inventory = fixture
	await settle()
	var fitting := client.equipment_menu
	var counts := {"weapon": 0, "shield": 0, "engine": 0, "extra": 0}
	for item: Dictionary in fixture["items"].values():
		if item["ship"].is_empty():
			counts[expected_categories[item["model"]]] += 1
	check(fitting.stored.size() == counts["weapon"] + counts["shield"] + counts["engine"], "Large inventory renders every stored instance across the expanded catalog")
	var categories: Array[String] = []
	for tile: EquipmentTile in fitting.stored.values():
		var category: String = expected_categories[fixture["items"][tile.item_id]["model"]]
		if categories.is_empty() or categories.back() != category:
			categories.append(category)
	check(categories == ["weapon", "shield", "engine"], "Interleaved inventory is grouped as weapons, shields, then speed generators")
	for child in fitting.storage_groups.get_children():
		if child is GridContainer:
			check(child.columns == 3, "Each category uses a three-column grid")
	var scroll := fitting.storage_groups.get_parent() as ScrollContainer
	scroll.scroll_vertical = 1000
	await settle()
	check(scroll.scroll_vertical > 0, "Inventory scrolls to items beyond the first visible rows")
	check(fitting.storage_groups.get_rect().size.x <= scroll.size.x, "Inventory groups fit their available width at 960 pixels")
	await screenshot(client, "equipment-inventory-scroll")
	for index in range(1, 5):
		fitting.storage_filter.item_selected.emit(index)
		await settle()
		var category: String = fitting.STORAGE_CATEGORIES.keys()[index - 1]
		check(fitting.stored.values().all(func(tile: EquipmentTile): return expected_categories[fixture["items"][tile.item_id]["model"]] == category), "Filter shows only " + category)
		check(fitting.stored.size() == counts[category], "Filter retains all stored instances for " + category)
		check(fitting.empty_storage.visible == (category == "extra"), "Empty extras filter explains that no items match")
	check(combat.inventory == fixture, "Filtering never changes ownership or fitting")
	fitting.set_filter("all")
	fitting.select_item("layout-0")
	fitting.set_filter("shield")
	check(fitting.selected_item.is_empty(), "Filtering out a stored selection clears it")
	await screenshot(client, "equipment-inventory-filter")
	fitting.set_filter("all")
	var payload := {"equipment_item": "starter-engine", "screen": fitting}
	combat.station_pending = true
	check(not fitting.can_drop(payload, "") and fitting.preview.text.contains("Waiting"), "Pending request blocks further fitting and explains why")
	combat.station_pending = false
	check(not fitting.can_drop({"equipment_item": "missing", "screen": fitting}, "") and not fitting.can_drop("foreign drag", ""), "Unknown items and unrelated drags are rejected")
	fitting.drop_hint = ""
	fitting.preview.text = ""
	client.get_viewport().size = Vector2i(1440, 900)
	await settle()
	check(fitting.get_global_rect().position.x >= 0 and fitting.get_global_rect().end.x <= 1440 and fitting.get_global_rect().end.y <= 900, "Equipment resizes within the larger viewport")
	if client.preflight:
		check(fitting.get_global_rect().position.y >= MainMenu.HEADER_HEIGHT and fitting.specifications.is_visible_in_tree() and not client.main_menu.start_button.is_visible_in_tree(), "Docked grouped inventory retains specifications and keeps Start exclusive to Overview")
	scroll.scroll_vertical = 0
	await screenshot(client, "equipment-large-window")
	client.get_viewport().size = Vector2i(960, 600)
	combat.inventory = committed
	await settle()


func check_quick_equip() -> void:
	var server := make_sector("QuickEquipServer", true, 24743)
	check(server.session.store.commit({"pilot0": 100000}), "Fund isolated quick-equip pilot for current catalog prices")
	var client := make_sector("QuickEquipClient")
	client.client_only = true
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", 24743)
	await settle(0.5)
	await replicate(server)
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var combat := client.session.combat
	var models := ["laser", "laser", "laser", "laser", "shield", "shield", "shield", "g3n-2010", "g3n-2010"]
	for index in range(models.size()):
		await request(client, index + 1, "buy", models[index])
	await click_item(client, client.main_menu.navigation["hangar"], false)
	var fitting := client.equipment_menu
	check(client.preflight and client.paused and fitting.visible and not client.main_menu.home.visible, "Main menu Hangar opens inventory while the pilot stays docked")
	check(Rect2(Vector2.ZERO, Vector2(960, 600)).encloses(fitting.get_global_rect()) and fitting.get_global_rect().position.y >= MainMenu.HEADER_HEIGHT, "Docked inventory fits below the header at the minimum window size")
	await check_inventory_layout(client)
	await click_item(client, fitting.stored["purchase-1"], false)
	check(fitting.selected_item == "purchase-1" and combat.inventory["revision"] == 9, "Plain mouse click still selects without equipping")
	combat.station_pending = true
	await click_item(client, fitting.stored["purchase-1"])
	check(combat.inventory["revision"] == 9, "Shift-click cannot equip while a request is pending")
	combat.station_pending = false
	client.player.time_since_hit = 0
	await click_item(client, fitting.stored["purchase-1"])
	check(combat.inventory["revision"] == 9, "Shift-click respects station damage restrictions")
	client.player.time_since_hit = 5
	await click_item(client, fitting.stored["purchase-1"], true, 2)
	check(combat.inventory["revision"] == 10 and fitting.slots["laser2"].item_id == "purchase-1", "Rapid Shift-clicks commit once into the first empty laser slot")
	for index in [2, 3]:
		await click_item(client, fitting.stored["purchase-%d" % index])
		check(fitting.slots["laser%d" % (index + 1)].item_id == "purchase-%d" % index, "Shift-click fills the next empty weapon slot")
	var before := combat.inventory.duplicate(true)
	await click_item(client, fitting.stored["purchase-4"])
	check(combat.inventory == before and fitting.preview.text.contains("No compatible empty slot"), "Full weapon slots leave inventory unchanged and explain why")
	fitting.set_filter("shield")
	await settle()
	await click_item(client, fitting.stored["purchase-5"])
	check(fitting.slots["generator3"].item_id == "purchase-5" and fitting.filter_category == "shield" and fitting.stored.size() == 2, "Shield Shift-click uses first empty shared generator slot and preserves the filter after the reply")
	fitting.set_filter("engine")
	await settle()
	await click_item(client, fitting.stored["purchase-8"])
	check(fitting.slots["generator4"].item_id == "purchase-8", "Speed generator uses the next empty shared generator slot")
	fitting.set_filter("shield")
	await settle()
	await click_item(client, fitting.stored["purchase-6"])
	fitting.set_filter("engine")
	await settle()
	await click_item(client, fitting.stored["purchase-9"])
	check(fitting.slots["generator5"].item_id == "purchase-6" and fitting.slots["generator6"].item_id == "purchase-9", "Both generator categories fill the shared pool without replacing items")
	fitting.set_filter("shield")
	await settle()
	before = combat.inventory.duplicate(true)
	await click_item(client, fitting.stored["purchase-7"])
	check(combat.inventory == before and fitting.preview.text.contains("No compatible empty slot"), "Full shared generator slots do not fall back to extra or laser slots")
	await click_item(client, fitting.slots["laser1"])
	check(combat.inventory == before and fitting.selected_item == "starter-laser", "Shift-clicking installed equipment only selects it")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(server.session.store.path))["pilots"]["pilot0"]["equipment"]
	check(int(saved["revision"]) == combat.inventory["revision"] and saved["items"] == combat.inventory["items"] and saved["active_ship"] == combat.inventory["active_ship"], "Quick-equip results persist through normal server transactions")
	await screenshot(client, "equipment-quick-equip")
	await press(client, KEY_ESCAPE)
	check(client.preflight and client.paused and client.main_menu.home.visible and not fitting.visible, "Esc returns from inventory to the main menu without launching")
	await click_item(client, client.main_menu.navigation["hangar"], false)
	check(fitting.visible and fitting.filter_category == "shield" and fitting.stored.size() == 1, "Reopening Hangar retains the filter and updated inventory")
	await click_item(client, client.main_menu.navigation["overview"], false)
	check(client.preflight and client.main_menu.home.visible and not fitting.visible, "Overview navigation returns from inventory to the docked overview")
	await click_item(client, client.main_menu.start_button, false)
	await replicate(server)
	check(not client.preflight and not client.main_menu.visible and combat.inventory == before and client.player.laser_damage == 260 and client.player.max_shield == 3000, "Start launches with the Shift-clicked fitting preserved")
	client.session.disconnect_session("Quick equip complete")
	server.session.disconnect_session("Quick equip complete")
	await settle()


func run() -> void:
	var server := make_sector("EquipmentServer", true, 24731)
	var store := server.session.store
	check(store.pilots["pilot0"]["equipment"]["items"].size() == 3, "Legacy pilots receive starter items")
	check(JSON.parse_string(FileAccess.get_file_as_string(store.path))["version"] == 3, "Migration commits before server admits pilots")
	check(not JSON.parse_string(FileAccess.get_file_as_string(store.path + ".bak"))["pilots"]["pilot0"].has("equipment"), "Migration backs up the original ledger")
	check(store.commit({"pilot0": 40600}), "Seed test wallet through the normal commit path")
	var client := make_sector("EquipmentClient")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", 24731)
	await settle(0.5)
	await replicate(server)
	var id := client.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var combat := client.session.combat
	check(combat.inventory["items"].size() == 3 and client.credits == 40600, "Only authenticated inventory and wallet reach the client")
	check(ship.laser_damage == 65 and ship.max_shield == 1000 and ship.cruise_speed == 41 and ship.boost_speed == 83, "Starter uses LF-1, SG3N-A01 and Liberator base speed plus its original engine")
	var snapshot: Dictionary = client.session.goals[id].duplicate(true)
	snapshot["contracts"] = {"sentinel": HuntingContracts.accept("sentinel")}
	check(var_to_bytes([{id: snapshot}, {}, 1]).size() < 1200, "Player snapshot with equipment and an active contract leaves room below the ENet MTU")
	print("Snapshot payload: one player=%d bytes; two players=%d bytes" % [var_to_bytes([{id: snapshot}, {}, 1]).size(), var_to_bytes([{id: snapshot, 2: snapshot}, {}, 1]).size()])
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if DisplayServer.get_name() != "headless":
		var screen := TextureRect.new()
		screen.texture = client.get_viewport().get_texture()
		root.add_child(screen)
		root.size = Vector2i(960, 600)
	client.shop.open()
	await settle()
	check(client.shop.visible and client.paused, "Station shop opens and stops flight commands")
	check(not client.settings_menu.pause_panel.visible, "Shop hides flight-menu controls")
	await press(client, KEY_C)
	check(client.hud.contract_panel.visible and not client.shop.visible and client.paused and not client.settings_menu.pause_panel.visible, "C switches from shop to contracts while flight stays paused")
	await press(client, KEY_B)
	check(client.shop.visible and not client.hud.contract_panel.visible and client.paused and not client.settings_menu.pause_panel.visible, "B switches back to shop without overlapping panels")
	await press(client, KEY_F7)
	check(client.session.menu.visible and not client.shop.visible and not client.hud.contract_panel.visible, "Session menu closes both station panels")
	await press(client, KEY_ESCAPE)
	check(not client.paused and not client.session.menu.visible, "Esc resumes flight after the session menu")
	await press(client, KEY_B)
	await screenshot(client, "equipment-starter")
	await press(client, KEY_I)
	check(client.equipment_menu.visible and not client.shop.visible and client.paused and not client.settings_menu.pause_panel.visible, "I opens separate equipment screen and hides shop and pause controls")
	check(client.equipment_menu.slots.size() == 12 and client.equipment_menu.stored.is_empty(), "Active ship shows its twelve real slots and storage excludes installed items")
	check(client.equipment_menu.get_global_rect().position.y >= 0 and client.equipment_menu.get_global_rect().end.y <= 600, "Equipment panel fits the minimum window height")
	await screenshot(client, "equipment-layout-starter")
	var slot_scroll := client.equipment_menu.slots["extra2"].get_parent().get_parent().get_parent() as ScrollContainer
	slot_scroll.scroll_vertical = 1000
	await settle()
	check(slot_scroll.get_global_rect().encloses(client.equipment_menu.slots["extra2"].get_global_rect()), "Scrolling exposes the reserved extras within the minimum window")
	check(slot_scroll.get_global_rect().encloses(client.equipment_menu.slots["generator6"].get_global_rect()), "The sixth generator slot is reachable at minimum window size")
	await screenshot(client, "equipment-extra-slots")
	slot_scroll.scroll_vertical = 0
	await press(client, KEY_C)
	check(client.hud.contract_panel.visible and not client.equipment_menu.visible, "Contracts hide the equipment screen")
	await press(client, KEY_I)
	await press(client, KEY_F7)
	check(client.session.menu.visible and not client.equipment_menu.visible, "Session menu hides equipment")
	await press(client, KEY_ESCAPE)
	await press(client, KEY_B)
	client.audio.muted = false
	client.audio.master = 1.0
	client.audio.effects = 1.0
	client.audio.last_played.clear()
	client.shop.buys["laser"].pressed.emit()
	await settle()
	await replicate(server)
	check(client.credits == 30600 and combat.inventory["items"].has("purchase-1"), "Shop buy grants a distinct stored item and deducts its price")
	check(client.audio.last_played.has("purchase"), "Successful server-confirmed purchase plays its sound")
	client.audio.last_played.erase("purchase")
	await request(client, 1, "buy", "laser")
	check(store.pilots["pilot0"]["credits"] == 30600 and combat.inventory["items"].size() == 4, "Duplicate purchase changes neither credits nor inventory")
	check(not client.audio.last_played.has("purchase"), "Duplicate purchase does not replay the success sound")
	await request(client, 2, "buy", "laser")
	check(combat.inventory["items"].size() == 5, "Separate intentional purchase of the same model succeeds")
	await request(client, 3, "fit", "purchase-1", "starter", "generator1")
	check(combat.station_message.contains("Incompatible"), "Server rejects incompatible slots")
	await request(client, 3, "fit", "purchase-1", "starter", "laser1")
	check(combat.station_message.contains("occupied"), "Server rejects occupied slots")
	await request(client, 3, "fit", "foreign-item", "starter", "laser2")
	check(combat.station_message.contains("not own"), "Server rejects unowned items")
	await request(client, 3, "fit", "purchase-1", "foreign-ship", "laser2")
	check(combat.station_message.contains("not own"), "Server rejects unowned ships")
	for reason in ["distance", "speed", "damage", "life"]:
		ship.position = Vector3(0, 0, 400) if reason == "distance" else server.session.combat.records[id]["spawn"]
		ship.velocity = Vector3(10, 0, 0) if reason == "speed" else Vector3.ZERO
		ship.time_since_hit = 0 if reason == "damage" else 5
		await request(client, 3, "fit", "purchase-1", "starter", "laser2", 99 if reason == "life" else 0)
		check(combat.inventory["revision"] == 2, "Station rejects fitting for " + reason)
	ship.time_since_hit = 5
	ship.shield = 23
	ship.hull = 87
	ship.energy = 42
	ship.shot_cooldown = 0.3
	# Exercise the actual Godot drag routing and server-committed result.
	await press(client, KEY_I)
	var fitting := client.equipment_menu
	fitting.select_item("purchase-1")
	fitting.inspect_tile(fitting.slots["laser2"])
	await settle()
	check(fitting.preview.text.contains("130 damage"), "Preview includes the resulting additive damage")
	var revision: int = combat.inventory["revision"]
	await drag(client, fitting.stored["purchase-1"], fitting.slots["generator1"])
	check(combat.inventory["revision"] == revision and fitting.preview.text.is_empty(), "Incompatible drop leaves authoritative inventory unchanged and clears drag preview")
	await drag(client, fitting.stored["purchase-1"], fitting.slots["laser1"])
	check(combat.inventory["revision"] == revision, "Occupied slot rejects drops")
	await drag(client, fitting.stored["purchase-1"], fitting.slots["laser2"])
	await replicate(server)
	check(ship.laser_damage == 130 and client.player.laser_damage == 130, "Fitting updates authoritative and displayed damage")
	check(not fitting.stored.has("purchase-1") and fitting.slots["laser2"].item_id == "purchase-1", "Successful drag moves one instance from inventory into its slot")
	check(ship.shield == 23 and ship.hull == 87 and ship.energy == 42 and ship.shot_cooldown == 0.3, "Installing grants no repairs, shield charge, boost energy or cooldown reset")
	await screenshot(client, "equipment-fitted")
	await check_inventory_layout(client)
	await request(client, 3, "fit", "purchase-1", "starter", "laser2")
	check(combat.inventory["revision"] == 3, "Duplicate fitting does not change revision")
	await drag(client, fitting.slots["generator1"], fitting.storage_panel)
	check(ship.max_shield == 0 and ship.shield == 0, "Removing the last shield clamps charge to zero")
	check(fitting.stored.has("starter-shield") and fitting.slots["generator1"].item_id.is_empty(), "Dragging a fitted item into inventory empties its slot")
	fitting.stored["starter-shield"].pressed.emit()
	fitting.slots["generator1"].pressed.emit()
	await settle()
	check(ship.max_shield == 1000 and ship.shield == 0, "Reinstalling shields does not refill them")
	await request(client, 6, "buy", "g3n-3210")
	await request(client, 7, "fit", "starter-shield")
	await request(client, 8, "fit", "purchase-6", "starter", "generator1")
	await replicate(server)
	check(ship.cruise_speed == 45 and client.player.cruise_speed == 45 and client.player.boost_speed == 87, "Reference and starter engines add speed to server and client prediction")
	await request(client, 9, "buy", "laser")
	client.audio.last_played.erase("purchase")
	await request(client, 10, "buy", "laser")
	check(combat.station_message.contains("Insufficient") and combat.inventory["revision"] == 9 and store.pilots["pilot0"]["credits"] == 2600, "Insufficient funds grant no item and leave the sequence unchanged")
	check(not client.audio.last_played.has("purchase"), "Failed purchase does not play a success sound")
	await replicate(server)
	await screenshot(client, "equipment-insufficient")
	fitting.close()
	ship.position = server.alien.home_position + Vector3(0, 0, 100)
	ship.rotation = Vector3.ZERO
	ship.velocity = Vector3.ZERO
	server.alien.position = server.alien.home_position
	await physics_frame
	await replicate(server)
	client.select_target(client.alien)
	ship.shot_cooldown = 0
	var health_before := server.alien.shield + server.alien.hull
	check(ship.try_fire(server.alien), "Fitted ship fires in the live physics world")
	check(is_equal_approx(health_before - server.alien.shield - server.alien.hull, 130), "Actual combat applies both lasers")
	await replicate(server)
	await screenshot(client, "equipment-combat")
	# Allow the heavier flight acceleration to reach the upgraded cruise speed.
	for frame in range(120):
		ship.fly_command(1.0 / 60.0, Vector3(1, 0, 0), false)
		client.player.fly_command(1.0 / 60.0, Vector3(1, 0, 0), false)
		await physics_frame
	check(is_equal_approx(ship.velocity.length(), 45), "Actual flight reaches the fitted cruise speed")
	check(is_equal_approx(client.player.velocity.length(), 45), "Client prediction reaches the same fitted cruise speed")
	await replicate(server)
	await screenshot(client, "equipment-flight")
	ship.take_damage(ship.max_hull + ship.max_shield + 1.0, server.alien)
	server.session.combat.tick(3.1)
	check(ship.alive and ship.laser_damage == 130 and ship.cruise_speed == 45, "Death and rescue preserve fitting")
	client.session.disconnect_session("Restart test")
	await settle()
	server.session.disconnect_session("Restart test")
	check(server.session.host(24731) == OK, "Migrated inventory reloads on restart")
	client.session.join("127.0.0.1", 24731)
	await settle(0.5)
	await replicate(server)
	await request(client, 1, "buy", "laser")
	check(combat.inventory["revision"] == 9 and combat.inventory["items"].size() == 7 and client.credits == 2590, "Restart retains fittings, rescue fee and duplicate protection without another starter grant")
	store = server.session.store
	var saved: Dictionary = store.pilots["pilot0"].duplicate(true)
	var candidate: Dictionary = saved["equipment"].duplicate(true)
	candidate["ships"]["spare"] = "pathfinder"
	check(Equipment.valid(candidate), "Ownership model supports a second owned hull without making it playable")
	check(Equipment.fitting_blocker(candidate, "starter-engine", "spare", "generator1").is_empty(), "Items can transfer directly to a free compatible slot on another owned hull")
	candidate["items"]["starter-engine"]["ship"] = "spare"
	candidate["items"]["starter-engine"]["slot"] = "generator1"
	check(Equipment.stats(candidate)["speed"] == 37 and Equipment.stats(candidate, "spare")["speed"] == 41, "Transferred item contributes to exactly one ship")
	var empty := Equipment.starter()
	for item: Dictionary in empty["items"].values():
		item["ship"] = ""
		item["slot"] = ""
	var empty_ship := Pilot.new()
	empty_ship.render_enabled = false
	server.add_child(empty_ship)
	empty_ship.position = Vector3(100, 100, 100)
	Equipment.apply_stats(empty_ship, Equipment.stats(empty))
	empty_ship.fly_command(1.0, Vector3.FORWARD, false)
	check(empty_ship.hull == Equipment.STARTER_HULL and empty_ship.velocity.length() == 33 and empty_ship.firing_blocker(server.alien) == "NO LASER INSTALLED", "An empty fitting retains base hull and flight but cannot fire")
	empty_ship.queue_free()
	candidate["items"]["starter-laser"]["slot"] = "laser2"
	check(not Equipment.valid(candidate), "Save validation rejects duplicate slot occupancy")
	var path := store.path
	var disk_before := FileAccess.get_file_as_string(path)
	check(store.commit({"pilot0": 35000}), "Fund atomic bulk failure test")
	disk_before = FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	store.transact("pilot0", 10, "buy", "laser:3", "", "")
	check(store.failed and store.pilots["pilot0"]["equipment"] == saved["equipment"] and store.pilots["pilot0"]["credits"] == 35000 and FileAccess.get_file_as_string(path) == disk_before, "Failed bulk purchase persists neither deduction nor any items and latches failure")
	var migration_dir := store.path.get_base_dir().path_join("migration")
	DirAccess.make_dir_absolute(migration_dir)
	var legacy_contract := HuntingContracts.accept("scout")
	legacy_contract["progress"] = 2
	var legacy := {"verifier": test_token(0).sha256_text(), "credits": 4345, "contract": legacy_contract}
	var legacy_path := migration_dir.path_join("pilots.json")
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "pilots": {"pilot0": legacy}}))
	file.close()
	var migration := PilotStore.new()
	check(migration.open(migration_dir) and migration.pilots["pilot0"]["credits"] == 4345, "Migration preserves a nonzero wallet")
	check(migration.commit({"pilot0": 14345}), "Fund a purchase after legacy migration")
	migration.transact("pilot0", 1, "buy", "laser", "", "")
	check(migration.pilots["pilot0"]["contracts"] == {"scout": legacy_contract}, "Migration and equipment saves preserve the accepted contract and progress")
	migration.close()
	check(migration.open(migration_dir) and migration.pilots["pilot0"]["equipment"]["items"].size() == 4, "Repeated startup grants no additional starter equipment")
	migration.close()
	var malformed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
	malformed["pilots"]["pilot0"].erase("equipment")
	file = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(malformed))
	file.close()
	check(not migration.open(migration_dir), "Current saves with missing equipment fail instead of granting replacements")
	migration.close()
	client.session.disconnect_session("Equipment test complete")
	server.session.disconnect_session("Equipment test complete")
	await settle()
	await check_quick_equip()
	finish()
