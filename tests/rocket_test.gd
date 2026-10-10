extends "res://tests/shop_test.gd"
## Real authenticated intentions and persistence; deterministic hit/miss rolls.


func roll(weapons: RocketWeapons, hit: bool, probability: float) -> void:
	for candidate in range(1000):
		weapons.rng.seed = candidate
		if (weapons.rng.randf() < probability) == hit:
			weapons.rng.seed = candidate
			return
	check(false, "Find deterministic hit/miss seed")


func run() -> void:
	var server := make_sector("RocketServer", true, 24839)
	var client := make_sector("RocketPilot")
	client.settings.reset_controls() # Other settings fixtures deliberately save swapped keys.
	client.get_viewport().size = Vector2i(1440, 900)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24839))
	await settle(0.5)
	await replicate(server)
	if not client.session.active:
		check(false, "Rocket pilot authenticates")
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	var remote := server.session.ships[id]
	var weapons := remote.rockets
	var store := server.session.store
	var combat := client.session.combat
	check(JSON.parse_string(FileAccess.get_file_as_string(store.path))["version"] == 8, "Old saves migrate to schema 8")
	check(remote.ammo["r-310"] == 100 and weapons.capacity == 0, "Starter gets 100 inherent single rockets without a launcher")
	check(store.commit({"pilot0": 10_000_000}), "Fund rocket shop purchases")
	server.session.combat.records[id]["credits"] = 10_000_000
	await replicate(server)
	client.main_menu.select_page("shop")
	for kind: String in Ammunition.ROCKETS:
		client.shop.select_model(kind)
		await capture(client, "rockets-shop-" + kind)
		var balance := client.credits
		var before: int = remote.ammo[kind]
		await click(client, client.shop.buys[kind])
		await replicate(server)
		check(remote.ammo[kind] == before + 100 and client.player.ammo[kind] == before + 100, kind + " purchase saves and replicates 100 rounds")
		check(client.credits == balance - int(Ammunition.ROCKETS[kind]["price"]), kind + " charges exact converted batch price")
	client.shop.select_model("hst-1")
	await capture(client, "rockets-shop-hst-1")
	client.shop.select_model("hst-2")
	await capture(client, "rockets-shop-hst-2")
	await click(client, client.shop.buys["hst-2"])
	await replicate(server)
	var item := "purchase-%d" % combat.inventory["revision"]
	combat.request_station("fit", item, "starter", "launcher1")
	await settle()
	await replicate(server)
	check(weapons.capacity == 5 and Equipment.valid(combat.inventory), "Owned HST-2 fits the dedicated launcher slot")
	var fitting := Equipment.starter()
	fitting["items"]["hst"] = {"model": "hst-1", "ship": "starter", "slot": "launcher1"}
	check(Equipment.stats(fitting)["launcher_capacity"] == 3, "HST-1 equips three-rocket capacity")
	check(not Equipment.fitting_blocker(fitting, "starter-laser", "starter", "launcher1").is_empty(), "Lasers cannot fit a launcher slot")
	client.main_menu.hide()
	client.main_menu.hide_pages()
	client.set_paused(false)
	client.session.launch()
	await settle()
	var enemy := server.alien
	enemy.max_hull = 1_000_000
	enemy.max_shield = 100_000
	enemy.reset_health()
	enemy.position = Vector3(0, 200, -70)
	enemy.home_position = enemy.position
	remote.position = Vector3(0, 200, 0)
	await physics_frame
	await replicate(server)
	client.alien.position = enemy.position # Fixture does not run client interpolation.
	client.select_target(client.alien)
	var before := remote.ammo.duplicate()
	weapons.tick(2.1)
	check(remote.ammo == before and weapons.pending.is_empty(), "Selection alone never launches rockets")
	var health_before := enemy.hull + enemy.shield
	var shield_before := enemy.shield
	roll(weapons, true, 0.7)
	client.settings.rebind("rocket", KEY_H)
	await press(client, KEY_H)
	client.settings.rebind("rocket", KEY_F)
	check(remote.ammo["r-310"] == before["r-310"] - 1 and weapons.pending.size() == 1, "Configured single-rocket key fires and spends exactly one saved round")
	var expected: float = weapons.pending[0]["damage"]
	check(expected >= 800 and expected <= 1000 and enemy.hull + enemy.shield == health_before, "Damage is an absolute 80-100% roll and waits for authoritative impact")
	combat.request_ammo("plt-2021")
	await settle()
	combat.request_rocket("single")
	await settle()
	check(remote.ammo["plt-2021"] == before["plt-2021"] and weapons.single_cooldown > 0, "Ammo switching cannot bypass shared single cooldown")
	client.select_target(client.aliens[1])
	weapons.tick(0.7)
	check(is_equal_approx(health_before - enemy.hull - enemy.shield, expected), "In-flight rocket keeps original target after selection changes")
	check(is_equal_approx(shield_before - enemy.shield, expected * enemy.shield_absorption), "Rocket damage follows existing shield absorption")
	weapons.tick(2.1)
	combat.request_ammo("r-310")
	await settle()
	client.select_target(client.alien)
	roll(weapons, false, 0.7)
	health_before = enemy.hull + enemy.shield
	var single_before: int = remote.ammo["r-310"]
	await press(client, KEY_7)
	var request_sequence := combat.rocket_request_sequence
	weapons.tick(2.1)
	check(remote.ammo["r-310"] == single_before - 1 and enemy.hull + enemy.shield == health_before, "Quickslot rocket command launches once; misses consume ammunition and deal zero damage")
	combat.rocket_request.rpc_id(1, request_sequence, 0, "single", "", 0, enemy.life)
	await settle()
	check(remote.ammo["r-310"] == single_before - 1 and weapons.pending.is_empty(), "Repeated request cannot launch again even after cooldown expires")
	before = remote.ammo.duplicate()
	for target: SpaceShip in [null, remote]:
		check(not weapons.fire_single(target).is_empty(), "Missing or friendly target is rejected")
	remote.position = Sector.STATION_POSITION
	check(weapons.fire_single(enemy) == "STATION PROTECTION", "Safe zone rejects rockets")
	remote.position = enemy.position + Vector3(0, 0, 130)
	check(weapons.fire_single(enemy) == "OUT OF RANGE", "Short rocket range is measured in game metres")
	remote.position = Vector3(0, 200, 0)
	remote.ammo["r-310"] = 0
	check(weapons.fire_single(enemy) == "NO ROCKET AMMUNITION", "Empty selected single ammunition gives clear feedback")
	remote.ammo = before.duplicate()
	check(remote.ammo == before and weapons.single_cooldown == 0, "All rejected shots preserve ammunition and cooldown")
	weapons.equip(0)
	check(weapons.activate(enemy) == "NO LAUNCHER EQUIPPED", "No launcher equipped gives clear feedback")
	weapons.equip(5)
	combat.request_ammo("hstrm-01")
	await settle()
	client.select_target(null)
	await press(client, KEY_G)
	weapons.tick(0.9)
	check(weapons.loaded == 0, "Launcher never loads before one second")
	weapons.tick(1.2)
	check(weapons.loaded == 2 and remote.ammo["hstrm-01"] == before["hstrm-01"] and weapons.available("hstrm-01") == before["hstrm-01"] - 2, "Loading reserves rounds without losing or charging them twice")
	check(weapons.activate(null) == "INVALID TARGET" and weapons.loaded == 2, "Invalid partial firing preserves loaded rockets")
	combat.request_ammo("eco-10")
	await settle()
	check(weapons.loaded == 0 and weapons.available("hstrm-01") == before["hstrm-01"], "Changing launcher ammo returns all unfired reservations")
	weapons.activate(null)
	weapons.tick(2.1)
	weapons.unload()
	check(weapons.available("eco-10") == before["eco-10"] and remote.ammo == before, "Unloading preserves total owned inventory")
	weapons.select("hstrm-01")
	weapons.activate(null)
	weapons.tick(5.1)
	await replicate(server)
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		await settle()
		var bar := client.hud.ammo_bar
		check(Rect2(Vector2.ZERO, dimensions).encloses(bar.get_global_rect()) and not bar.get_global_rect().intersects(client.hud.ship_rect()) and not bar.get_global_rect().intersects(client.hud.target_rect()), "Ammo bar fits above status cards at %s" % dimensions)
		check(client.player.rockets.loaded == 5 and (bar.launcher_fire as QuickslotTile).amount.text.count("●") == 5, "Confirmed launcher reservations replicate into capacity dots")
		var launcher_art := (bar.launcher_fire as QuickslotTile).art.texture
		check(launcher_art != null and launcher_art.resource_path.ends_with("/hst-2.png"), "Equipped Hellstorm artwork appears on its fire/load button")
		await capture(client, "rockets-flight-%d" % dimensions.x)
	client.select_target(client.alien)
	roll(weapons, true, 0.7)
	remote.shot_cooldown = 0
	check(remote.try_fire(enemy), "Lasers still fire while a launcher is loaded")
	var laser_clock := remote.shot_cooldown
	await click(client, client.hud.ammo_bar.single_fire)
	await press(client, KEY_SPACE)
	check(client.auto_fire, "Clicking the rocket button leaves Space available for laser combat")
	await press(client, KEY_SPACE)
	combat.request_rocket("launcher")
	await settle()
	if DisplayServer.get_name() != "headless":
		await replicate(server)
		var visible_rockets := get_nodes_in_group("rocket_feedback").filter(func(node: Node): return node.get_parent() == client)
		check(visible_rockets.size() == 6, "Confirmed volley renders five separate homing rockets alongside the single rocket")
		await capture(client, "rockets-volley")
	check(weapons.pending.size() == 6 and remote.shot_cooldown == laser_clock and weapons.launcher_cooldown == 3 and weapons.single_cooldown == 2, "Lasers, single rockets and a five-rocket volley run concurrently")
	check(remote.ammo["hstrm-01"] == before["hstrm-01"] - 5, "Full volley debits only five actual reservations")
	check(weapons.activate(null) == "LAUNCHER COOLDOWN" and not weapons.loading, "Launcher cannot reload during its independent three-second cooldown")
	weapons.select("eco-10")
	check(weapons.launcher_cooldown == 3, "Launcher ammo switching never resets cooldown")
	health_before = enemy.hull + enemy.shield
	weapons.tick(0.7)
	check(is_equal_approx(health_before - enemy.hull - enemy.shield, 20000 + float(expected_damage_single(weapons))), "Five HSTRM rockets total 20,000 damage plus the independent single rocket")
	weapons.tick(3.1)
	var next := remote.ammo.duplicate()
	next["eco-10"] = 2
	check(store.commit({}, {}, {}, {"pilot0": next}), "Seed scarce launcher ammo durably")
	remote.ammo = next.duplicate()
	weapons.activate(null)
	weapons.tick(5.1)
	check(weapons.loaded == 2 and not weapons.loading, "Scarce ammo finishes as a partial volley")
	check(weapons.activate(enemy).is_empty() and remote.ammo["eco-10"] == 0 and weapons.pending.size() == 2, "Partial volley consumes exactly its two rockets")
	health_before = enemy.hull + enemy.shield
	enemy.life += 1
	weapons.tick(0.7)
	check(enemy.hull + enemy.shield == health_before and weapons.pending.is_empty() and remote.ammo["eco-10"] == 0, "Encounter transition invalidates pending impacts without refunds")
	weapons.tick(3.1)
	roll(weapons, true, 0.7)
	weapons.fire_single(enemy)
	enemy.alive = false
	weapons.tick(0.7)
	check(weapons.pending.is_empty() and enemy.hull + enemy.shield == health_before, "Destroyed targets cannot receive pending damage")
	enemy.alive = true
	check(store.pilots["pilot0"]["ammo"] == remote.ammo, "All ammunition consumption matches the durable ledger")
	weapons.tick(3.1)
	roll(weapons, true, 0.7)
	weapons.fire_single(enemy)
	var map := Node3D.new()
	server.add_child(map)
	enemy.reparent(map, true)
	weapons.tick(0.7)
	check(weapons.pending.is_empty() and enemy.hull + enemy.shield == health_before, "Map transition invalidates locked pending impacts")
	enemy.reparent(server, true)
	map.queue_free()
	weapons.tick(3.1)
	before = remote.ammo.duplicate()
	combat.rocket_request_sequence += 1
	combat.rocket_request.rpc_id(1, combat.rocket_request_sequence, 999, "single", "", 0, enemy.life)
	await settle()
	check(remote.ammo == before and weapons.pending.is_empty(), "Old flight-life requests cannot fire after rescue or hull changes")
	await failed_debit(server, remote, enemy)
	check(not client.player.rockets.fire_single(client.alien).is_empty(), "Client cannot simulate firing or damage locally")
	before = remote.ammo.duplicate()
	client.select_target(null)
	weapons.tick(3.1)
	check(remote.ammo == before, "Stopping laser combat never triggers automatic rockets")
	weapons.select("hstrm-01")
	weapons.activate(null)
	weapons.tick(2.1)
	check(weapons.loaded == 2, "Prepare unfired reservations before disconnect")
	client.session.disconnect_session("Rocket reconnect check")
	await settle()
	client.session.join("127.0.0.1", test_port(24839))
	await settle(0.5)
	await replicate(server)
	check(client.player.ammo == before and client.player.rockets.loaded == 0, "Reconnect retains spent ammunition and releases reservations")
	await boosted_rockets(server, client, server.session.ships[client.multiplayer.get_unique_id()], enemy)
	finish()


func boosted_rockets(server: Sector, client: Sector, remote: Pilot, enemy: Alien) -> void:
	var weapons := remote.rockets
	var store := server.session.store
	var hull: String = store.pilots["pilot0"]["equipment"]["active_ship"]
	var hold := {"prometid": 1, "promerium": 1, "seprom": 1}
	var boosts := {}
	for resource: String in ["prometid", "promerium", "seprom"]:
		check(ResourceBoosts.apply(hold, boosts, "rockets", resource, 1, true).is_empty() and ResourceBoosts.remaining(boosts, "rockets") == 10, "Each rocket resource provides ten rounds: " + resource)
	var saved: Dictionary = store.pilots["pilot0"]["boosts"].duplicate(true)
	var cargo: Dictionary = store.pilots["pilot0"]["cargo"].duplicate(true)
	cargo[hull] = {"seprom": 1}
	check(store.commit({}, {}, {"pilot0": cargo}), "Seed cargo for confirmed rocket update")
	server.session.combat.cargo_holds[client.multiplayer.get_unique_id()] = cargo
	server.session.combat.publish_inventory(client.multiplayer.get_unique_id())
	await settle()
	client.main_menu.select_page("refining")
	var menu := client.resource_workshop
	menu.select_tab("update")
	menu.select_group("rockets")
	menu.select_resource("seprom")
	menu.upgrade_amount.value = 1
	await settle()
	check(not menu.upgrade_button.disabled, "Seprom rocket update is available at the outpost")
	await capture(client, "rocket-resource-update")
	await click(client, menu.upgrade_button)
	check(ResourceBoosts.remaining(remote.resource_boosts, "rockets") == 10 and not client.cargo.has("seprom"), "Confirmed rocket update spends one cargo unit and persists ten rounds")
	client.set_paused(false)
	client.session.launch()
	await settle()
	remote.position = Vector3(0, 100, 0)
	remote.set_meta("docked", false)
	enemy.position = Vector3(0, 100, -70)
	enemy.home_position = enemy.position
	enemy.reset_health()
	weapons.select("r-310")
	weapons.single_cooldown = 0
	roll(weapons, true, 0.7)
	check(weapons.fire_single(enemy).is_empty(), "Boosted single rocket fires")
	check(weapons.pending[0]["damage"] >= 1280 and weapons.pending[0]["damage"] <= 1600, "Seprom multiplies the single rocket damage roll by 1.6")
	check(ResourceBoosts.remaining(remote.resource_boosts, "rockets") == 9 and store.pilots["pilot0"]["boosts"][hull] == remote.resource_boosts, "Ammo and boost reserve are committed together before impact")
	check(weapons.fire_single(enemy) == "ROCKET COOLDOWN" and ResourceBoosts.remaining(remote.resource_boosts, "rockets") == 9, "Rejected shot preserves rocket reserve")
	weapons.pending.clear()
	weapons.single_cooldown = 0
	roll(weapons, false, 0.7)
	check(weapons.fire_single(enemy).is_empty() and not weapons.pending[0]["hit"] and ResourceBoosts.remaining(remote.resource_boosts, "rockets") == 8, "Misses consume one boosted round at launch")
	weapons.pending.clear()
	remote.resource_boosts["rockets"]["remaining"] = 2
	var ammo := remote.ammo.duplicate()
	ammo["eco-10"] = 3
	check(store.commit({}, {}, {}, {"pilot0": ammo}), "Seed ammunition for the partly boosted volley")
	remote.ammo = ammo
	weapons.select("eco-10")
	weapons.loaded = 3
	weapons.launcher_cooldown = 0
	check(weapons.activate(enemy).is_empty(), "Partly boosted Hellstorm volley fires")
	check(weapons.pending.size() == 3 and weapons.pending[0]["damage"] == 3200 and weapons.pending[1]["damage"] == 3200 and weapons.pending[2]["damage"] == 2000, "Only remaining boosted rounds increase Hellstorm damage")
	check(not remote.resource_boosts.has("rockets") and not store.pilots["pilot0"]["boosts"][hull].has("rockets"), "Exhausted rocket reserve clears in memory and ledger")
	weapons.pending.clear()
	remote.resource_boosts = {"rockets": {"resource": "promerium", "remaining": 7}}
	saved[hull] = remote.resource_boosts.duplicate(true)
	check(store.commit({}, {}, {}, {}, {"pilot0": saved}), "Save remaining reserve for reconnect")
	weapons.single_cooldown = 0
	weapons.launcher_cooldown = 0
	await failed_debit(server, remote, enemy)
	check(ResourceBoosts.remaining(remote.resource_boosts, "rockets") == 7, "Failed rocket debit preserves boost reserve")
	client.session.disconnect_session("Rocket boost reconnect")
	await settle()
	client.session.join("127.0.0.1", test_port(24839))
	await settle(0.5)
	await replicate(server)
	check(ResourceBoosts.remaining(client.player.resource_boosts, "rockets") == 7, "Reconnect restores remaining rocket boost")


func failed_debit(server: Sector, remote: Pilot, enemy: Alien) -> void:
	var directory := server.session.store.path.get_base_dir().path_join("rocket-save-failure-%d" % server.session.store.journal_sequence)
	DirAccess.make_dir_absolute(directory)
	var file := FileAccess.open(directory.path_join("pilots.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 7, "pilots": {"pilot0": server.session.store.pilots["pilot0"]}}))
	file.close()
	var probe := PilotStore.new()
	check(probe.open(directory), "Open isolated rocket debit failure ledger")
	var before := remote.ammo.duplicate()
	var disk := FileAccess.get_file_as_string(probe.path)
	var health_before := enemy.hull + enemy.shield
	DirAccess.make_dir_absolute(probe.path + ".tmp")
	var callback := remote.rockets.debit
	remote.rockets.debit = func(kind: String, count: int):
		var next := remote.ammo.duplicate()
		next[kind] -= count
		var holds: Dictionary = probe.pilots["pilot0"]["boosts"].duplicate(true)
		var boost := remote.resource_boosts.duplicate(true)
		ResourceBoosts.consume_rockets(boost, count)
		holds[probe.pilots["pilot0"]["equipment"]["active_ship"]] = boost
		return probe.commit_combat({"pilot0": next}, {"pilot0": holds})
	check(remote.rockets.fire_single(enemy) == "AMMUNITION SAVE FAILED" and probe.failed, "Failed durable single debit cancels the shot")
	remote.rockets.select("hstrm-01")
	remote.rockets.activate(null)
	remote.rockets.tick(2.1)
	check(remote.rockets.activate(enemy) == "AMMUNITION SAVE FAILED" and remote.rockets.loaded == 2, "Failed volley debit preserves loaded reservations")
	check(remote.ammo == before and enemy.hull + enemy.shield == health_before and remote.rockets.pending.is_empty() and remote.rockets.single_cooldown == 0 and remote.rockets.launcher_cooldown == 0 and FileAccess.get_file_as_string(probe.path) == disk, "Save failure preserves ammo, health, cooldowns and original disk")
	remote.rockets.debit = callback
	remote.rockets.unload()
	probe.close()


func expected_damage_single(weapons: RocketWeapons) -> float:
	# Same deterministic seed as the concurrent accepted single shot.
	roll(weapons, true, 0.7)
	weapons.rng.randf()
	return 1000.0 * weapons.rng.randf_range(0.8, 1.0)
