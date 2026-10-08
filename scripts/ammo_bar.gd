class_name AmmoBar
extends Control
## One mixed instrument; weapon rules remain in existing combat commands.

var sector: Sector
var config := Quickslots.new()
var tiles: Array[QuickslotTile] = []
var buttons: Dictionary[String, Button] = {}
var counts: Dictionary[String, Label] = {}
var single_fire: Button
var launcher_fire: Button
var unload_button: Button
var toolbar: HBoxContainer
var picker: PanelContainer
var tabs: TabContainer
var picker_tiles: Array[QuickslotTile] = []
var slot_editing := false
var selected_slot := -1
var selection_label: Label
var picker_help: Label
var items_button: Button
var orientation_button: Button
var clear_button: Button
var reset_button: Button
var extras: Dictionary = {}


func _ready() -> void:
	name = "AmmoBar"
	config.load_from()
	for index in config.slots.size():
		var tile := QuickslotTile.new()
		tile.bar = self
		tile.slot = index
		add_child(tile)
		tiles.append(tile)
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 2)
	add_child(toolbar)
	items_button = StationUi.button(toolbar, "+", func():
		if picker.visible:
			close_picker()
		else:
			begin_editing())
	items_button.tooltip_text = "Open items and customize quickslots"
	items_button.custom_minimum_size = Vector2(34, 30)
	build_picker()
	config.changed.connect(func():
		if not config.save():
			sector.notify("Could not save quickslots.")
		refresh_tiles())
	get_parent().resized.connect(update_geometry)


func build_picker() -> void:
	picker = PanelContainer.new()
	add_child(picker)
	picker.set_as_top_level(true)
	picker.z_index = 20
	picker.add_theme_stylebox_override("panel", StationUi.style(StationUi.SURFACE, FlightHud.LINE))
	var rows := StationUi.rows(picker, 8)
	rows.add_theme_constant_override("separation", 4)
	var header := HBoxContainer.new()
	rows.add_child(header)
	selection_label = StationUi.text(header, "QUICKSLOTS", 18, FlightHud.AMBER)
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := StationUi.button(header, "Close", close_picker)
	close.custom_minimum_size.y = 28
	close.add_theme_font_size_override("font_size", 16)
	picker_help = StationUi.text(rows, "Click an item to use. Drag to assign, or click a slot then an item.", 14)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(tabs)
	rebuild_picker()
	var footer := HBoxContainer.new()
	rows.add_child(footer)
	clear_button = StationUi.button(footer, "Clear slot", func(): config.assign(selected_slot, ""))
	reset_button = StationUi.button(footer, "Reset slots", config.reset_slots)
	orientation_button = StationUi.button(footer, "Vertical", toggle_orientation)
	var done := StationUi.button(footer, "Done", close_picker)
	for button: Button in [clear_button, reset_button, orientation_button, done]:
		button.custom_minimum_size.y = 28
		button.add_theme_font_size_override("font_size", 16)
	picker.hide()


func rebuild_picker() -> void:
	for child: Node in tabs.get_children():
		tabs.remove_child(child)
		child.queue_free()
	picker_tiles.clear()
	for category: String in ["Lasers", "Rockets", "Hellstorm", "Extras"]:
		var scroll := ScrollContainer.new()
		scroll.name = category
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		scroll.add_child(grid)
		var actions: Array[String] = []
		if category == "Lasers":
			for kind: String in Ammunition.TYPES:
				actions.append("ammo:" + kind)
		elif category in ["Rockets", "Hellstorm"]:
			for kind: String in Ammunition.ROCKETS:
				if Ammunition.ROCKETS[kind]["launcher"] == (category == "Hellstorm"):
					actions.append("ammo:" + kind)
			actions.append("rocket:single" if category == "Rockets" else "rocket:launcher")
			if category == "Hellstorm":
				actions.append("rocket:unload")
		else:
			actions.assign(extras.keys())
		if actions.is_empty():
			StationUi.text(grid, "Usable extras appear here when available.", 14)
		for action: String in actions:
			var tile := QuickslotTile.new()
			tile.bar = self
			tile.action_id = action
			tile.custom_minimum_size = Vector2(86, 80)
			grid.add_child(tile)
			picker_tiles.append(tile)


# Extras owners register their command and live state. Saved IDs survive removal.
# State returns name/icon/count/active/available/tooltip. Commands must use their
# normal authoritative request path; the bar never grants an equipment effect.
func register_extra(id: String, state: Callable, command: Callable) -> void:
	var action := "extra:" + id
	if not Quickslots.valid_id(action) or not state.is_valid() or not command.is_valid():
		return
	extras[action] = {"state": state, "command": command}
	if is_instance_valid(tabs):
		rebuild_picker()


func unregister_extra(id: String) -> void:
	extras.erase("extra:" + id)
	if is_instance_valid(tabs):
		rebuild_picker()


func begin_editing() -> void:
	if sector.hud.layout.editing or sector.paused or sector.preflight or not sector.player.alive or (sector.client_only and not sector.session.active):
		return
	slot_editing = true
	selected_slot = -1
	picker.show()
	refresh_tiles()


func close_picker() -> void:
	slot_editing = false
	selected_slot = -1
	picker.hide()


func select_slot(index: int) -> void:
	selected_slot = index
	refresh_tiles()


func assign_selected(action: String) -> void:
	if slot_editing and selected_slot >= 0:
		config.assign(selected_slot, action)
		selected_slot = -1
		refresh_tiles()


func toggle_orientation() -> void:
	if not slot_editing:
		return
	var layout := sector.hud.layout
	var previous := layout.rect_for("ammo")
	var factor := previous.size.x / default_rect().size.x
	config.vertical = not config.vertical
	var dimensions := default_rect().size * factor
	layout.store_rect("ammo", Rect2(previous.get_center() - dimensions * 0.5, dimensions))
	layout.save_layout()
	config.changed.emit()
	update_geometry()


func default_rect() -> Rect2:
	var hud_size: Vector2 = get_parent().size
	if config.vertical:
		return Rect2(Vector2(hud_size.x - 122, 24), Vector2(90, 548))
	var dimensions := Vector2(745, 80)
	return Rect2(Vector2((hud_size.x - dimensions.x) * 0.5, hud_size.y - FlightHud.BOTTOM_MARGIN - 182 - dimensions.y), dimensions)


func update_geometry() -> void:
	if not is_instance_valid(sector.hud) or not is_instance_valid(sector.hud.layout):
		return
	var rect := sector.hud.layout.rect_for("ammo")
	size = default_rect().size
	position = rect.position
	scale = Vector2.ONE * (rect.size.x / size.x)
	for index in tiles.size():
		tiles[index].position = Vector2(0, index * 51) if config.vertical else Vector2(index * 71, 0)
		tiles[index].size = Vector2(90, 48) if config.vertical else Vector2(66, 80)
	toolbar.position = Vector2(0, 510) if config.vertical else Vector2(710, 0)
	toolbar.size = Vector2(90, 38) if config.vertical else Vector2(35, 80)
	var area: Vector2 = get_parent().size
	var above := rect.position.y - 24
	var below := area.y - rect.end.y - 24
	var height := minf(320, maxf(210, maxf(above, below)))
	picker.size = Vector2(minf(620, area.x - 32), height)
	picker_help.visible = height >= 280
	for tile: QuickslotTile in picker_tiles:
		tile.custom_minimum_size.y = 64 if height < 280 else 80
	var origin := Vector2(rect.position.x, rect.position.y - picker.size.y - 8 if above >= below else rect.end.y + 8)
	if config.vertical:
		origin = Vector2(rect.position.x - picker.size.x - 8 if rect.position.x >= picker.size.x + 24 else rect.end.x + 8, rect.position.y)
	picker.position = origin.clamp(Vector2(16, 16), (area - picker.size - Vector2(16, 16)).max(Vector2(16, 16)))


func state_for(action: String) -> Dictionary:
	var ship := sector.player
	if action.begins_with("ammo:"):
		var kind := action.trim_prefix("ammo:")
		if Ammunition.TYPES.has(kind):
			var amount := int(ship.ammo.get(kind, 0))
			return {"name": kind, "icon": StationUi.texture(kind), "count": compact_count(amount), "active": ship.ammo_type == kind, "color": FlightHud.INK if amount >= maxi(1, ship.laser_count) else FlightHud.RED, "tooltip": "%s / %dx laser damage / %s shots\n%d rounds per volley (%d installed lasers)" % [kind, Ammunition.TYPES[kind]["multiplier"], StationShop.credits_text(amount), ship.laser_count, ship.laser_count]}
		if Ammunition.ROCKETS.has(kind):
			var rockets := ship.rockets
			var amount := rockets.available(kind)
			return {"name": Ammunition.ROCKETS[kind]["name"], "icon": StationUi.texture(kind), "count": compact_count(amount), "active": kind in [rockets.single_type, rockets.launcher_type], "color": FlightHud.INK if amount > 0 else FlightHud.RED, "tooltip": "%s\n%s\n%s available / select ammunition" % [Ammunition.ROCKETS[kind]["name"], StationShop.ammo_description(kind), StationShop.credits_text(amount)]}
	if action.begins_with("rocket:"):
		var rockets := ship.rockets
		if action == "rocket:single":
			return {"name": "Rocket", "icon": StationUi.texture(rockets.single_type), "count": "%.1fs" % rockets.single_cooldown if rockets.single_cooldown > 0 else "FIRE", "tooltip": "Fire one selected %s rocket. Independent of laser fire." % Ammunition.ROCKETS[rockets.single_type]["name"]}
		if action == "rocket:launcher":
			var dots := ""
			for index in rockets.capacity:
				dots += "●" if index < rockets.loaded else "○"
			var status := "%.1fs" % rockets.launcher_cooldown if rockets.launcher_cooldown > 0 else ("%.1fs LOAD" % rockets.load_clock if rockets.loading else ("FIRE %d" % rockets.loaded if rockets.loaded > 0 else "LOAD"))
			return {"name": "Hellstorm", "icon": StationUi.texture("hst-2" if rockets.capacity == 5 else "hst-1") if rockets.capacity > 0 else null, "count": dots + "\n" + status, "compact": "%d/%d %s" % [rockets.loaded, rockets.capacity, status], "available": rockets.capacity > 0, "tooltip": "Load without a target; activate again to fire loaded %s rockets.\n%s / %s" % [Ammunition.ROCKETS[rockets.launcher_type]["name"], dots if rockets.capacity > 0 else "No launcher equipped", status]}
		if action == "rocket:unload":
			return {"name": "Unload", "count": str(rockets.loaded), "available": rockets.loaded > 0 or rockets.loading, "tooltip": "Unload Hellstorm and release unfired ammunition."}
	if extras.has(action) and extras[action]["state"].is_valid() and extras[action]["command"].is_valid():
		var value: Variant = extras[action]["state"].call()
		if value is Dictionary:
			return value.merged({"name": action.get_slice(":", 1), "available": false})
	return {"name": "Empty" if action.is_empty() else action.get_slice(":", 1), "available": false, "tooltip": "Empty slot" if action.is_empty() else "This action is unavailable on the active ship."}


static func compact_count(amount: int) -> String:
	return StationShop.credits_text(amount) if amount < 1000000 else ("%.1fM" % (amount / 1000000.0) if amount < 1000000000 else "%.1fB" % (amount / 1000000000.0))


func activate(action: String) -> void:
	if sector.paused or sector.preflight or not sector.player.alive or (sector.client_only and not sector.session.active) or not state_for(action).get("available", true):
		return
	if action.begins_with("ammo:"):
		sector.session.combat.request_ammo(action.trim_prefix("ammo:"))
	elif action.begins_with("rocket:"):
		sector.session.combat.request_rocket(action.trim_prefix("rocket:"))
	elif extras.has(action) and extras[action]["command"].is_valid():
		extras[action]["command"].call()


func refresh_tiles() -> void:
	buttons.clear()
	counts.clear()
	single_fire = null
	launcher_fire = null
	unload_button = null
	for index in tiles.size():
		var tile := tiles[index]
		tile.action_id = config.slots[index]
		if not is_instance_valid(tile.amount) or not is_instance_valid(sector.hud.layout):
			continue
		tile.refresh(state_for(tile.action_id), GameSettings.binding_text("quickslot_%d" % (index + 1)))
		if tile.action_id.begins_with("ammo:"):
			var kind := tile.action_id.trim_prefix("ammo:")
			buttons[kind] = tile
			counts[kind] = tile.amount
		match tile.action_id:
			"rocket:single": single_fire = tile
			"rocket:launcher": launcher_fire = tile
			"rocket:unload": unload_button = tile
	for tile: QuickslotTile in picker_tiles:
		tile.refresh(state_for(tile.action_id), "")
	selection_label.text = "EDIT SLOT %d" % (selected_slot + 1) if slot_editing and selected_slot >= 0 else "QUICKSLOTS"
	clear_button.disabled = selected_slot < 0
	for button: Button in [clear_button, reset_button, orientation_button]:
		button.visible = slot_editing
	orientation_button.text = "Horizontal" if config.vertical else "Vertical"


func _process(_delta: float) -> void:
	var layout := sector.hud.layout
	visible = not sector.preflight and (not sector.paused or layout.editing) and sector.player.alive and (not sector.client_only or sector.session.active) and layout.shown("ammo")
	if not visible:
		close_picker()
		return
	items_button.disabled = layout.editing
	z_index = 5 if slot_editing else 0
	update_geometry()
	refresh_tiles()
