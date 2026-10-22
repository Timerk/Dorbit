class_name FlightNavigation
extends Control
## Navigation display and autopilot status. Combat selection keeps its authoritative rules.

const RANGES: Array[float] = [250.0, 500.0, 1000.0, 2400.0]
const RADAR_RINGS := [31, 62]
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
var autopilot_status: Label
var reset_button: Button
var view_yaw: float = -0.55
var view_pitch: float = atan2(0.55, 0.7)
var view_zoom: float = 1.0
var view_offset := Vector2.ZERO
var font: Font = StationUi.FONT
var info: Label
var overview_title: Label
var overview_hint: Label
var overview_legend: Label
var tabs: TabContainer
var network_plot: NetworkPlot
var contact_cache: Array[Dictionary] = []
var contact_cache_map := -1
var contact_builds := 0
var contact_buttons_build := -1
var safe_contact := {"key": "safe", "name": "Safe space", "position": Vector3.ZERO, "color": FlightHud.RED, "ship": null}
var card_style := FlightHud.panel_style()
var sector_style := StationUi.style(StationUi.SURFACE, FlightHud.LINE)
var radar_title := ""
var radar_title_state := Vector2i(-1, -1)
var guidance_name := ""
var guidance_title := ""
var overview_state := Vector3i(-1, -1, -1)
var info_alert := false
var radar_buttons: Array[Button] = []
var range_buttons: Array[Button] = []
var drew_instruments := true


class NetworkPlot extends Control:
	var navigation: FlightNavigation
	var hovered_map := -1
	var keyboard_map := -1
	const POINTS := [Vector2(0.155, 0.5), Vector2(0.47, 0.5), Vector2(0.8, 0.26), Vector2(0.8, 0.74)]
	const PICTURES := [preload("res://assets/ui/maps/m1.png"), preload("res://assets/ui/maps/m2.png"), preload("res://assets/ui/maps/m3.png"), preload("res://assets/ui/maps/m4.png")]

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mouse_exited.connect(func():
			hovered_map = -1
			tooltip_text = ""
			queue_redraw())
		focus_exited.connect(func():
			keyboard_map = -1
			queue_redraw())

	func map_rect(map: int) -> Rect2:
		var dimensions := Vector2(size.x * 0.245, minf(192, (size.y - 76) * 0.46))
		return Rect2(size * POINTS[map] - dimensions * 0.5, dimensions)

	func link_points(source: int, destination: int) -> PackedVector2Array:
		var a := map_rect(source)
		var b := map_rect(destination)
		if source == 2 and destination == 3:
			var rail := a.end.x + 24
			return PackedVector2Array([Vector2(a.end.x, a.get_center().y), Vector2(rail, a.get_center().y), Vector2(rail, b.get_center().y), Vector2(b.end.x, b.get_center().y)])
		var start := Vector2(a.end.x, a.get_center().y)
		var end := Vector2(b.position.x, b.get_center().y)
		var rail := (start.x + end.x) * 0.5
		return PackedVector2Array([start, Vector2(rail, start.y), Vector2(rail, end.y), end])

	func route_edges(destination: int) -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		var source := navigation.sector.map_id
		while destination >= 0 and source != destination:
			var hop := SectorMaps.first_hop(source, destination)
			if hop < 0:
				break
			result.append(Vector2i(mini(source, hop), maxi(source, hop)))
			source = hop
		return result

	func select_map(map: int) -> void:
		var hop := SectorMaps.first_hop(navigation.sector.map_id, map)
		if hop >= 0:
			navigation.choose_contact("gate%d" % hop)

	func _draw() -> void:
		var current := navigation.sector.map_id
		var selected := hovered_map if hovered_map >= 0 else keyboard_map
		var route := route_edges(selected)
		draw_rect(Rect2(Vector2.ZERO, size), Color("09131b"))
		for x in range(24, int(size.x), 32):
			for y in range(20, int(size.y), 32):
				draw_circle(Vector2(x,y), 0.7, Color("263944"))
		for source: int in SectorMaps.GATES:
			for destination: int in SectorMaps.GATES[source]:
				if source < destination:
					var points := link_points(source, destination)
					var highlighted := route.has(Vector2i(source, destination))
					var color := FlightHud.AMBER if highlighted else Color("657e8d")
					if highlighted:
						draw_polyline(points, Color(color, 0.12), 7, true)
					draw_polyline(points, color, 1.5, true)
					for port: Vector2 in [points[0], points[-1]]:
						draw_circle(port, 3.5, color)
		for map: int in SectorMaps.network_maps():
			var rect := map_rect(map)
			var color: Color = SectorMaps.MAPS[map]["color"]
			var border := FlightHud.AMBER if selected == map else color if map == current else Color("405767")
			draw_rect(Rect2(rect.position+Vector2(4,6), rect.size), Color(0,0,0,0.45))
			if map == current or map == selected:
				draw_rect(rect.grow(4), Color(border,0.12))
			draw_rect(rect, border)
			var picture := Rect2(rect.position+Vector2.ONE*2, rect.size-Vector2(4,42))
			# Crop, rather than stretch, the actual rendered sector view.
			var texture: Texture2D = PICTURES[map]
			var crop := texture.get_size()
			crop.y = minf(crop.y, crop.x*picture.size.y/picture.size.x)
			crop.x = minf(crop.x, crop.y*picture.size.x/picture.size.y)
			draw_texture_rect_region(texture, picture, Rect2((texture.get_size()-crop)*0.5,crop))
			draw_rect(Rect2(picture.position,Vector2(picture.size.x,27)), Color(0.015,0.03,0.045,0.65))
			navigation.label_at(self, picture.position+Vector2(9,19), "M%d" % (map+1), 18, color)
			var status := "YOU ARE HERE" if map == current else "HOME / STATION" if map == 0 else "TIER %d" % map
			var status_width := navigation.font.get_string_size(status,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
			navigation.label_at(self, Vector2(picture.end.x-status_width-9,picture.position.y+18),status,13,border if map == current else FlightHud.INK)
			draw_rect(Rect2(Vector2(rect.position.x+1,rect.end.y-40),Vector2(rect.size.x-2,39)),Color("101e28"))
			var name: String = SectorMaps.MAPS[map]["name"].get_slice(" / ",1)
			navigation.label_at(self, Vector2(rect.position.x+10,rect.end.y-15),name,20,FlightHud.INK)
			if map == current:
				draw_line(Vector2(rect.position.x,rect.end.y),rect.end,color,3)
		navigation.label_at(self, Vector2(18, size.y-14), "RECLAMATION SECTORS  /  4 OPEN MAPS",14,FlightHud.MUTED)
		var legend := "CONNECTED GATES / TWO-WAY"
		var width := navigation.font.get_string_size(legend,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		navigation.label_at(self, Vector2(size.x-width-18,size.y-14),legend,14,FlightHud.MUTED)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			hovered_map = -1
			for map: int in SectorMaps.network_maps():
				if map_rect(map).has_point(event.position):
					hovered_map = map
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hovered_map >= 0 and hovered_map != navigation.sector.map_id else Control.CURSOR_ARROW
			tooltip_text = ""
			if hovered_map >= 0:
				var hop := SectorMaps.first_hop(navigation.sector.map_id,hovered_map)
				tooltip_text = SectorMaps.MAPS[hovered_map]["description"]
				if hop >= 0:
					tooltip_text += "\nSet waypoint to " + SectorMaps.MAPS[hop]["name"]
			queue_redraw()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			for map: int in SectorMaps.network_maps():
				if map_rect(map).has_point(event.position):
					select_map(map)
					accept_event()
		elif event is InputEventKey and event.pressed:
			if event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]:
				if keyboard_map < 0:
					keyboard_map = navigation.sector.map_id
				keyboard_map = posmod(keyboard_map + (-1 if event.keycode in [KEY_LEFT,KEY_UP] else 1),SectorMaps.network_maps().size())
				hovered_map = -1
				queue_redraw()
				accept_event()
			elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE] and keyboard_map >= 0:
				select_map(keyboard_map)
				accept_event()


class SectorPlot extends Control:
	var navigation: FlightNavigation
	var drag_button: int = MOUSE_BUTTON_NONE
	var drag_distance: float = 0.0
	var dragged: bool = false
	var hovered_key := ""

	func _ready() -> void:
		mouse_exited.connect(func():
			hovered_key = ""
			tooltip_text = ""
			queue_redraw())

	func _draw() -> void:
		navigation.draw_sector(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				if event.pressed:
					navigation.zoom_plot(event.position, 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2)
				accept_event()
			elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				if event.pressed and drag_button == MOUSE_BUTTON_NONE:
					drag_button = event.button_index
					drag_distance = 0.0
					dragged = false
					hovered_key = ""
					tooltip_text = ""
				elif not event.pressed and drag_button == event.button_index:
					var select := drag_button == MOUSE_BUTTON_LEFT and not dragged
					drag_button = MOUSE_BUTTON_NONE
					if select:
						navigation.pick_contact(event.position)
				accept_event()
		elif event is InputEventMouseMotion:
			if drag_button != MOUSE_BUTTON_NONE:
				drag_distance += event.relative.length()
				dragged = dragged or drag_distance >= 6.0
				if dragged:
					navigation.view_yaw += event.relative.x * 0.008
					navigation.view_pitch = clampf(navigation.view_pitch + event.relative.y * 0.008, -1.4, 1.4)
			else:
				hovered_key = navigation.contact_at(event.position)
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hovered_key.is_empty() else Control.CURSOR_ARROW
				tooltip_text = ""
				for contact in navigation.contacts():
					if contact["key"] == hovered_key:
						tooltip_text = "%s / click to navigate" % contact["name"]
			queue_redraw()
			accept_event()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = StationUi.menu_theme()
	range_less = StationUi.button(self, "-", func(): change_range(-1))
	range_more = StationUi.button(self, "+", func(): change_range(1))
	map_button = StationUi.button(self, "Map [M]", open_overview)
	autopilot_status = Label.new()
	autopilot_status.text = "Autopilot enabled"
	autopilot_status.add_theme_font_size_override("font_size", 16)
	autopilot_status.add_theme_color_override("font_color", FlightHud.AMBER)
	autopilot_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(autopilot_status)
	range_buttons.assign([range_less, range_more])
	radar_buttons.assign([range_less, range_more, map_button])
	for button in radar_buttons:
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 16)
	for button in range_buttons:
		button.custom_minimum_size = Vector2(26, 26)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			style.set_content_margin_all(2)
			button.add_theme_stylebox_override(state, style)
	build_overview()


func contacts() -> Array[Dictionary]:
	# Callers share one read-only list; it is rebuilt only when membership changes.
	if not contacts_current():
		contact_cache = build_contacts()
		contact_cache_map = sector.map_id
		contact_builds += 1
	return contact_cache


func contacts_current() -> bool:
	# Allocation-free check of the cached membership; refreshes moving positions.
	if contact_cache_map != sector.map_id:
		return false
	var index: int = SectorMaps.links(sector.map_id).size() + (1 if sector.map_id == 0 else 0)
	var site := Story.site(sector.story_state(), sector.map_id)
	if not site.is_empty():
		if index >= contact_cache.size() or contact_cache[index]["key"] != "story_" + site["id"]:
			return false
		index += 1
	elif index < contact_cache.size() and str(contact_cache[index]["key"]).begins_with("story_"):
		return false
	for alien_id: int in sector.aliens:
		var enemy := sector.aliens[alien_id]
		if enemy.alive and enemy.visible:
			if index >= contact_cache.size() or contact_cache[index]["ship"] != enemy:
				return false
			contact_cache[index]["position"] = enemy.position
			index += 1
	if sector.session.active:
		for id: int in sector.session.ships:
			var ship := sector.session.ships[id]
			if ship != sector.player and ship.alive and ship.map_id == sector.map_id and not ship.get_meta("docked", false):
				if index >= contact_cache.size() or contact_cache[index]["ship"] != ship:
					return false
				contact_cache[index]["position"] = ship.position
				index += 1
	return index == contact_cache.size()


func has_contact(key: String) -> bool:
	for contact in contacts():
		if contact["key"] == key:
			return true
	return false


func build_contacts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if sector.map_id == 0:
		result.append({"key": "station", "name": "Outpost 01", "position": Sector.STATION_POSITION, "color": FlightHud.GREEN, "ship": null})
	for map: int in SectorMaps.links(sector.map_id):
		result.append({"key": "gate%d" % map, "name": SectorMaps.gate_label(map).capitalize() if GalaxyGates.is_arena(map) else "Gate to " + SectorMaps.code(map), "position": SectorMaps.gate_position(sector.map_id, map), "color": SectorMaps.MAPS[map]["color"], "ship": null})
	var site := Story.site(sector.story_state(), sector.map_id)
	if not site.is_empty():
		result.append({"key": "story_" + site["id"], "name": "Objective: " + site["site"], "position": Story.site_position(site), "color": StorySites.GOLD, "ship": null})
	for enemy: Alien in sector.aliens.values():
		if enemy.alive and enemy.visible:
			result.append({"key": "alien%d" % enemy.alien_id, "name": "%s %d" % [enemy.kind, enemy.alien_id % 100 + 1], "position": enemy.position, "color": enemy.tuning()["color"], "ship": enemy})
	if sector.session.active:
		for id: int in sector.session.ships:
			var ship := sector.session.ships[id]
			if ship != sector.player and ship.alive and ship.map_id == sector.map_id and not ship.get_meta("docked", false):
				result.append({"key": "friend%d" % id, "name": "Pilot %d" % id, "position": ship.position, "color": FlightHud.CYAN, "ship": ship})
	return result


func sync_waypoint() -> void:
	if sector.target != last_target:
		if sector.target is Alien and sector.target.alive:
			waypoint_key = "alien%d" % sector.target.alien_id
		elif waypoint_key.begins_with("alien"):
			waypoint_key = contacts()[0]["key"]
		last_target = sector.target
	if not has_contact(waypoint_key):
		waypoint_key = contacts()[0]["key"]


func destination() -> Dictionary:
	var local := sector.player.position - SectorMaps.origin(sector.map_id)
	if local.length() > Sector.MAP_RADIUS:
		safe_contact["position"] = SectorMaps.origin(sector.map_id) + local.normalized() * (Sector.MAP_RADIUS - 50)
		return safe_contact
	for contact in contacts():
		if contact["key"] == waypoint_key:
			return contact
	return contacts()[0]


func choose_contact(key: String) -> void:
	for contact in contacts():
		if contact["key"] != key:
			continue
		sector.autopilot.cancel()
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
	var rows := StationUi.rows(overview, 16)
	var header := HBoxContainer.new()
	rows.add_child(header)
	overview_title = StationUi.text(header, "SECTOR OVERVIEW / OUTPOST 01", 22, FlightHud.AMBER)
	overview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button = StationUi.button(header, "Reset view", reset_view)
	StationUi.button(header, "Back to flight [M / Esc]", close_overview)
	rows.add_child(HSeparator.new())
	overview_hint = StationUi.text(rows, "Click a contact to navigate. Drag to rotate / Scroll to zoom", 16, FlightHud.MUTED)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(tabs)
	body.name = "Local sector"
	tabs.add_child(body)
	network_plot = NetworkPlot.new()
	network_plot.name = "Connected maps"
	network_plot.navigation = self
	network_plot.custom_minimum_size = Vector2(810, 360)
	tabs.add_child(network_plot)
	var sidebar := StationUi.card(body)
	sidebar.custom_minimum_size.x = 230
	var left := StationUi.rows(sidebar, 12)
	StationUi.text(left, "CONTACTS / SET WAYPOINT", 16, FlightHud.AMBER)
	left.add_child(HSeparator.new())
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
	plot.custom_minimum_size = Vector2(550, 280)
	plot.mouse_filter = Control.MOUSE_FILTER_STOP
	plot.clip_contents = true
	body.add_child(plot)
	info = StationUi.text(rows, "", 16, FlightHud.AMBER)
	overview_legend = StationUi.text(rows, "White: you / Colored: gates and aliens / Green: outpost / Gold: objective / Cyan: pilots", 14, FlightHud.MUTED)
	overview.hide()


func open_overview() -> void:
	if sector.paused or not sector.player.alive or (sector.client_only and not sector.session.active):
		return
	sector.set_paused(true)
	plot.drag_button = MOUSE_BUTTON_NONE
	plot.hovered_key = ""
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
	var state := Vector3i(tabs.current_tab, sector.map_id, GameSettings.binding_revision)
	if state != overview_state:
		# Header text depends only on the tab, current map and bindings.
		overview_state = state
		overview_title.text = ("STAR SYSTEM / " if tabs.current_tab == 1 else "SECTOR OVERVIEW / ") + SectorMaps.MAPS[sector.map_id]["name"]
		reset_button.visible = tabs.current_tab == 0
		overview_legend.text = "Hover to preview a route / Click a sector to navigate / Arrow keys + Enter also select" if tabs.current_tab == 1 else "White: you / Colored: gates and aliens / Green: outpost / Gold: objective / Cyan: pilots"
		overview_hint.text = "Click a map to set the next gate on its route. Fly to the gate and press %s to jump." % GameSettings.binding_text("jump_gate") if tabs.current_tab == 1 else "Click a contact to navigate. Drag to rotate / Scroll to zoom"
	network_plot.queue_redraw()
	var current := contacts()
	if contact_builds != contact_buttons_build:
		for key: String in contact_buttons.keys():
			if not has_contact(key):
				contact_buttons[key].queue_free()
				contact_buttons.erase(key)
		contact_buttons_build = contact_builds
	for contact in current:
		var key: String = contact["key"]
		if not contact_buttons.has(key):
			var button := StationUi.button(contact_list, "", func(): choose_contact(key))
			StationUi.list_entry(button, false, 16)
			# Long contact names trim instead of widening the fixed sidebar.
			button.remove_theme_font_override("font")
			button.clip_text = true
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.toggle_mode = true
			button.add_theme_color_override("font_color", contact["color"])
			contact_buttons[key] = button
		var distance := sector.player.position.distance_to(contact["position"])
		contact_buttons[key].text = "%s / %.0f m" % [contact["name"], distance]
		contact_buttons[key].tooltip_text = contact_buttons[key].text
		contact_buttons[key].set_pressed_no_signal(key == waypoint_key)
	var selected := destination()
	info.text = "Waypoint: %s / %.0f m%s" % [selected["name"], sector.player.position.distance_to(selected["position"]), " / RADIATION: return to safety first" if selected["key"] == "safe" else ""]
	var alert: bool = selected["key"] == "safe"
	if alert != info_alert or not info.has_theme_color_override("font_color"):
		info_alert = alert
		info.add_theme_color_override("font_color", FlightHud.RED if alert else FlightHud.AMBER)
	if tabs.current_tab == 1:
		info.text = SectorMaps.MAPS[sector.map_id]["description"]


func _process(_delta: float) -> void:
	sync_waypoint()
	if overview.visible:
		StationUi.centered(overview, Vector2(1100,700) if tabs.current_tab == 1 else Vector2(880,550))
		if not sector.session.active and (sector.client_only or overview_shared):
			close_overview(false)
		elif not sector.player.alive:
			close_overview()
		else:
			update_contacts()
			plot.queue_redraw()
	var layout := sector.hud.layout
	var radar := layout.rect_for("radar")
	var factor := radar.size.x / radar_rect().size.x
	var origin := radar.position
	range_less.position = origin + Vector2(216, 8) * factor
	range_more.position = origin + Vector2(248, 8) * factor
	for button in range_buttons:
		button.size = Vector2(26, 26)
		button.scale = Vector2.ONE * factor
	map_button.position = origin + Vector2(164, 131) * factor
	map_button.size = Vector2(110, 34)
	map_button.scale = Vector2.ONE * factor
	var status_rect := layout.rect_for("autopilot")
	autopilot_status.text = "Autopilot / preview" if layout.editing else "Autopilot enabled"
	autopilot_status.position = status_rect.position
	autopilot_status.scale = Vector2.ONE * (status_rect.size.x / layout.default_rect("autopilot").size.x)
	var flight := not sector.preflight and sector.player.alive and not sector.paused and (not sector.client_only or sector.session.active)
	autopilot_status.visible = (flight and sector.autopilot.enabled or layout.editing) and layout.shown("autopilot")
	for button in radar_buttons:
		button.visible = (flight or layout.editing) and layout.shown("radar")
	range_less.disabled = range_index == 0
	range_more.disabled = range_index == RANGES.size() - 1
	# Moving contacts need a redraw every frame; hidden instruments need one clear.
	var drawing := draws_instruments()
	if drawing or drew_instruments:
		queue_redraw()
	drew_instruments = drawing


func label_at(canvas: Control, point: Vector2, content: String, pixels: int = 12, color: Color = FlightHud.INK) -> void:
	canvas.draw_string(font, point, content, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)


func radar_rect() -> Rect2:
	return Rect2(size.x - FlightHud.SIDE_MARGIN - 290, FlightHud.TOP_MARGIN, 290, 182)


func guidance_rect() -> Rect2:
	return Rect2(size.x * 0.5 - 140, FlightHud.TOP_MARGIN, 280, 114)


func card(rect: Rect2, title: String, accent: Color = FlightHud.AMBER) -> void:
	draw_style_box(card_style, rect)
	draw_line(rect.position + Vector2(2, 2), rect.position + Vector2(2, 40), accent, 3)
	var width := 174.0 if rect == radar_rect() else rect.size.x - 24
	label_at(self, rect.position + Vector2(14, 27), title, FlightHud.fit_pixels(title, 18, width), accent)
	draw_line(rect.position + Vector2(14, 40), Vector2(rect.end.x - 14, rect.position.y + 40), FlightHud.LINE)


func draws_instruments() -> bool:
	return not (sector.preflight or not sector.player.alive or (sector.paused and not sector.hud.layout.editing) or (sector.client_only and not sector.session.active))


func _draw() -> void:
	var layout := sector.hud.layout
	if not draws_instruments():
		return
	var selected := destination()
	var local_goal := relative_position(sector.player.global_transform, selected["position"])
	if layout.begin_draw(self, "radar"):
		draw_radar()
		layout.end_draw(self)
	if layout.begin_draw(self, "guidance"):
		draw_guidance(selected, local_goal)
		layout.end_draw(self)


func draw_radar() -> void:
	var origin := radar_rect().position
	var title_state := Vector2i(sector.map_id, range_index)
	if title_state != radar_title_state:
		radar_title_state = title_state
		radar_title = "%s / RADAR / %s m" % [SectorMaps.code(sector.map_id), FlightHud.number(RANGES[range_index])]
	card(radar_rect(), radar_title)
	var center := origin + Vector2(84, 108)
	draw_circle(center, 62, Color("111a20"))
	for radius: int in RADAR_RINGS:
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
			draw_arc(point, 6, 0, TAU, 24, FlightHud.AMBER, 1.5, true)
	var local_goal := relative_position(sector.player.global_transform, selected["position"])
	if local_goal.length() > RANGES[range_index] or selected["key"] == "safe":
		var direction := Vector2(local_goal.x, local_goal.z).normalized()
		if direction.length_squared() > 0.01:
			var tip := center + direction * 59
			var side := direction.orthogonal() * 4
			draw_colored_polygon(PackedVector2Array([tip, tip - direction * 8 + side, tip - direction * 8 - side]), selected["color"])
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -6), center + Vector2(-4, 4), center + Vector2(4, 4)]), Color.WHITE)
	label_at(self, origin + Vector2(163, 61), "↑↓  HEIGHT", 13, FlightHud.MUTED)
	draw_arc(origin + Vector2(168, 78), 4, 0, TAU, 20, FlightHud.AMBER, 1.5, true)
	label_at(self, origin + Vector2(180, 82), "WAYPOINT", 13, FlightHud.MUTED)
	draw_circle(origin + Vector2(168, 100), 3, FlightHud.GREEN)
	label_at(self, origin + Vector2(180, 104), "GATE / BASE", 13, FlightHud.MUTED)
	draw_circle(origin + Vector2(168, 120), 3, FlightHud.RED)
	label_at(self, origin + Vector2(180, 124), "HOSTILE", 13, FlightHud.MUTED)


func draw_guidance(selected: Dictionary, local: Vector3) -> void:
	var origin := guidance_rect().position
	var color := FlightHud.RED if selected["key"] == "safe" else FlightHud.AMBER
	if selected["name"] != guidance_name:
		guidance_name = selected["name"]
		guidance_title = "DESTINATION / " + guidance_name.to_upper()
	card(guidance_rect(), guidance_title, color)
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
	elif selected["key"].begins_with("gate") and local.length() <= SectorMaps.JUMP_RADIUS:
		hint = GameSettings.binding_text("jump_gate") + " / JUMP THROUGH GATE"
	label_at(self, origin + Vector2(82, 65), hint, FlightHud.fit_pixels(hint, 16, 186), color)
	label_at(self, origin + Vector2(82, 91), "%.0f m / %+.0f m" % [local.length(), local.y], 16)


func plot_point(location: Vector3) -> Vector2:
	var rotated := Basis(Vector3.RIGHT, view_pitch) * Basis(Vector3.UP, view_yaw) * (location - SectorMaps.origin(sector.map_id))
	var scale := minf(plot.size.x * 0.44, plot.size.y * 0.44) / Sector.MAP_RADIUS * view_zoom
	return plot.size * 0.5 + view_offset + Vector2(rotated.x, -rotated.y * 0.89) * scale


func zoom_plot(point: Vector2, factor: float) -> void:
	var next_zoom := clampf(view_zoom * factor, 0.6, 3.0)
	# Keep the position under the cursor stable while zooming.
	view_offset = point - plot.size * 0.5 - (point - plot.size * 0.5 - view_offset) * (next_zoom / view_zoom)
	view_zoom = next_zoom
	plot.queue_redraw()


func reset_view() -> void:
	view_yaw = -0.55
	view_pitch = atan2(0.55, 0.7)
	view_zoom = 1.0
	view_offset = Vector2.ZERO
	plot.queue_redraw()


func plot_labels() -> Dictionary[String, Rect2]:
	var labels: Dictionary[String, Rect2] = {}
	var captions: Array[Rect2] = [Rect2(Vector2.ZERO, Vector2(plot.size.x, 35))]
	captions.append(Rect2(plot_point(sector.player.position) + Vector2(8, 4), Vector2(32, 16)))
	# The waypoint label is placed first; the shared contact list stays unsorted.
	for waypoint_pass: bool in [true, false]:
		for contact in contacts():
			if (contact["key"] == waypoint_key) != waypoint_pass:
				continue
			var point := plot_point(contact["position"])
			var width := font.get_string_size(contact["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			for offset: Vector2 in [Vector2(12, -8), Vector2(12, 20), Vector2(-width - 12, -8), Vector2(-width - 12, 20)]:
				var rect := Rect2(point + offset - Vector2(2, 13), Vector2(width + 4, 18))
				if Rect2(Vector2.ZERO, plot.size).encloses(rect) and not captions.any(func(other: Rect2): return rect.intersects(other)):
					labels[contact["key"]] = rect
					captions.append(rect)
					break
	return labels


func draw_sector(canvas: Control) -> void:
	canvas.draw_style_box(sector_style, Rect2(Vector2.ZERO, canvas.size))
	canvas.draw_line(Vector2(2, 2), Vector2(2, 38), FlightHud.AMBER, 3)
	canvas.draw_line(Vector2(14, 40), Vector2(canvas.size.x - 14, 40), FlightHud.LINE)
	var ring := PackedVector2Array()
	for step in range(65):
		var angle := step * TAU / 64
		ring.append(plot_point(SectorMaps.origin(sector.map_id) + Vector3(cos(angle), 0, sin(angle)) * Sector.MAP_RADIUS))
	canvas.draw_polyline(ring, Color(FlightHud.AMBER, 0.35), 1.5, true)
	for axis in [Vector3.RIGHT, Vector3.FORWARD]:
		var meridian := PackedVector2Array()
		for step in range(65):
			var angle := step * TAU / 64
			meridian.append(plot_point(SectorMaps.origin(sector.map_id) + (axis * cos(angle) + Vector3.UP * sin(angle)) * Sector.MAP_RADIUS))
		canvas.draw_polyline(meridian, Color(FlightHud.MUTED, 0.24), 1, true)
	for fraction in [-0.5, 0.0, 0.5]:
		var extent := sqrt(1 - fraction * fraction) * Sector.MAP_RADIUS
		var center := SectorMaps.origin(sector.map_id)
		canvas.draw_line(plot_point(center + Vector3(-extent, 0, fraction * Sector.MAP_RADIUS)), plot_point(center + Vector3(extent, 0, fraction * Sector.MAP_RADIUS)), Color(FlightHud.MUTED, 0.15))
		canvas.draw_line(plot_point(center + Vector3(fraction * Sector.MAP_RADIUS, 0, -extent)), plot_point(center + Vector3(fraction * Sector.MAP_RADIUS, 0, extent)), Color(FlightHud.MUTED, 0.15))
	var player_point := plot_point(sector.player.position)
	canvas.draw_circle(player_point, 5, Color.WHITE)
	label_at(canvas, player_point + Vector2(8, 16), "YOU", 12)
	var labels := plot_labels()
	for contact in contacts():
		var point := plot_point(contact["position"])
		var floor_point := plot_point(Vector3(contact["position"].x, 0, contact["position"].z))
		var color: Color = contact["color"]
		canvas.draw_line(floor_point, point, Color(color, 0.6), 1.5)
		canvas.draw_circle(floor_point, 2, Color(color, 0.4))
		canvas.draw_circle(point, 6, color)
		if contact["key"] == waypoint_key:
			canvas.draw_arc(point, 10, 0, TAU, 32, FlightHud.AMBER, 2, true)
		if contact["key"] == plot.hovered_key:
			canvas.draw_arc(point, 13, 0, TAU, 32, FlightHud.INK, 1, true)
		if labels.has(contact["key"]):
			label_at(canvas, labels[contact["key"]].position + Vector2(2, 13), contact["name"], 12, color)
	label_at(canvas, Vector2(14, 27), "2.4 km SECTOR / HEIGHT VIEW", 16, FlightHud.AMBER)


func contact_at(point: Vector2) -> String:
	if not Rect2(Vector2.ZERO, plot.size).has_point(point):
		return ""
	var nearest := 16.0
	var key := ""
	for contact in contacts():
		var distance := plot_point(contact["position"]).distance_to(point)
		if distance < nearest:
			nearest = distance
			key = contact["key"]
	if not key.is_empty():
		return key
	var labels := plot_labels()
	for label_key: String in labels:
		if labels[label_key].has_point(point):
			return label_key
	for contact in contacts():
		var position: Vector3 = contact["position"]
		var floor_point := plot_point(Vector3(position.x, 0, position.z))
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, floor_point, plot_point(position))) <= 5:
			return contact["key"]
	return ""


func pick_contact(point: Vector2) -> void:
	var key := contact_at(point)
	if not key.is_empty():
		choose_contact(key)
