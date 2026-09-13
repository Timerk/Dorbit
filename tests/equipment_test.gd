extends "res://tests/dedicated_server_test.gd"
## Real authenticated RPCs, atomic disk changes, and the rendered fitting controls.


func request(client: Sector, sequence: int, action: String, subject: String, ship: String = "", slot: String = "", life: int = 0) -> void:
	client.session.combat.station_request.rpc_id(1, sequence, action, subject, ship, slot, life)
	await settle(0.1)


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


func run() -> void:
	var server := make_sector("EquipmentServer", true, 24731)
	var store := server.session.store
	check(store.pilots["pilot0"]["equipment"]["items"].size() == 3, "Legacy pilots receive starter items")
	check(JSON.parse_string(FileAccess.get_file_as_string(store.path))["version"] == 2, "Migration commits before server admits pilots")
	check(not JSON.parse_string(FileAccess.get_file_as_string(store.path + ".bak"))["pilots"]["pilot0"].has("equipment"), "Migration backs up the original ledger")
	check(store.commit({"pilot0": 12000}), "Seed test wallet through the normal commit path")
	var client := make_sector("EquipmentClient")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", 24731)
	await settle(0.5)
	await replicate(server)
	var id := client.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var combat := client.session.combat
	check(combat.inventory["items"].size() == 3 and client.credits == 12000, "Only authenticated inventory and wallet reach the client")
	check(ship.laser_damage == 11 and ship.max_shield == 70 and ship.cruise_speed == 36 and ship.boost_speed == 78, "Starter performance is preserved")
	var chunk := {id: client.session.goals[id], 2: client.session.goals[id]}
	check(var_to_bytes([chunk, server.session.combat.pack_alien(), 1]).size() < 1200, "Two-player snapshot with equipment stats leaves room below the ENet MTU")
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
	await screenshot(client, "equipment-starter")
	client.shop.buys["laser"].pressed.emit()
	await settle()
	await replicate(server)
	check(client.credits == 9000 and combat.inventory["items"].has("purchase-1"), "Shop buy grants a distinct stored item and deducts its price")
	await request(client, 1, "buy", "laser")
	check(store.pilots["pilot0"]["credits"] == 9000 and combat.inventory["items"].size() == 4, "Duplicate purchase changes neither credits nor inventory")
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
	# Exercise the same buttons and preview used by a player.
	client.shop.items.select(client.shop.item_ids.find("purchase-1"))
	client.shop.destination.select(1)
	await settle()
	check(client.shop.preview.text.contains("22 damage"), "Preview includes the resulting additive damage")
	client.shop.fit_button.pressed.emit()
	await settle()
	await replicate(server)
	check(ship.laser_damage == 22 and client.player.laser_damage == 22, "Fitting updates authoritative and displayed damage")
	check(ship.shield == 23 and ship.hull == 87 and ship.energy == 42 and ship.shot_cooldown == 0.3, "Installing grants no repairs, shield charge, boost energy or cooldown reset")
	await screenshot(client, "equipment-fitted")
	await request(client, 3, "fit", "purchase-1", "starter", "laser2")
	check(combat.inventory["revision"] == 3, "Duplicate fitting does not change revision")
	await request(client, 4, "fit", "starter-shield")
	check(ship.max_shield == 0 and ship.shield == 0, "Removing the last shield clamps charge to zero")
	await request(client, 5, "fit", "starter-shield", "starter", "generator1")
	check(ship.max_shield == 70 and ship.shield == 0, "Reinstalling shields does not refill them")
	await request(client, 6, "buy", "engine")
	await request(client, 7, "fit", "starter-shield")
	await request(client, 8, "fit", "purchase-6", "starter", "generator1")
	await replicate(server)
	check(ship.cruise_speed == 44 and client.player.cruise_speed == 44 and client.player.boost_speed == 86, "Two engines add speed to server and client prediction")
	await request(client, 9, "buy", "laser")
	await request(client, 10, "buy", "laser")
	check(combat.station_message.contains("Insufficient") and combat.inventory["revision"] == 9 and store.pilots["pilot0"]["credits"] == 600, "Insufficient funds grant no item and leave the sequence unchanged")
	await replicate(server)
	await screenshot(client, "equipment-insufficient")
	client.shop.close()
	ship.position = Vector3(0, 60, 0)
	ship.rotation = Vector3.ZERO
	ship.velocity = Vector3.ZERO
	server.alien.position = Vector3(0, 60, -100)
	await physics_frame
	await replicate(server)
	client.select_target(client.alien)
	ship.shot_cooldown = 0
	var health_before := server.alien.shield + server.alien.hull
	check(ship.try_fire(server.alien), "Fitted ship fires in the live physics world")
	check(is_equal_approx(health_before - server.alien.shield - server.alien.hull, 22), "Actual combat applies both lasers")
	await replicate(server)
	await screenshot(client, "equipment-combat")
	for frame in range(60):
		ship.fly_command(1.0 / 60.0, Vector3(1, 0, 0), false)
		client.player.fly_command(1.0 / 60.0, Vector3(1, 0, 0), false)
		await physics_frame
	check(is_equal_approx(ship.velocity.length(), 44), "Actual flight reaches the fitted cruise speed")
	check(is_equal_approx(client.player.velocity.length(), 44), "Client prediction reaches the same fitted cruise speed")
	await replicate(server)
	await screenshot(client, "equipment-flight")
	ship.take_damage(999, server.alien)
	server.session.combat.tick(3.1)
	check(ship.alive and ship.laser_damage == 22 and ship.cruise_speed == 44, "Death and rescue preserve fitting")
	client.session.disconnect_session("Restart test")
	await settle()
	server.session.disconnect_session("Restart test")
	check(server.session.host(24731) == OK, "Migrated inventory reloads on restart")
	client.session.join("127.0.0.1", 24731)
	await settle(0.5)
	await replicate(server)
	await request(client, 1, "buy", "laser")
	check(combat.inventory["revision"] == 9 and combat.inventory["items"].size() == 7 and client.credits == 590, "Restart retains fittings, rescue fee and duplicate protection without another starter grant")
	store = server.session.store
	var saved: Dictionary = store.pilots["pilot0"].duplicate(true)
	var candidate: Dictionary = saved["equipment"].duplicate(true)
	candidate["ships"]["spare"] = "pathfinder"
	check(Equipment.valid(candidate), "Ownership model supports a second owned hull without making it playable")
	check(Equipment.fitting_blocker(candidate, "starter-engine", "spare", "generator1").is_empty(), "Items can transfer directly to a free compatible slot on another owned hull")
	candidate["items"]["starter-engine"]["ship"] = "spare"
	candidate["items"]["starter-engine"]["slot"] = "generator1"
	check(Equipment.stats(candidate)["speed"] == 36 and Equipment.stats(candidate, "spare")["speed"] == 36, "Transferred item contributes to exactly one ship")
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
	check(empty_ship.hull == 120 and empty_ship.velocity.length() == 28 and empty_ship.firing_blocker(server.alien) == "NO LASER INSTALLED", "An empty fitting retains base hull and flight but cannot fire")
	empty_ship.queue_free()
	candidate["items"]["starter-laser"]["slot"] = "laser2"
	check(not Equipment.valid(candidate), "Save validation rejects duplicate slot occupancy")
	var path := store.path
	var disk_before := FileAccess.get_file_as_string(path)
	check(store.commit({"pilot0": 5000}), "Fund atomic failure test")
	disk_before = FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	store.transact("pilot0", 10, "buy", "laser", "", "")
	check(store.failed and store.pilots["pilot0"]["equipment"] == saved["equipment"] and store.pilots["pilot0"]["credits"] == 5000 and FileAccess.get_file_as_string(path) == disk_before, "Failed purchase persists neither deduction nor item and latches failure")
	var migration_dir := store.path.get_base_dir().path_join("migration")
	DirAccess.make_dir_absolute(migration_dir)
	var legacy := {"verifier": test_token(0).sha256_text(), "credits": 4345, "contract": {"id": "test", "progress": 2}}
	var legacy_path := migration_dir.path_join("pilots.json")
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "pilots": {"pilot0": legacy}}))
	file.close()
	var migration := PilotStore.new()
	check(migration.open(migration_dir) and migration.pilots["pilot0"]["credits"] == 4345, "Migration preserves a nonzero wallet")
	migration.transact("pilot0", 1, "buy", "laser", "", "")
	check(migration.pilots["pilot0"]["contract"]["id"] == "test" and migration.pilots["pilot0"]["contract"]["progress"] == 2, "Migration and equipment saves preserve unrelated contract fields")
	migration.close()
	check(migration.open(migration_dir) and migration.pilots["pilot0"]["equipment"]["items"].size() == 4, "Repeated startup grants no additional starter equipment")
	migration.close()
	var malformed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
	malformed["pilots"]["pilot0"].erase("equipment")
	file = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(malformed))
	file.close()
	check(not migration.open(migration_dir), "Version two saves with missing equipment fail instead of granting replacements")
	migration.close()
	finish()
