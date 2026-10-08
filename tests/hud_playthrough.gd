extends "res://tests/map_layout_playthrough.gd"
## Real viewport layout/input checks and deterministic presentation-state captures.


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	sector.settings.configure_input()
	sector.show_performance = false
	sector.toast_time = 0
	await sync_physics()
	var player := sector.player
	var hud := sector.hud
	var navigation := hud.navigation
	player.position = Vector3(500, 350, 600)
	player.rotation = Vector3(0.1, 0.5, 0)
	sector.aliens[1].position = Vector3(600, 440, 320)
	sector.select_target(sector.aliens[1])
	# Presentation fixture only: networking/payouts are covered by the existing
	# dedicated-server and hunting-contract suites. Freeze simulation throughout.
	sector.session.active = true
	for kind: String in HuntingContracts.OFFERS:
		sector.active_contracts[kind] = HuntingContracts.accept(kind)
	sector.active_contracts["scout"]["progress"] = 1
	sector.autopilot.enabled = true
	for pixels in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		root.size = pixels
		root.content_scale_size = pixels
		DisplayServer.window_set_size(pixels)
		await capture("hud-flight-%d" % pixels.x)
		var viewport := Rect2(Vector2.ZERO, Vector2(pixels))
		var cards: Array[Rect2] = [hud.objectives_rect(), navigation.radar_rect(), hud.ship_rect(), navigation.guidance_rect(), hud.target_rect()]
		for card: Rect2 in cards:
			check(viewport.encloses(card), "Flight cards stay inside the %d viewport" % pixels.x)
		for first in range(cards.size()):
			for second in range(first + 1, cards.size()):
				check(not cards[first].intersects(cards[second]), "Flight cards do not overlap at %d" % pixels.x)
		check(hud.objectives_rect().position.y == navigation.radar_rect().position.y and navigation.radar_rect().position.y <= 24, "Contracts and radar share a small top margin")
		check(is_equal_approx(hud.ship_rect().end.y, navigation.guidance_rect().end.y) and is_equal_approx(hud.target_rect().end.y, navigation.guidance_rect().end.y), "Ship, guidance and target cards share their bottom edge")
		check(navigation.autopilot_status.visible and navigation.autopilot_status.position.y >= navigation.radar_rect().end.y, "Active autopilot label sits below radar")
		if DisplayServer.get_name() != "headless":
			for caption in hud.marker_labels.slice(5):
				for card: Rect2 in cards:
					check(not caption.intersects(card), "World captions avoid every HUD card after displacement")
		for button in [navigation.range_less, navigation.range_more, navigation.map_button]:
			check(navigation.radar_rect().encloses(button.get_rect()), "Radar click targets remain inside their card")
		for button in [navigation.range_less, navigation.range_more]:
			check(button.size == Vector2(26, 26), "Radar range buttons retain their compact size")
			check(button.get_rect().end.y <= navigation.radar_rect().position.y + 34, "Radar range buttons leave a gap above the header divider")
		await click_at(navigation.range_more.get_global_rect().get_center())
		check(navigation.range_index == 2, "Native radar button changes range after repositioning")
		await click_at(navigation.range_less.get_global_rect().get_center())
		check(navigation.range_index == 1, "Native radar button restores range")
		await click_at(navigation.map_button.get_global_rect().get_center())
		check(navigation.overview.visible and not sector.auto_fire and not sector.autopilot.enabled, "Map button still opens overview and releases fire/autopilot")
		navigation.close_overview()
		sector.autopilot.enabled = true
		await sync_physics()
		sector.auto_fire = false
		check(hud.fire_feedback().contains(GameSettings.binding_text("fire")), "Fire hint uses current binding")
		for reason in ["OUT OF RANGE", "TURN TOWARD TARGET", "LINE OF SIGHT BLOCKED"]:
			sector.auto_fire = true
			sector.weapon_status = reason
			check(hud.fire_feedback() == ("OUTSIDE FIRING ARC" if reason == "TURN TOWARD TARGET" else reason), "HUD retains authoritative firing blocker %s" % reason)
		sector.auto_fire = false
		sector.active_contracts["scout"]["required"] = 90
		sector.active_contracts["scout"]["progress"] = 90
		sector.cargo = {"prometium": sector.cargo_capacity}
		sector.notify("Reward pending: wallet full. Cargo full; return to Outpost 01 to trade.")
		sector.show_performance = true
		await capture("hud-alerts-%d" % pixels.x)
		sector.show_performance = false
		sector.active_contracts["scout"]["required"] = 3
		sector.active_contracts["scout"]["progress"] = 1
		sector.cargo = {}
		sector.toast_time = 0
	check(FlightHud.number(116000) == "116,000" and FlightHud.number(100000000) == "100,000,000", "Large health and credit values remain legible")
	root.size = Vector2i(960, 600)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	sector.settings.rebind("fire", KEY_G)
	check(hud.fire_feedback().contains("G"), "Rebound fire appears in current HUD feedback")
	sector.settings.bindings = GameSettings.DEFAULT_BINDINGS.duplicate()
	sector.settings.configure_input()
	sector.session.active = false
	sector.autopilot.enabled = false
	sector.select_target(null)
	player.position = Sector.SPAWN_POSITION
	player.velocity = Vector3.ZERO
	player.time_since_hit = 10
	sector.objective_stage = 0
	await capture("hud-station-960")
	check(not navigation.autopilot_status.visible, "Disabled autopilot has no label")
	for stage in range(5):
		sector.objective_stage = stage
		await capture("hud-solo-%d-960" % stage)
	player.position = Vector3(0, 300, 1200)
	player.radiation_exposure = 5
	await capture("hud-radiation-960")
	check(navigation.destination()["key"] == "safe", "Radiation still takes navigation priority")
	player.alive = false
	sector.player_respawn = 3
	await capture("hud-rescue-960")
	check(not navigation.map_button.visible and not navigation.autopilot_status.visible, "Rescue hides live navigation actions")
	player.reset_health()
	sector.client_only = true
	sector.session.status = "Connection lost. Reconnect from the menu."
	await capture("hud-disconnected-960")
	check(not navigation.map_button.visible, "Disconnected pilot has no live map action")
	sector.preflight = true
	await sync_physics()
	check(not navigation.map_button.visible, "Docked pilot has no flight map action")
	print("HUD replay: %d passed, %d failed" % [checks - failures, failures])
	sector.free()
	quit(0 if failures == 0 else 1)
