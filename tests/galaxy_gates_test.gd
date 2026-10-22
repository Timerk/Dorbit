extends "res://tests/hunting_contracts_test.gd"
## Gate part rules, the Signal Anomaly operation, assembly, preview gates and a
## full Vashar Gate run with lives, waves, escorts, victory and collapse.


func run_rules() -> void:
	var gates := GalaxyGates.empty()
	check(GalaxyGates.valid(gates), "Empty gate progress is valid")
	for invalid: Variant in [null, {"parts": 0}, {"parts": -1, "signal": "available", "progress": 0}, {"parts": 100, "signal": "available", "progress": 0},
			{"parts": 0, "signal": "unknown", "progress": 0}, {"parts": 0, "signal": "available", "progress": 1},
			{"parts": 0, "signal": "active", "progress": GalaxyGates.SIGNAL["required"]}, {"parts": 0, "signal": "done", "progress": 0, "extra": 1}]:
		check(not GalaxyGates.valid(invalid), "Malformed gate state is rejected: %s" % JSON.stringify(invalid))
	var equipment := Equipment.starter()
	equipment["gates"] = {"parts": 7, "signal": "active", "progress": 3}
	check(Equipment.valid(equipment), "Saved gate progress keeps equipment valid")
	equipment["gates"] = {"parts": 7, "signal": "active", "progress": 99}
	check(not Equipment.valid(equipment), "Equipment with impossible gate progress is rejected")
	check(GalaxyGates.accept_blocker(gates).is_empty() and not GalaxyGates.assemble_blocker(gates).is_empty(), "A new pilot can trace the signal but cannot assemble")
	var plain := GalaxyGates.collect(gates, 2, 2)
	check(plain["gates"]["parts"] == 2 and plain["gates"]["progress"] == 0 and not plain["completed"], "Parts outside the operation only add to stock")
	var active := {"parts": 0, "signal": "active", "progress": 6}
	var partial := GalaxyGates.collect(active, 1, 1)
	check(GalaxyGates.collect(active, 3, 0)["gates"] == {"parts": 3, "signal": "active", "progress": 6}, "Parts from other maps add stock without operation progress")
	check(partial["gates"] == {"parts": 1, "signal": "active", "progress": 7} and partial["credits"] == 0, "Operation parts advance progress")
	var done := GalaxyGates.collect(partial["gates"], 3, 3)
	check(done["completed"] and done["gates"] == {"parts": 4 + GalaxyGates.SIGNAL["parts"], "signal": "done", "progress": 0}
		and done["credits"] == GalaxyGates.SIGNAL["credits"] and done["research"] == GalaxyGates.SIGNAL["research"], "The final part decodes the cache once")
	check(not GalaxyGates.accept_blocker(done["gates"]).is_empty(), "A decoded signal waits for the next gate")
	check(GalaxyGates.collect({"parts": 98, "signal": "available", "progress": 0}, 5, 5)["gates"]["parts"] == GalaxyGates.MAX_PARTS, "Stock is capped")
	var assembled := GalaxyGates.assemble({"parts": 23, "signal": "done", "progress": 0})
	check(assembled == {"parts": 3, "signal": "available", "progress": 0}, "Assembly consumes one gate and reopens the signal")
	var rng := RandomNumberGenerator.new()
	for attempt in range(50):
		check(GalaxyGates.roll_parts("Scout", rng, false) == 0 and GalaxyGates.roll_parts("Shardling", rng, false) == 0, "Home-map and arena aliens carry no parts")
		check(GalaxyGates.roll_parts("Skirmisher", rng, true) >= 1, "The operation guarantees a part")
	check(GalaxyGates.wave_counts(0, 1) == {"Shardling": 3} and GalaxyGates.wave_counts(1, 3) == {"Shardling": 8},
		"Waves scale with pilots and stay within the arena pool")
	check(GalaxyGates.wave_counts(6, 10)["Mothership"] == 1 and GalaxyGates.wave_counts(6, 10)["Shardling"] <= GalaxyGates.POOL["Shardling"] - GalaxyGates.ESCORTS,
		"The boss wave has one mothership and leaves dormant escorts at any group size")
	check(Alien.TYPES["Mothership"]["range"] < 310.0, "The mothership stays out-ranged by pilot lasers")
	check(str(GalaxyGates.pool_kinds()) == str(SectorMaps.MAPS[GalaxyGates.MAP]["aliens"]), "The arena roster matches the gate pool")


func saved(server: Sector, client: Sector) -> Dictionary:
	return GalaxyGates.state(server.session.store.pilots[server.session.pilot_ids[client.multiplayer.get_unique_id()]]["equipment"])


func move_to(server: Sector, client: Sector, map: int) -> void:
	var id := client.multiplayer.get_unique_id()
	if server.session.ships[id].map_id != map:
		server.session.transfer(id, map)
		await settle(0.08)


func request(server: Sector, client: Sector, action: String) -> void:
	await move_to(server, client, 0)
	station(server, client)
	client.session.combat.request_station(action, "")
	await settle(0.12)


# Kill one alien on `map` with the listed pilots contributing; returns its loot box ID.
func kill_on_map(server: Sector, map: int, clients: Array[Sector]) -> int:
	var alien: Alien = server.map_rosters[map].values()[0]
	alien.reset_encounter()
	for client in clients:
		await move_to(server, client, map)
		var ship := server.session.ships[client.multiplayer.get_unique_id()]
		ship.position = alien.home_position + Vector3(0, 0, 80)
		alien.take_damage(1, ship)
	var before := server.loot.next_id
	alien.take_damage(alien.max_hull + alien.max_shield + 1.0, server.session.ships[clients.back().multiplayer.get_unique_id()])
	return server.loot.next_id if server.loot.next_id != before else -1


func pick_up(server: Sector, client: Sector, drop_id: int) -> void:
	var ship := server.session.ships[client.multiplayer.get_unique_id()]
	ship.position = server.loot.drops[drop_id]["position"]
	server.session.combat.collect_loot()
	await settle(0.05)


func enter(server: Sector, client: Sector) -> String:
	var id := client.multiplayer.get_unique_id()
	await move_to(server, client, 0)
	var ship := server.session.ships[id]
	ship.position = SectorMaps.gate_position(0, GalaxyGates.MAP)
	server.session.jump_until.erase(id)
	var reason := server.session.jump(id, server.session.combat.records[id]["life"], GalaxyGates.MAP)
	# Leave the protected arrival zone so the pilot can fight.
	ship.position = SectorMaps.origin(GalaxyGates.MAP) + Vector3(0, 0, 200)
	return reason


func clear_wave(server: Sector, client: Sector) -> void:
	var ship := server.session.ships[client.multiplayer.get_unique_id()]
	for alien: Alien in server.session.combat.gate.wave_aliens.duplicate():
		if alien.alive:
			ship.position = alien.position + Vector3(0, 0, 60)
			alien.take_damage(alien.max_hull + alien.max_shield + 1.0, ship)


# Pilots on different maps never see each other, so wait for snapshots rather
# than the shared-map convergence used by other suites.
func sync(server: Sector) -> void:
	for attempt in range(4):
		server.session.send_snapshot()
		await settle(0.05)


func run() -> void:
	run_rules()
	var server := make_sector("GateServer", true, CONTRACT_PORT)
	var pilot := make_sector("GatePilot")
	var partner := make_sector("GatePartner")
	await connect_pilot(pilot, 0)
	await connect_pilot(partner, 1)
	if server.session.ships.size() != 2:
		check(false, "Gate pilots authenticate")
		finish()
		return
	var store := server.session.store
	var combat := server.session.combat
	var gate := combat.gate
	var id := pilot.multiplayer.get_unique_id()
	var partner_id := partner.multiplayer.get_unique_id()
	var pilot_id: String = server.session.pilot_ids[id]
	check(saved(server, pilot) == GalaxyGates.empty(), "Existing pilots start without gate parts")
	for alien: Alien in server.map_rosters[GalaxyGates.MAP].values():
		check(not alien.alive, "Arena aliens are dormant before any run")

	# Signal Anomaly: guaranteed M2 parts, pickup without cargo space and the cache reward.
	await request(server, pilot, "gate_signal")
	check(saved(server, pilot)["signal"] == "active" and pilot.session.combat.inventory["gates"]["signal"] == "active", "Accepting the operation is saved and published")
	await request(server, pilot, "gate_signal")
	check(pilot.session.combat.station_message.contains("already active"), "An active operation cannot be accepted twice")
	var next := store.pilots.duplicate(true)
	next[pilot_id]["cargo"]["starter"] = {"prometium": CargoResources.capacity(next[pilot_id]["equipment"])}
	check(store.persist(next), "Fill the pilot's cargo hold")
	combat.cargo_holds[id] = next[pilot_id]["cargo"].duplicate(true)
	var credits: int = combat.records[id]["credits"]
	var drop: int = await kill_on_map(server, 1, [pilot])
	check(drop >= 0 and int(server.loot.drops[drop].get("parts", 0)) >= 1, "An M2 kill during the operation carries a gate part")
	var carried := int(server.loot.drops[drop]["parts"])
	await pick_up(server, pilot, drop)
	check(saved(server, pilot)["parts"] == carried and saved(server, pilot)["progress"] == mini(carried, GalaxyGates.SIGNAL["required"] - 1), "Gate parts are collected and saved with a full cargo hold")
	check(server.loot.drops.has(drop) and not server.loot.drops[drop].has("parts"), "Resources stay in the box when the hold is full")
	var partner_drop: int = await kill_on_map(server, 1, [partner])
	check(partner_drop < 0 or int(server.loot.drops[partner_drop].get("parts", 0)) <= 1, "Pilots without the operation get only random parts")
	# A closer pilot without the operation cannot take the operation pilot's parts.
	var shared: int = await kill_on_map(server, 1, [pilot])
	var before_shared: int = saved(server, pilot)["parts"]
	server.session.ships[partner_id].position = server.loot.drops[shared]["position"]
	server.session.ships[id].position = server.loot.drops[shared]["position"] + Vector3(6, 0, 0)
	combat.collect_loot()
	await settle(0.05)
	check(saved(server, pilot)["parts"] > before_shared, "Gate parts go to the in-range pilot running the operation first")
	for attempt in range(GalaxyGates.SIGNAL["required"]):
		if saved(server, pilot)["signal"] != "active":
			break
		var box: int = await kill_on_map(server, 1, [pilot])
		await pick_up(server, pilot, box)
	var after := saved(server, pilot)
	check(after["signal"] == "done" and after["parts"] >= GalaxyGates.SIGNAL["required"] + GalaxyGates.SIGNAL["parts"], "Completing the operation adds the cache parts")
	check(store.pilots[pilot_id]["credits"] >= credits + GalaxyGates.SIGNAL["credits"], "The operation pays its credit reward")
	await request(server, pilot, "gate_assemble")
	check(saved(server, pilot)["parts"] == after["parts"] and not gate.active, "Assembly needs a full set of parts")

	# Assembly consumes parts and opens one shared run.
	next = store.pilots.duplicate(true)
	next[pilot_id]["equipment"]["gates"]["parts"] = GalaxyGates.PARTS_REQUIRED + 2
	check(store.persist(next), "Seed a full set of gate parts")
	await request(server, pilot, "gate_assemble")
	check(gate.active and SectorMaps.rift_open and saved(server, pilot) == {"parts": 2, "signal": "available", "progress": 0}, "Assembly consumes parts, reopens the signal and opens the gate")
	check(gate.builder == "Pilot %d" % id, "Runs are announced by the public pilot label, not the login ID")
	await sync(server)
	check(pilot.session.combat.gate_summary.get("active", false) and partner.session.combat.gate_summary.get("open", false), "Every pilot learns the gate is open")
	check(pilot.hud.navigation.has_contact("gate%d" % GalaxyGates.MAP), "The open gate is a navigation contact at Outpost 01")
	await request(server, partner, "gate_assemble")
	check(partner.session.combat.station_message.contains("already open"), "Only one run is open at a time")

	# Entry, lives and the first wave.
	var first: String = await enter(server, pilot)
	var second: String = await enter(server, partner)
	check(first.is_empty() and second.is_empty(), "Pilots fly through the open gate")
	check(server.session.ships[id].map_id == GalaxyGates.MAP and gate.lives[pilot_id] == GalaxyGates.LIVES, "Entering joins the run with full lives")
	gate.tick(1.0)
	await settle(0.1)
	var countdown: float = pilot.hud.gate_countdown()
	check(countdown > 0.0 and countdown <= GalaxyGates.FIRST_WAVE_DELAY, "Entering shows the countdown to the first wave")
	check(pilot.hud.gate_status().contains("WAVE 1 IN"), "The status line names the next wave and its countdown")
	gate.tick(GalaxyGates.FIRST_WAVE_DELAY)
	var alive := gate.wave_aliens.filter(func(alien: Alien): return alien.alive).size()
	check(gate.phase == "fighting" and gate.wave == 0 and alive == GalaxyGates.wave_counts(0, 2)["Shardling"], "The first wave scales to the pilots inside")
	await sync(server)
	check(pilot.map_id == GalaxyGates.MAP and pilot.session.combat.gate_summary["wave"] == 1, "The pilot's client shows the arena and wave")
	check(pilot.hud.gate_status().begins_with("VASHAR GATE / WAVE 1 OF") and pilot.hud.gate_countdown() < 0.0, "The HUD reports the active wave once the countdown ends")
	# No safe zone in the rift: aliens pursue a pilot waiting at the exit, which stays sealed.
	var holder := server.session.ships[id]
	holder.position = SectorMaps.gate_position(GalaxyGates.MAP, 0)
	server.session.ships[partner_id].position = holder.position + Vector3(8, 0, 0)
	check(not SectorMaps.protected(holder), "The rift exit has no protected zone")
	var hunter: Alien = gate.wave_aliens.filter(func(alien: Alien): return alien.alive)[0]
	check(combat.choose_target(hunter) in [holder, server.session.ships[partner_id]], "Wave aliens pursue pilots waiting at the rift exit")
	server.session.jump_until.erase(id)
	check(server.session.jump(id, combat.records[id]["life"], 0).contains("sealed") and holder.map_id == GalaxyGates.MAP, "The rift exit is sealed while a wave is alive")
	holder.position = SectorMaps.origin(GalaxyGates.MAP) + Vector3(0, 0, 200)
	var ship := server.session.ships[partner_id]
	ship.take_damage(ship.max_hull + ship.max_shield + 1.0, null)
	check(gate.lives[server.session.pilot_ids[partner_id]] == GalaxyGates.LIVES - 1, "Dying in the arena costs one life")
	combat.tick(3.1)
	check(ship.alive and ship.map_id == 0, "Rescue returns the pilot to Outpost 01")
	var rejoined: String = await enter(server, partner)
	check(rejoined.is_empty(), "A pilot with lives left can rejoin while the gate is open")

	# Clear every wave; the mothership launches escorts.
	var pilot_credits: int = store.pilots[pilot_id]["credits"]
	var partner_pilot: String = server.session.pilot_ids[partner_id]
	var x4 := {pilot_id: int(store.pilots[pilot_id]["ammo"]["x4"]), partner_pilot: int(store.pilots[partner_pilot]["ammo"]["x4"])}
	# Fix the LF-4 roll: this seed awards the pilot and not the partner.
	var seed := 0
	while true:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		if probe.randf() < GalaxyGates.REWARD["item_chance"] and probe.randf() >= GalaxyGates.REWARD["item_chance"]:
			break
		seed += 1
	var research := int(Research.state(store.pilots[pilot_id]["equipment"])["points"])
	for wave in range(GalaxyGates.WAVES.size()):
		if wave > 0:
			gate.tick(GalaxyGates.WAVE_DELAY + 0.1)
		check(gate.phase == "fighting" and gate.wave == wave, "Wave %d starts" % (wave + 1))
		if wave == GalaxyGates.WAVES.size() - 1:
			var boss := gate.wave_aliens.filter(func(alien: Alien): return alien.kind == "Mothership")
			check(boss.size() == 1 and boss[0].alive, "The final wave brings the mothership")
			var before := gate.wave_aliens.filter(func(alien: Alien): return alien.alive).size()
			gate.tick(GalaxyGates.ESCORT_INTERVAL + 0.1)
			gate.rng.seed = seed
			check(gate.wave_aliens.filter(func(alien: Alien): return alien.alive).size() > before, "The mothership launches escorts")
		clear_wave(server, pilot)
		gate.tick(0.1)
	check(gate.phase == "victory" and not SectorMaps.rift_open, "Destroying the last wave wins and closes the entrance")
	check(store.pilots[pilot_id]["credits"] >= pilot_credits + GalaxyGates.REWARD["credits"]
		and int(Research.state(store.pilots[pilot_id]["equipment"])["points"]) == research + GalaxyGates.REWARD["research"], "Victory pays participants credits and research")
	for winner: String in x4:
		check(int(store.pilots[winner]["ammo"]["x4"]) == x4[winner] + GalaxyGates.REWARD["x4"], "Victory adds 15,000 x4 shots to each participant")
	check(server.session.ships[id].ammo["x4"] == store.pilots[pilot_id]["ammo"]["x4"], "The live ship can fire the rewarded x4 shots")
	var lasers := func(pilot: String) -> Array: return store.pilots[pilot]["equipment"]["items"].values().filter(func(item: Dictionary): return item["model"] == "lf-4")
	check(lasers.call(pilot_id).size() == 1 and lasers.call(pilot_id)[0]["ship"] == "" and lasers.call(partner_pilot).is_empty(), "A won LF-4 roll places one LF-4 in storage")
	check(Equipment.fitting_blocker(store.pilots[pilot_id]["equipment"], store.pilots[pilot_id]["equipment"]["items"].find_key(lasers.call(pilot_id)[0]), "starter", "laser2").is_empty(), "The rewarded LF-4 can be fitted")
	await settle(0.1)
	check(pilot.session.combat.inventory["items"].values().any(func(item: Dictionary): return item["model"] == "lf-4"), "The pilot's client receives the LF-4")
	var closed: String = await enter(server, pilot)
	check(not closed.is_empty(), "A won gate cannot be re-entered")
	gate.tick(GalaxyGates.VICTORY_TIME + 0.1)
	await settle(0.1)
	check(not gate.active and server.session.ships[id].map_id == 0 and server.session.ships[partner_id].map_id == 0, "The rift closes and returns remaining pilots home")
	for alien: Alien in server.map_rosters[GalaxyGates.MAP].values():
		check(not alien.alive, "Closing the rift leaves arena aliens dormant")

	# Preview gates need an allowlisted pilot; an empty gate collapses.
	await request(server, partner, "gate_preview")
	check(not gate.active and partner.session.combat.station_message.contains("unavailable"), "Preview gates are refused for ordinary pilots")
	server.session.preview_tools_enabled = true
	server.session.preview_pilots = PackedStringArray([pilot_id])
	await sync(server)
	await request(server, pilot, "gate_preview")
	check(gate.active and saved(server, pilot)["parts"] == 2, "A preview pilot opens a gate without parts")
	await process_frame
	pilot.main_menu.select_page("gates")
	await process_frame
	check(pilot.gate_menu.visible and pilot.gate_menu.preview_button.visible and pilot.gate_menu.run_label.text.contains("GATE OPEN"), "The Galaxy Gates page shows the open gate and preview tool")
	# Quitting to the station mid-wave costs a life instead of a free repair.
	var retreating: String = await enter(server, partner)
	gate.tick(GalaxyGates.FIRST_WAVE_DELAY + 0.1)
	var partner_pilot_id: String = server.session.pilot_ids[partner_id]
	check(retreating.is_empty() and gate.phase == "fighting" and gate.lives[partner_pilot_id] == GalaxyGates.LIVES, "A pilot joins the preview wave")
	partner.session.quit_to_menu()
	await settle(0.15)
	check(server.session.ships[partner_id].get_meta("docked", false) and gate.lives[partner_pilot_id] == GalaxyGates.LIVES - 1, "Quitting to the station mid-wave costs a life")
	gate.tick(GalaxyGates.ABANDON_TIME + 0.1)
	check(not gate.active and not SectorMaps.rift_open, "A gate nobody holds collapses")
	finish()
