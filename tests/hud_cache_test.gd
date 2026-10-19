extends "res://tests/encounter_test.gd"
## Flight HUD caches: shared contacts, fitted text sizes and binding labels.


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	# Freeze simulation so only explicit changes alter the contact list.
	sector.set_physics_process(false)
	sector.settings.configure_input()
	await sync_physics()
	var navigation := sector.hud.navigation
	var alien: Alien = sector.aliens[1]
	navigation.contacts()
	var builds := navigation.contact_builds
	var shared := navigation.contacts()
	for frame in range(10):
		await process_frame
	navigation.sync_waypoint()
	navigation.destination()
	check(navigation.contact_builds == builds, "Steady frames, radar, guidance and waypoint checks reuse one contact list")
	check(is_same(navigation.contacts(), shared), "Every caller receives the same shared contact list")
	var key := "alien%d" % alien.alien_id
	alien.position += Vector3(40, 0, 0)
	var moved: Array = navigation.contacts().filter(func(contact: Dictionary): return contact["key"] == key)
	check(moved.size() == 1 and moved[0]["position"] == alien.position and navigation.contact_builds == builds, "Moving contacts update their cached position without a rebuild")
	alien.alive = false
	check(not navigation.has_contact(key) and navigation.contact_builds == builds + 1, "A contact leaving rebuilds the list once")
	navigation.contacts()
	check(navigation.contact_builds == builds + 1, "The rebuilt list is shared again")
	alien.alive = true
	check(navigation.has_contact(key) and navigation.contact_builds == builds + 2, "A contact entering rebuilds the list once")
	sector.select_target(alien)
	navigation.sync_waypoint()
	check(navigation.destination()["ship"] == alien and navigation.contact_builds == builds + 2, "Target selection guides to the cached contact")
	sector.player.position = SectorMaps.origin(sector.map_id) + Vector3(0, Sector.MAP_RADIUS + 20, 0)
	var safe := navigation.destination()
	check(safe["key"] == "safe" and safe["position"].distance_to(SectorMaps.origin(sector.map_id)) < Sector.MAP_RADIUS, "Radiation guidance still points to safe space")
	sector.player.position = Sector.SPAWN_POSITION

	var long_text := "DESTINATION / A VERY LONG CONTACT NAME THAT DOES NOT FIT"
	var fitted := FlightHud.fit_pixels(long_text, 18, 120)
	check(fitted < 18 and fitted >= 12 and FlightHud.fit_pixels(long_text, 18, 120) == fitted, "Long text shrinks and its fitted size is reused")
	check(FlightHud.fit_pixels(long_text, 18, 4000) == 18, "A wider bound measures the text again")
	check(FlightHud.fit_pixels("FIT", 16, 186) == 16, "Short text keeps its requested size")

	var revision := GameSettings.binding_revision
	sector.hud.refresh_control_hints(16)
	check(sector.hud.control_hints[2][0] == GameSettings.binding_text("fire"), "Control hints use the cached fire label")
	var original := GameSettings.binding_text("fire")
	sector.auto_fire = false
	sector.select_target(alien)
	check(sector.hud.fire_feedback().contains(original) and GameSettings.binding_text("fire") == original, "Cached binding labels match the installed key")
	sector.settings.rebind("fire", KEY_G)
	check(GameSettings.binding_revision > revision, "Rebinding advances the binding revision")
	check(GameSettings.binding_text("fire") == "G" and sector.hud.fire_feedback().contains("G"), "Rebinding refreshes cached labels and HUD phrases")
	var forward := GameSettings.binding_text("forward")
	sector.settings.rebind("fire", KEY_W)
	check(GameSettings.binding_text("fire") == "W" and GameSettings.binding_text("forward") == "G" and forward == "W", "Swapped bindings refresh both labels")
	sector.hud.refresh_control_hints(16)
	check(sector.hud.control_hints.any(func(hint: Array): return hint[0] == "W" and hint[2] == "Fire"), "Control hints rebuild after a rebind")
	sector.settings.reset_controls()
	check(GameSettings.binding_text("fire") == original and GameSettings.binding_text("forward") == "W", "Restoring defaults refreshes cached labels")
	sector.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
