class_name StationUi
extends RefCounted
## Shared station presentation. Ownership and transaction rules live in Equipment.

static var atlas: Texture2D
const AMBER := Color("ff880b")
const MUTED := Color("93a5b5")
const LINE := Color("34434b")
const SURFACE := Color("0c1217")
const FONT = preload("res://assets/ui/fonts/Rajdhani-SemiBold.ttf")


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


static func primary(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, style(AMBER.lightened(0.12) if state == "hover" else AMBER, AMBER))
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), SURFACE)
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 24)


static func ship_texture(model: String) -> Texture2D:
	var source: Texture2D = load("res://assets/ui/menu/ships/%s.png" % model)
	var value := AtlasTexture.new()
	value.atlas = source
	value.region = source.get_image().get_used_rect()
	return value


static func frame(panel: Control, dimensions: Vector2) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -dimensions.x / 2
	panel.offset_right = dimensions.x / 2
	panel.offset_top = -dimensions.y / 2
	panel.offset_bottom = dimensions.y / 2
	panel.theme = menu_theme()
	panel.add_theme_stylebox_override("panel", style(SURFACE, LINE))
	panel.add_theme_color_override("font_color", FlightHud.INK)


static func centered(panel: Control, preferred: Vector2) -> void:
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
	var surface := style(Color("0b1115"), LINE)
	surface.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", surface)
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


static func navigation(parent: Node, sector: Sector, current: String, close: Callable) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	parent.add_child(bar)
	button(bar, "Station shop [B]", sector.shop.open).disabled = current == "shop"
	button(bar, "Ship equipment [I]", sector.equipment_menu.open).disabled = current == "equipment"
	button(bar, "Contracts [C]", sector.hud.toggle_contracts)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	button(bar, "Back [Esc]", close)
	return bar


static func texture(model: String) -> Texture2D:
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
	if info["kind"] == "laser":
		return "+%d damage / shot" % info["damage"] + ("\n+%d%% damage against aliens" % roundi(info["npc_bonus"] * 100) if info.has("npc_bonus") else "")
	if info["shield"] > 0.0:
		return "+%d shield / %d%% absorption" % [info["shield"], roundi(info["absorption"] * 100)] + ("\n+%.2f%% shield regeneration" % (info["regen_bonus"] * 100) if info.has("regen_bonus") else "")
	return "+%d m/s cruise & boost" % info["speed"]


static func accent(model: String) -> Color:
	var group := Equipment.category(model)
	return Color("f4c778") if group == "weapons" else (FlightHud.CYAN if group == "shields" else Color("9aafff"))


static func can_open(sector: Sector) -> bool:
	if not sector.session.active or sector.session.combat.inventory.is_empty():
		sector.notify("Equipment is available on a persistent dedicated server.")
		return false
	var reason := sector.repair_blocker()
	if not reason.is_empty():
		sector.notify(reason)
		return false
	return true


static func blocker(sector: Sector) -> String:
	return "Waiting for server..." if sector.session.combat.station_pending else sector.repair_blocker()
