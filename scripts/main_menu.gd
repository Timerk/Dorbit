class_name MainMenu
extends Control
## Docked pilot console. Uses the existing authoritative station screens.

const HEADER_HEIGHT := 144.0
var sector: Sector
var start_button: Button
var navigation: Dictionary[String, Button] = {}
var wallet: Label
var connection: Label
var home: PanelContainer
var ship_art: TextureRect
var ship_title: Label
var ship_stats: Label
var quests: Label
var notice: Label
var placeholder: PanelContainer
var placeholder_title: Label
var selected_page := "overview"
var last_model := ""
var header: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	header = PanelContainer.new()
	header.add_theme_stylebox_override("panel", StationUi.style(Color("152432"), Color("578298")))
	add_child(header)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	header.add_child(rows)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	rows.add_child(bar)
	build_navigation(bar, [["hangar", "HANGAR  /  I"], ["quests", "QUESTS  /  C"], ["settings", "SETTINGS"], ["skylab", "SKYLAB"]])
	start_button = StationUi.button(bar, "START", sector.session.launch)
	start_button.custom_minimum_size = Vector2(280, 70)
	start_button.add_theme_font_size_override("font_size", 28)
	start_button.add_theme_stylebox_override("normal", StationUi.style(Color("365f23"), Color("98d35b")))
	start_button.add_theme_stylebox_override("hover", StationUi.style(Color("4a7d2d"), Color("beff80")))
	start_button.add_theme_stylebox_override("disabled", StationUi.style(Color("283d28"), Color("52704c")))
	start_button.add_theme_stylebox_override("focus", StationUi.style(Color(0, 0, 0, 0), Color("beff80")))
	build_navigation(bar, [["shop", "SHOP  /  B"], ["cargo", "CARGO TRADE"], ["gates", "GALAXY GATES"], ["connection", "CONNECTION"]])
	var readouts := HBoxContainer.new()
	rows.add_child(readouts)
	var brand := StationUi.button(readouts, "D O R B I T   /   OVERVIEW", show_home)
	brand.custom_minimum_size.y = 22
	brand.add_theme_font_size_override("font_size", 11)
	connection = StationUi.text(readouts, "OUTPOST 01 / DOCKED", 12, FlightHud.CYAN)
	connection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wallet = StationUi.text(readouts, "", 14, FlightHud.GREEN)
	wallet.custom_minimum_size.x = 150
	wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_home()
	placeholder = PanelContainer.new()
	StationUi.frame(placeholder, Vector2(1100, 620))
	add_child(placeholder)
	var future := StationUi.rows(placeholder, 32)
	StationUi.text(future, "OUTPOST 01 / FUTURE SYSTEM", 12, FlightHud.CYAN)
	placeholder_title = StationUi.text(future, "", 32)
	StationUi.text(future, "COMING SOON", 18, FlightHud.GREEN)
	StationUi.text(future, "This facility is not implemented yet. Prepare your ship in the hangar, browse the shop or choose a hunting quest before launch.", 16)
	StationUi.button(future, "Back to overview", show_home)
	placeholder.hide()
	get_viewport().size_changed.connect(queue_redraw)
	hide()


func build_navigation(parent: Node, entries: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for entry: Array in entries:
		var page: String = entry[0]
		var button := StationUi.button(grid, entry[1], func(): select_page(page))
		button.custom_minimum_size = Vector2(144, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		button.toggle_mode = true
		button.add_theme_stylebox_override("pressed", StationUi.style(Color("315364"), FlightHud.CYAN))
		if page in ["skylab", "gates"]:
			button.text += " *"
			button.tooltip_text = "Coming soon / not implemented"
		navigation[page] = button


func build_home() -> void:
	home = PanelContainer.new()
	StationUi.frame(home, Vector2(1100, 620))
	add_child(home)
	var rows := StationUi.rows(home, 24)
	StationUi.text(rows, "PILOT CONSOLE   /   OUTPOST 01", 12, FlightHud.CYAN)
	StationUi.text(rows, "PREPARE FOR LAUNCH", 28)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	rows.add_child(body)
	var ship := StationUi.card(body)
	ship.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ship_rows := StationUi.rows(ship, 16)
	ship_title = StationUi.text(ship_rows, "", 24)
	StationUi.text(ship_rows, "ACTIVE SHIP / READY IN HANGAR", 11, FlightHud.CYAN)
	ship_art = StationUi.art(ship_rows, "ship", Vector2(300, 100))
	ship_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ship_stats = StationUi.text(ship_rows, "", 14)
	StationUi.button(ship_rows, "Open hangar / equip your ship", func(): select_page("hangar"))
	var briefing := StationUi.card(body)
	briefing.custom_minimum_size.x = 310
	briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var brief_rows := StationUi.rows(briefing, 16)
	StationUi.text(brief_rows, "FLIGHT PREPARATION", 18, FlightHud.CYAN)
	StationUi.text(brief_rows, "01  SHOP\nBuy ships, lasers, shields and engines.\n\n02  HANGAR\nActivate a hull and fit owned equipment.\n\n03  QUESTS\nAccept Scout, Sentinel and Heavy hunts.", 15)
	quests = StationUi.text(brief_rows, "", 14, FlightHud.GREEN)
	quests.size_flags_vertical = Control.SIZE_EXPAND_FILL
	StationUi.text(brief_rows, "Choose START above to spawn at Outpost 01. Your ship stays docked until launch.", 15)
	notice = StationUi.text(rows, "", 13, FlightHud.CYAN)
	var footer := HBoxContainer.new()
	rows.add_child(footer)
	StationUi.button(footer, "Settings", func(): select_page("settings"))
	StationUi.button(footer, "Disconnect", func(): sector.session.disconnect_session("Disconnected. You can connect again when ready."))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	StationUi.button(footer, "Quit to desktop", func(): get_tree().quit())


func hide_pages() -> void:
	sector.shop.hide()
	sector.equipment_menu.hide()
	sector.hud.contract_panel.hide()
	sector.settings_menu.dismiss()
	placeholder.hide()
	home.hide()


func show_home() -> void:
	if not sector.preflight:
		return
	hide_pages()
	sector.session.menu.hide()
	selected_page = "overview"
	show()
	home.show()
	sector.player.release_mouse()
	sector.paused = true
	start_button.grab_focus()


func select_page(page: String) -> void:
	if not sector.preflight:
		return
	if page in ["shop", "hangar", "cargo", "quests"] and (not sector.session.received_snapshot or sector.session.combat.inventory.is_empty()):
		return
	hide_pages()
	sector.session.menu.hide()
	selected_page = page
	match page:
		"shop", "cargo":
			sector.shop.open()
			if page == "cargo":
				sector.shop.cargo_button.pressed.emit()
			else:
				sector.shop.catalog_button.pressed.emit()
		"hangar": sector.equipment_menu.open()
		"quests": sector.hud.toggle_contracts()
		"settings": sector.settings_menu.open()
		"connection": sector.session.open_menu()
		"skylab", "gates":
			placeholder_title.text = "SKYLAB" if page == "skylab" else "GALAXY GATES"
			placeholder.show()


func fit_panel(panel: Control, preferred: Vector2) -> void:
	var dimensions := preferred.max(panel.get_combined_minimum_size())
	var area := Rect2(Vector2(20, HEADER_HEIGHT + 12), size - Vector2(40, HEADER_HEIGHT + 32))
	var factor := minf(1.0, minf(area.size.x / dimensions.x, area.size.y / dimensions.y))
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.size = dimensions
	panel.scale = Vector2.ONE * factor
	panel.position = area.position + (area.size - dimensions * factor) / 2


func _process(_delta: float) -> void:
	if not visible:
		return
	var header_width := minf(size.x - 40, 1160)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	header.position = Vector2((size.x - header_width) / 2, 16)
	header.size = Vector2(header_width, HEADER_HEIGHT - 28)
	if sector.shop.visible:
		selected_page = "cargo" if sector.shop.cargo_page.visible else "shop"
	elif sector.equipment_menu.visible:
		selected_page = "hangar"
	elif sector.hud.contract_panel.visible:
		selected_page = "quests"
	var ready := sector.session.received_snapshot and not sector.session.combat.inventory.is_empty()
	start_button.disabled = not ready or sector.session.combat.station_pending
	start_button.tooltip_text = "Waiting for server confirmation." if start_button.disabled else "Launch your active ship at Outpost 01."
	for page: String in navigation:
		navigation[page].set_pressed_no_signal(selected_page == page)
		if page in ["shop", "hangar", "cargo", "quests"]:
			navigation[page].disabled = not ready
	wallet.text = StationShop.credits_text(sector.credits) + " CR"
	connection.text = "OUTPOST 01 / DOCKED" if ready else "SYNCING PILOT..."
	notice.text = sector.session.combat.station_message if not sector.session.combat.station_message.is_empty() else "Your equipment, credits and quests are saved on the server."
	if ready:
		var data := sector.session.combat.inventory
		var model: String = ShipCatalog.canonical(data["ships"][data["active_ship"]])
		if last_model != model:
			last_model = model
			ship_art.texture = StationUi.texture(model)
			ship_title.text = ShipCatalog.info(model)["name"].to_upper()
		var stats := Equipment.stats(data)
		ship_stats.text = "%s hull   /   %s shield\n%d damage   /   %d m/s cruise\nCargo %d / %d units" % [StationShop.credits_text(int(sector.player.hull)), StationShop.credits_text(int(stats["shield"])), stats["damage"], stats["speed"], CargoResources.units(sector.cargo), sector.cargo_capacity]
		quests.text = "QUESTS / %d ACTIVE" % sector.active_contracts.size()
	for panel: Control in [home, placeholder, sector.shop, sector.equipment_menu, sector.hud.contract_panel]:
		if panel.visible:
			fit_panel(panel, Vector2(1100, 620) if panel in [home, placeholder] else Vector2(920, 550))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("050c16"))
	# Restrained steel rails and cyan seams echo the supplied station console.
	for y in range(0, int(size.y), 64):
		draw_line(Vector2(0, y), Vector2(size.x, y - 140), Color("0b1420"), 1)
	draw_rect(Rect2(Vector2(8, 6), size - Vector2(16, 12)), Color("335268"), false, 2)
	draw_line(Vector2(20, HEADER_HEIGHT + 5), Vector2(size.x - 20, HEADER_HEIGHT + 5), FlightHud.CYAN, 1)
	for y in [HEADER_HEIGHT + 8, size.y - 12]:
		draw_line(Vector2(10, y), Vector2(size.x - 10, y), Color("1b2c3b"), 6)
		draw_line(Vector2(10, y + 4), Vector2(size.x - 10, y + 4), Color("426173"), 1)
	for x in [18.0, size.x - 18.0]:
		for y in [14.0, HEADER_HEIGHT + 15, size.y - 20]:
			draw_circle(Vector2(x, y), 3, Color("6a7b87"))
	for x in [12.0, size.x - 12.0]:
		draw_line(Vector2(x, 24), Vector2(x, 90), Color("66e2ee"), 3)
