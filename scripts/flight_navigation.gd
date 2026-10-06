class_name FlightNavigation
extends Control
## Presentation-only navigation. Target selection still uses normal authoritative combat rules.

const RANGES: Array[float] = [250.0, 500.0, 1000.0, 2400.0]
var sector: Sector
var range_index: int = 1
var waypoint_key := "station"
var last_target: SpaceShip
var overview: PanelContainer
var overview_shared: bool = false
var plot: SectorPlot
var contact_list: VBoxContainer
var contact_buttons: Dictionary[String, Button] = {}
var range_less: Button
var range_more: Button
var map_button: Button
var view_yaw: float = -0.55
var font: Font = ThemeDB.fallback_font
var info: Label


class SectorPlot extends Control:
	var navigation: FlightNavigation

	func _draw() -> void:
		navigation.draw_sector(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			navigation.pick_contact(event.position)
			accept_event()
		elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			navigation.view_yaw += event.relative.x * 0.008
			queue_redraw()
			accept_event()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	range_less = StationUi.button(self, "-", func(): change_range(-1))
	range_more = StationUi.button(self, "+", func(): change_range(1))
	map_button = StationUi.button(self, "Map [M]", open_overview)
	for button in [range_less, range_more, map_button]:
		button.focus_mode = Control.FOCUS_NONE
	build_overview()


func contacts() -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"key": "station", "name": "Outpost 01", "position": Sector.STATION_POSITION, "color": FlightHud.GREEN, "ship": null}]
	for enemy: Alien in sector.aliens.values():
		if enemy.alive and enemy.visible:
			result.append({"key": "alien%d" % enemy.alien_id, "name": "%s %d" % [enemy.kind, enemy.alien_id + 1], "position": enemy.position, "color": enemy.tuning()["color"], "ship": enemy})
	if sector.session.active:
		for id: int in sector.session.ships:
			var ship := sector.session.ships[id]
			if ship != sector.player and ship.alive:
				result.append({"key": "friend%d" % id, "name": "Pilot %d" % id, "position": ship.position, "color": FlightHud.CYAN, "ship": ship})
	return result


func sync_waypoint() -> void:
	if sector.target != last_target:
		if sector.target is Alien and sector.target.alive:
			waypoint_key = "alien%d" % sector.target.alien_id
		elif waypoint_key.begins_with("alien"):
			waypoint_key = "station"
		last_target = sector.target
	if not contacts().any(func(contact: Dictionary): return contact["key"] == waypoint_key):
		waypoint_key = "station"


func destination() -> Dictionary:
	if sector.player.position.length() > Sector.MAP_RADIUS:
		return {"key": "safe", "name": "Safe space", "position": sector.player.position.normalized() * (Sector.MAP_RADIUS - 50), "color": FlightHud.RED, "ship": null}
	for contact in contacts():
		if contact["key"] == waypoint_key:
			return contact
	return contacts()[0]


func choose_contact(key: String) -> void:
	for contact in contacts():
		if contact["key"] != key:
			continue
		sector.select_target(contact["ship"] if contact["ship"] is Alien else null)
		last_target = sector.target
		waypoint_key = key
		close_overview()
		return


func change_range(step: int) -> void:
	range_index = clampi(range_index + step, 0, RANGES.size() - 1)
	queue_redraw()


static func relative_position(pilot_transform: Transform3D, location: Vector3) -> Vector3:
	return pilot_transform.basis.inverse() * (location - pilot_transform.origin)


static func compass_point(relative: Vector3) -> Vector2:
	if relative.length_squared() < 0.01:
		return Vector2.ZERO
	var direction := relative.normalized()
	var bearing := Vector2(direction.x, -direction.y)
	if bearing.length_squared() < 0.00001:
		return Vector2.DOWN if direction.z > 0 else Vector2.ZERO
	var angle := acos(clampf(-direction.z, -1, 1))
	return bearing.normalized() * minf(angle / (PI * 0.5), 1.0)


static func turn_hint(relative: Vector3) -> String:
	var direction := relative.normalized()
	if direction.z > 0:
		return "TURN AROUND / BEHIND"
	var parts: Array[String] = []
	if absf(direction.x) > 0.08:
		parts.append("RIGHT" if direction.x > 0 else "LEFT")
	if absf(direction.y) > 0.08:
		parts.append("UP" if direction.y > 0 else "DOWN")
	return "TURN " + " + ".join(parts) if not parts.is_empty() else "ALIGNED / FLY FORWARD"


func build_overview() -> void:
	overview = PanelContainer.new()
	StationUi.frame(overview, Vector2(880, 550))
	add_child(overview)
	var rows := StationUi.rows(overview, 8)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := StationUi.text(header, "SECTOR OVERVIEW / OUTPOST 01", 20, FlightHud.CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	StationUi.button(header, "Back to flight [M / Esc]", close_overview)
	StationUi.text(rows, "Choose a destination. Click a contact or its row; drag right mouse on the map to rotate.", 13, FlightHud.MUTED)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	var sidebar := StationUi.card(body)
	sidebar.custom_minimum_size.x = 230
	var left := StationUi.rows(sidebar, 4)
	StationUi.text(left, "CONTACTS / SET WAYPOINT", 12, FlightHud.CYAN)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	contact_list = VBoxContainer.new()
	contact_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(contact_list)
	plot = SectorPlot.new()
	plot.navigation = self
	plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot.custom_minimum_size = Vector2(550, 360)
	plot.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(plot)
	info = StationUi.text(rows, "", 13, FlightHud.INK)
	StationUi.text(rows, "White: you   Green: outpost   Colored: aliens   Cyan: pilots   Vertical lines show height", 12, FlightHud.MUTED)
	overview.hide()


func open_overview() -> void:
	if sector.paused or not sector.player.alive or (sector.client_only and not sector.session.active):
		return
	sector.set_paused(true)
	overview_shared = sector.session.active
	overview.show()
	update_contacts()
	plot.queue_redraw()


func close_overview(resume: bool = true) -> void:
	if not overview.visible:
		return
	overview.hide()
	if resume:
		sector.set_paused(false)


func update_contacts() -> void:
	var current := contacts()
	for key: String in contact_buttons.keys():
		if not current.any(func(contact: Dictionary): return contact["key"] == key):
			contact_buttons[key].queue_free()
			contact_buttons.erase(key)
	for contact in current:
		var key: String = contact["key"]
		if not contact_buttons.has(key):
			var button := StationUi.button(contact_list, "", func(): choose_contact(key))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.toggle_mode = true
			button.add_theme_color_override("font_color", contact["color"])
			contact_buttons[key] = button
		var distance := sector.player.position.distance_to(contact["position"])
		contact_buttons[key].text = "%s / %.0f m" % [contact["name"], distance]
		contact_buttons[key].set_pressed_no_signal(key == waypoint_key)
	var selected := destination()
	info.text = "Waypoint: %s / %.0f m%s" % [selected["name"], sector.player.position.distance_to(selected["position"]), " / RADIATION: return to safety first" if selected["key"] == "safe" else ""]
	info.add_theme_color_override("font_color", selected["color"])


func _process(_delta: float) -> void:
	sync_waypoint()
	if overview.visible:
		if not sector.session.active and (sector.client_only or overview_shared):
			close_overview(false)
		elif not sector.player.alive:
			close_overview()
		else:
			update_contacts()
			plot.queue_redraw()
	var origin := Vector2(size.x - 322, 96)
	range_less.position = origin + Vector2(202, 5)
	range_more.position = origin + Vector2(242, 5)
	for button in [range_less, range_more]:
		button.size = Vector2(32, 30)
	map_button.position = origin + Vector2(164, 131)
	map_button.size = Vector2(110, 34)
	var flight := sector.player.alive and not sector.paused and (not sector.client_only or sector.session.active)
	for button in [range_less, range_more, map_button]:
		button.visible = flight
	range_less.disabled = range_index == 0
	range_more.disabled = range_index == RANGES.size() - 1
	queue_redraw()


func label_at(canvas: Control, point: Vector2, content: String, pixels: int = 12, color: Color = FlightHud.INK) -> void:
	canvas.draw_string(font, point, content, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)


func _draw() -> void:
	if not sector.player.alive or sector.paused or (sector.client_only and not sector.session.active):
		return
	var origin := Vector2(size.x - 322, 96)
	draw_style_box(FlightHud.panel_style(), Rect2(origin, Vector2(290, 182)))
	label_at(self, origin + Vector2(14, 23), "LOCAL RADAR / %d m" % RANGES[range_index], 12, FlightHud.CYAN)
	var center := origin + Vector2(84, 100)
	draw_circle(center, 62, Color("0d1d2c"))
	for radius in [31, 62]:
		draw_arc(center, radius, 0, TAU, 64, Color(FlightHud.MUTED, 0.4), 1, true)
	draw_line(center - Vector2(62, 0), center + Vector2(62, 0), Color(FlightHud.MUTED, 0.2))
	draw_line(center - Vector2(0, 62), center + Vector2(0, 62), Color(FlightHud.MUTED, 0.2))
	label_at(self, center + Vector2(-17, -46), "FWD", 10, FlightHud.MUTED)
	var selected := destination()
	for contact in contacts():
		var local := relative_position(sector.player.global_transform, contact["position"])
		if local.length() > RANGES[range_index]:
			continue
		var point := center + Vector2(local.x, local.z) / RANGES[range_index] * 58
		var color: Color = contact["color"]
		draw_circle(point, 3, color)
		if absf(local.y) > 15:
			var sign_y := -1.0 if local.y > 0 else 1.0
			var tip := point + Vector2(0, sign_y * 10)
			draw_line(point + Vector2(0, sign_y * 4), tip, color)
			draw_line(tip, tip + Vector2(-3, -sign_y * 3), color)
			draw_line(tip, tip + Vector2(3, -sign_y * 3), color)
		if contact["key"] == selected["key"]:
			draw_arc(point, 6, 0, TAU, 24, Color.WHITE, 1.5, true)
	var local_goal := relative_position(sector.player.global_transform, selected["position"])
	if local_goal.length() > RANGES[range_index] or selected["key"] == "safe":
		var direction := Vector2(local_goal.x, local_goal.z).normalized()
		if direction.length_squared() > 0.01:
			var tip := center + direction * 59
			var side := direction.orthogonal() * 4
			draw_colored_polygon(PackedVector2Array([tip, tip - direction * 8 + side, tip - direction * 8 - side]), selected["color"])
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -6), center + Vector2(-4, 4), center + Vector2(4, 4)]), Color.WHITE)
	label_at(self, origin + Vector2(163, 59), "FORWARD UP", 11, FlightHud.INK)
	label_at(self, origin + Vector2(163, 79), "Arrows: height", 11, FlightHud.MUTED)
	label_at(self, origin + Vector2(163, 99), "Green: outpost", 11, FlightHud.GREEN)
	label_at(self, origin + Vector2(163, 119), "Ring: waypoint", 11, FlightHud.MUTED)
	draw_guidance(selected, local_goal)


func draw_guidance(selected: Dictionary, local: Vector3) -> void:
	# All three flight panels end 71 pixels above the bottom of the viewport.
	var origin := Vector2(size.x * 0.5 - 140, size.y - 185)
	draw_style_box(FlightHud.panel_style(), Rect2(origin, Vector2(280, 114)))
	var color: Color = selected["color"]
	label_at(self, origin + Vector2(12, 23), "DESTINATION / " + selected["name"].to_upper(), 12, color)
	var center := origin + Vector2(43, 68)
	draw_arc(center, 26, 0, TAU, 48, FlightHud.MUTED, 1, true)
	draw_line(center - Vector2(6, 0), center + Vector2(6, 0), FlightHud.MUTED)
	draw_line(center - Vector2(0, 6), center + Vector2(0, 6), FlightHud.MUTED)
	var dot := center + compass_point(local) * 22
	if local.z > 0:
		draw_arc(dot, 4, 0, TAU, 20, color, 2, true)
	else:
		draw_circle(dot, 4, color)
	var hint := turn_hint(local)
	if selected["key"] == "station" and local.length() <= Sector.REPAIR_RADIUS:
		hint = "AT OUTPOST 01"
	label_at(self, origin + Vector2(82, 57), hint, 11, color)
	label_at(self, origin + Vector2(82, 80), "%.0f m / %+.0f m height" % [local.length(), local.y], 12)
	label_at(self, origin + Vector2(12, 105), "Center dot to face destination / hollow = behind", 10, FlightHud.MUTED)


func plot_point(location: Vector3) -> Vector2:
	var rotated := Basis(Vector3.UP, view_yaw) * location
	var scale := minf(plot.size.x * 0.44, plot.size.y * 0.44) / Sector.MAP_RADIUS
	return plot.size * 0.5 + Vector2(rotated.x, rotated.z * 0.55 - rotated.y * 0.7) * scale


func draw_sector(canvas: Control) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color("07111d"))
	var ring := PackedVector2Array()
	for step in range(65):
		var angle := step * TAU / 64
		ring.append(plot_point(Vector3(cos(angle), 0, sin(angle)) * Sector.MAP_RADIUS))
	canvas.draw_polyline(ring, Color(FlightHud.CYAN, 0.4), 1.5, true)
	for axis in [Vector3.RIGHT, Vector3.FORWARD]:
		var meridian := PackedVector2Array()
		for step in range(65):
			var angle := step * TAU / 64
			meridian.append(plot_point((axis * cos(angle) + Vector3.UP * sin(angle)) * Sector.MAP_RADIUS))
		canvas.draw_polyline(meridian, Color(FlightHud.CYAN, 0.16), 1, true)
	for fraction in [-0.5, 0.0, 0.5]:
		var extent := sqrt(1 - fraction * fraction) * Sector.MAP_RADIUS
		canvas.draw_line(plot_point(Vector3(-extent, 0, fraction * Sector.MAP_RADIUS)), plot_point(Vector3(extent, 0, fraction * Sector.MAP_RADIUS)), Color(FlightHud.MUTED, 0.15))
		canvas.draw_line(plot_point(Vector3(fraction * Sector.MAP_RADIUS, 0, -extent)), plot_point(Vector3(fraction * Sector.MAP_RADIUS, 0, extent)), Color(FlightHud.MUTED, 0.15))
	var captions: Array[Rect2] = [Rect2(Vector2.ZERO, Vector2(canvas.size.x, 35))]
	var player_point := plot_point(sector.player.position)
	canvas.draw_circle(player_point, 5, Color.WHITE)
	label_at(canvas, player_point + Vector2(8, 16), "YOU", 12)
	captions.append(Rect2(player_point + Vector2(8, 4), Vector2(32, 16)))
	var current := contacts()
	current.sort_custom(func(a: Dictionary, b: Dictionary): return a["key"] == waypoint_key and b["key"] != waypoint_key)
	for contact in current:
		var point := plot_point(contact["position"])
		var floor_point := plot_point(Vector3(contact["position"].x, 0, contact["position"].z))
		var color: Color = contact["color"]
		canvas.draw_line(floor_point, point, Color(color, 0.6), 1.5)
		canvas.draw_circle(floor_point, 2, Color(color, 0.4))
		canvas.draw_circle(point, 5, color)
		if contact["key"] == waypoint_key:
			canvas.draw_arc(point, 10, 0, TAU, 32, Color.WHITE, 2, true)
		var width := font.get_string_size(contact["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		for offset: Vector2 in [Vector2(12, -8), Vector2(12, 20), Vector2(-width - 12, -8), Vector2(-width - 12, 20)]:
			var rect := Rect2(point + offset - Vector2(2, 13), Vector2(width + 4, 18))
			if Rect2(Vector2.ZERO, canvas.size).encloses(rect) and not captions.any(func(other: Rect2): return rect.intersects(other)):
				label_at(canvas, point + offset, contact["name"], 12, color)
				captions.append(rect)
				break
	label_at(canvas, Vector2(14, 23), "2.4 km SECTOR / HEIGHT VIEW", 12, FlightHud.CYAN)


func pick_contact(point: Vector2) -> void:
	var nearest := 14.0
	var key := ""
	for contact in contacts():
		var distance := plot_point(contact["position"]).distance_to(point)
		if distance < nearest:
			nearest = distance
			key = contact["key"]
	if not key.is_empty():
		choose_contact(key)
