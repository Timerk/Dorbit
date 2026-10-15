class_name StationUi
extends RefCounted
## Shared station presentation. Ownership and transaction rules live in Equipment.

static var atlas: Texture2D
const AMBER := Color("ff880b")
const MUTED := Color("93a5b5")
const LINE := Color("34434b")
const SURFACE := Color("0c1217")
const FONT = preload("res://assets/ui/fonts/Rajdhani-SemiBold.ttf")
const BOLD = preload("res://assets/ui/fonts/Rajdhani-Bold.ttf")
const DEEP := Color("070b0e")
const CARD := Color(0.043, 0.067, 0.082, 0.9)
const OFFLINE_BLOCKER := "Connect to a server to use station actions."
static var offline_inventory: Dictionary = Equipment.starter()
static var cached_page_theme: Theme
static var cached: Dictionary = {}


static func offline_preview(sector: Sector) -> bool:
	return sector.session.offline_main_menu()


static func inventory(sector: Sector) -> Dictionary:
	# Display the solo starter fitting without creating an authoritative inventory.
	return offline_inventory if offline_preview(sector) else sector.session.combat.inventory


static func set_text(label: Label, content: String) -> void:
	if label.text != content:
		label.text = content


static func menu_theme() -> Theme:
	var value := Theme.new()
	value.default_font = FONT
	value.default_font_size = 18
	for type: String in ["Label", "Button", "OptionButton", "CheckButton", "LineEdit", "SpinBox", "PopupMenu", "TabContainer", "TabBar"]:
		value.set_color("font_color", type, FlightHud.INK)
		value.set_color("font_hover_color", type, FlightHud.INK)
		value.set_color("font_pressed_color", type, AMBER)
		value.set_color("font_focus_color", type, AMBER)
		value.set_color("font_disabled_color", type, Color("60717e"))
	for type: String in ["Button", "OptionButton", "CheckButton", "LineEdit"]:
		value.set_stylebox("normal", type, style(Color("111a20"), LINE))
		value.set_stylebox("hover", type, style(Color("242522"), AMBER))
		value.set_stylebox("pressed", type, style(Color("30251a"), AMBER))
		value.set_stylebox("hover_pressed", type, style(Color("30251a"), AMBER))
		value.set_stylebox("focus", type, style(Color.TRANSPARENT, AMBER))
		value.set_stylebox("disabled", type, style(Color("0e151a"), Color("253139")))
		value.set_stylebox("read_only", type, style(Color("0e151a"), LINE))
	for type: String in ["TabContainer", "TabBar"]:
		value.set_stylebox("tab_unselected", type, style(SURFACE, LINE))
		value.set_stylebox("tab_hovered", type, style(Color("242522"), AMBER))
		value.set_stylebox("tab_selected", type, style(Color("30251a"), AMBER))
		value.set_stylebox("tab_focus", type, style(Color.TRANSPARENT, AMBER))
		value.set_color("font_selected_color", type, AMBER)
		value.set_color("font_unselected_color", type, MUTED)
		value.set_constant("side_margin", type, 24)
	value.set_stylebox("panel", "TabContainer", style(SURFACE, LINE))
	value.set_stylebox("panel", "PopupMenu", style(SURFACE, LINE))
	value.set_stylebox("hover", "PopupMenu", style(Color("30251a"), AMBER))
	var track := style(Color("253139"), LINE)
	track.set_content_margin_all(3)
	value.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = AMBER
	fill.border_color = AMBER
	value.set_stylebox("grabber_area", "HSlider", fill)
	value.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var divider := StyleBoxLine.new()
	divider.color = LINE
	divider.thickness = 1
	value.set_stylebox("separator", "HSeparator", divider)
	return value


static func page_theme() -> Theme:
	# Station pages share a game-console finish; the flight HUD keeps menu_theme().
	if cached_page_theme != null:
		return cached_page_theme
	var value := menu_theme()
	var states := {
		"normal": chamfer(Color(0.067, 0.102, 0.125, 0.92), LINE, 0, 6),
		"hover": chamfer(Color("1f1e1a"), AMBER.darkened(0.3), 0, 6),
		"pressed": chamfer(Color("2e2216"), AMBER, 0, 6),
		"disabled": chamfer(Color(0.05, 0.075, 0.09, 0.8), Color("22303a"), 0, 6),
		"focus": chamfer(Color.TRANSPARENT, Color(AMBER, 0.85), 0, 6),
	}
	states["hover"].border_width_left = 3
	states["pressed"].border_width_left = 3
	states["hover_pressed"] = states["pressed"]
	for state: String in states:
		states[state].content_margin_left = 14
		states[state].content_margin_right = 14
		states[state].content_margin_top = 6
		states[state].content_margin_bottom = 6
		for type: String in ["Button", "OptionButton"]:
			value.set_stylebox(state, type, states[state])
	value.set_color("font_hover_color", "Button", Color.WHITE)
	var field := chamfer(Color(DEEP, 0.92), LINE, 0, 0)
	field.content_margin_left = 10
	field.content_margin_right = 10
	value.set_stylebox("normal", "LineEdit", field)
	value.set_stylebox("focus", "LineEdit", chamfer(Color.TRANSPARENT, AMBER, 0, 0))
	value.set_stylebox("read_only", "LineEdit", chamfer(Color(DEEP, 0.6), Color("22303a"), 0, 0))
	value.set_color("caret_color", "LineEdit", AMBER)
	value.set_color("selection_color", "LineEdit", Color(AMBER, 0.35))
	# Toggle rows read as list entries; the switch itself carries the state.
	var row := StyleBoxFlat.new()
	row.bg_color = Color.TRANSPARENT
	row.border_color = Color(LINE, 0.7)
	row.border_width_bottom = 1
	row.content_margin_left = 10
	row.content_margin_right = 10
	row.content_margin_top = 8
	row.content_margin_bottom = 8
	var row_hover := row.duplicate() as StyleBoxFlat
	row_hover.bg_color = Color(1, 1, 1, 0.04)
	row_hover.border_color = AMBER.darkened(0.3)
	for state: String in ["normal", "pressed", "disabled"]:
		value.set_stylebox(state, "CheckButton", row)
	for state: String in ["hover", "hover_pressed"]:
		value.set_stylebox(state, "CheckButton", row_hover)
	var row_focus := row.duplicate() as StyleBoxFlat
	row_focus.border_color = AMBER
	value.set_stylebox("focus", "CheckButton", row_focus)
	for state: String in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		value.set_color(state, "CheckButton", FlightHud.INK)
	value.set_icon("checked", "CheckButton", switch_icon(true, true))
	value.set_icon("unchecked", "CheckButton", switch_icon(false, true))
	value.set_icon("checked_disabled", "CheckButton", switch_icon(true, false))
	value.set_icon("unchecked_disabled", "CheckButton", switch_icon(false, false))
	# Underlined tabs, as in the shop categories and quest filters.
	for type: String in ["TabContainer", "TabBar"]:
		for state: String in ["tab_unselected", "tab_hovered", "tab_selected", "tab_focus", "tab_disabled"]:
			value.set_stylebox(state, type, tab_style(state.trim_prefix("tab_")))
		value.set_font("font", type, tracked(true, 2))
		value.set_font_size("font_size", type, 17)
		value.set_color("font_hovered_color", type, FlightHud.INK)
		value.set_constant("side_margin", type, 0)
	var tab_panel := chamfer(CARD, LINE, 0, 10)
	tab_panel.border_width_top = 0
	value.set_stylebox("panel", "TabContainer", tab_panel)
	var popup := chamfer(Color(SURFACE, 0.98), LINE, 0, 0)
	popup.content_margin_top = 4
	popup.content_margin_bottom = 4
	value.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := chamfer(Color("2e2216"), AMBER, 0, 0)
	popup_hover.set_border_width_all(0)
	popup_hover.border_width_left = 3
	value.set_stylebox("hover", "PopupMenu", popup_hover)
	value.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	value.set_constant("v_separation", "PopupMenu", 10)
	var tip := chamfer(Color(SURFACE, 0.97), LINE, 0, 0)
	tip.border_width_left = 3
	tip.border_color = LINE
	tip.content_margin_left = 12
	tip.content_margin_right = 12
	tip.content_margin_top = 6
	tip.content_margin_bottom = 6
	value.set_stylebox("panel", "TooltipPanel", tip)
	value.set_color("font_color", "TooltipLabel", FlightHud.INK)
	value.set_font_size("font_size", "TooltipLabel", 16)
	# Slim sliders and scrollbars instead of engine defaults.
	var track := StyleBoxFlat.new()
	track.bg_color = Color("1c272e")
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	value.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = AMBER
	value.set_stylebox("grabber_area", "HSlider", fill)
	value.set_stylebox("grabber_area_highlight", "HSlider", fill)
	value.set_icon("grabber", "HSlider", bar_icon(AMBER))
	value.set_icon("grabber_highlight", "HSlider", bar_icon(Color("ffb35c")))
	value.set_icon("grabber_disabled", "HSlider", bar_icon(MUTED))
	for type: String in ["VScrollBar", "HScrollBar"]:
		var gutter := StyleBoxFlat.new()
		gutter.bg_color = Color(1, 1, 1, 0.03)
		for side: String in (["left", "right"] if type == "VScrollBar" else ["top", "bottom"]):
			gutter.set("content_margin_" + side, 3)
		value.set_stylebox("scroll", type, gutter)
		value.set_stylebox("scroll_focus", type, gutter)
		for entry: Array in [["grabber", LINE.lightened(0.2)], ["grabber_highlight", MUTED], ["grabber_pressed", AMBER]]:
			var thumb := StyleBoxFlat.new()
			thumb.bg_color = entry[1]
			thumb.set_corner_radius_all(3)
			value.set_stylebox(entry[0], type, thumb)
	var progress := StyleBoxFlat.new()
	progress.bg_color = Color("1c272e")
	value.set_stylebox("background", "ProgressBar", progress)
	var progress_fill := progress.duplicate() as StyleBoxFlat
	progress_fill.bg_color = AMBER
	value.set_stylebox("fill", "ProgressBar", progress_fill)
	cached_page_theme = value
	return value


static func chamfer(background: Color, border: Color, cut_top_left: int = 0, cut_bottom_right: int = 10) -> StyleBoxFlat:
	# A single corner segment draws a straight bevel.
	var value := style(background, border)
	value.set_corner_radius_all(0)
	value.corner_radius_top_left = cut_top_left
	value.corner_radius_bottom_right = cut_bottom_right
	value.corner_detail = 1
	return value


static func tab_style(state: String) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = {"selected": Color(AMBER, 0.1), "hovered": Color(1, 1, 1, 0.04), "pressed": Color(AMBER, 0.1)}.get(state, Color.TRANSPARENT)
	value.border_color = {"selected": AMBER, "pressed": AMBER, "hovered": MUTED, "focus": Color(AMBER, 0.6), "disabled": Color("22303a")}.get(state, LINE)
	value.border_width_bottom = 3 if state in ["selected", "pressed", "focus"] else 2
	value.content_margin_left = 18
	value.content_margin_right = 18
	value.content_margin_top = 8
	value.content_margin_bottom = 8
	return value


static func tab(button: Button) -> void:
	# Toggle buttons used as page filters read as underlined tabs.
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, tab_style({"hover": "hovered", "hover_pressed": "pressed"}.get(state, state)))
	button.add_theme_font_override("font", tracked(true, 2))
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_hover_color", FlightHud.INK)
	button.add_theme_color_override("font_focus_color", FlightHud.INK)
	button.add_theme_color_override("font_pressed_color", AMBER)
	button.add_theme_color_override("font_hover_pressed_color", AMBER)
	button.text = button.text.to_upper()
	if button.get_parent() is BoxContainer:
		button.get_parent().add_theme_constant_override("separation", 0)


static func tracked(bold: bool = true, spacing: int = 2) -> FontVariation:
	var key := "font:%s:%d" % [bold, spacing]
	if not cached.has(key):
		var value := FontVariation.new()
		value.base_font = BOLD if bold else FONT
		value.spacing_glyph = spacing
		cached[key] = value
	return cached[key]


static func switch_icon(on: bool, enabled: bool) -> ImageTexture:
	var width := 44
	var height := 22
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var radius := height / 2.0
	var edge := AMBER if on else LINE.lightened(0.2)
	var groove := Color("4a2b0c") if on else Color("141d23")
	var knob := AMBER if on else MUTED
	var knob_center := Vector2(width - radius if on else radius, radius)
	for y in height:
		for x in width:
			var point := Vector2(x + 0.5, y + 0.5)
			var distance := point.distance_to(Vector2(clampf(point.x, radius, width - radius), radius))
			var color := edge.lerp(groove, clampf(radius - 1.5 - distance + 0.5, 0, 1))
			color = color.lerp(knob, clampf(radius - 4.5 - point.distance_to(knob_center) + 0.5, 0, 1))
			color.a = clampf(radius - distance + 0.5, 0, 1) * (1.0 if enabled else 0.45)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func bar_icon(color: Color) -> ImageTexture:
	var image := Image.create_empty(10, 22, false, Image.FORMAT_RGBA8)
	image.fill(color)
	image.fill_rect(Rect2i(4, 6, 2, 10), color.darkened(0.45))
	return ImageTexture.create_from_image(image)


static func primary(button: Button) -> void:
	var fills := {"normal": AMBER, "hover": Color("ffa32b"), "pressed": Color("e97600"), "hover_pressed": Color("e97600")}
	for state: String in fills:
		var value := chamfer(fills[state], fills[state].lightened(0.15), 0, 12)
		if state == "hover":
			value.shadow_color = Color(AMBER, 0.35)
			value.shadow_size = 10
		button.add_theme_stylebox_override(state, value)
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), SURFACE)
	button.add_theme_stylebox_override("disabled", chamfer(Color(AMBER, 0.07), Color(AMBER, 0.3), 0, 12))
	button.add_theme_color_override("font_disabled_color", Color(AMBER, 0.45))
	button.add_theme_stylebox_override("focus", chamfer(Color.TRANSPARENT, Color("ffe1a3"), 0, 12))
	button.add_theme_color_override("font_focus_color", SURFACE)
	button.add_theme_font_override("font", tracked(true, 2))
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 22)


static func window_style() -> StyleBoxFlat:
	if not cached.has("window"):
		var value := chamfer(Color(0.047, 0.071, 0.09, 0.97), LINE, 14, 14)
		value.border_width_top = 2
		value.border_color = LINE
		value.shadow_color = Color(0, 0, 0, 0.5)
		value.shadow_size = 28
		cached["window"] = value
	return cached["window"]


static func shell_style() -> StyleBox:
	# Inside the docked console, pages sit directly on the shared backdrop.
	if not cached.has("shell"):
		var value := StyleBoxEmpty.new()
		value.set_content_margin_all(8)
		cached["shell"] = value
	return cached["shell"]


static func set_panel_style(panel: Control, value: StyleBox) -> void:
	if panel.get_theme_stylebox("panel") != value:
		panel.add_theme_stylebox_override("panel", value)


static func header(parent: Node, title: String, kicker: String, title_size: int = 40) -> Label:
	# Breadcrumb, title and accent rule shared by every station page.
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 0)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(row)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -6)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(titles)
	var crumb := text(titles, kicker, 14, AMBER)
	crumb.add_theme_font_override("font", tracked(true, 4))
	crumb.autowrap_mode = TextServer.AUTOWRAP_OFF
	crumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crumb.visible = not kicker.is_empty()
	var heading := text(titles, title, title_size)
	heading.add_theme_font_override("font", tracked(true, 3))
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := Control.new()
	line.custom_minimum_size.y = 12
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func():
		line.draw_rect(Rect2(0, 6, line.size.x, 1), LINE)
		line.draw_rect(Rect2(0, 5, 72, 3), AMBER)
		line.draw_rect(Rect2(78, 5, 6, 3), Color(AMBER, 0.5)))
	block.add_child(line)
	return heading


static func list_entry(button: Button, secondary: bool = false, font_size: int = 19) -> void:
	# Left-aligned menu list entries with an amber accent on hover and focus.
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", tracked(true, 2))
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", MUTED if secondary else FlightHud.INK)
	for state: String in ["normal", "hover", "focus", "pressed", "hover_pressed"]:
		var key := "entry:%s:%d" % [state, font_size]
		if not cached.has(key):
			var value := StyleBoxFlat.new()
			value.bg_color = Color(AMBER, 0.12) if state != "normal" else Color.TRANSPARENT
			value.border_color = AMBER if state != "normal" else Color(LINE, 0.6)
			value.border_width_left = 4 if state != "normal" else 0
			value.border_width_bottom = 1 if state == "normal" else 0
			value.content_margin_left = 18 if font_size > 17 else 12
			value.content_margin_right = value.content_margin_left
			cached[key] = value
		button.add_theme_stylebox_override(state, cached[key])
	for state: String in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, Color.WHITE)


static func header_row(title: Label) -> HBoxContainer:
	# Pages may place summaries to the right of their header title.
	return title.get_parent().get_parent() as HBoxContainer


static func heading(parent: Node, content: String, font_size: int = 17, color: Color = FlightHud.INK) -> Label:
	var value := text(parent, content, font_size, color)
	value.add_theme_font_override("font", tracked(true, 2))
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	return value


static func frame(panel: Control, dimensions: Vector2) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -dimensions.x / 2
	panel.offset_right = dimensions.x / 2
	panel.offset_top = -dimensions.y / 2
	panel.offset_bottom = dimensions.y / 2
	panel.theme = page_theme()
	panel.add_theme_stylebox_override("panel", window_style())
	panel.add_theme_color_override("font_color", FlightHud.INK)


static func centered(panel: Control, preferred: Vector2) -> void:
	set_panel_style(panel, window_style())
	var dimensions := preferred.max(panel.get_combined_minimum_size())
	var viewport_size := panel.get_viewport_rect().size
	var area := viewport_size - Vector2(32, 32)
	var factor := minf(1.0, minf(area.x / dimensions.x, area.y / dimensions.y))
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.size = dimensions
	panel.scale = Vector2.ONE * factor
	panel.position = (viewport_size - dimensions * factor) / 2


static func style(background: Color, border: Color) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = background
	value.border_color = border
	value.set_border_width_all(1)
	value.set_corner_radius_all(2)
	value.set_content_margin_all(8)
	return value


static func rows(parent: Node, padding: int = 16) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, padding)
	parent.add_child(margin)
	var value := VBoxContainer.new()
	value.add_theme_constant_override("separation", 8)
	margin.add_child(value)
	return value


static func card(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	if not cached.has("card"):
		var surface := chamfer(CARD, LINE, 0, 12)
		surface.set_content_margin_all(0)
		cached["card"] = surface
	panel.add_theme_stylebox_override("panel", cached["card"])
	parent.add_child(panel)
	return panel


static func text(parent: Node, content: String, font_size: int = 14, color: Color = FlightHud.INK) -> Label:
	var value := Label.new()
	value.text = content
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", color)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(value)
	return value


static func button(parent: Node, content: String, action: Callable) -> Button:
	var value := Button.new()
	value.text = content
	value.custom_minimum_size.y = 34
	value.add_theme_font_size_override("font_size", 18)
	value.pressed.connect(action)
	parent.add_child(value)
	return value


static func texture(model: String) -> Texture2D:
	if Ammunition.ROCKETS.has(model) or model in ["hst-1", "hst-2"]:
		return load("res://assets/ui/rockets/%s.png" % model)
	if Equipment.MODELS.has(model) and Equipment.MODELS[model]["kind"] == "extra":
		return load("res://assets/ui/extras/%s.png" % model)
	if Ammunition.TYPES.has(model):
		return load("res://assets/ui/ammo/%s.png" % model)
	if model == "ship" or ShipCatalog.MODELS.has(model):
		return load("res://assets/ui/ships/%s.png" % ("liberator" if model == "ship" else model))
	if atlas == null:
		atlas = load("res://assets/ui/equipment-atlas.png")
	var value := AtlasTexture.new()
	value.atlas = atlas
	var group := Equipment.category(model) if Equipment.MODELS.has(model) else model
	var index: int = {"weapons": 0, "laser": 0, "shields": 1, "shield": 1, "engines": 2, "engine": 2, "ship": 3}.get(group, 0)
	var cell := atlas.get_size() / 2
	value.region = Rect2(Vector2(index % 2, index / 2) * cell, cell)
	return value


static func art(parent: Node, model: String, minimum: Vector2) -> TextureRect:
	var value := TextureRect.new()
	value.texture = texture(model)
	value.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	value.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	value.custom_minimum_size = minimum
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(value)
	return value


static func bonus(model: String) -> String:
	var info: Dictionary = Equipment.MODELS[model]
	if info["kind"] == "launcher":
		return "%d rockets / volley\n1 second / load\n3 seconds / reload cooldown" % info["capacity"]
	if info["kind"] == "extra":
		return {"rep-1": "Hull repair / 165 s", "rep-2": "Hull repair / 120 s", "repair-auto": "Automatic repair / requires robot", "cargo-expander": "Cargo capacity x2", "slot-cpu-1": "+2 extra slots", "ammo-cpu": "Auto-buy 10,000 configured rounds", "generator-cpu": "Automatic shield & engine boosts"}[model]
	if info["kind"] == "laser":
		return "+%d damage / shot" % info["damage"] + ("\n+%d%% damage against aliens" % roundi(info["npc_bonus"] * 100) if info.has("npc_bonus") else "")
	if info["shield"] > 0.0:
		return "+%d shield / %d%% absorption" % [info["shield"], roundi(info["absorption"] * 100)] + ("\n+%.2f%% shield regeneration" % (info["regen_bonus"] * 100) if info.has("regen_bonus") else "")
	return "+%d m/s cruise & boost" % info["speed"]


static func accent(model: String) -> Color:
	var group := Equipment.category(model)
	return Color("f4c778") if group == "weapons" else (FlightHud.CYAN if group == "shields" else Color("9aafff"))


static func can_open(sector: Sector, station_required: bool = true) -> bool:
	if offline_preview(sector):
		return true
	if not sector.session.active or sector.session.combat.inventory.is_empty():
		sector.notify("Equipment is available on a persistent dedicated server.")
		return false
	var reason := sector.repair_blocker() if station_required else ("" if sector.player.alive else "Wait for rescue.")
	if not reason.is_empty():
		sector.notify(reason)
		return false
	return true


static func blocker(sector: Sector, station_required: bool = true) -> String:
	if offline_preview(sector):
		return OFFLINE_BLOCKER
	if sector.session.combat.station_pending:
		return "Waiting for server..."
	return sector.repair_blocker() if station_required else ("" if sector.player.alive else "Wait for rescue.")
