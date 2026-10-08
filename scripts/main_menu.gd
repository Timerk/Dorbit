class_name MainMenu
extends Control
## Shared docked and flight menus. Transactions and launch remain server-authoritative.

const HEADER_HEIGHT := 78.0
const SIDEBAR_WIDTH := 220.0
const DESIGN_SIZE := Vector2(1440, 900)
const AMBER := Color("ff880b")
const INK := Color("e0e5ec")
const MUTED := Color("93a5b5")
const LINE := Color("34434b")
const BOLD = preload("res://assets/ui/fonts/Rajdhani-Bold.ttf")
const REGULAR = preload("res://assets/ui/fonts/Rajdhani-SemiBold.ttf")

var sector: Sector
var start_button: Button
var navigation: Dictionary[String, Button] = {}
var wallet: Label
var home: Control
var ship_art: ShipHangarPreview
var ship_title: Label
var notice: Label
var placeholder: PanelContainer
var placeholder_title: Label
var placeholder_icon: TextureRect
var selected_page := "overview"
var last_model := ""
var canvas: Control
var header: Panel
var sidebar: Panel
var background: TextureRect
var brand: Label
var wallet_icon: TextureRect
var ship_status: Label
var ship_ready: Label
var ship_shadow: TextureRect
var ship_accent: ColorRect
var specifications: Panel
var stat_values: Dictionary[String, Label] = {}
var stat_cells: Array[Control] = []
var start_caption: Label
var exit_buttons: Array[Button] = []
var resume_button: Button
var opening_page := false
var fitting_stats := Equipment.StatsCache.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := ColorRect.new()
	backdrop.color = Color("091015")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var menu_theme := Theme.new()
	menu_theme.default_font = REGULAR
	menu_theme.default_font_size = 18
	theme = menu_theme
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	header = Panel.new()
	header.add_theme_stylebox_override("panel", surface(Color("0c1217")))
	canvas.add_child(header)
	brand = label(header, "DORBIT", 52, INK, true)
	label(header, "\\", 34, AMBER).position = Vector2(218, 17)
	wallet_icon = icon(header, "wallet", AMBER)
	wallet = label(header, "", 26, AMBER, true)
	wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sidebar = Panel.new()
	sidebar.add_theme_stylebox_override("panel", surface(Color("0b1115")))
	canvas.add_child(sidebar)
	build_navigation()
	resume_button = rail_button("Resume flight", "quit", func(): sector.set_paused(false))
	resume_button.add_theme_font_size_override("font_size", 14)
	resume_button.add_theme_constant_override("icon_max_width", 16)
	exit_buttons.append(rail_button("Disconnect", "disconnect", func(): sector.session.disconnect_session("Disconnected. You can connect again when ready.")))
	exit_buttons.append(rail_button("Quit to desktop", "quit", func(): get_tree().quit()))
	for button in exit_buttons:
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_constant_override("icon_max_width", 16)
	build_home()
	placeholder = PanelContainer.new()
	placeholder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(placeholder)
	var future := StationUi.rows(placeholder, 32)
	var upper := Control.new()
	upper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	future.add_child(upper)
	placeholder_icon = StationUi.art(future, "ship", Vector2(96, 96))
	placeholder_icon.modulate = Color("60717e")
	placeholder_title = StationUi.text(future, "COMING SOON", 24, MUTED)
	placeholder_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lower := Control.new()
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	future.add_child(lower)
	placeholder.hide()
	hide()


func surface(background_color: Color, border: Color = LINE) -> StyleBoxFlat:
	var value := StationUi.style(background_color, border)
	value.set_corner_radius_all(2)
	return value


func label(parent: Node, text: String, font_size: int, color: Color = INK, bold: bool = false) -> Label:
	var value := Label.new()
	value.text = text
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", color)
	if bold:
		value.add_theme_font_override("font", BOLD)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(value)
	return value


func icon(parent: Node, name: String, color: Color = INK) -> TextureRect:
	var value := TextureRect.new()
	value.texture = load("res://assets/ui/menu/%s.svg" % name)
	value.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	value.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	value.modulate = color
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(value)
	return value


func rail_button(text: String, icon_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon = load("res://assets/ui/menu/%s.svg" % icon_name)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	button.add_theme_constant_override("h_separation", 24)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("icon_pressed_color", AMBER)
	for state: String in ["normal", "disabled"]:
		var style := surface(Color(0, 0, 0, 0), Color("213039"))
		style.set_border_width_all(0)
		style.border_width_bottom = 1
		style.content_margin_left = 34
		button.add_theme_stylebox_override(state, style)
	var hover_style := surface(Color("171f24"), LINE)
	hover_style.content_margin_left = 34
	hover_style.set_border_width_all(0)
	hover_style.border_width_bottom = 1
	button.add_theme_stylebox_override("hover", hover_style)
	for state: String in ["pressed", "hover_pressed"]:
		var style := surface(Color("242522"), AMBER)
		style.set_border_width_all(0)
		style.border_width_left = 4
		style.border_width_right = 4
		style.content_margin_left = 34
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", surface(Color(0, 0, 0, 0), AMBER))
	button.pressed.connect(action)
	sidebar.add_child(button)
	return button


func build_navigation() -> void:
	for entry: Array in [["overview", "OVERVIEW"], ["hangar", "HANGAR"], ["quests", "QUESTS"], ["shop", "SHOP"], ["cargo", "CARGO TRADE"], ["refining", "REFINING"], ["skylab", "SKYLAB"], ["gates", "GALAXY GATES"], ["settings", "SETTINGS"], ["connection", "CONNECTION"]]:
		var page: String = entry[0]
		var button := rail_button(entry[1], page, func(): select_page(page))
		button.toggle_mode = true
		if page == "gates":
			button.add_theme_color_override("font_color", Color("60717e"))
			button.add_theme_color_override("font_hover_color", Color("60717e"))
			button.add_theme_color_override("icon_normal_color", Color("60717e"))
			button.add_theme_color_override("icon_hover_color", Color("60717e"))
			button.add_theme_stylebox_override("hover", button.get_theme_stylebox("normal"))
			button.tooltip_text = "Coming soon"
			var soon := label(button, "COMING SOON", 11, Color("60717e"))
			soon.position = Vector2(86, 48)
		navigation[page] = button


func build_home() -> void:
	home = Control.new()
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(home)
	background = TextureRect.new()
	background.texture = preload("res://assets/ui/menu/hangar-background.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	canvas.move_child(background, 0)
	ship_shadow = TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.65))
	gradient.set_color(1, Color(0, 0, 0, 0))
	var shadow := GradientTexture2D.new()
	shadow.gradient = gradient
	shadow.fill = GradientTexture2D.FILL_RADIAL
	shadow.fill_from = Vector2(0.5, 0.5)
	shadow.fill_to = Vector2(0.5, 1)
	ship_shadow.texture = shadow
	ship_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ship_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(ship_shadow)
	ship_art = ShipHangarPreview.new()
	ship_art.hull_only = true
	home.add_child(ship_art)
	ship_art.hide()
	ship_title = label(home, "SYNCING PILOT", 36, INK, true)
	ship_title.add_theme_constant_override("outline_size", 4)
	ship_title.add_theme_color_override("font_outline_color", Color("091016"))
	ship_status = label(home, "", 13, Color("94dacf"))
	ship_ready = label(home, "READY IN HANGAR", 13, Color("a7e277"))
	ship_accent = ColorRect.new()
	ship_accent.color = AMBER
	ship_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(ship_accent)
	specifications = Panel.new()
	specifications.add_theme_stylebox_override("panel", surface(Color(0.035, 0.055, 0.065, 0.96)))
	home.add_child(specifications)
	label(specifications, "SHIP SPECIFICATIONS", 16, MUTED).position = Vector2(18, 12)
	var seam := ColorRect.new()
	seam.color = LINE
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	specifications.add_child(seam)
	seam.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	seam.offset_left = 18
	seam.offset_right = -18
	seam.offset_top = 42
	seam.offset_bottom = 43
	for entry: Array in [["hull", "Hull"], ["shield", "Shield"], ["damage", "Damage"], ["speed", "Cruise"], ["cargo", "Cargo"]]:
		var cell := Control.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		specifications.add_child(cell)
		stat_cells.append(cell)
		var artwork := icon(cell, entry[0])
		artwork.position = Vector2(10, 18)
		artwork.size = Vector2(28, 28)
		var value := label(cell, "—", 22, INK, true)
		value.position = Vector2(48, 11)
		stat_values[entry[0]] = value
		label(cell, entry[1], 16, MUTED).position = Vector2(48, 37)
	start_button = Button.new()
	start_button.text = "START  →"
	start_button.add_theme_font_override("font", BOLD)
	start_button.add_theme_font_size_override("font_size", 52)
	start_button.add_theme_color_override("font_focus_color", Color("090e11"))
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var fill: Color = {"normal": AMBER, "hover": Color("ffa32b"), "pressed": Color("e97600"), "disabled": Color("735033")}[state]
		var style := surface(fill, fill.lightened(0.1))
		style.content_margin_bottom = 26
		style.set_corner_radius_all(3)
		start_button.add_theme_stylebox_override(state, style)
		start_button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), Color("090e11"))
	start_button.add_theme_stylebox_override("focus", surface(Color(0, 0, 0, 0), Color("ffe1a3")))
	start_button.pressed.connect(sector.session.launch)
	home.add_child(start_button)
	start_caption = label(start_button, "LAUNCH FROM OUTPOST 01", 14, Color("14120b"), true)
	start_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice = label(home, "", 16, Color("ffcf89"))
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_constant_override("outline_size", 4)
	notice.add_theme_color_override("font_outline_color", Color("091016"))


func hide_pages() -> void:
	sector.hud.navigation.close_overview(false)
	sector.shop.hide()
	sector.equipment_menu.hide()
	sector.resource_workshop.hide()
	sector.hud.contract_panel.hide()
	sector.settings_menu.dismiss()
	placeholder.hide()
	sector.skylab_menu.hide()
	home.hide()


func show_home() -> void:
	# Discard stale flight greetings when entering the console.
	if not visible:
		sector.toast_time = 0.0
	hide_pages()
	sector.session.menu.hide()
	selected_page = "overview"
	show()
	home.show()
	sector.set_paused(true)
	layout()
	if sector.preflight:
		start_button.grab_focus()
	else:
		resume_button.grab_focus()


func route_page(page: String) -> bool:
	# Page open methods also serve shortcuts; selection calls them once inside the shell.
	if opening_page or not (sector.preflight or visible or StationUi.offline_preview(sector) or (sector.session.active and not sector.session.combat.inventory.is_empty())):
		return false
	select_page(page)
	return true


func select_page(page: String) -> void:
	if page == "overview":
		show_home()
		return
	var offline := StationUi.offline_preview(sector)
	if not offline and page in ["shop", "hangar", "cargo", "quests", "refining"] and (not sector.session.received_snapshot or sector.session.combat.inventory.is_empty()):
		return
	if not offline and page in ["shop", "hangar", "cargo", "quests", "refining"]:
		var blocker := sector.repair_blocker()
		if not blocker.is_empty():
			sector.notify(blocker)
			show_home()
			return
	hide_pages()
	sector.session.menu.hide()
	show()
	sector.set_paused(true)
	layout()
	selected_page = page
	opening_page = true
	match page:
		"skylab": sector.skylab_menu.open()
		"shop", "cargo":
			sector.shop.open()
			sector.shop.select_cargo(page == "cargo")
		"hangar": sector.equipment_menu.open()
		"refining": sector.resource_workshop.open()
		"quests": sector.hud.toggle_contracts()
		"settings": sector.settings_menu.open()
		"connection": sector.session.open_menu()
		"gates":
			placeholder_icon.texture = load("res://assets/ui/menu/%s.svg" % page)
			placeholder.show()
	opening_page = false
	if not home.visible:
		navigation[page].grab_focus()


func content_rect() -> Rect2:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	return Rect2(Vector2(SIDEBAR_WIDTH, HEADER_HEIGHT) * factor, size - Vector2(SIDEBAR_WIDTH, HEADER_HEIGHT) * factor)


func fit_panel(panel: Control, preferred: Vector2) -> void:
	var dimensions := preferred.max(panel.get_combined_minimum_size())
	var area := content_rect().grow(-16)
	var factor := minf(1.0, minf(area.size.x / dimensions.x, area.size.y / dimensions.y))
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.size = dimensions
	panel.scale = Vector2.ONE * factor
	panel.position = area.position + (area.size - dimensions * factor) / 2


func layout() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	canvas.scale = Vector2.ONE * factor
	canvas.size = size / factor
	header.size = Vector2(canvas.size.x, HEADER_HEIGHT)
	brand.position = Vector2(40, 6)
	var wallet_width := wallet.get_minimum_size().x
	wallet.position = Vector2(canvas.size.x - wallet_width - 28, 21)
	wallet.size = Vector2(wallet_width, 40)
	wallet_icon.position = Vector2(wallet.position.x - 30, 29)
	wallet_icon.size = Vector2(18, 18)
	sidebar.position = Vector2(0, HEADER_HEIGHT)
	sidebar.size = Vector2(SIDEBAR_WIDTH, canvas.size.y - HEADER_HEIGHT)
	resume_button.visible = not sector.preflight
	resume_button.position = Vector2(18, sidebar.size.y - 124)
	resume_button.size = Vector2(SIDEBAR_WIDTH - 36, 32)
	var row_height := (sidebar.size.y - (145 if sector.preflight else 177)) / navigation.size()
	var index := 0
	for page: String in navigation:
		navigation[page].position = Vector2(1, 30 + index * row_height)
		navigation[page].size = Vector2(SIDEBAR_WIDTH - 2, row_height)
		index += 1
	for i in exit_buttons.size():
		var button := exit_buttons[i]
		button.position = Vector2(18, sidebar.size.y - 92 + i * 32)
		button.size = Vector2(SIDEBAR_WIDTH - 36, 32)
	home.position = Vector2(SIDEBAR_WIDTH, HEADER_HEIGHT)
	# A subpixel inset avoids extending beyond the viewport after scaling.
	home.size = canvas.size - home.position - Vector2(0.1, 0.1)
	background.position = home.position
	background.size = home.size
	var footer_y := home.size.y - 170
	ship_art.position = Vector2(home.size.x * 0.17, 140)
	ship_art.size = Vector2(home.size.x * 0.73, footer_y - 165)
	ship_shadow.position = Vector2(home.size.x * 0.24, footer_y - 115)
	ship_shadow.size = Vector2(home.size.x * 0.61, 100)
	ship_title.position = Vector2(58, home.size.y * 0.27)
	ship_status.position = ship_title.position + Vector2(2, 45)
	ship_ready.position = ship_status.position + Vector2(0, 18)
	ship_accent.position = ship_title.position - Vector2(18, -5)
	ship_accent.size = Vector2(3, 84)
	var footer_width := home.size.x - 44
	var specs_width := footer_width * 0.68 - 12 if sector.preflight else footer_width
	specifications.position = Vector2(22, footer_y)
	specifications.size = Vector2(specs_width, 124)
	for i in stat_cells.size():
		var cell_width := (specs_width - 28) / stat_cells.size()
		stat_cells[i].position = Vector2(14 + i * cell_width, 51)
		stat_cells[i].size = Vector2(cell_width, 68)
	start_button.position = Vector2(34 + specs_width, footer_y)
	start_button.size = Vector2(maxf(1, footer_width - specs_width - 12), 124)
	start_button.visible = sector.preflight
	start_caption.position = Vector2(0, 83)
	start_caption.size = Vector2(start_button.size.x, 26)
	notice.position = Vector2(24, home.size.y - 38)
	notice.size = Vector2(home.size.x - 48, 36)


func _process(_delta: float) -> void:
	if not visible:
		return
	layout()
	if sector.shop.visible:
		selected_page = "cargo" if sector.shop.cargo_page.visible else "shop"
	elif sector.equipment_menu.visible:
		selected_page = "hangar"
	elif sector.resource_workshop.visible:
		selected_page = "refining"
	elif sector.hud.contract_panel.visible:
		selected_page = "quests"
	elif sector.settings_menu.panel.visible:
		selected_page = "settings"
	elif sector.session.menu.visible:
		selected_page = "connection"
	elif sector.skylab_menu.visible:
		selected_page = "skylab"
	# Keyboard shortcuts and the existing panels' links also switch pages.
	if selected_page != "overview":
		home.hide()
	var offline := StationUi.offline_preview(sector)
	var ready := offline or (sector.session.received_snapshot and not sector.session.combat.inventory.is_empty())
	exit_buttons[0].disabled = not sector.session.active
	StationUi.set_text(start_caption, "SOLO ENCOUNTER" if offline else "LAUNCH FROM OUTPOST 01")
	start_button.disabled = not ready or not sector.player.alive or sector.session.combat.station_pending
	start_button.tooltip_text = "Wait for rescue before launching." if not sector.player.alive else ("Waiting for server confirmation." if start_button.disabled else ("Enter the solo development encounter." if offline else "Launch your active ship at Outpost 01."))
	for page: String in navigation:
		if navigation[page].button_pressed != (selected_page == page):
			navigation[page].set_pressed_no_signal(selected_page == page)
		if page in ["shop", "hangar", "cargo", "quests", "refining"]:
			navigation[page].disabled = not ready or (not offline and not sector.player.alive)
	StationUi.set_text(wallet, StationShop.credits_text(sector.credits) + " CR")
	StationUi.set_text(ship_status, ("OFFLINE PREVIEW" if offline else "ACTIVE SHIP") if ready and sector.player.alive else ("RESCUE IN %d s" % ceili(sector.player_respawn) if ready else "WAITING FOR SERVER"))
	ship_ready.visible = ready and sector.player.alive
	StationUi.set_text(notice, sector.toast if sector.toast_time > 0 else sector.session.combat.station_message)
	notice.visible = not notice.text.is_empty()
	ship_art.visible = ready
	ship_shadow.visible = ready
	if ready:
		var data := StationUi.inventory(sector)
		var model: String = ShipCatalog.canonical(data["ships"][data["active_ship"]])
		if last_model != model:
			last_model = model
			ship_art.set_model(model)
			ship_title.text = ShipCatalog.info(model)["name"].to_upper()
		var stats := ResourceBoosts.stats(fitting_stats.get_stats(data), sector.player.resource_boosts)
		StationUi.set_text(stat_values["hull"], StationShop.credits_text(int(sector.player.hull)))
		StationUi.set_text(stat_values["shield"], StationShop.credits_text(int(stats["shield"])))
		StationUi.set_text(stat_values["damage"], str(int(stats["damage"])))
		StationUi.set_text(stat_values["speed"], "%d m/s" % stats["speed"])
		StationUi.set_text(stat_values["cargo"], "%d / %d" % [CargoResources.units(sector.cargo), sector.cargo_capacity])
	for panel: Control in [placeholder, sector.shop, sector.equipment_menu, sector.resource_workshop, sector.hud.contract_panel]:
		if panel.visible:
			fit_panel(panel, Vector2(1150, 690))
