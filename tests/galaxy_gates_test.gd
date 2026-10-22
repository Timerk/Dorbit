extends "res://tests/hunting_contracts_test.gd"
## Gate part rules for every gate, the Vashar operation, assembly, preview gates,
## a full Vashar run with lives, waves, escorts, victory and collapse, and full
## runs of every further gate.


const VASHAR := "vashar"
const KORRATH := "korrath"
const SYLITH := "sylith"
const VMAP := 4
const KMAP := 5


func run_rules() -> void:
	var gates := GalaxyGates.empty()
	var vashar := GalaxyGates.info(VASHAR)
	var operation: Dictionary = vashar["signal"]
	check(GalaxyGates.valid(gates, VASHAR) and GalaxyGates.valid_collection({}), "Empty gate progress is valid")
	for invalid: Variant in [null, {"parts": 0}, {"parts": -1, "signal": "available", "progress": 0}, {"parts": 100, "signal": "available", "progress": 0},
			{"parts": 0, "signal": "unknown", "progress": 0}, {"parts": 0, "signal": "available", "progress": 1},
			{"parts": 0, "signal": "active", "progress": operation["required"]}, {"parts": 0, "signal": "done", "progress": 0, "extra": 1}]:
		check(not GalaxyGates.valid(invalid, VASHAR), "Malformed gate state is rejected: %s" % JSON.stringify(invalid))
	check(not GalaxyGates.valid_collection({"unknown": gates}) and not GalaxyGates.valid_collection([gates]), "Unknown gates and non-dictionaries are rejected")
	check(GalaxyGates.valid({"parts": 0, "signal": "active", "progress": 9}, KORRATH) and not GalaxyGates.valid({"parts": 0, "signal": "active", "progress": 9}, VASHAR),
		"Operation progress is bounded by each gate's own requirement")
	var equipment := Equipment.starter()
	equipment["gates"] = {VASHAR: {"parts": 7, "signal": "active", "progress": 3}, KORRATH: {"parts": 2, "signal": "available", "progress": 0}}
	check(Equipment.valid(equipment), "Saved progress for several gates keeps equipment valid")
	equipment["gates"] = {VASHAR: {"parts": 7, "signal": "active", "progress": 99}}
	check(not Equipment.valid(equipment), "Equipment with impossible gate progress is rejected")
	check(GalaxyGates.accept_blocker(gates, VASHAR).is_empty() and not GalaxyGates.assemble_blocker(gates, VASHAR).is_empty(), "A new pilot can trace the signal but cannot assemble")
	var plain := GalaxyGates.collect(gates, VASHAR, 2)
	check(plain["gates"]["parts"] == 2 and plain["gates"]["progress"] == 0 and not plain["completed"], "Parts outside the operation only add to stock")
	var active := {"parts": 0, "signal": "active", "progress": 6}
	var partial := GalaxyGates.collect(active, VASHAR, 1)
	check(partial["gates"] == {"parts": 1, "signal": "active", "progress": 7} and partial["credits"] == 0, "Operation parts advance progress")
	var done := GalaxyGates.collect(partial["gates"], VASHAR, 3)
	check(done["completed"] and done["gates"] == {"parts": 4 + operation["parts"], "signal": "done", "progress": 0}
		and done["credits"] == operation["credits"] and done["research"] == operation["research"], "The final part decodes the cache once")
	check(not GalaxyGates.accept_blocker(done["gates"], VASHAR).is_empty(), "A decoded signal waits for the next gate")
	check(GalaxyGates.collect({"parts": 98, "signal": "available", "progress": 0}, VASHAR, 5)["gates"]["parts"] == GalaxyGates.MAX_PARTS, "Stock is capped")
	var assembled := GalaxyGates.assemble({"parts": 23, "signal": "done", "progress": 0}, VASHAR)
	check(assembled == {"parts": 3, "signal": "available", "progress": 0}, "Assembly consumes one gate and reopens the signal")
	check(GalaxyGates.assemble({"parts": 30, "signal": "available", "progress": 0}, KORRATH)["parts"] == 6, "Each gate consumes its own part count")
	var rng := RandomNumberGenerator.new()
	for attempt in range(50):
		check(GalaxyGates.roll_parts("Scout", rng, []).is_empty() and GalaxyGates.roll_parts("Shardling", rng, []).is_empty() and GalaxyGates.roll_parts("Husk", rng, []).is_empty(),
			"Home-map and arena aliens carry no parts")
		check(int(GalaxyGates.roll_parts("Skirmisher", rng, [VASHAR]).get(VASHAR, 0)) >= 1, "The operation guarantees a part")
		check(not GalaxyGates.roll_parts("Skirmisher", rng, []).has(KORRATH), "Korrath parts only come from the deeper maps")
	check(GalaxyGates.wave_counts(VASHAR, 0, 1) == {"Shardling": 3} and GalaxyGates.wave_counts(VASHAR, 1, 3) == {"Shardling": 8},
		"Waves scale with pilots and stay within the arena pool")
	check(GalaxyGates.wave_counts(VASHAR, 6, 10)["Mothership"] == 1, "The boss wave has one mothership at any group size")
	for gate_id: String in GalaxyGates.ORDER:
		var definition := GalaxyGates.info(gate_id)
		check(str(GalaxyGates.pool_kinds(gate_id)) == str(SectorMaps.MAPS[definition["map"]]["aliens"]), "%s arena roster matches its pool" % definition["name"])
		check(GalaxyGates.for_map(definition["map"]) == gate_id and SectorMaps.SPECIAL_GATES[0][definition["map"]] == definition["portal"], "%s has its own arena and Outpost 01 portal" % definition["name"])
		check(Equipment.MODELS.has(definition["reward"]["item"]) and not Equipment.purchase_blocker(definition["reward"]["item"]).is_empty(), "%s rewards an item the shop does not sell" % definition["name"])
		for wave: Dictionary in definition["waves"]:
			for kind: String in wave:
				check(Alien.TYPES.has(kind) and CargoResources.LOOT.has(kind) and int(wave[kind]) <= int(definition["pool"][kind]), "%s wave aliens exist and fit the pool" % definition["name"])
		check(definition["waves"].back().has(definition["boss"]) and definition["pool"].has(definition["escort"]), "%s ends with its boss and escorts" % definition["name"])
		var final_wave: int = definition["waves"].size() - 1
		check(int(GalaxyGates.wave_counts(gate_id, final_wave, 10)[definition["escort"]]) <= int(definition["pool"][definition["escort"]]) - GalaxyGates.ESCORTS,
			"%s boss wave leaves dormant escorts at any group size" % definition["name"])
		check(float(Alien.TYPES[definition["boss"]]["range"]) < 310.0, "%s boss stays out-ranged by pilot lasers" % definition["name"])


func saved(server: Sector, client: Sector, gate_id: String = VASHAR) -> Dictionary:
	return GalaxyGates.state(server.session.store.pilots[server.session.pilot_ids[client.multiplayer.get_unique_id()]]["equipment"], gate_id)


func move_to(server: Sector, client: Sector, map: int) -> void:
	var id := client.multiplayer.get_unique_id()
	# Follow real gate connections; arenas connect only to Outpost 01.
	while server.session.ships[id].map_id != map:
		var current := server.session.ships[id].map_id
		var hop := 0
		if SectorMaps.GATES.get(current, {}).has(map) or (current == 0 and GalaxyGates.is_arena(map)):
			hop = map
		elif not GalaxyGates.is_arena(current) and not GalaxyGates.is_arena(map):
			hop = SectorMaps.first_hop(current, map)
		server.session.transfer(id, hop)
		await settle(0.08)


func request(server: Sector, client: Sector, action: String, gate_id: String = VASHAR) -> void:
	await move_to(server, client, 0)
	station(server, client)
	client.session.combat.request_station(action, gate_id)
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


func enter(server: Sector, client: Sector, arena: int = VMAP) -> String:
	var id := client.multiplayer.get_unique_id()
	await move_to(server, client, 0)
	var ship := server.session.ships[id]
	ship.position = SectorMaps.gate_position(0, arena)
	server.session.jump_until.erase(id)
	var reason := server.session.jump(id, server.session.combat.records[id]["life"], arena)
	# Leave the protected arrival zone so the pilot can fight.
	ship.position = SectorMaps.origin(arena) + Vector3(0, 0, 200)
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
	for alien: Alien in server.map_rosters[VMAP].values():
		check(not alien.alive, "Arena aliens are dormant before any run")

	# Signal Anomaly: guaranteed M2 parts, pickup without cargo space and the cache reward.
	await request(server, pilot, "gate_signal")
	check(saved(server, pilot)["signal"] == "active" and pilot.session.combat.inventory["gates"][VASHAR]["signal"] == "active", "Accepting the operation is saved and published")
	await request(server, pilot, "gate_signal")
	check(pilot.session.combat.station_message.contains("already active"), "An active operation cannot be accepted twice")
	var next := store.pilots.duplicate(true)
	next[pilot_id]["cargo"]["starter"] = {"prometium": CargoResources.capacity(next[pilot_id]["equipment"])}
	check(store.persist(next), "Fill the pilot's cargo hold")
	combat.cargo_holds[id] = next[pilot_id]["cargo"].duplicate(true)
	var credits: int = combat.records[id]["credits"]
	var drop: int = await kill_on_map(server, 1, [pilot])
	check(drop >= 0 and int(server.loot.drops[drop].get("parts", {}).get(VASHAR, 0)) >= 1, "An M2 kill during the operation carries a gate part")
	var carried := int(server.loot.drops[drop]["parts"][VASHAR])
	await pick_up(server, pilot, drop)
	check(saved(server, pilot)["parts"] == carried and saved(server, pilot)["progress"] == mini(carried, GalaxyGates.info(VASHAR)["signal"]["required"] - 1), "Gate parts are collected and saved with a full cargo hold")
	check(server.loot.drops.has(drop) and not server.loot.drops[drop].has("parts"), "Resources stay in the box when the hold is full")
	var partner_drop: int = await kill_on_map(server, 1, [partner])
	check(partner_drop < 0 or int(server.loot.drops[partner_drop].get("parts", {}).get(VASHAR, 0)) <= 1, "Pilots without the operation get only random parts")
	for attempt in range(GalaxyGates.info(VASHAR)["signal"]["required"]):
		if saved(server, pilot)["signal"] != "active":
			break
		var box: int = await kill_on_map(server, 1, [pilot])
		await pick_up(server, pilot, box)
	var after := saved(server, pilot)
	check(after["signal"] == "done" and after["parts"] >= GalaxyGates.info(VASHAR)["signal"]["required"] + GalaxyGates.info(VASHAR)["signal"]["parts"], "Completing the operation adds the cache parts")
	check(store.pilots[pilot_id]["credits"] >= credits + GalaxyGates.info(VASHAR)["signal"]["credits"], "The operation pays its credit reward")
	await request(server, pilot, "gate_assemble")
	check(saved(server, pilot)["parts"] == after["parts"] and not gate.active, "Assembly needs a full set of parts")

	# Assembly consumes parts and opens one shared run.
	next = store.pilots.duplicate(true)
	next[pilot_id]["equipment"]["gates"][VASHAR]["parts"] = GalaxyGates.info(VASHAR)["parts_required"] + 2
	check(store.persist(next), "Seed a full set of gate parts")
	await request(server, pilot, "gate_assemble")
	check(gate.active and SectorMaps.open_rift == VMAP and saved(server, pilot) == {"parts": 2, "signal": "available", "progress": 0}, "Assembly consumes parts, reopens the signal and opens the gate")
	await sync(server)
	check(pilot.session.combat.gate_summary.get("active", false) and partner.session.combat.gate_summary.get("open", false), "Every pilot learns the gate is open")
	check(pilot.hud.navigation.has_contact("gate%d" % VMAP), "The open gate is a navigation contact at Outpost 01")
	await request(server, partner, "gate_assemble")
	check(partner.session.combat.station_message.contains("already open"), "Only one run is open at a time")

	# Entry, lives and the first wave.
	var first: String = await enter(server, pilot)
	var second: String = await enter(server, partner)
	check(first.is_empty() and second.is_empty(), "Pilots fly through the open gate")
	check(server.session.ships[id].map_id == VMAP and gate.lives[pilot_id] == GalaxyGates.info(VASHAR)["lives"], "Entering joins the run with full lives")
	gate.tick(1.0)
	await settle(0.1)
	var countdown: float = pilot.hud.gate_countdown()
	check(countdown > 0.0 and countdown <= GalaxyGates.FIRST_WAVE_DELAY, "Entering shows the countdown to the first wave")
	check(pilot.hud.gate_status().contains("WAVE 1 IN"), "The status line names the next wave and its countdown")
	gate.tick(GalaxyGates.FIRST_WAVE_DELAY)
	var alive := gate.wave_aliens.filter(func(alien: Alien): return alien.alive).size()
	check(gate.phase == "fighting" and gate.wave == 0 and alive == GalaxyGates.wave_counts(VASHAR, 0, 2)["Shardling"], "The first wave scales to the pilots inside")
	await sync(server)
	check(pilot.map_id == VMAP and pilot.session.combat.gate_summary["wave"] == 1, "The pilot's client shows the arena and wave")
	check(pilot.hud.gate_status().begins_with("VASHAR GATE / WAVE 1 OF") and pilot.hud.gate_countdown() < 0.0, "The HUD reports the active wave once the countdown ends")
	# No safe zone in the rift: aliens pursue a pilot waiting at the exit, which stays sealed.
	var holder := server.session.ships[id]
	holder.position = SectorMaps.gate_position(VMAP, 0)
	server.session.ships[partner_id].position = holder.position + Vector3(8, 0, 0)
	check(not SectorMaps.protected(holder), "The rift exit has no protected zone")
	var hunter: Alien = gate.wave_aliens.filter(func(alien: Alien): return alien.alive)[0]
	check(combat.choose_target(hunter) in [holder, server.session.ships[partner_id]], "Wave aliens pursue pilots waiting at the rift exit")
	server.session.jump_until.erase(id)
	check(server.session.jump(id, combat.records[id]["life"], 0).contains("sealed") and holder.map_id == VMAP, "The rift exit is sealed while a wave is alive")
	holder.position = SectorMaps.origin(VMAP) + Vector3(0, 0, 200)
	var ship := server.session.ships[partner_id]
	ship.take_damage(ship.max_hull + ship.max_shield + 1.0, null)
	check(gate.lives[server.session.pilot_ids[partner_id]] == GalaxyGates.info(VASHAR)["lives"] - 1, "Dying in the arena costs one life")
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
		if probe.randf() < GalaxyGates.info(VASHAR)["reward"]["item_chance"] and probe.randf() >= GalaxyGates.info(VASHAR)["reward"]["item_chance"]:
			break
		seed += 1
	var research := int(Research.state(store.pilots[pilot_id]["equipment"])["points"])
	for wave in range(GalaxyGates.info(VASHAR)["waves"].size()):
		if wave > 0:
			gate.tick(GalaxyGates.WAVE_DELAY + 0.1)
		check(gate.phase == "fighting" and gate.wave == wave, "Wave %d starts" % (wave + 1))
		if wave == GalaxyGates.info(VASHAR)["waves"].size() - 1:
			var boss := gate.wave_aliens.filter(func(alien: Alien): return alien.kind == "Mothership")
			check(boss.size() == 1 and boss[0].alive, "The final wave brings the mothership")
			var before := gate.wave_aliens.filter(func(alien: Alien): return alien.alive).size()
			gate.tick(GalaxyGates.ESCORT_INTERVAL + 0.1)
			gate.rng.seed = seed
			check(gate.wave_aliens.filter(func(alien: Alien): return alien.alive).size() > before, "The mothership launches escorts")
		clear_wave(server, pilot)
		gate.tick(0.1)
	check(gate.phase == "victory" and SectorMaps.open_rift != VMAP, "Destroying the last wave wins and closes the entrance")
	check(store.pilots[pilot_id]["credits"] >= pilot_credits + GalaxyGates.info(VASHAR)["reward"]["credits"]
		and int(Research.state(store.pilots[pilot_id]["equipment"])["points"]) == research + GalaxyGates.info(VASHAR)["reward"]["research"], "Victory pays participants credits and research")
	for winner: String in x4:
		check(int(store.pilots[winner]["ammo"]["x4"]) == x4[winner] + GalaxyGates.info(VASHAR)["reward"]["x4"], "Victory adds 15,000 x4 shots to each participant")
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
	for alien: Alien in server.map_rosters[VMAP].values():
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
	check(retreating.is_empty() and gate.phase == "fighting" and gate.lives[partner_pilot_id] == GalaxyGates.info(VASHAR)["lives"], "A pilot joins the preview wave")
	partner.session.quit_to_menu()
	await settle(0.15)
	check(server.session.ships[partner_id].get_meta("docked", false) and gate.lives[partner_pilot_id] == GalaxyGates.info(VASHAR)["lives"] - 1, "Quitting to the station mid-wave costs a life")
	gate.tick(GalaxyGates.ABANDON_TIME + 0.1)
	check(not gate.active and SectorMaps.open_rift != VMAP, "A gate nobody holds collapses")
	await run_gate(server, pilot, KORRATH)
	await run_gate(server, pilot, SYLITH)
	finish()


# Further gates: their own operation map, portal, arena, boss and rewards.
func run_gate(server: Sector, pilot: Sector, gate_id: String) -> void:
	var store := server.session.store
	var combat := server.session.combat
	var gate := combat.gate
	var id := pilot.multiplayer.get_unique_id()
	var pilot_id: String = server.session.pilot_ids[id]
	var definition := GalaxyGates.info(gate_id)
	var arena: int = definition["map"]
	var label: String = definition["name"]
	var operation_map: int = definition["signal"]["map"]
	await request(server, pilot, "gate_signal", gate_id)
	check(saved(server, pilot, gate_id)["signal"] == "active" and saved(server, pilot)["signal"] == "available", "%s operation is tracked separately from the Vashar one" % label)
	var drop: int = await kill_on_map(server, operation_map, [pilot])
	check(drop >= 0 and int(server.loot.drops[drop].get("parts", {}).get(gate_id, 0)) >= 1, "%s kills during the %s operation carry its parts" % [SectorMaps.code(operation_map), label])
	await pick_up(server, pilot, drop)
	check(saved(server, pilot, gate_id)["parts"] >= 1 and saved(server, pilot, gate_id)["progress"] >= 1, "%s parts are saved under their own gate" % label)
	await request(server, pilot, "gate_preview", gate_id)
	check(gate.active and gate.gate == gate_id and SectorMaps.open_rift == arena, "A preview pilot opens the %s" % label)
	var others := GalaxyGates.ORDER.filter(func(other: String): return other != gate_id and SectorMaps.links(0).has(int(GalaxyGates.info(other)["map"])))
	check(SectorMaps.links(0).has(arena) and others.is_empty(), "Only the open gate's portal is usable at Outpost 01")
	await sync(server)
	check(pilot.hud.navigation.has_contact("gate%d" % arena) and pilot.session.combat.gate_summary["gate"] == gate_id, "Clients see the open %s" % label)
	var blocked := server.session.jump(id, combat.records[id]["life"], VMAP)
	check(not blocked.is_empty(), "A closed gate cannot be entered while another is open")
	var entered: String = await enter(server, pilot, arena)
	check(entered.is_empty() and server.session.ships[id].map_id == arena, "Pilots fly into the %s" % definition["arena"])
	await settle(0.1)
	check(pilot.hud.gate_status().begins_with("%s / WAVE 1 IN" % label.to_upper()), "The HUD names the %s and its countdown" % label)
	var credits: int = store.pilots[pilot_id]["credits"]
	var item: String = definition["reward"]["item"]
	var items := func() -> int: return store.pilots[pilot_id]["equipment"]["items"].values().filter(func(entry: Dictionary): return entry["model"] == item).size()
	var items_before: int = items.call()
	gate.tick(GalaxyGates.FIRST_WAVE_DELAY + 0.1)
	var first_kind: String = definition["waves"][0].keys()[0]
	check(gate.wave_aliens.size() == GalaxyGates.wave_counts(gate_id, 0, 1)[first_kind] and gate.wave_aliens.all(func(alien: Alien): return alien.kind == first_kind and alien.map_id == arena),
		"The first %s wave sends %ss into the arena" % [definition["faction"], first_kind])
	var seed := 0
	while true:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		if probe.randf() < definition["reward"]["item_chance"]:
			break
		seed += 1
	for wave in range(definition["waves"].size()):
		if wave > 0:
			gate.tick(GalaxyGates.WAVE_DELAY + 0.1)
		if wave == definition["waves"].size() - 1:
			check(gate.wave_aliens.any(func(alien: Alien): return alien.kind == definition["boss"] and alien.alive), "The final wave brings the %s" % definition["boss"])
			var before := gate.wave_aliens.filter(func(alien: Alien): return alien.alive).size()
			gate.tick(GalaxyGates.ESCORT_INTERVAL + 0.1)
			check(gate.wave_aliens.filter(func(alien: Alien): return alien.alive).size() > before, "The %s launches %s escorts" % [definition["boss"], definition["escort"]])
			gate.rng.seed = seed
		clear_wave(server, pilot)
		gate.tick(0.1)
	check(gate.phase == "victory" and store.pilots[pilot_id]["credits"] >= credits + int(definition["reward"]["credits"]), "Destroying the %s pays the %s reward" % [definition["boss"], label])
	check(items.call() == items_before + 1, "A won roll places an %s in storage" % GalaxyGates.item_name(gate_id))
	gate.tick(GalaxyGates.VICTORY_TIME + 0.1)
	await settle(0.1)
	check(not gate.active and server.session.ships[id].map_id == 0, "The %s closes and returns pilots home" % definition["arena"])
