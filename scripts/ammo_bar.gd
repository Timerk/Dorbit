class_name AmmoBar
extends HBoxContainer
## One horizontal HUD instrument; its tiles always move and scale together.

var sector: Sector
var buttons: Dictionary[String, Button] = {}
var counts: Dictionary[String, Label] = {}
var single_fire: Button
var launcher_fire: Button
var unload_button: Button
var launcher_art_capacity: int = -1


func _ready() -> void:
	name = "AmmoBar"
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
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
	for kind: String in Ammunition.ROCKETS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(60, 80)
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func(): sector.session.combat.request_ammo(kind))
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			button.add_theme_stylebox_override(state, StationUi.style(Color("172b3b") if state in ["pressed", "hover_pressed"] else Color("0c141e"), FlightHud.AMBER if state in ["pressed", "hover_pressed"] else Color("4b657b")))
		add_child(button)
		buttons[kind] = button
		var rows := VBoxContainer.new()
		button.add_child(rows)
		rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rows.offset_left = 2
		rows.offset_right = -2
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_theme_constant_override("separation", 0)
		var title := StationUi.text(rows, Ammunition.ROCKETS[kind]["name"], 12, FlightHud.AMBER if Ammunition.ROCKETS[kind]["launcher"] else FlightHud.CYAN)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		var art := StationUi.art(rows, kind, Vector2(0, 32))
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var count := StationUi.text(rows, "", 14, FlightHud.INK)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		counts[kind] = count
	single_fire = StationUi.button(self, "FIRE ROCKET", func(): sector.session.combat.request_rocket("single"))
	single_fire.custom_minimum_size = Vector2(90, 80)
	single_fire.focus_mode = Control.FOCUS_NONE
	single_fire.add_theme_font_size_override("font_size", 13)
	var launcher_rows := VBoxContainer.new()
	launcher_rows.add_theme_constant_override("separation", 0)
	add_child(launcher_rows)
	launcher_fire = StationUi.button(launcher_rows, "HELLSTORM", func(): sector.session.combat.request_rocket("launcher"))
	launcher_fire.custom_minimum_size = Vector2(96, 56)
	launcher_fire.focus_mode = Control.FOCUS_NONE
	launcher_fire.add_theme_font_size_override("font_size", 12)
	launcher_fire.expand_icon = true
	launcher_fire.add_theme_constant_override("icon_max_width", 24)
	unload_button = StationUi.button(launcher_rows, "UNLOAD", func(): sector.session.combat.request_rocket("unload"))
	unload_button.custom_minimum_size.y = 24
	unload_button.focus_mode = Control.FOCUS_NONE
	unload_button.add_theme_font_size_override("font_size", 12)
	get_parent().resized.connect(update_geometry)
	minimum_size_changed.connect(update_geometry)


func default_rect() -> Rect2:
	var dimensions := get_combined_minimum_size()
	var hud_size: Vector2 = get_parent().size
	return Rect2(Vector2((hud_size.x - dimensions.x) * 0.5, hud_size.y - FlightHud.BOTTOM_MARGIN - 182 - dimensions.y), dimensions)


func update_geometry() -> void:
	if not is_instance_valid(sector.hud) or not is_instance_valid(sector.hud.layout):
		return
	var rect := sector.hud.layout.rect_for("ammo")
	size = default_rect().size
	position = rect.position
	scale = Vector2.ONE * (rect.size.x / size.x)


func _process(_delta: float) -> void:
	var layout := sector.hud.layout
	visible = not sector.preflight and (not sector.paused or layout.editing) and sector.player.alive and (not sector.client_only or sector.session.active) and layout.shown("ammo")
	if not visible:
		return
	for kind: String in buttons:
		buttons[kind].disabled = layout.editing
	single_fire.disabled = layout.editing
	launcher_fire.disabled = layout.editing
	for kind: String in Ammunition.TYPES:
		var amount := int(sector.player.ammo[kind])
		buttons[kind].set_pressed_no_signal(sector.player.ammo_type == kind)
		counts[kind].text = StationShop.credits_text(amount) if amount < 1000000 else ("%.1fM" % (amount / 1000000.0) if amount < 1000000000 else "%.1fB" % (amount / 1000000000.0))
		counts[kind].add_theme_color_override("font_color", FlightHud.INK if amount > 0 and amount >= sector.player.laser_count else FlightHud.RED)
		buttons[kind].tooltip_text = "%s / %dx laser damage / %s shots\n%d rounds per volley (%d installed lasers)\nPress %s or click to select.%s" % [kind, Ammunition.TYPES[kind]["multiplier"], StationShop.credits_text(amount), sector.player.laser_count, sector.player.laser_count, kind.trim_prefix("x"), "\nReserved for future quests and special rewards." if kind == "x4" else "\nBuy at Outpost 01 in batches of 100."]
	var rockets := sector.player.rockets
	if launcher_art_capacity != rockets.capacity:
		launcher_art_capacity = rockets.capacity
		launcher_fire.icon = StationUi.texture("hst-2" if rockets.capacity == 5 else "hst-1") if rockets.capacity > 0 else null
	for kind: String in Ammunition.ROCKETS:
		var amount := rockets.available(kind)
		buttons[kind].set_pressed_no_signal(kind == rockets.single_type or kind == rockets.launcher_type)
		counts[kind].text = StationShop.credits_text(amount) if amount < 1000000 else "%.1fM" % (amount / 1000000.0)
		counts[kind].add_theme_color_override("font_color", FlightHud.INK if amount > 0 else FlightHud.RED)
		buttons[kind].tooltip_text = "%s\n%s\n%s available / click to select" % [Ammunition.ROCKETS[kind]["name"], StationShop.ammo_description(kind), StationShop.credits_text(amount)]
	single_fire.text = "%s / ROCKET\n%s" % [GameSettings.binding_text("rocket"), "%.1fs" % rockets.single_cooldown if rockets.single_cooldown > 0 else "FIRE"]
	single_fire.tooltip_text = "Fire one selected rocket at your target. Independent of laser fire."
	var dots := ""
	for index in range(rockets.capacity):
		dots += "●" if index < rockets.loaded else "○"
	var status := "%.1fs COOLDOWN" % rockets.launcher_cooldown if rockets.launcher_cooldown > 0 else ("%.1fs LOAD" % maxf(0, rockets.load_clock) if rockets.loading else ("FIRE %d" % rockets.loaded if rockets.loaded > 0 else "LOAD"))
	launcher_fire.text = "%s / HST\n%s\n%s" % [GameSettings.binding_text("launcher"), dots if rockets.capacity > 0 else "NO LAUNCHER", status]
	launcher_fire.tooltip_text = "Load without a target; activate again to fire all loaded rockets, including a partial volley."
	unload_button.disabled = layout.editing or (rockets.loaded == 0 and not rockets.loading)
	update_geometry()
