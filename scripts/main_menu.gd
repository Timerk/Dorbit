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
var page_scrim: TextureRect
var hints: HBoxContainer
var hint_action: Label
var placeholder_heading: Label
var brand_slash: Label
var page_name: Label
var header_accent: ColorRect
var wallet_chip: Panel
var sidebar_rule: ColorRect
var stat_dividers: Array[ColorRect] = []
var home_shade: TextureRect
var title_shade: TextureRect
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
	header.add_theme_stylebox_override("panel", edge(Color("0c1217"), "bottom"))
	canvas.add_child(header)
	brand = label(header, "DORBIT", 52, INK, true)
	brand.add_theme_font_override("font", StationUi.tracked(true, 4))
	brand_slash = label(header, "\\", 34, AMBER)
	# The header names the open page beside the brand.
	page_name = label(header, "", 22, INK, true)
	page_name.add_theme_font_override("font", StationUi.tracked(true, 3))
	header_accent = ColorRect.new()
	header_accent.color = AMBER
	header_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(header_accent)
	wallet_chip = Panel.new()
	var chip := StationUi.chamfer(Color("111a20"), LINE, 0, 10)
	chip.border_width_left = 3
	wallet_chip.add_theme_stylebox_override("panel", chip)
	wallet_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(wallet_chip)
	wallet_icon = icon(header, "wallet", AMBER)
	wallet = label(header, "", 26, AMBER, true)
	wallet.add_theme_font_override("font", StationUi.tracked(true, 1))
	wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sidebar = Panel.new()
	sidebar.add_theme_stylebox_override("panel", edge(Color("0a1014"), "right"))
	canvas.add_child(sidebar)
	var kicker := label(sidebar, "STATION", 12, Color("60717e"), true)
	kicker.add_theme_font_override("font", StationUi.tracked(true, 4))
	kicker.position = Vector2(34, 8)
	build_navigation()
	sidebar_rule = ColorRect.new()
	sidebar_rule.color = LINE
	sidebar_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sidebar.add_child(sidebar_rule)
	resume_button = rail_button("Resume flight", "quit", func(): sector.set_paused(false))
	resume_button.add_theme_font_size_override("font_size", 14)
	resume_button.add_theme_constant_override("icon_max_width", 16)
	resume_button.add_theme_constant_override("h_separation", 12)
	# Resuming is the main action in flight, so it reads as an amber outline.
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var lit := state != "normal"
		var outline := StationUi.chamfer(Color(AMBER, 0.16 if lit else 0.07), AMBER if lit else Color(AMBER, 0.6), 0, 8)
		outline.content_margin_left = 16
		resume_button.add_theme_stylebox_override(state, outline)
	resume_button.add_theme_color_override("font_color", AMBER)
	resume_button.add_theme_color_override("icon_normal_color", AMBER)
	exit_buttons.append(rail_button("Disconnect", "disconnect", func(): sector.session.disconnect_session("Disconnected. You can connect again when ready.")))
	exit_buttons.append(rail_button("Quit to desktop", "quit", func(): get_tree().quit()))
	for button in exit_buttons:
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_constant_override("icon_max_width", 16)
		button.add_theme_constant_override("h_separation", 12)
		button.add_theme_color_override("font_color", MUTED)
		for state: String in ["normal", "hover", "disabled", "focus"]:
			var compact := button.get_theme_stylebox(state).duplicate() as StyleBox
			compact.content_margin_left = 16
			button.add_theme_stylebox_override(state, compact)
	build_home()
	placeholder = PanelContainer.new()
	placeholder.theme = StationUi.page_theme()
	placeholder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(placeholder)
	var future := StationUi.rows(placeholder, 16)
	placeholder_heading = StationUi.header(future, "GALAXY GATES", "OPERATIONS")
	var upper := Control.new()
	upper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	future.add_child(upper)
	placeholder_icon = StationUi.art(future, "ship", Vector2(96, 96))
	placeholder_icon.modulate = Color("60717e")
	placeholder_title = StationUi.heading(future, "COMING SOON", 24, MUTED)
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


func edge(background_color: Color, side: String) -> StyleBoxFlat:
	# Shell panels meet the hangar view with a single hairline.
	var value := StationUi.style(background_color, LINE)
	value.set_corner_radius_all(0)
	value.set_border_width_all(0)
	value.set("border_width_" + side, 1)
	return value


func shade(parent: Node, from: Vector2, to: Vector2, strength: float) -> TextureRect:
	# Gradients keep overlaid text readable against the bright hangar art.
	var value := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.027, 0.043, 0.055, 0))
	gradient.set_color(1, Color(0.027, 0.043, 0.055, strength))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = from
	texture.fill_to = to
	value.texture = texture
	value.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(value)
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


func rail_style(state: String) -> StyleBox:
	var key := "rail:" + state
	if StationUi.cached.has(key):
		return StationUi.cached[key]
	var value: StyleBox
	if state == "pressed":
		# The open page glows from an amber edge, fading toward the hangar view.
		var glow := Gradient.new()
		glow.offsets = PackedFloat32Array([0.0, 0.016, 0.02, 1.0])
		glow.colors = PackedColorArray([AMBER, AMBER, Color(AMBER, 0.24), Color(AMBER, 0.02)])
		var texture := GradientTexture2D.new()
		texture.gradient = glow
		texture.width = 256
		texture.height = 4
		var fill := StyleBoxTexture.new()
		fill.texture = texture
		value = fill
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(1, 1, 1, 0.04) if state == "hover" else Color.TRANSPARENT
		flat.border_color = {"hover": Color(AMBER, 0.45), "focus": Color(AMBER, 0.8)}.get(state, Color("172229"))
		flat.border_width_left = 3 if state in ["hover", "focus"] else 0
		flat.border_width_bottom = 0 if state == "focus" else 1
		value = flat
	value.content_margin_left = 34
	StationUi.cached[key] = value
	return value


func rail_button(text: String, icon_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon = load("res://assets/ui/menu/%s.svg" % icon_name)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 26)
	button.add_theme_constant_override("h_separation", 22)
	button.add_theme_font_override("font", StationUi.tracked(true, 1))
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("b4c1cc"))
	for state: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("4f5f6b"))
	button.add_theme_color_override("icon_normal_color", MUTED)
	button.add_theme_color_override("icon_hover_color", INK)
	button.add_theme_color_override("icon_focus_color", INK)
	button.add_theme_color_override("icon_pressed_color", AMBER)
	button.add_theme_color_override("icon_hover_pressed_color", AMBER)
	button.add_theme_color_override("icon_disabled_color", Color("3d4b55"))
	for state: String in ["normal", "disabled"]:
		button.add_theme_stylebox_override(state, rail_style("normal"))
	button.add_theme_stylebox_override("hover", rail_style("hover"))
	button.add_theme_stylebox_override("focus", rail_style("focus"))
	for state: String in ["pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, rail_style("pressed"))
	button.pressed.connect(action)
	sidebar.add_child(button)
	return button


func build_navigation() -> void:
	for entry: Array in [["overview", "OVERVIEW"], ["hangar", "HANGAR"], ["quests", "QUESTS"], ["shop", "SHOP"], ["cargo", "CARGO TRADE"], ["refining", "REFINING"], ["skylab", "SKYLAB"], ["research", "RESEARCH"], ["gates", "GALAXY GATES"], ["settings", "SETTINGS"], ["connection", "CONNECTION"]]:
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
			var soon := label(button, "COMING SOON", 11, Color("60717e"), true)
			soon.add_theme_font_override("font", StationUi.tracked(true, 3))
			soon.position = Vector2(82, 48)
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
	# Pages dim the hangar so dense station data stays readable.
	page_scrim = TextureRect.new()
	var dim := Gradient.new()
	dim.set_color(0, Color(0.027, 0.043, 0.055, 0.93))
	dim.set_color(1, Color(0.027, 0.043, 0.055, 0.8))
	var dim_texture := GradientTexture2D.new()
	dim_texture.gradient = dim
	dim_texture.fill_to = Vector2(1, 0)
	page_scrim.texture = dim_texture
	page_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(page_scrim)
	canvas.move_child(page_scrim, 1)
	hints = HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_END
	hints.add_theme_constant_override("separation", 10)
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hints)
	var keycap := PanelContainer.new()
	var cap := StationUi.chamfer(Color("111a20"), Color("4a5a64"), 0, 0)
	cap.border_width_bottom = 2
	cap.content_margin_left = 8
	cap.content_margin_right = 8
	cap.content_margin_top = 1
	cap.content_margin_bottom = 1
	keycap.add_theme_stylebox_override("panel", cap)
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_child(keycap)
	label(keycap, "ESC", 14, INK, true)
	hint_action = label(hints, "BACK", 15, MUTED, true)
	hint_action.add_theme_font_override("font", StationUi.tracked(true, 2))
	home_shade = shade(home, Vector2(0, 0.45), Vector2(0, 1), 0.9)
	title_shade = shade(home, Vector2(0.5, 0), Vector2(0, 0), 0.75)
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
	ship_title = label(home, "SYNCING PILOT", 48, INK, true)
	ship_title.add_theme_font_override("font", StationUi.tracked(true, 4))
	ship_title.add_theme_constant_override("outline_size", 4)
	ship_title.add_theme_color_override("font_outline_color", Color("091016"))
	ship_status = label(home, "", 14, AMBER, true)
	ship_status.add_theme_font_override("font", StationUi.tracked(true, 4))
	ship_ready = label(home, "READY IN HANGAR", 13, Color("a7e277"), true)
	ship_ready.add_theme_font_override("font", StationUi.tracked(true, 2))
	var ready_chip := StyleBoxFlat.new()
	ready_chip.bg_color = Color(Color("a7e277"), 0.1)
	ready_chip.border_color = Color("a7e277")
	ready_chip.border_width_left = 3
	ready_chip.content_margin_left = 10
	ready_chip.content_margin_right = 10
	ready_chip.content_margin_top = 2
	ready_chip.content_margin_bottom = 2
	ship_ready.add_theme_stylebox_override("normal", ready_chip)
	ship_accent = ColorRect.new()
	ship_accent.color = AMBER
	ship_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(ship_accent)
	specifications = Panel.new()
	var card := StationUi.chamfer(Color(0.035, 0.055, 0.065, 0.94), LINE, 0, 16)
	card.shadow_color = Color(0, 0, 0, 0.35)
	card.shadow_size = 16
	specifications.add_theme_stylebox_override("panel", card)
	home.add_child(specifications)
	var specs_heading := label(specifications, "SHIP SPECIFICATIONS", 14, MUTED, true)
	specs_heading.add_theme_font_override("font", StationUi.tracked(true, 3))
	specs_heading.position = Vector2(18, 13)
	var seam := ColorRect.new()
	seam.color = LINE
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	specifications.add_child(seam)
	seam.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	seam.offset_left = 18
	seam.offset_right = -18
	seam.offset_top = 42
	seam.offset_bottom = 43
	var seam_accent := ColorRect.new()
	seam_accent.color = AMBER
	seam_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seam_accent.position = Vector2(18, 41)
	seam_accent.size = Vector2(56, 3)
	specifications.add_child(seam_accent)
	for entry: Array in [["hull", "Hull"], ["shield", "Shield"], ["damage", "Damage"], ["speed", "Cruise"], ["cargo", "Cargo"]]:
		if not stat_cells.is_empty():
			var divider := ColorRect.new()
			divider.color = Color(LINE, 0.7)
			divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
			specifications.add_child(divider)
			stat_dividers.append(divider)
		var cell := Control.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		specifications.add_child(cell)
		stat_cells.append(cell)
		var artwork := icon(cell, entry[0], MUTED)
		artwork.position = Vector2(12, 18)
		artwork.size = Vector2(28, 28)
		var value := label(cell, "—", 24, INK, true)
		value.position = Vector2(50, 9)
		stat_values[entry[0]] = value
		var caption := label(cell, entry[1].to_upper(), 13, MUTED, true)
		caption.add_theme_font_override("font", StationUi.tracked(true, 2))
		caption.position = Vector2(50, 39)
	start_button = Button.new()
	start_button.text = "START  →"
	start_button.add_theme_font_override("font", StationUi.tracked(true, 6))
	start_button.add_theme_font_size_override("font_size", 52)
	start_button.add_theme_color_override("font_focus_color", Color("090e11"))
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill: Color = {"normal": AMBER, "hover": Color("ffa32b"), "pressed": Color("e97600"), "hover_pressed": Color("e97600"), "disabled": Color("5a3f25")}[state]
		var style := StationUi.chamfer(fill, fill.lightened(0.15), 18, 18)
		style.content_margin_bottom = 26
		if state != "disabled":
			style.shadow_color = Color(AMBER, 0.45 if state == "hover" else 0.22)
			style.shadow_size = 24 if state == "hover" else 14
		start_button.add_theme_stylebox_override(state, style)
		start_button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), Color("090e11"))
	start_button.add_theme_color_override("font_disabled_color", Color("1d150d"))
	var focus := StationUi.chamfer(Color.TRANSPARENT, Color("ffe1a3"), 18, 18)
	focus.set_border_width_all(2)
	start_button.add_theme_stylebox_override("focus", focus)
	start_button.pressed.connect(sector.session.launch)
	home.add_child(start_button)
	start_caption = label(start_button, "LAUNCH FROM OUTPOST 01", 14, Color("14120b"), true)
	start_caption.add_theme_font_override("font", StationUi.tracked(true, 3))
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
	sector.research_menu.hide()
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
	if not offline and page in ["shop", "hangar", "cargo", "quests", "refining", "research"] and (not sector.session.received_snapshot or sector.session.combat.inventory.is_empty()):
		return
	if not offline and page in ["shop", "hangar", "cargo", "quests"]:
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
		"research": sector.research_menu.open()
		"quests": sector.hud.toggle_contracts()
		"settings": sector.settings_menu.open()
		"connection": sector.session.open_menu()
		"gates":
			placeholder_heading.text = "GALAXY GATES"
			placeholder_icon.texture = load("res://assets/ui/menu/%s.svg" % page)
			placeholder.show()
	opening_page = false
	if not home.visible:
		navigation[page].grab_focus()


func content_rect() -> Rect2:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	return Rect2(Vector2(SIDEBAR_WIDTH, HEADER_HEIGHT) * factor, size - Vector2(SIDEBAR_WIDTH, HEADER_HEIGHT) * factor)


func page_area() -> Rect2:
	# Pages fill the content area above the shared hint bar.
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var area := content_rect()
	return Rect2(area.position + Vector2(28, 18) * factor, area.size - Vector2(56, 70) * factor)


func fit_panel(panel: Control, _preferred: Vector2) -> void:
	StationUi.set_panel_style(panel, StationUi.shell_style())
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var area := page_area()
	var minimum := panel.get_combined_minimum_size()
	var scale_factor := minf(factor, minf(area.size.x / minimum.x, area.size.y / minimum.y))
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.size = (area.size / scale_factor).max(minimum)
	panel.scale = Vector2.ONE * scale_factor
	panel.position = area.position


func layout() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	canvas.scale = Vector2.ONE * factor
	canvas.size = size / factor
	header.size = Vector2(canvas.size.x, HEADER_HEIGHT)
	brand.position = Vector2(40, 6)
	brand_slash.position = Vector2(brand.position.x + brand.get_minimum_size().x + 18, 17)
	page_name.position = Vector2(brand_slash.position.x + 34, 24)
	header_accent.position = Vector2(40, HEADER_HEIGHT - 3)
	header_accent.size = Vector2(brand.get_minimum_size().x, 3)
	var wallet_width := wallet.get_minimum_size().x
	wallet.position = Vector2(canvas.size.x - wallet_width - 40, 19)
	wallet.size = Vector2(wallet_width, 40)
	wallet_icon.position = Vector2(wallet.position.x - 30, 29)
	wallet_icon.size = Vector2(18, 18)
	wallet_chip.position = Vector2(wallet_icon.position.x - 18, 16)
	wallet_chip.size = Vector2(canvas.size.x - 20 - wallet_chip.position.x, HEADER_HEIGHT - 32)
	sidebar.position = Vector2(0, HEADER_HEIGHT)
	sidebar.size = Vector2(SIDEBAR_WIDTH, canvas.size.y - HEADER_HEIGHT)
	resume_button.visible = not sector.preflight
	resume_button.position = Vector2(18, sidebar.size.y - 124)
	sidebar_rule.position = Vector2(18, sidebar.size.y - (134 if resume_button.visible else 102))
	sidebar_rule.size = Vector2(SIDEBAR_WIDTH - 36, 1)
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
	page_scrim.position = home.position
	page_scrim.size = home.size
	page_scrim.visible = selected_page != "overview"
	hints.visible = page_scrim.visible and selected_page != "skylab"
	hints.position = Vector2(SIDEBAR_WIDTH + 28, canvas.size.y - 44)
	hints.size = Vector2(canvas.size.x - SIDEBAR_WIDTH - 56, 28)
	StationUi.set_text(hint_action, "BACK" if sector.preflight else "RESUME FLIGHT")
	var footer_y := home.size.y - 170
	ship_art.position = Vector2(home.size.x * 0.17, 140)
	ship_art.size = Vector2(home.size.x * 0.73, footer_y - 165)
	ship_shadow.position = Vector2(home.size.x * 0.24, footer_y - 115)
	ship_shadow.size = Vector2(home.size.x * 0.61, 100)
	home_shade.size = home.size
	title_shade.size = Vector2(home.size.x * 0.5, home.size.y)
	ship_title.position = Vector2(60, home.size.y * 0.25)
	ship_status.position = ship_title.position + Vector2(3, -18)
	ship_ready.position = ship_title.position + Vector2(3, 62)
	ship_accent.position = ship_title.position - Vector2(20, 14)
	ship_accent.size = Vector2(3, 104)
	var footer_width := home.size.x - 44
	var specs_width := footer_width * 0.68 - 12 if sector.preflight else footer_width
	specifications.position = Vector2(22, footer_y)
	specifications.size = Vector2(specs_width, 124)
	for i in stat_cells.size():
		var cell_width := (specs_width - 28) / stat_cells.size()
		stat_cells[i].position = Vector2(14 + i * cell_width, 51)
		stat_cells[i].size = Vector2(cell_width, 68)
		if i > 0:
			stat_dividers[i - 1].position = stat_cells[i].position + Vector2(-1, 14)
			stat_dividers[i - 1].size = Vector2(1, 40)
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
	elif sector.research_menu.visible:
		selected_page = "research"
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
		if page in ["shop", "hangar", "cargo", "quests", "refining", "research"]:
			navigation[page].disabled = not ready or (not offline and not sector.player.alive)
	StationUi.set_text(wallet, StationShop.credits_text(sector.credits) + " CR")
	var current := navigation.get(selected_page) as Button
	StationUi.set_text(page_name, current.text if current else "")
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
	for panel: Control in [placeholder, sector.shop, sector.equipment_menu, sector.resource_workshop, sector.research_menu, sector.hud.contract_panel]:
		if panel.visible:
			fit_panel(panel, Vector2(1150, 690))
