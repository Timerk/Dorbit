class_name AmmoBar
extends HBoxContainer
## One horizontal HUD instrument; its tiles always move and scale together.

var sector: Sector
var buttons: Dictionary[String, Button] = {}
var counts: Dictionary[String, Label] = {}


func _ready() -> void:
	name = "AmmoBar"
	add_theme_constant_override("separation", 5)
	for kind: String in Ammunition.TYPES:
		var color: Color = Ammunition.TYPES[kind]["color"]
		var button := Button.new()
		button.custom_minimum_size = Vector2(66, 80)
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var selected := state in ["pressed", "hover_pressed"]
			var style := StationUi.style(Color("172b3b") if selected else Color("0c141e"), FlightHud.AMBER if selected else Color("4b657b"))
			style.set_content_margin_all(4)
			style.set_border_width_all(2 if selected else 1)
			button.add_theme_stylebox_override(state, style)
		add_child(button)
		button.pressed.connect(func(): sector.session.combat.request_ammo(kind))
		buttons[kind] = button
		var rows := VBoxContainer.new()
		button.add_child(rows)
		rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rows.offset_left = 5
		rows.offset_right = -5
		rows.offset_top = 3
		rows.offset_bottom = -3
		rows.add_theme_constant_override("separation", 0)
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var header := HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(header)
		var key := StationUi.text(header, kind.trim_prefix("x"), 13, FlightHud.MUTED)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.autowrap_mode = TextServer.AUTOWRAP_OFF
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := StationUi.text(header, kind, 17, color)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var art := StationUi.art(rows, kind, Vector2(0, 32))
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var count := StationUi.text(rows, "", 15, FlightHud.INK)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		counts[kind] = count


func default_rect() -> Rect2:
	var dimensions := get_combined_minimum_size()
	var viewport := get_viewport_rect().size
	return Rect2(Vector2((viewport.x - dimensions.x) * 0.5, viewport.y - FlightHud.BOTTOM_MARGIN - dimensions.y), dimensions)


func _process(_delta: float) -> void:
	var layout := sector.hud.layout
	visible = not sector.preflight and (not sector.paused or layout.editing) and sector.player.alive and (not sector.client_only or sector.session.active) and layout.shown("ammo")
	if not visible:
		return
	var rect := layout.rect_for("ammo")
	size = default_rect().size
	position = rect.position
	scale = Vector2.ONE * (rect.size.x / size.x)
	for kind: String in buttons:
		buttons[kind].disabled = layout.editing
		var amount := int(sector.player.ammo[kind])
		buttons[kind].set_pressed_no_signal(sector.player.ammo_type == kind)
		counts[kind].text = StationShop.credits_text(amount) if amount < 1000000 else ("%.1fM" % (amount / 1000000.0) if amount < 1000000000 else "%.1fB" % (amount / 1000000000.0))
		counts[kind].add_theme_color_override("font_color", FlightHud.INK if amount > 0 and amount >= sector.player.laser_count else FlightHud.RED)
		buttons[kind].tooltip_text = "%s / %dx laser damage / %s shots\n%d rounds per volley (%d installed lasers)\nPress %s or click to select.%s" % [kind, Ammunition.TYPES[kind]["multiplier"], StationShop.credits_text(amount), sector.player.laser_count, sector.player.laser_count, kind.trim_prefix("x"), "\nReserved for future quests and special rewards." if kind == "x4" else "\nBuy at Outpost 01 in batches of 100."]
