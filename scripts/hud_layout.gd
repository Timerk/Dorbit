class_name HudLayout
extends Control
## Device-local flight instruments. World-space contact markers retain their tracking.

const PATH := "user://hud-layout.cfg"
const GRID := 16.0
const MIN_SCALE := 0.8
const ITEMS := {
	"objectives": ["Quests", "quests"], "ship": ["Ship status", "hull"],
	"target": ["Target status", "damage"], "radar": ["Radar", "overview"],
	"guidance": ["Destination", "gates"], "speed": ["Speed", "speed"],
	"controls": ["Control hints", "settings"], "context": ["Notifications", "connection"],
	"station": ["Station actions", "shop"], "radiation": ["Radiation", "shield"],
	"reticle": ["Reticle", "damage"], "autopilot": ["Autopilot status", "speed"],
	"performance": ["Performance", "settings"], "ammo": ["Ammunition", "damage"]
}

var hud: FlightHud
var editing := false
var entries: Dictionary = {}
var sidebar: PanelContainer
var buttons: Dictionary[String, Button] = {}
var drag_id := ""
var resizing := false
var drag_start := Vector2.ZERO
var drag_rect := Rect2()
var chord_down := false
var snap := true
var save_path := PATH
var selected_id := ""
var rail_toggle: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = StationUi.menu_theme()
	load_layout()
	sidebar = PanelContainer.new()
	add_child(sidebar)
	var rail_style := FlightHud.panel_style()
	rail_style.bg_color.a = 1.0
	sidebar.add_theme_stylebox_override("panel", rail_style)
	var rows := StationUi.rows(sidebar, 8)
	StationUi.text(rows, "HUD EDITOR", 22, FlightHud.AMBER)
	StationUi.text(rows, "Ctrl + Alt / Esc to finish\nDrag panels to move\nResize from lower right", 14)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id: String in ITEMS:
		var button := StationUi.button(list, ITEMS[id][0], func(): reopen(id))
		button.icon = load("res://assets/ui/menu/%s.svg" % ITEMS[id][1])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 20)
		button.custom_minimum_size.y = 30
		button.add_theme_font_size_override("font_size", 16)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "Show " + ITEMS[id][0]
		buttons[id] = button
	var snapping := CheckButton.new()
	snapping.text = "Snap to grid"
	snapping.button_pressed = snap
	snapping.toggled.connect(func(value: bool): snap = value)
	rows.add_child(snapping)
	StationUi.button(rows, "Reset layout", reset_layout)
	StationUi.button(rows, "Done [Esc]", func(): set_editing(false))
	StationUi.button(rows, "Hide sidebar", func(): sidebar.hide(); rail_toggle.show())
	sidebar.hide()
	rail_toggle = StationUi.button(self, "HUD editor / Show sidebar", func(): sidebar.show(); rail_toggle.hide())
	rail_toggle.position = Vector2(8, 8)
	rail_toggle.hide()


func default_rect(id: String) -> Rect2:
	match id:
		"ship": return hud.ship_rect()
		"target": return hud.target_rect()
		"objectives": return hud.objectives_rect()
		"radar": return hud.navigation.radar_rect()
		"guidance": return hud.navigation.guidance_rect()
		"ammo": return hud.ammo_bar.default_rect()
		"speed": return Rect2(hud.ship_rect().end.x + 20, size.y - (236 if size.x < 1200 else 124), 130, 50)
		"controls": return Rect2(FlightHud.SIDE_MARGIN, size.y - 46, size.x - 2 * FlightHud.SIDE_MARGIN, 32)
		"context": return Rect2(FlightHud.SIDE_MARGIN, hud.objectives_rect().end.y + 12, minf(440, size.x - 2 * FlightHud.SIDE_MARGIN - 322), 170)
		"station": return Rect2(hud.target_rect().position - Vector2(0, 88 if hud.sector.session.active else 66), Vector2(290, 78 if hud.sector.session.active else 56))
		"radiation": return Rect2(maxf(FlightHud.SIDE_MARGIN, (size.x - 764) * 0.5), 248, 410, 62)
		"reticle": return Rect2(size * 0.5 - Vector2(48, 20), Vector2(96, 40))
		"autopilot": return Rect2(hud.navigation.radar_rect().position + Vector2(14, 190), Vector2(170, 26))
		"performance": return Rect2(FlightHud.SIDE_MARGIN, hud.objectives_rect().end.y + 192, 350, 26)
	return Rect2()


func shown(id: String) -> bool:
	return entries.get(id, {}).get("visible", true)


func rect_for(id: String) -> Rect2:
	var base := default_rect(id)
	var entry: Dictionary = entries.get(id, {})
	if not entry.has("position") and id != "reticle":
		return base
	var factor := clampf(float(entry.get("scale", 1.0)), MIN_SCALE, 3.0)
	factor = minf(factor, minf(size.x / base.size.x, (size.y - 24) / base.size.y))
	var dimensions := base.size * factor
	if id == "reticle":
		return Rect2((size - dimensions) * 0.5, dimensions)
	# Store a fraction of available travel, preserving edge placement on resize.
	var position_ratio: Vector2 = entry["position"]
	var origin := position_ratio * (size - dimensions).max(Vector2.ZERO)
	if editing:
		origin.y = maxf(24, origin.y)
	return Rect2(origin, dimensions)


func store_rect(id: String, rect: Rect2) -> void:
	var base := default_rect(id)
	var factor := clampf(rect.size.x / base.size.x, MIN_SCALE, 3.0)
	factor = minf(factor, minf(size.x / base.size.x, (size.y - 24) / base.size.y))
	var dimensions := base.size * factor
	if id == "reticle":
		entries[id] = {"scale": factor, "visible": shown(id)}
		return
	var travel := (size - dimensions).max(Vector2.ZERO)
	var origin := rect.position.clamp(Vector2.ZERO, travel)
	entries[id] = {"position": origin / travel.max(Vector2.ONE), "scale": factor, "visible": shown(id)}


func begin_draw(canvas: Control, id: String) -> bool:
	if not shown(id):
		return false
	var base := default_rect(id)
	var actual := rect_for(id)
	var factor := actual.size.x / base.size.x
	canvas.draw_set_transform(actual.position - base.position * factor, 0, Vector2.ONE * factor)
	return true


func end_draw(canvas: Control) -> void:
	canvas.draw_set_transform(Vector2.ZERO)


func transform_rect(id: String, drawn_rect: Rect2) -> Rect2:
	var base := default_rect(id)
	var actual := rect_for(id)
	var factor := actual.size.x / base.size.x
	return Rect2(actual.position + (drawn_rect.position - base.position) * factor, drawn_rect.size * factor)


func set_editing(value: bool, resume: bool = true) -> void:
	if value == editing:
		return
	if value and (hud.sector.preflight or hud.sector.paused or not hud.sector.player.alive or (hud.sector.client_only and not hud.sector.session.active)):
		return
	editing = value
	drag_id = ""
	sidebar.visible = value
	rail_toggle.hide()
	if value:
		hud.sector.set_paused(true)
	else:
		save_layout()
		if resume:
			hud.sector.set_paused(false)
	queue_redraw()


func reopen(id: String) -> void:
	var entry: Dictionary = entries.get(id, {})
	entry["visible"] = true
	entries[id] = entry
	selected_id = id
	if id == "performance":
		hud.sector.settings.show_performance = true
		hud.sector.show_performance = true
		hud.sector.settings.save()
	# Hide the rail when it covers the selected panel, so its full saved position
	# can be edited without relocating it just by opening the editor.
	if rect_for(id).intersects(sidebar.get_rect()):
		sidebar.hide()
		rail_toggle.show()
	queue_redraw()


func close_item(id: String) -> void:
	var entry: Dictionary = entries.get(id, {})
	entry["visible"] = false
	entries[id] = entry
	queue_redraw()


func reset_layout() -> void:
	entries.clear()
	selected_id = ""
	save_layout()
	queue_redraw()


func save_layout() -> void:
	var config := ConfigFile.new()
	for id: String in entries:
		for key: String in entries[id]:
			config.set_value(id, key, entries[id][key])
	if config.save(save_path) != OK:
		hud.sector.notify("Could not save HUD layout.")


func load_layout() -> void:
	entries.clear()
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	for id: String in ITEMS:
		if not config.has_section(id):
			continue
		var entry := {"visible": config.get_value(id, "visible", true) == true}
		var position_ratio: Variant = config.get_value(id, "position") if config.has_section_key(id, "position") else null
		var factor: Variant = config.get_value(id, "scale", 1.0)
		var valid_scale: bool = (factor is float or factor is int) and is_finite(float(factor))
		if id == "reticle" and valid_scale:
			entry["scale"] = clampf(float(factor), MIN_SCALE, 3.0)
		elif position_ratio is Vector2 and is_finite(position_ratio.x) and is_finite(position_ratio.y) and valid_scale:
			entry["position"] = position_ratio.clamp(Vector2.ZERO, Vector2.ONE)
			entry["scale"] = clampf(float(factor), MIN_SCALE, 3.0)
		entries[id] = entry


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		# Toggle once on the modifier chord; ignore key repeat and right Alt / AltGr.
		# Windows omits a modifier's own flag on that key's event. Include the
		# currently pressed key, so either Ctrl-then-Alt or Alt-then-Ctrl works.
		var control: bool = event.ctrl_pressed or (event.keycode == KEY_CTRL and event.pressed)
		var alt: bool = event.alt_pressed or (event.keycode == KEY_ALT and event.pressed)
		var chord: bool = control and alt and not event.shift_pressed and not event.meta_pressed and not (event.keycode == KEY_ALT and event.location == KEY_LOCATION_RIGHT)
		if event.keycode in [KEY_CTRL, KEY_ALT]:
			if event.pressed and chord and not chord_down and not event.echo:
				chord_down = true
				set_editing(not editing)
				get_viewport().set_input_as_handled()
			elif not event.pressed:
				chord_down = false
		if editing and event.pressed and event.keycode == KEY_ESCAPE:
			set_editing(false)
			get_viewport().set_input_as_handled()
	if not editing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			drag_id = ""
		elif not over_rail(event.position):
			var order: Array = ITEMS.keys()
			if not selected_id.is_empty():
				order.erase(selected_id)
				order.append(selected_id)
			order.reverse()
			for id: String in order:
				if not shown(id):
					continue
				var rect := rect_for(id)
				if Rect2(rect.position - Vector2(0, 24), Vector2(rect.size.x, 24)).has_point(event.position) and event.position.x > rect.end.x - 24:
					close_item(id)
					break
				if rect.grow_individual(0, 24, 0, 0).has_point(event.position):
					drag_id = id
					selected_id = id
					drag_start = event.position
					drag_rect = rect
					resizing = Rect2(rect.end - Vector2(24, 24), Vector2(24, 24)).has_point(event.position)
					if id == "reticle" and not resizing:
						drag_id = ""
					break
	if event is InputEventMouseMotion and not drag_id.is_empty():
		var delta: Vector2 = event.position - drag_start
		var rect := drag_rect
		if resizing:
			if drag_id == "reticle":
				delta *= 2.0 # Resizing expands equally on both sides of the center.
			# Project the pointer onto the aspect-ratio diagonal, supporting both axes.
			var aspect := default_rect(drag_id).size.normalized()
			var width := drag_rect.size.x + delta.dot(aspect) * aspect.x
			if snap:
				width = snappedf(width, GRID)
			rect.size = default_rect(drag_id).size * (width / default_rect(drag_id).size.x)
		else:
			rect.position += delta
			if snap:
				rect.position = rect.position.snapped(Vector2.ONE * GRID)
			rect.position.y = maxf(24, rect.position.y)
		store_rect(drag_id, rect)
		queue_redraw()
	# The sidebar still receives GUI events; everything else is editor input.
	if not (event is InputEventMouse and over_rail(event.position) and drag_id.is_empty()):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		drag_id = ""
		chord_down = false


func over_rail(point: Vector2) -> bool:
	return sidebar.visible and sidebar.get_rect().has_point(point) or rail_toggle.visible and rail_toggle.get_rect().has_point(point)


func _process(_delta: float) -> void:
	if editing and (hud.sector.preflight or not hud.sector.player.alive or (hud.sector.client_only and not hud.sector.session.active)):
		set_editing(false, false)
	if editing:
		sidebar.position = Vector2.ZERO
		sidebar.size = Vector2(224, size.y)
		for id: String in buttons:
			buttons[id].modulate = FlightHud.INK if shown(id) else FlightHud.AMBER
		queue_redraw()


func _draw() -> void:
	if not editing:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.06, 0.2))
	for x in range(0, int(size.x), int(GRID)):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(FlightHud.CYAN, 0.12))
	for y in range(0, int(size.y), int(GRID)):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(FlightHud.CYAN, 0.12))
	var order: Array = ITEMS.keys()
	if not selected_id.is_empty():
		order.erase(selected_id)
		order.append(selected_id)
	for id: String in order:
		if not shown(id):
			continue
		var rect := rect_for(id)
		draw_rect(rect, Color(FlightHud.AMBER, 0.95 if id == selected_id else 0.55), false, 2 if id == selected_id else 1)
		var header := Rect2(rect.position - Vector2(0, 24), Vector2(rect.size.x, 24))
		draw_rect(header, Color("263039"))
		draw_string(StationUi.FONT, header.position + Vector2(6, 17), ITEMS[id][0], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 30, 14, FlightHud.INK)
		draw_string(StationUi.FONT, Vector2(rect.end.x - 18, rect.position.y - 7), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, FlightHud.AMBER)
		draw_line(rect.end - Vector2(18, 3), rect.end - Vector2(3, 18), FlightHud.AMBER, 3)
