extends "res://tests/shop_test.gd"
## Real purchases and fitting RPCs; repair, automated costs, save recovery and UI.

var owned: Dictionary = {}


func extra_state(store: PilotStore) -> Dictionary:
	var state: Dictionary = store.pilots["pilot0"].duplicate(true)
	state.erase("skylab") # Station requests independently advance industry time.
	return state


func station(client: Sector, action: String, subject: String, ship: String = "", slot: String = "") -> void:
	client.session.combat.request_station(action, subject, ship, slot)
	await settle()


func run() -> void:
	var server := make_sector("ExtrasServer", true, 24849)
	var store := server.session.store
	check(store.commit({"pilot0": 20000000}), "Fund a disposable extras pilot")
	var client := make_sector("ExtrasPilot")
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	client.hud.layout.entries.clear() # Capture defaults without changing device preferences.
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24849))
	await settle(0.5)
	await replicate(server)
	if not client.session.active:
		check(false, "Extras pilot authenticates")
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	var remote := server.session.ships[id]
	check(client.player.repair_visual == null, "Idle pilot creates no repair meshes before working")
	var combat := client.session.combat
	client.shop.select_category("extras")
	check(client.shop.models_in_category("extras").size() == 7, "All seven extras appear in the shop")
	for model: String in client.shop.models_in_category("extras"):
		var sequence: int = combat.inventory["revision"] + 1
		var credits := client.credits
		await station(client, "buy", model)
		owned[model] = "purchase-%d" % sequence
		check(combat.inventory["items"][owned[model]]["ship"].is_empty() and client.credits == credits - Equipment.MODELS[model]["price"], model + " purchase saves exact cost and a stored instance")
		combat.station_request.rpc_id(1, sequence, "buy", model, "", "", 0)
		await settle()
		check(client.credits == credits - Equipment.MODELS[model]["price"], "Duplicate purchase does not charge " + model)
		check(StationUi.texture(model) != null, "Generated artwork loads for " + model)
	await station(client, "fit", owned["slot-cpu-1"], "starter", "extra1")
	await station(client, "fit", owned["rep-1"], "starter", "extra2")
	await station(client, "fit", owned["repair-auto"], "starter", "extra3")
	await station(client, "fit", owned["cargo-expander"], "starter", "extra4")
	check(Equipment.valid(combat.inventory) and Equipment.slots(combat.inventory).values().count("extra") == 4, "Slot CPU adds two valid slots")
	check(CargoResources.capacity(combat.inventory) == 800 and client.cargo_capacity == 800, "Cargo expansion replicates")
	var before := extra_state(store)
	await station(client, "fit", owned["rep-2"], "starter", "extra3")
	check(extra_state(store) == before, "A second robot cannot stack with REP-1")
	check(store.commit({}, {}, {"pilot0": {"starter": {"prometium": 500}}}), "Load expanded cargo")
	server.session.combat.cargo_holds[id] = store.pilots["pilot0"]["cargo"].duplicate(true)
	before = extra_state(store)
	await station(client, "fit", owned["slot-cpu-1"])
	check(extra_state(store) == before and combat.station_message.contains("Sell excess"), "Slot CPU removal cannot indirectly destroy expanded cargo")
	check(store.commit({}, {}, {"pilot0": {"starter": {}}}), "Clear disposable cargo")
	server.session.combat.cargo_holds[id] = {"starter": {}}
	var shipment_pilot: Dictionary = store.pilots["pilot0"].duplicate(true)
	var at := Skylab.now()
	shipment_pilot["skylab"]["shipment"] = {"id": "shipment-extras", "recipientId": "starter", "manifest": {"prometium": 800}, "dispatchedAt": at, "arrivesAt": at + 3600, "delivered": false}
	check(store.persist(store.pilots.merged({"pilot0": shipment_pilot}, true)), "Save a shipment that requires expanded capacity")
	before = extra_state(store)
	await station(client, "fit", owned["slot-cpu-1"])
	check(extra_state(store) == before and store.pilots["pilot0"]["skylab"]["shipment"]["manifest"] == {"prometium": 800} and combat.station_message.contains("shipment"), "Capacity removal preserves an in-flight expanded shipment")
	shipment_pilot = store.pilots["pilot0"].duplicate(true)
	shipment_pilot["skylab"]["shipment"] = null
	check(store.persist(store.pilots.merged({"pilot0": shipment_pilot}, true)), "Clear disposable shipment")
	await station(client, "fit", owned["slot-cpu-1"])
	check(combat.inventory["items"][owned["repair-auto"]]["ship"].is_empty() and combat.inventory["items"][owned["cargo-expander"]]["ship"].is_empty(), "Removing expansion returns both displaced items to storage")
	await station(client, "fit", owned["slot-cpu-1"], "starter", "extra1")
	await station(client, "fit", owned["repair-auto"], "starter", "extra3")
	client.main_menu.select_page("shop")
	for dimensions: Vector2i in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		client.shop.select_model("generator-cpu")
		await settle()
		check(client.shop.get_global_rect().encloses(client.shop.buys["generator-cpu"].get_global_rect()), "Extras purchase controls fit at %s" % dimensions)
		await capture(client, "extras-shop-%d" % dimensions.x)
	client.main_menu.select_page("hangar")
	client.equipment_menu.select_item(owned["ammo-cpu"])
	await settle()
	check(client.equipment_menu.extra_status.visible and client.equipment_menu.extra_ammo.visible, "Hangar explains quickslot automation and retains ammo selection")
	check(not Extras.enabled(combat.inventory["items"][owned["ammo-cpu"]]), "Ammo spending starts disabled")
	await capture(client, "extras-hangar")
	client.get_viewport().size = Vector2i(960, 600)
	await settle()
	check(client.equipment_menu.get_global_rect().encloses(client.equipment_menu.extra_status.get_global_rect()) and client.equipment_menu.get_global_rect().encloses(client.equipment_menu.extra_ammo.get_global_rect()), "Automation guidance and ammo controls fit the minimum supported window")
	var scroll := client.equipment_menu.slot_rows.get_parent() as ScrollContainer
	scroll.scroll_vertical = 10000
	await settle()
	check(scroll.get_global_rect().encloses(client.equipment_menu.slots["extra4"].get_global_rect()), "Expanded fitting slots remain accessible by scrolling")
	await capture(client, "extras-hangar-960")
	before = extra_state(store)
	await station(client, "configure_extra", owned["ammo-cpu"], "on", "x4")
	check(extra_state(store) == before, "Automatic x4 purchase is rejected without changing progression")
	client.session.launch()
	await settle()
	client.main_menu.hide()
	client.main_menu.hide_pages()
	client.set_paused(false)
	remote.position = Vector3(0, 200, 0)
	remote.velocity = Vector3.ZERO
	remote.time_since_hit = 100.0
	remote.hull = remote.max_hull / 2.0
	await replicate(server)
	var bar := client.hud.ammo_bar
	bar.config.save_path = "user://extras-test-quickslots.cfg"
	bar.config.reset_slots()
	bar.config.assign(9, "extra:repair-auto")
	bar.begin_editing()
	bar.tabs.current_tab = 3
	await settle()
	await click(client, bar.tiles[9])
	await settle()
	check(not remote.repair_auto and not Extras.enabled(store.pilots["pilot0"]["equipment"]["items"][owned["repair-auto"]]) and bar.tiles[9].amount.text == "OFF", "Assigned automation slot toggles OFF and saves away from station")
	var auto_tile: QuickslotTile
	for tile: QuickslotTile in bar.picker_tiles:
		if tile.action_id == "extra:repair-auto":
			auto_tile = tile
	await click(client, auto_tile)
	await settle()
	check(remote.repair_auto and auto_tile.amount.text == "ON" and bar.tiles[9].amount.text == "ON", "Picker click toggles ON and synchronizes assigned slot")
	await click(client, auto_tile)
	await settle()
	check(not remote.repair_auto, "Repeated picker click toggles OFF")
	await click(client, bar.tiles[9])
	await settle()
	check(remote.repair_auto, "Repeated assigned-slot click toggles ON")
	for dimensions: Vector2i in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		await settle()
		check(client.hud.get_global_rect().encloses(bar.picker.get_global_rect()), "Automation picker fits at %s" % dimensions)
		await capture(client, "extras-quickslots-%d" % dimensions.x)
	bar.close_picker()
	before = extra_state(store)
	await click(client, bar.tiles[9])
	await settle()
	check(extra_state(store) == before, "Automation click outside slot editing leaves saved settings unchanged")
	check(not bar.state_for("extra:ammo")["available"], "Stored CPUs are unavailable in the flight picker")
	await station(client, "configure_extra", owned["ammo-cpu"], "on", "x1")
	check(extra_state(store) == before, "Server rejects configuring a stored CPU away from station")
	combat.station_request.rpc_id(1, combat.inventory["revision"] + 1, "configure_extra", owned["repair-auto"], "off", "", -1)
	await settle()
	check(extra_state(store) == before, "Server rejects stale-life automation toggles")
	var observer := make_sector("ExtrasObserver")
	observer.session.credential_id = "pilot1"
	observer.session.credential_token = test_token(1)
	observer.session.join("127.0.0.1", test_port(24849))
	await settle(0.5)
	var hull := remote.hull
	Extras.tick_repair(remote, 1.0, false)
	check(is_equal_approx(remote.hull - hull, remote.max_hull / 165.0), "REP-1 auto-repairs at its full-hull rate")
	remote.velocity = Vector3.ONE
	hull = remote.hull
	Extras.tick_repair(remote, 1.0, false)
	check(remote.hull == hull and not remote.robot_repairing, "Movement interrupts repair")
	remote.velocity = Vector3.ZERO
	remote.time_since_hit = 0.0
	Extras.tick_repair(remote, 1.0, false)
	check(remote.hull == hull, "Damage blocks repair")
	remote.time_since_hit = 100.0
	Extras.tick_repair(remote, 1.0, true)
	check(remote.hull == hull, "Fire intent blocks repair")
	remote.repair_auto = false
	remote.time_since_attack = 100.0
	bar.config.assign(8, "extra:repair")
	await settle()
	await click(client, bar.tiles[8])
	await settle()
	check(remote.repair_requested, "Assigned repair action starts the fitted robot through the server")
	await press(client, KEY_R)
	await settle()
	check(not remote.repair_requested, "Repair key stops the manually activated robot")
	await press(client, KEY_R)
	await settle()
	check(remote.repair_requested, "Repair key restarts the fitted robot through the server")
	Extras.tick_repair(remote, 1.0, false)
	check(remote.hull > hull, "Manual robot repairs hull")
	await replicate(server)
	check(client.player.robot_repairing and is_equal_approx(client.player.hull, remote.hull), "Robot status and health replicate")
	check(client.player.repair_visual != null and client.player.repair_visual.visible and client.player.repair_visual.beams.size() == 2, "Working robot and repair beams appear on the local ship")
	check(observer.session.ships.has(id) and observer.session.ships[id].repair_visual.visible, "Working repair bot is visible on a remote pilot")
	check(remote.repair_visual == null, "Dedicated server does not create repair visuals")
	await capture(client, "extras-repair")
	check(server.session.combat.repair(id, -1) == false, "Stale repair life is rejected")
	var enemy := server.alien
	enemy.reset_health()
	enemy.returning = false
	enemy.position = remote.position + Vector3(0, 0, -50)
	check(remote.rockets.fire_single(enemy).is_empty() and remote.time_since_attack == 0.0 and not remote.repair_requested and not remote.robot_repairing, "A fired rocket interrupts repair and starts the combat delay")
	hull = remote.hull
	Extras.tick_repair(remote, 1.0, false)
	check(remote.hull == hull, "Robot cannot resume immediately after firing a rocket")
	await replicate(server)
	check(not client.player.repair_visual.visible and not observer.session.ships[id].repair_visual.visible, "Repair bot disappears on local and remote ships after interruption")
	# Automation uses copies; no effect becomes visible until the store commits.
	var pilot: Dictionary = store.pilots["pilot0"].duplicate(true)
	var equipment: Dictionary = pilot["equipment"]
	Equipment.move(equipment, owned["repair-auto"], "", "")
	Equipment.move(equipment, owned["ammo-cpu"], "starter", "extra3")
	Equipment.move(equipment, owned["generator-cpu"], "starter", "extra4")
	Equipment.move(equipment, owned["rep-1"], "", "")
	Equipment.move(equipment, owned["rep-2"], "starter", "extra2")
	equipment["items"][owned["ammo-cpu"]]["enabled"] = false
	pilot["ammo"]["x1"] = 0
	var boosts := {}
	check(not Extras.automatic_update(pilot, boosts), "Automatic spending is opt-in")
	equipment["items"][owned["ammo-cpu"]]["enabled"] = true
	equipment["items"][owned["ammo-cpu"]]["ammo_type"] = "x2"
	pilot["ammo"]["x2"] = 999
	var credits: int = pilot["credits"]
	check(Extras.automatic_update(pilot, boosts) and pilot["ammo"]["x2"] == 10999 and pilot["credits"] == credits - 5000, "Ammo CPU buys exactly 10,000 configured rounds for normal price")
	check(not Extras.automatic_update(pilot, boosts), "A full supply cannot trigger another charge")
	pilot["ammo"]["x2"] = 0
	pilot["credits"] = 0
	check(not Extras.automatic_update(pilot, boosts), "Insufficient credits cause no partial refill")
	equipment["items"][owned["ammo-cpu"]]["enabled"] = false
	equipment["items"][owned["generator-cpu"]]["enabled"] = true
	pilot["cargo"]["starter"] = {"seprom": 2, "promerium": 2, "duranium": 2}
	check(Extras.automatic_update(pilot, boosts) and boosts["shields"]["resource"] == "seprom" and boosts["engines"]["resource"] == "promerium", "Generator CPU selects the strongest compatible resource per group")
	check(pilot["cargo"]["starter"] == {"seprom": 1, "promerium": 1, "duranium": 2}, "One resource per generator group is consumed")
	check(not Extras.automatic_update(pilot, boosts), "Existing reserves are never overwritten or topped up automatically")
	# Exercise the real authority's commit path and client supply snapshots.
	check(store.persist(store.pilots.merged({"pilot0": pilot}, true)), "Save disposable configured fitting")
	server.session.combat.apply_equipment(id)
	check(remote.repair_seconds == 120.0, "REP-2 replaces REP-1 with its faster repair rate")
	remote.extras_clock = 1.0
	remote.resource_boosts.clear()
	check(server.session.combat.tick_extras(id, 0.0), "Server commits automatic resource costs")
	await replicate(server)
	check(client.player.resource_boosts == remote.resource_boosts and client.cargo == store.pilots["pilot0"]["cargo"]["starter"], "Automatic boost and cargo updates replicate")
	await replicate(server)
	server.session.combat.publish_inventory(id)
	await settle()
	# Fitted spending CPUs can toggle while moving or in combat without refitting.
	remote.position = Vector3(0, 200, 0)
	remote.velocity = Vector3.ONE
	remote.time_since_hit = 0.0
	remote.repair_requested = true
	await replicate(server)
	bar.begin_editing()
	bar.tabs.current_tab = 3
	var ammo_tile: QuickslotTile
	var generator_tile: QuickslotTile
	for tile: QuickslotTile in bar.picker_tiles:
		if tile.action_id == "extra:ammo":
			ammo_tile = tile
		elif tile.action_id == "extra:generators":
			generator_tile = tile
	await settle()
	await click(client, ammo_tile)
	await settle()
	check(Extras.enabled(store.pilots["pilot0"]["equipment"]["items"][owned["ammo-cpu"]]) and remote.repair_requested, "Fitted ammo toggle persists in flight without clearing manual repair intent")
	await click(client, generator_tile)
	await settle()
	check(not Extras.enabled(store.pilots["pilot0"]["equipment"]["items"][owned["generator-cpu"]]), "Fitted generator CPU toggles independently")
	bar.close_picker()
	before = extra_state(store)
	remote.alive = false
	await station(client, "configure_extra", owned["ammo-cpu"], "off", "x2")
	check(extra_state(store) == before, "Dead ship cannot configure automation")
	remote.alive = true
	remote.velocity = Vector3.ZERO
	# Configure and use the buyer through real RPCs and the authority commit path.
	remote.position = server.session.combat.records[id]["spawn"]
	remote.time_since_hit = 100.0
	await station(client, "configure_extra", owned["ammo-cpu"], "on", "x3")
	var refill_ammo := remote.ammo.duplicate()
	for kind: String in Ammunition.TYPES:
		refill_ammo[kind] = 0
	check(store.commit({"pilot0": 100000}, {}, {}, {"pilot0": refill_ammo}), "Fund an authoritative automatic refill")
	remote.ammo = store.pilots["pilot0"]["ammo"].duplicate()
	var selected: String = remote.ammo_type
	remote.extras_clock = 1.0
	check(server.session.combat.tick_extras(id, 0.0), "Automatic ammo refill commits on the server")
	await replicate(server)
	check(store.pilots["pilot0"]["ammo"]["x3"] == 10000 and remote.ammo["x3"] == 10000 and client.player.ammo["x3"] == 10000 and client.credits == 90000 and remote.ammo_type == selected, "Automatic x3 purchase saves and replicates exact rounds and price without changing selected ammo")
	var reloaded := PilotStore.new()
	store.close()
	check(reloaded.open(store.path.get_base_dir()) and extra_state(reloaded) == extra_state(store), "Extra items, settings, cargo and automatic costs survive reload")
	reloaded.close()
	finish()
