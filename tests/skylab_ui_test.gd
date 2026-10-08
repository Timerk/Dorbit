extends "res://tests/shop_test.gd"
## Module clicks, authoritative controls and rendered 960/1440 layouts.


func run() -> void:
	var server := make_sector("IndustryServer", true, 24745)
	var client := make_sector("IndustryPilot")
	client.client_only = true
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24745))
	await settle(.6)
	var id := client.multiplayer.get_unique_id()
	server.session.store.commit({"pilot0": 1000000})
	server.session.combat.sync_lab_accounts()
	server.session.combat.publish_inventory(id)
	await settle()
	check(client.session.active, "Skylab UI authenticates with the existing session")
	if not client.session.active:
		finish()
		return
	var menu := client.skylab_menu
	if DisplayServer.get_name() != "headless":
		client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var screen := TextureRect.new()
		screen.texture = client.get_viewport().get_texture()
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(screen)
	for dimensions in [Vector2i(1920, 1080), Vector2i(1440, 900), Vector2i(960, 600)]:
		client.get_viewport().size = dimensions
		root.size = dimensions
		await click(client, client.main_menu.navigation["skylab"])
		await settle(.3)
		check(menu.visible and not client.main_menu.placeholder.visible, "Skylab replaces the Coming soon placeholder")
		check(menu.buttons.size() == 12 and menu.ore_labels.size() == 8 and menu.ore_labels.has("xenomit"), "All modules and eight separate resource capacities are displayed")
		check(client.main_menu.content_rect().grow(1).encloses(menu.get_global_rect()), "Industry screen fits %s" % dimensions)
		check(menu.get_global_rect().position.distance_to(client.main_menu.content_rect().position) < 1 and menu.get_global_rect().size.distance_to(client.main_menu.content_rect().size) < 1, "Skylab fills the entire navigation content area at %s" % dimensions)
		for button: Button in menu.buttons.values(): check(menu.canvas.get_global_rect().grow(1).encloses(button.get_global_rect()), "Module button fits the station canvas")
		await capture(client, "skylab-%d" % dimensions.x)
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.position = menu.canvas.get_global_transform() * menu.art.point("enduriumCollector")
			client.get_viewport().push_input(event)
			await process_frame
		check(menu.detail.visible and menu.selected == "enduriumCollector", "The station machinery itself opens the corresponding module at %s" % dimensions)
		menu.detail.hide()
		await click(client, menu.buttons["promeriumRefinery"])
		check(menu.detail.visible and menu.info.text.contains("Xenomit"), "Clicking a module opens recipe info with the real/virtual catalyst distinction")
		check(menu.canvas.get_global_rect().grow(1).encloses(menu.detail.get_global_rect()), "Detail panel fits %s" % dimensions)
		await capture(client, "skylab-detail-%d" % dimensions.x)
		menu.detail.hide()
	menu.select_module("basic")
	menu.tabs.current_tab = 1
	await settle()
	await click(client, menu.build)
	check(server.session.store.pilots["pilot0"]["skylab"]["modules"]["basic"]["upgrade"] != null, "Upgrade button saves a real server job")
	check(menu.progress.visible and menu.upgrade_info.text.contains("Target: 2"), "Construction shows completed and target levels separately")
	await capture(client, "skylab-upgrade-960")
	menu.select_module("prometiumCollector")
	menu.tabs.current_tab = 2
	await settle()
	await click(client, menu.credit_robot)
	check(server.session.store.pilots["pilot0"]["skylab"]["robots"]["prometiumCollector"]["active"].size() == 1, "Productivity purchase creates an authoritative robot")
	check(menu.robot_summary.text.contains("+1%") and menu.robot_info.tooltip_text.contains("Standard"), "Collector bonus is shown once and individual lifetimes remain in the tooltip")
	menu.robot_amount.value = 24
	await click(client, menu.advanced_robot)
	check(menu.robot_summary.text.contains("12 / 12") and menu.robot_info.tooltip_text.split("\n").size() == 12, "Full robot slots retain individual expiry details without a visible list")
	var robot_page := menu.tabs.get_child(2) as ScrollContainer
	check(robot_page.get_child(0).get_combined_minimum_size().y <= robot_page.size.y, "All robot controls fit without scrolling even with full slots and queued robots")
	await capture(client, "skylab-robots-960")
	menu.select_module("transport")
	menu.amounts["prometium"].text = "1.5"
	await settle()
	check(menu.send.disabled and menu.instant_send.disabled, "Transport fields block fractional cargo before requesting payment")
	menu.amounts["prometium"].value = 10
	await settle()
	(menu.tabs.get_child(0) as ScrollContainer).ensure_control_visible(menu.send)
	await process_frame
	await click(client, menu.send)
	check(server.session.store.pilots["pilot0"]["skylab"]["shipment"] != null and menu.transport_info.text.contains("In flight"), "Transport fields dispatch and display the existing shipment (%s)" % client.session.combat.station_message)
	(menu.tabs.get_child(0) as ScrollContainer).scroll_vertical = 0
	await process_frame
	await capture(client, "skylab-transport-960")
	check(menu.instant_send.visible and not menu.finish_send.disabled, "Both direct instant send and active-flight acceleration are visible")
	var balance_before: int = server.session.store.pilots["pilot0"]["credits"]
	(menu.tabs.get_child(0) as ScrollContainer).ensure_control_visible(menu.finish_send)
	await process_frame
	await click(client, menu.finish_send)
	check(server.session.store.pilots["pilot0"]["skylab"]["shipment"] == null and server.session.store.pilots["pilot0"]["credits"] == balance_before - 125000, "Visible delivery action uses the flat credit price")
	menu.amounts["prometium"].value = 5
	await settle()
	await click(client, menu.instant_send)
	check(server.session.store.pilots["pilot0"]["cargo"]["starter"].get("prometium", 0) == 15, "Direct instant-send control delivers the entered manifest")
	var delivered: Dictionary = server.session.store.pilots["pilot0"].duplicate(true)
	client.session.combat.skylab_request.rpc_id(1, int(delivered["equipment"]["revision"]), "ship_instant", {"manifest": {"prometium": 5}})
	await settle()
	check(server.session.store.pilots["pilot0"]["credits"] == delivered["credits"] and server.session.store.pilots["pilot0"]["cargo"] == delivered["cargo"], "Retrying an instant-send request cannot charge or deliver twice")
	for module_id: String in ["basic", "solar", "storage", "xeno", "prometiumCollector", "prometidRefinery", "promeriumRefinery", "transport"]:
		menu.select_module(module_id)
		await settle()
		check(menu.canvas.get_global_rect().encloses(menu.detail.get_global_rect()), "Reference-style %s window fits the canvas" % module_id)
		await capture(client, "skylab-%s-info-960" % module_id)
		menu.tabs.current_tab = 1
		await settle()
		await capture(client, "skylab-%s-upgrade-960" % module_id)
	menu.detail.hide()
	menu.snapshot = Skylab.screenshot_snapshot(Skylab.now())
	menu.received_at = Time.get_ticks_msec()
	menu.refresh_clock = 0
	client.get_viewport().size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	await settle()
	check(menu.power_label.text.contains("454 / 870") and menu.ore_labels["prometium"].text.contains("4,018,569"), "Screenshot fixture displays historical reference values separately from balance")
	await capture(client, "skylab-screenshot-fixture-1440")
	menu.hide()
	await settle()
	check(menu.art.texture != null and menu.art.get_child_count() == 0, "Detailed station art needs no continuously rendered 3D viewport")
	server.session.disconnect_session("Finished")
	finish()
