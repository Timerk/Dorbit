class_name StationUi
extends RefCounted
## Shared station presentation. Ownership and transaction rules live in Equipment.

static var atlas: Texture2D


static func frame(panel: Control, dimensions: Vector2) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -dimensions.x / 2
	panel.offset_right = dimensions.x / 2
	panel.offset_top = -dimensions.y / 2
	panel.offset_bottom = dimensions.y / 2
	panel.add_theme_stylebox_override("panel", style(Color("0c1929"), Color("31516c")))
	panel.add_theme_color_override("font_color", FlightHud.INK)


static func style(background: Color, border: Color) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = background
	value.border_color = border
	value.set_border_width_all(1)
	value.set_corner_radius_all(5)
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
	panel.add_theme_stylebox_override("panel", style(Color("091522"), Color("263e53")))
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
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_stylebox_override("normal", style(Color("172c40"), Color("385b76")))
	value.add_theme_stylebox_override("hover", style(Color("20455b"), FlightHud.CYAN))
	value.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), FlightHud.CYAN))
	value.pressed.connect(action)
	parent.add_child(value)
	return value


static func navigation(parent: Node, sector: Sector, current: String, close: Callable) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	parent.add_child(bar)
	button(bar, "Station shop [B]", sector.shop.open).disabled = current == "shop"
	button(bar, "Ship equipment [I]", sector.equipment_menu.open).disabled = current == "equipment"
	button(bar, "Contracts [C]", sector.hud.toggle_contracts)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	button(bar, "Back to flight [Esc]", close)


static func texture(model: String) -> Texture2D:
	if model == "ship" or ShipCatalog.MODELS.has(model):
		return load("res://assets/ui/ships/%s.png" % ("liberator" if model == "ship" else model))
	if atlas == null:
		atlas = load("res://assets/ui/equipment-atlas.png")
	var value := AtlasTexture.new()
	value.atlas = atlas
	var index: int = {"laser": 0, "shield": 1, "engine": 2, "ship": 3}.get(model, 0)
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
	if model == "laser":
		return "+%d damage / shot" % info["damage"]
	if model == "shield":
		return "+%d shield / %d%% absorption" % [info["shield"], roundi(info["absorption"] * 100)]
	return "+%d m/s cruise & boost" % info["speed"]


static func accent(model: String) -> Color:
	return Color("f4c778") if model == "laser" else (FlightHud.CYAN if model == "shield" else Color("9aafff"))


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
