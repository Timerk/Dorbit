extends "res://tests/hunting_contracts_test.gd"
## Prologue rules, every objective type through authenticated play, skipping and persistence.


func run_rules() -> void:
	var story := Story.empty()
	check(Story.valid(story) and Story.STEPS.size() == 10, "An empty chapter is valid and the prologue has ten steps")
	for invalid: Variant in [null, {"step": 0}, {"step": 11, "progress": 0}, {"step": 3, "progress": 2}, {"step": 0, "progress": -1}, {"step": 10, "progress": 1}, {"step": 0, "progress": 0, "extra": 1}]:
		check(not Story.valid(invalid), "Malformed story state is rejected: %s" % JSON.stringify(invalid))
	check(Story.valid({"step": 3, "progress": 1}) and Story.valid({"step": 10, "progress": 0}), "Partial kills and the complete chapter are valid")
	check(Story.current({}).is_empty() and Story.site({}, 0).is_empty(), "No inventory means no story step")
	check(Story.advance(story, "kill", 1, "Scout").is_empty(), "Events for another step type do not count")
	var kills := {"step": 3, "progress": 0}
	check(Story.advance(kills, "kill", 1, "Sentinel").is_empty(), "Kill steps require their alien kind")
	var partial := Story.advance(kills, "kill", 1, "Scout")
	check(partial["story"] == {"step": 3, "progress": 1} and partial["credits"] == 0 and partial["finished"].is_empty(), "A partial kill saves progress without a reward")
	var done := Story.advance(partial["story"], "kill", 1, "Scout")
	check(done["story"] == {"step": 4, "progress": 0} and done["credits"] == 1200 and done["finished"]["id"] == "first_contact", "The final kill pays once and moves to the next step")
	check(Story.advance({"step": 6, "progress": 8}, "collect", 50)["story"] == {"step": 7, "progress": 0}, "Large pickups complete collection without overflowing progress")
	var total_credits := 0
	var total_research := 0
	for step: Dictionary in Story.STEPS:
		total_credits += step["credits"]
		total_research += step["research"]
		check(not Story.hint(step).contains("{") and not Story.hint(step).contains("}"), "%s hint names bound keys" % step["title"])
		check(Story.CONTACTS.has(step["contact"]), "%s has a known contact" % step["title"])
	var skipped := Story.skip(story)
	check(skipped["story"] == {"step": 10, "progress": 0} and skipped["credits"] == total_credits and skipped["research"] == total_research, "Skipping pays every remaining step reward")
	check(Story.skip({"step": 9, "progress": 0})["credits"] == 5000, "Skipping late pays only the remaining steps")
	check(Story.objective({"step": 2, "progress": 0}, 2.6) == "Hold position inside the scan field  2 / 5 s", "Scan objectives show elapsed seconds")
	check(Story.completion_notice(Story.STEPS[9], {"step": 10, "progress": 0}).ends_with("Operation Foothold complete."), "The last step closes the chapter")
	var equipment := Equipment.starter()
	equipment["story"] = {"step": 4, "progress": 0}
	check(Equipment.valid(equipment), "Saved story progress keeps equipment valid")
	equipment["story"] = {"step": 4, "progress": 5}
	check(not Equipment.valid(equipment), "Equipment with impossible story progress is rejected")


func capture(client: Sector, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/validation")
	check(client.get_viewport().get_texture().get_image().save_png("res://build/validation/" + label + ".png") == OK, "Save rendered " + label)


func press(client: Sector, input: String) -> void:
	var event := InputEventAction.new()
	event.action = input
	event.pressed = true
	client.get_viewport().push_input(event)


func site_clear(server: Sector, location: Vector3) -> bool:
	if location.distance_to(SectorMaps.origin(0)) > Sector.MAP_RADIUS - 100.0:
		return false
	for collider: CollisionShape3D in server.find_children("*", "CollisionShape3D", true, false):
		if collider.get_parent() is StaticBody3D and collider.shape is SphereShape3D and location.distance_to(collider.global_position) < collider.shape.radius + 10.0:
			return false
	return location.distance_to(Sector.STATION_POSITION) > Sector.REPAIR_RADIUS


func reach(server: Sector, client: Sector, seconds: float = 0.02) -> void:
	var ship := server.session.ships[client.multiplayer.get_unique_id()]
	var step := Story.current(Story.state(server.session.store.pilots[server.session.pilot_ids[client.multiplayer.get_unique_id()]]["equipment"]))
	ship.position = Story.site_position(step)
	ship.velocity = Vector3.ZERO
	server.session.combat.tick(seconds)
	await settle(0.08)
	await replicate(server)


func saved(server: Sector, client: Sector) -> Dictionary:
	return Story.state(server.session.store.pilots[server.session.pilot_ids[client.multiplayer.get_unique_id()]]["equipment"])


func run() -> void:
	run_rules()
	var server := make_sector("StoryServer", true, CONTRACT_PORT)
	for step: Dictionary in Story.STEPS:
		if step["type"] in Story.POSITIONAL:
			check(site_clear(server, Story.site_position(step)), "%s site is inside safe space and clear of obstacles" % step["title"])
	var pilot := make_sector("StoryPilot")
	var partner := make_sector("StoryPartner")
	for client: Sector in [pilot, partner]:
		client.get_viewport().size = Vector2i(1440, 900)
		client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await connect_pilot(pilot, 0)
	await connect_pilot(partner, 1)
	if server.session.ships.size() != 2:
		check(false, "Story pilots authenticate")
		finish()
		return
	var store := server.session.store
	var id := pilot.multiplayer.get_unique_id()
	var pilot_id: String = server.session.pilot_ids[id]
	var combat := server.session.combat
	await settle(0.1)
	check(pilot.story_state() == Story.empty(), "New and existing pilots start the prologue")
	check(pilot.story_sites.comm.begins_with("VANCE: Pilot, this is Commander Vance"), "Joining shows the current briefing as a transmission")
	check(pilot.story_sites.comm_lines.size() == 1 and pilot.story_sites.comm_lines[0][0] == "vance", "The briefing transmission is attributed to its contact")
	for contact: String in Story.CONTACTS:
		var picture := StorySites.portrait(contact)
		check(picture != null and maxi(picture.get_width(), picture.get_height()) <= 512, "%s has a portrait within the UI budget" % contact)
	await process_frame
	check(pilot.story_sites.site.visible and pilot.hud.story_height() > 0.0, "The first site and flight card section are shown")
	await capture(pilot, "story-comms-check")
	for step: Dictionary in Story.STEPS:
		var rows: Array = Story.CONTROLS.get(step["id"], [])
		check(rows.size() >= 2 and rows.size() <= 3, "%s teaches two or three controls" % step["title"])
		for row: Array in rows:
			for input: String in row[0]:
				check(InputMap.has_action(input), "%s control %s is a bound input action" % [step["title"], input])
	var sites := pilot.story_sites
	check(sites.tips == Story.CONTROLS["comms_check"] and not sites.tips_used.has(true), "The first step opens its controls pop-up")
	press(pilot, "backward")
	await process_frame
	check(sites.tips_used == [false, true, false], "Pressing a taught control ticks its row")
	for input: String in ["steer", "strafe_right"]:
		press(pilot, input)
	await process_frame
	check(not sites.tips.is_empty() and not sites.tips_used.has(false), "The pop-up lingers once every control is tried")
	await settle(StorySites.TIPS_LINGER + 0.2)
	check(sites.tips.is_empty(), "The pop-up closes after its controls are tried")
	var credits: int = store.pilots[pilot_id]["credits"]
	await reach(server, pilot)
	check(saved(server, pilot)["step"] == 1 and store.pilots[pilot_id]["credits"] == credits + 300, "Reaching the rendezvous saves the step and its reward")
	await process_frame
	check(pilot.story_state()["step"] == 1 and pilot.story_sites.comm.begins_with("VANCE: Clean flying."), "The owner receives progress and the contact's closing line")
	check(sites.tips == Story.CONTROLS["survey_run"], "The next step opens its own controls pop-up")
	check(sites.comm_lines.size() == 1 and sites.comm_lines[0][0] == "vance" and sites.comm_lines[0][1].ends_with(Story.STEPS[1]["briefing"]), "One speaker's closing line and next briefing share a portrait")
	var handover := Story.completion_lines(Story.STEPS[1], {"step": 2, "progress": 0})
	check(handover.size() == 2 and handover[0][0] == "vance" and handover[1] == ["sato", Story.STEPS[2]["briefing"]], "A new speaker gets their own portrait line")
	await capture(pilot, "story-controls")
	for pixels in [Vector2i(960, 600), Vector2i(1440, 900)]:
		pilot.get_viewport().size = pixels
		await process_frame
		var hud := pilot.hud
		var tips := hud.tutorial_rect()
		var clear := [hud.objectives_rect(), hud.navigation.radar_rect(), hud.navigation.guidance_rect(), hud.layout.default_rect("reticle")].all(func(card: Rect2) -> bool: return not card.intersects(tips))
		check(clear and Rect2(Vector2.ZERO, hud.size).encloses(tips), "The controls pop-up stays clear of flight cards at %d" % pixels.x)
	check(pilot.credits == credits + 300, "The owner's wallet includes the step reward")
	await reach(server, pilot)
	check(saved(server, pilot)["step"] == 2, "The survey run completes at its waypoint")
	await reach(server, pilot, 3.0)
	check(saved(server, pilot)["step"] == 2, "A partial scan does not complete the step")
	await capture(pilot, "story-ring-scan")
	check(pilot.hud.navigation.has_contact("story_ring_scan") and not pilot.hud.navigation.has_contact("story_survey_run"), "The current site replaces the previous map contact")
	server.session.ships[id].position = Story.site_position(Story.STEPS[2]) + Vector3(0, 0, 60)
	combat.tick(0.02)
	await reach(server, pilot, 3.0)
	check(saved(server, pilot)["step"] == 2, "Leaving the scan field restarts the scan")
	await reach(server, pilot, 2.1)
	check(saved(server, pilot)["step"] == 3, "Five seconds inside the field completes the scan")
	await kill(server, "Sentinel", [pilot])
	check(saved(server, pilot) == {"step": 3, "progress": 0}, "Kills of another kind do not count")
	await kill(server, "Scout", [pilot, partner])
	check(saved(server, pilot) == {"step": 3, "progress": 1} and saved(server, partner) == Story.empty(), "Contributors progress only steps that ask for the kill")
	await kill(server, "Scout", [pilot])
	await kill(server, "Sentinel", [pilot])
	check(saved(server, pilot)["step"] == 5, "Scout and Sentinel kills complete the combat steps")
	var research: int = Research.state(store.pilots[pilot_id]["equipment"])["points"]
	await reach(server, pilot)
	check(saved(server, pilot)["step"] == 6 and Research.state(store.pilots[pilot_id]["equipment"])["points"] == research + 1, "Recovering the recorder awards a research point")
	await kill(server, "Sentinel", [pilot])
	server.session.ships[id].position = server.loot.drops.values()[-1]["position"]
	combat.collect_loot()
	await settle(0.08)
	await replicate(server)
	check(saved(server, pilot)["step"] == 7, "Fresh loot pickups complete field salvage")
	var hold: Dictionary = store.pilots[pilot_id]["cargo"][store.pilots[pilot_id]["equipment"]["active_ship"]]
	var prometium := int(hold.get("prometium", 0))
	check(prometium >= 5, "Salvage provides Prometium for delivery")
	server.session.ships[id].position = Vector3(0, 0, 400)
	pilot.session.combat.request_station("story_deliver", "")
	await settle(0.1)
	check(saved(server, pilot)["step"] == 7, "Delivery follows station service rules")
	station(server, pilot)
	credits = store.pilots[pilot_id]["credits"]
	pilot.session.combat.request_station("story_deliver", "")
	await settle(0.1)
	await replicate(server)
	hold = store.pilots[pilot_id]["cargo"][store.pilots[pilot_id]["equipment"]["active_ship"]]
	check(saved(server, pilot)["step"] == 8 and int(hold.get("prometium", 0)) == prometium - 5 and store.pilots[pilot_id]["credits"] == credits + 2000, "Delivery consumes cargo and pays in one transaction")
	pilot.session.combat.request_station("story_deliver", "")
	await settle(0.1)
	check(saved(server, pilot)["step"] == 8 and pilot.session.combat.station_message == "Nothing to deliver for this step.", "Repeated delivery cannot pay twice")
	await reach(server, pilot, 6.1)
	check(saved(server, pilot)["step"] == 9, "Holding at the beacon lights it")
	await process_frame
	check(pilot.story_sites.beacon_lit, "The owner's beacon is lit after installation")
	station(server, pilot)
	research = Research.state(store.pilots[pilot_id]["equipment"])["points"]
	await action(server, pilot, "accept", "scout")
	combat.tick(0.02)
	await settle(0.08)
	await replicate(server)
	check(Story.complete(saved(server, pilot)) and Research.state(store.pilots[pilot_id]["equipment"])["points"] == research + 3, "Accepting a hunt completes the prologue with its research reward")
	await process_frame
	check(pilot.hud.story_height() == 0.0 and not pilot.story_sites.site.visible and not pilot.hud.navigation.contacts().any(func(contact: Dictionary) -> bool: return str(contact["key"]).begins_with("story_")), "A finished chapter leaves the flight card, map and space clear")
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	check(int(file["pilots"][pilot_id]["equipment"]["story"]["step"]) == 10, "Story progress is written to the pilot ledger")
	# The partner skips at the board after arming the confirmation.
	var partner_id: String = server.session.pilot_ids[partner.multiplayer.get_unique_id()]
	station(server, partner)
	await replicate(server)
	partner.hud.toggle_contracts()
	partner.hud.show_story()
	check(partner.hud.story_choices[0].visible and partner.hud.story_choices[1].disabled and partner.hud.story_skip.visible, "The Story tab lists current and locked steps")
	check(partner.hud.story_portrait.texture == StorySites.portrait("vance") and partner.hud.story_speaker.visible, "The Story tab shows the briefing contact's portrait")
	await process_frame
	await capture(partner, "story-board")
	partner.session.combat.request_station("story_deliver", "")
	await settle(0.1)
	check(partner.session.combat.station_message == "Nothing to deliver for this step.", "Delivery is limited to delivery steps")
	credits = store.pilots[partner_id]["credits"]
	research = Research.state(store.pilots[partner_id]["equipment"])["points"]
	partner.hud.act_on_story("story_skip")
	await settle(0.1)
	check(saved(server, partner) == Story.empty() and partner.hud.story_skip.text.begins_with("CONFIRM"), "The first skip press only asks for confirmation")
	partner.hud.act_on_story("story_skip")
	await settle(0.1)
	await replicate(server)
	check(Story.complete(saved(server, partner)) and store.pilots[partner_id]["credits"] == credits + 17300 and Research.state(store.pilots[partner_id]["equipment"])["points"] == research + 4, "Skipping completes the chapter and pays the remaining rewards")
	partner.session.combat.request_station("story_skip", "")
	await settle(0.1)
	check(store.pilots[partner_id]["credits"] == credits + 17300 and partner.session.combat.station_message == "Prologue already complete.", "A completed chapter cannot be skipped again")
	server.session.disconnect_session("Restart")
	await settle(0.3)
	check(server.session.host(test_port(CONTRACT_PORT)) == OK, "Server reopens the ledger")
	await connect_pilot(pilot, 0)
	await settle(0.1)
	check(Story.complete(pilot.story_state()), "Restart restores the completed chapter")
	server.session.disconnect_session("Schema validation")
	await settle(0.2)
	var ledger: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	ledger["pilots"]["pilot0"]["equipment"]["story"] = {"step": 11, "progress": 0}
	write_ledger(store.path, ledger)
	var original := FileAccess.get_file_as_string(store.path)
	var reopened := PilotStore.new()
	check(not reopened.open(store.path.get_base_dir()) and FileAccess.get_file_as_string(store.path) == original, "Malformed story progress fails closed without changing saves")
	reopened.close()
	finish()
