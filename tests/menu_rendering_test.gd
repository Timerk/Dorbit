extends "res://tests/shop_test.gd"
## Opaque console coverage, immediate flight restoration and live ENet simulation.


func check_console(client: Sector, mode: String) -> void:
	var viewport := client.get_viewport()
	var camera := client.player.camera
	var pose := camera.global_transform
	client.main_menu.show_home()
	check(viewport.disable_3d, "%s console suppresses sector rendering synchronously" % mode)
	for page: String in ["hangar", "shop", "cargo", "refining", "quests", "skylab", "gates", "settings", "connection", "overview"]:
		client.main_menu.select_page(page)
		check(viewport.disable_3d, "%s page switch to %s never enables sector rendering" % [mode, page])
		await settle(0.05)
		check(viewport.disable_3d and not paused, "%s %s keeps the scene tree running" % [mode, page])
	check(not client.main_menu.ship_art.stage.disable_3d, "%s isolated ship preview retains 3D rendering" % mode)
	await capture(client, "menu-rendering-%s-console" % mode)
	if DisplayServer.get_name() != "headless":
		check(viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) == 0, "%s covered sector submits no 3D draw calls" % mode)
	client.set_paused(false)
	check(not viewport.disable_3d, "%s closing the console restores rendering before the next draw" % mode)
	check(viewport.get_camera_3d() == camera and camera.global_transform.is_equal_approx(pose), "%s menu transitions preserve the current camera and its pose" % mode)
	if DisplayServer.get_name() != "headless":
		# Capture the very first draw after closing, before any settling frames.
		await capture(client, "menu-rendering-%s-first-flight-frame" % mode)
	for attempt in range(3):
		client.main_menu.show_home()
		client.set_paused(false)
		check(not viewport.disable_3d, "%s rapid reopen/close restores rendering" % mode)
	await press(client, KEY_ESCAPE)
	check(client.settings_menu.pause_panel.visible and not viewport.disable_3d, "%s partial flight pause panel keeps the sector visible" % mode)
	client.set_paused(false)
	await press(client, KEY_M)
	check(client.hud.navigation.overview.visible and not viewport.disable_3d, "%s partial sector map keeps the sector visible" % mode)
	client.hud.navigation.close_overview()
	client.hud.layout.set_editing(true)
	check(client.hud.layout.editing and not viewport.disable_3d, "%s translucent HUD editor keeps the sector visible" % mode)
	client.hud.layout.set_editing(false)


func run() -> void:
	var client := make_sector("MenuRendering")
	var viewport := client.get_viewport() as SubViewport
	viewport.size = Vector2i(960, 600)
	if DisplayServer.get_name() != "headless":
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.size = viewport.size
		var screen := TextureRect.new()
		screen.texture = viewport.get_texture()
		root.add_child(screen)
	check(not viewport.disable_3d, "Uncovered sector starts with 3D enabled")
	client.offline = true
	client.session.open_offline_main_menu()
	check(viewport.disable_3d, "Offline preflight suppresses sector rendering")
	client.session.launch()
	check(not viewport.disable_3d and not client.preflight, "Offline launch restores sector rendering immediately")
	await settle()
	await check_console(client, "offline")
	var server := make_sector("MenuRenderingServer", true, 24744)
	client.offline = false
	client.client_only = true
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	check(client.session.join("127.0.0.1", test_port(24744)) == OK, "Rendering test connects to the dedicated server")
	var deadline := Time.get_ticks_msec() + 8000
	while not client.session.received_snapshot and Time.get_ticks_msec() < deadline:
		server.session.send_snapshot()
		await process_frame
	check(client.session.active and client.session.received_snapshot and client.preflight, "Connected preflight receives authoritative state")
	if not client.session.active or not client.session.received_snapshot:
		finish()
		return
	check(viewport.disable_3d, "Connected preflight suppresses sector rendering")
	client.session.launch()
	deadline = Time.get_ticks_msec() + 8000
	while client.preflight and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not client.preflight and not viewport.disable_3d, "Server-confirmed launch restores sector rendering")
	await settle()
	await check_console(client, "connected")
	var id := client.multiplayer.get_unique_id()
	var remote := server.session.ships[id]
	client.main_menu.show_home()
	var sequence: int = client.session.player_sequences[id]
	remote.shield = 0
	remote.time_since_hit = 6
	# Enable ordinary physics processing: opening the console must leave it running.
	server.set_physics_process(true)
	client.set_physics_process(true)
	await settle(0.5)
	check(server.is_physics_processing() and client.is_physics_processing() and not paused, "Menus leave client/server physics and the scene tree running")
	check(viewport.disable_3d and client.session.player_sequences[id] > sequence, "Fresh network snapshots arrive while sector rendering is disabled")
	check(remote.shield > 0 and client.player.shield > 0, "Authoritative shield recovery continues and reaches the covered client")
	var camera := client.player.camera.global_transform
	client.set_paused(false)
	check(not viewport.disable_3d and client.player.camera.global_transform.is_equal_approx(camera), "Closing a live network console restores rendering without a camera jump")
	check(client.session.active and client.multiplayer.get_unique_id() == id and server.session.ships[id] == remote, "Menu transitions preserve network identity and server ship state")
	await capture(client, "menu-rendering-connected-live-flight")
	client.session.disconnect_session("Rendering test complete")
	check(not viewport.disable_3d, "Disconnect to the uncovered connection panel leaves rendering enabled")
	finish()
