extends "res://tests/hunting_contracts_test.gd"
## Skill tree rules, contract research rewards and authoritative research transactions.


func run_rules() -> void:
	var research := Research.empty()
	check(Research.valid(research), "An empty tree is valid")
	check(not Research.valid({"points": 0, "skills": {"shield_capacitors": 1}, "resets": 0}), "Saves cannot skip a row prerequisite")
	var full := {"points": 0, "skills": {}, "resets": 0}
	for row: String in ["defense", "economy"]:
		for id: String in Research.ROWS[row]:
			full["skills"][id] = Research.MAX_LEVEL
	check(not Research.valid(full), "Saves cannot exceed the research level cap")
	var stock := {"prometid": 50, "duranium": 49}
	research["points"] = 1
	check(Research.learn_blocker(research, "reinforced_plating", stock).begins_with("Need"), "Missing Skylab stock blocks research")
	check(Research.learn_blocker(research, "shield_capacitors", {}) == "Complete Reinforced Plating first.", "Later skills require the previous skill")
	var equipment := Equipment.starter()
	var base := Equipment.stats(equipment)
	var capacity := CargoResources.capacity(equipment)
	equipment["research"] = {"points": 6, "skills": {}, "resets": 0}
	stock = {"prometid": 1000, "duranium": 1000, "promerium": 1000, "seprom": 100}
	for level in range(Research.MAX_LEVEL):
		check(Research.learn(equipment, stock, "reinforced_plating").is_empty(), "Reinforced Plating level %d is researched" % (level + 1))
	check(stock == {"prometid": 850, "duranium": 850, "promerium": 835, "seprom": 93}, "Each level consumes its configured lab stock")
	check(Research.learn(equipment, stock, "shield_capacitors").is_empty() and Research.state(equipment)["points"] == 0, "Completing a skill unlocks the next and spends points")
	check(Research.learn(equipment, stock, "shield_capacitors").begins_with("Need 1 research point"), "Research requires points")
	var stats := Equipment.stats(equipment)
	check(stats["hull"] == base["hull"] + 50000.0 and is_equal_approx(stats["shield"], base["shield"] * 1.04), "Hull and shield skills change fitting stats")
	check(Equipment.valid(equipment), "Researched equipment remains valid")
	equipment["research"]["skills"] = {"cargo_compression": 5}
	check(CargoResources.capacity(equipment) == int(capacity * 1.25), "Cargo Compression expands cargo capacity")
	equipment["research"]["skills"] = {"xeno_targeting": 5}
	stats = Equipment.stats(equipment)
	check(is_equal_approx(stats["npc_damage"], base["npc_damage"] + base["damage"] * 0.12) and is_equal_approx(stats["lasers"][0]["npc_damage"], base["lasers"][0]["npc_damage"] + base["lasers"][0]["damage"] * 0.12), "Xeno Targeting adds laser damage only against aliens")
	equipment["research"] = {"points": 0, "skills": {"reinforced_plating": 5, "shield_capacitors": 2}, "resets": 0}
	check(Research.reset_price(Research.state(equipment)) == Research.RESET_BASE_CREDITS, "The first reset uses the base price")
	Research.reset(equipment)
	check(Research.state(equipment) == {"points": 7, "skills": {}, "resets": 1} and Research.reset_price(Research.state(equipment)) == Research.RESET_BASE_CREDITS * 2, "Reset refunds points and doubles the next price")
	var prices_match := true
	for resets in range(65):
		var expected: int = PilotStore.MAX_CREDITS if resets >= 15 else Research.RESET_BASE_CREDITS << resets
		prices_match = prices_match and Research.reset_price({"points": 0, "skills": {}, "resets": resets}) == expected
	check(prices_match, "Reset prices double, then saturate at the wallet cap from reset 15 through 64")
	check(Research.reset_price({"points": 0, "skills": {}, "resets": 14}) == 1_638_400_000, "The last uncapped reset costs 1,638,400,000 credits")
	check(PilotStore.valid_credits(0) and PilotStore.valid_credits(PilotStore.MAX_CREDITS) and not PilotStore.valid_credits(-1) and not PilotStore.valid_credits(PilotStore.MAX_CREDITS + 1) and not PilotStore.valid_credits(1.0), "The wallet guard accepts only whole credits within the cap")
	var legacy := {"type": "heavy", "required": 1, "reward": 30000, "progress": 1, "run": "a".repeat(64)}
	check(HuntingContracts.valid(legacy), "Contracts accepted before research remain valid")
	var payout := HuntingContracts.settle({"heavy": legacy, "scout": HuntingContracts.accept("scout")}, 0)
	check(payout["research"] == 4 and payout["reward"] == 30000 and payout["contracts"].has("scout"), "Completed runs pay their offer's research points")
	var hold := {}
	check(CargoResources.collect_bonus(hold, {"prometium": 50}, 0.2, 400) == {"prometium": 10} and CargoResources.collect_bonus({"prometium": 400}, {"prometium": 50}, 0.2, 400).is_empty(), "Salvage Drones adds whole bonus units within free cargo")


# Saturated resets must charge the cap and leave a ledger that reopens.
func run_reset_ledger(template: Dictionary, directory: String) -> void:
	DirAccess.make_dir_absolute(directory)
	var path := directory.path_join("pilots.json")
	for resets: int in [14, 15, 47, 48, 63, 64]:
		var price: int = PilotStore.MAX_CREDITS if resets >= 15 else Research.RESET_BASE_CREDITS << resets
		for credits: int in [price - 1, price, PilotStore.MAX_CREDITS]:
			var pilots := template.duplicate(true)
			pilots["pilot0"]["credits"] = credits
			pilots["pilot0"]["equipment"]["research"] = {"points": 0, "skills": {"reinforced_plating": 1}, "resets": resets}
			for suffix in [".bak", ".combat"]:
				DirAccess.remove_absolute(path + suffix)
			# A future simulation time makes lab advances no-ops, so a rejected
			# reset can be compared byte for byte even across a clock second.
			pilots["pilot0"]["skylab"]["lastSimulatedAt"] = Skylab.now() + 3600
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(JSON.stringify({"version": 7, "pilots": pilots}))
			file.close()
			var store := PilotStore.new()
			if not store.open(directory):
				check(false, "Reset ledger with %d resets opens: %s" % [resets, store.error])
				return
			var saved := FileAccess.get_file_as_string(path)
			var result := store.transact("pilot0", int(store.pilots["pilot0"]["equipment"]["revision"]) + 1, "research_reset", "", "", "")
			var research := Research.state(store.pilots["pilot0"]["equipment"])
			if credits < price:
				check(result == "Insufficient credits. Need %d CR." % price and store.pilots["pilot0"]["credits"] == credits and research["resets"] == resets and FileAccess.get_file_as_string(path) == saved, "Reset %d without %d CR keeps the balance and files" % [resets, price])
			else:
				check(result.begins_with("Skill tree reset.") and store.pilots["pilot0"]["credits"] == credits - price and research["resets"] == mini(64, resets + 1), "Reset %d charges %d CR" % [resets, price])
			check(store.close(), "Reset ledger with %d resets closes" % resets)
			var reopened := PilotStore.new()
			check(reopened.open(directory) and reopened.pilots["pilot0"]["credits"] == store.pilots["pilot0"]["credits"], "Ledger reopens after reset %d with %d CR: %s" % [resets, credits, reopened.error])
			reopened.close()


func run() -> void:
	run_rules()
	var server := make_sector("ResearchServer", true, CONTRACT_PORT)
	run_reset_ledger(server.session.store.pilots, server.session.store.path.get_base_dir().path_join("reset-cases"))
	var pilot := make_sector("ResearchPilot")
	await connect_pilot(pilot, 0)
	if server.session.ships.size() != 1:
		check(false, "Research pilot authenticates")
		finish()
		return
	var id := pilot.multiplayer.get_unique_id()
	var pilot_id: String = server.session.pilot_ids[id]
	var store := server.session.store
	var remote := server.session.ships[id]
	station(server, pilot)
	await action(server, pilot, "accept", "heavy")
	await kill(server, "Heavy", [pilot])
	await settle()
	check(Research.state(store.pilots[pilot_id]["equipment"])["points"] == 4, "A Heavy contract saves four research points")
	check(Research.state(pilot.session.combat.inventory)["points"] == 4, "The owner receives the research point balance")
	var base_hull := remote.max_hull
	# Pause refineries so exact stock checks cannot cross a production tick.
	for module: String in Skylab.RECIPES:
		store.pilots[pilot_id]["skylab"]["modules"][module]["enabled"] = false
	var lab: Dictionary = store.pilots[pilot_id]["skylab"]["inventory"]
	for resource: String in ["prometid", "duranium", "promerium"]:
		lab[resource] = 100
	station(server, pilot)
	pilot.session.combat.request_station("research", "shield_capacitors")
	await settle()
	check(pilot.session.combat.station_message == "Complete Reinforced Plating first." and Research.spent(Research.state(store.pilots[pilot_id]["equipment"])) == 0, "The server enforces row prerequisites")
	pilot.session.combat.request_station("research", "reinforced_plating")
	await settle()
	await replicate(server)
	var saved: Dictionary = store.pilots[pilot_id]
	check(Research.level(Research.state(saved["equipment"]), "reinforced_plating") == 1 and Research.state(saved["equipment"])["points"] == 3, "Research spends one point")
	check(saved["skylab"]["inventory"]["prometid"] == 50 and saved["skylab"]["inventory"]["duranium"] == 50, "Research consumes Skylab stock")
	check(remote.max_hull == base_hull + 5000.0, "Researched hull applies to the flying ship")
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	check(file["pilots"][pilot_id]["equipment"]["research"]["skills"] == {"reinforced_plating": 1.0}, "Research is written to the pilot ledger")
	remote.position = Vector3(0, 0, 400)
	pilot.session.combat.request_station("research", "reinforced_plating")
	await settle()
	check(Research.level(Research.state(store.pilots[pilot_id]["equipment"]), "reinforced_plating") == 1, "Research follows station service rules")
	station(server, pilot)
	pilot.session.combat.request_station("research_reset", "")
	await settle()
	check(Research.level(Research.state(store.pilots[pilot_id]["equipment"]), "reinforced_plating") == 1 and pilot.session.combat.station_message.begins_with("Insufficient credits"), "Reset requires its credit price")
	store.pilots[pilot_id]["credits"] = Research.RESET_BASE_CREDITS
	pilot.session.combat.request_station("research_reset", "")
	await settle()
	await replicate(server)
	saved = store.pilots[pilot_id]
	check(Research.state(saved["equipment"]) == {"points": 4, "skills": {}, "resets": 1} and saved["credits"] == 0, "Reset refunds points for credits")
	check(remote.max_hull == base_hull, "Reset removes researched stats")
	pilot.main_menu.select_page("research")
	await process_frame
	await process_frame
	check(pilot.research_menu.visible and pilot.research_menu.summary.text.begins_with("4 RESEARCH POINTS"), "Research page shows the synchronized balance")
	finish()
