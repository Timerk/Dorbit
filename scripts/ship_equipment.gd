class_name ShipEquipment
extends PanelContainer
## Visual fitting for the active hull; authoritative inventory changes only on reply.

var sector: Sector
var summary: Label
var ship_stats: Label
var storage_count: Label
var detail: Label
var preview: Label
var status: Label
var storage_panel: PanelContainer
var storage_grid: GridContainer
var empty_storage: Label
var remove_button: Button
var slots: Dictionary[String, EquipmentTile] = {}
var stored: Dictionary[String, EquipmentTile] = {}
var selected_item: String = ""
var last_inventory: Dictionary = {}
var drop_hint: String = ""
var ship_title: Label
var ship_art: TextureRect
var ship_choice: OptionButton
var activate_button: Button
var owned_ships: Array[String] = []
var slot_rows: VBoxContainer
var current_slot_model: String = ""
var navigation_bar: HBoxContainer
var specifications: PanelContainer
var stat_values: Dictionary[String, Label] = {}
var stat_notes: Dictionary[String, Label] = {}


func _ready() -> void:
	StationUi.frame(self, Vector2(1150, 690))
	get_viewport().size_changed.connect(fit_window)
	var rows := StationUi.rows(self, 16)
	navigation_bar = StationUi.navigation(rows, sector, "equipment", close)
	summary = StationUi.text(rows, "HANGAR", 28)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	var ship_card := StationUi.card(body)
	ship_card.custom_minimum_size.x = 320
	ship_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ship_card.size_flags_stretch_ratio = 1.3
	var ship_rows := StationUi.rows(ship_card, 14)
	ship_title = StationUi.text(ship_rows, "LIBERATOR", 28)
	ship_choice = OptionButton.new()
	ship_rows.add_child(ship_choice)
	ship_art = StationUi.art(ship_rows, "ship", Vector2(0, 180))
	ship_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	activate_button = StationUi.button(ship_rows, "ACTIVE", activate_selected)
	StationUi.primary(activate_button)
	var fitting := StationUi.card(body)
	fitting.custom_minimum_size.x = 360
	fitting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fitting_rows := StationUi.rows(fitting, 12)
	StationUi.text(fitting_rows, "EQUIPMENT", 22)
	var fitting_scroll := ScrollContainer.new()
	fitting_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fitting_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fitting_rows.add_child(fitting_scroll)
	slot_rows = VBoxContainer.new()
	slot_rows.add_theme_constant_override("separation", 10)
	slot_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fitting_scroll.add_child(slot_rows)
	rebuild_slots("liberator")
	remove_button = StationUi.button(fitting_rows, "REMOVE", func(): move_item(selected_item, ""))
	remove_button.mouse_entered.connect(preview_removal)
	remove_button.focus_entered.connect(preview_removal)
	storage_panel = StationUi.card(body)
	storage_panel.custom_minimum_size.x = 260
	storage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_panel.set_drag_forwarding(Callable(), storage_can_drop, storage_drop)
	var storage_rows := StationUi.rows(storage_panel, 12)
	storage_count = StationUi.text(storage_rows, "INVENTORY", 22)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	storage_rows.add_child(scroll)
	storage_grid = GridContainer.new()
	storage_grid.columns = 3
	storage_grid.add_theme_constant_override("h_separation", 6)
	storage_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(storage_grid)
	empty_storage = StationUi.text(storage_rows, "Inventory empty", 18, StationUi.MUTED)
	empty_storage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_storage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for control: Control in [storage_rows.get_parent(), storage_rows, scroll, storage_grid, storage_count, empty_storage]:
		control.set_drag_forwarding(Callable(), storage_can_drop, storage_drop)
	detail = StationUi.text(rows, "", 16, StationUi.MUTED)
	preview = StationUi.text(rows, "", 16, Color("a7e277"))
	status = StationUi.text(rows, "", 16, StationUi.AMBER)
	specifications = StationUi.card(rows)
	var stats_rows := StationUi.rows(specifications, 12)
	StationUi.text(stats_rows, "SHIP SPECIFICATIONS", 16, StationUi.MUTED)
	stats_rows.add_child(HSeparator.new())
	var stats_bar := HBoxContainer.new()
	stats_bar.add_theme_constant_override("separation", 12)
	stats_rows.add_child(stats_bar)
	for entry: Array in [["hull", "Hull"], ["shield", "Shield"], ["damage", "Damage"], ["speed", "Cruise"], ["cargo", "Cargo"]]:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_bar.add_child(cell)
		var icon := StationUi.art(cell, "ship", Vector2(28, 28))
		icon.texture = load("res://assets/ui/menu/%s.svg" % entry[0])
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var values := VBoxContainer.new()
		values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		values.add_theme_constant_override("separation", 0)
		cell.add_child(values)
		stat_values[entry[0]] = StationUi.text(values, "", 24)
		stat_values[entry[0]].autowrap_mode = TextServer.AUTOWRAP_OFF
		var caption := StationUi.text(values, entry[1], 16, StationUi.MUTED)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		stat_notes[entry[0]] = StationUi.text(values, "", 14, StationUi.MUTED)
		stat_notes[entry[0]].autowrap_mode = TextServer.AUTOWRAP_OFF
	ship_stats = StationUi.text(stats_rows, "", 14, StationUi.MUTED)
	fit_window()
	hide()


func fit_window() -> void:
	if sector.preflight and is_instance_valid(sector.main_menu):
		sector.main_menu.fit_panel(self, Vector2(1150, 690))
		return
	StationUi.centered(self, Vector2(1150, 690))


func inventory() -> Dictionary:
	return sector.session.combat.inventory


func slots_kind(slot: String) -> String:
	return ShipCatalog.slots(current_slot_model).get(slot, "")


func rebuild_slots(model_id: String) -> void:
	if current_slot_model == model_id:
		return
	current_slot_model = model_id
	for child in slot_rows.get_children():
		slot_rows.remove_child(child)
		child.queue_free()
	slots.clear()
	var available := ShipCatalog.slots(model_id)
	for kind: String in ["laser", "generator", "extra"]:
		StationUi.text(slot_rows, "%s / %d SLOTS" % [kind.to_upper() + "S", available.values().count(kind)], 13, Color("f4c778") if kind == "laser" else FlightHud.CYAN)
		var group := GridContainer.new()
		group.columns = 4
		group.add_theme_constant_override("h_separation", 6)
		group.add_theme_constant_override("v_separation", 6)
		slot_rows.add_child(group)
		for slot: String in available:
			if available[slot] != kind:
				continue
			var tile := EquipmentTile.new()
			tile.screen = self
			tile.slot = slot
			tile.compact = true
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			group.add_child(tile)
			slots[slot] = tile


func activate_selected() -> void:
	if ship_choice.selected < 0 or not StationUi.blocker(sector).is_empty():
		return
	sector.session.combat.request_station("switch_ship", owned_ships[ship_choice.selected])


func open() -> void:
	if not StationUi.can_open(sector):
		return
	sector.shop.hide()
	sector.hud.contract_panel.hide()
	sector.session.menu.hide()
	sector.set_paused(true)
	fit_window()
	show()
	refresh_inventory()


func close() -> void:
	hide()
	drop_hint = ""
	sector.set_paused(false)


func refresh_inventory() -> void:
	var data := inventory()
	if data.is_empty() or data == last_inventory:
		return
	last_inventory = data.duplicate(true)
	var model_id: String = ShipCatalog.canonical(data["ships"][data["active_ship"]])
	rebuild_slots(model_id)
	ship_title.text = ShipCatalog.info(model_id)["name"].to_upper()
	ship_art.texture = StationUi.ship_texture(model_id)
	ship_choice.clear()
	owned_ships.clear()
	for id: String in data["ships"]:
		owned_ships.append(id)
		ship_choice.add_item(ShipCatalog.info(data["ships"][id])["name"] + (" (active)" if id == data["active_ship"] else ""))
		if id == data["active_ship"]:
			ship_choice.select(owned_ships.size() - 1)
	if not data["items"].has(selected_item):
		selected_item = ""
	for tile: EquipmentTile in stored.values():
		storage_grid.remove_child(tile)
		tile.queue_free()
	stored.clear()
	for slot: String in slots:
		slots[slot].item_id = ""
	for id: String in data["items"]:
		var item: Dictionary = data["items"][id]
		if item["ship"] == data["active_ship"]:
			slots[item["slot"]].item_id = id
		elif item["ship"].is_empty():
			var tile := EquipmentTile.new()
			tile.screen = self
			tile.item_id = id
			storage_grid.add_child(tile)
			stored[id] = tile
	for tile: EquipmentTile in slots.values():
		tile.refresh()
	storage_count.text = "INVENTORY / %d" % stored.size()
	empty_storage.visible = stored.is_empty()
	update_stats()
	drop_hint = ""
	preview.text = ""


func update_stats() -> void:
	var values := Equipment.stats(inventory())
	stat_values["hull"].text = StationShop.credits_text(int(values["hull"]))
	stat_values["shield"].text = StationShop.credits_text(int(values["shield"]))
	stat_values["damage"].text = str(int(values["damage"]))
	stat_values["speed"].text = "%d m/s" % values["speed"]
	stat_values["cargo"].text = "%d / %d" % [CargoResources.units(sector.cargo), CargoResources.capacity(inventory())]
	stat_notes["shield"].text = "%d%% absorption" % roundi(values["absorption"] * 100)
	stat_notes["speed"].text = "%d m/s boost" % values["boost"]
	ship_stats.text = ""
	if values["npc_damage"] > 0.0:
		ship_stats.text = "+%.2f damage against aliens" % values["npc_damage"]
	if values["regen_bonus"] > 0.0:
		ship_stats.text += ("   /   " if not ship_stats.text.is_empty() else "") + "+%.2f%% shield regeneration" % (values["regen_bonus"] * 100)
	ship_stats.visible = not ship_stats.text.is_empty()


func select_item(id: String) -> void:
	selected_item = id
	for tile: EquipmentTile in slots.values() + stored.values():
		tile.refresh()
	var item: Dictionary = inventory()["items"].get(id, {})
	if not item.is_empty():
		detail.text = "%s / %s" % [Equipment.MODELS[item["model"]]["name"], StationUi.bonus(item["model"])]
	preview.text = ""


func choose(tile: EquipmentTile) -> void:
	if not tile.slot.is_empty() and tile.item_id.is_empty() and not selected_item.is_empty():
		move_item(selected_item, tile.slot)
	elif not tile.item_id.is_empty():
		select_item(tile.item_id)


func inspect_tile(tile: EquipmentTile) -> void:
	if not selected_item.is_empty() and not tile.slot.is_empty():
		show_proposal(selected_item, tile.slot)


func preview_removal() -> void:
	if not selected_item.is_empty():
		show_proposal(selected_item, "")


func reason(id: String, slot: String) -> String:
	var blocked := StationUi.blocker(sector)
	if not blocked.is_empty():
		return blocked
	return Equipment.fitting_blocker(inventory(), id, inventory()["active_ship"] if not slot.is_empty() else "", slot)


func show_proposal(id: String, slot: String) -> void:
	var blocked := reason(id, slot)
	if not blocked.is_empty():
		preview.text = blocked
		return
	var proposed := inventory().duplicate(true)
	proposed["items"][id]["ship"] = proposed["active_ship"] if not slot.is_empty() else ""
	proposed["items"][id]["slot"] = slot
	var values := Equipment.stats(proposed)
	preview.text = "After %s: %d damage / %d shield (%d%%) / %d m/s cruise / %d m/s boost" % ["install" if not slot.is_empty() else "removal", values["damage"], values["shield"], roundi(values["absorption"] * 100), values["speed"], values["boost"]]
	if values["npc_damage"] > 0.0:
		preview.text += " / +%.2f alien damage" % values["npc_damage"]
	if values["regen_bonus"] > 0.0:
		preview.text += " / +%.2f%% shield regeneration" % (values["regen_bonus"] * 100)


func valid_drag(data: Variant) -> bool:
	return data is Dictionary and data.get("screen") == self and data.get("equipment_item") is String and inventory().get("items", {}).has(data["equipment_item"])


func can_drop(data: Variant, slot: String) -> bool:
	if not visible or not valid_drag(data):
		return false
	drop_hint = reason(data["equipment_item"], slot)
	show_proposal(data["equipment_item"], slot)
	return drop_hint.is_empty()


func drop_item(data: Variant, slot: String) -> void:
	if visible and valid_drag(data):
		move_item(data["equipment_item"], slot)


func storage_can_drop(_position: Vector2, data: Variant) -> bool:
	return can_drop(data, "")


func storage_drop(_position: Vector2, data: Variant) -> void:
	drop_item(data, "")


func move_item(id: String, slot: String) -> void:
	var blocked := reason(id, slot)
	if not blocked.is_empty():
		drop_hint = blocked
		return
	sector.session.combat.request_station("fit", id, inventory()["active_ship"] if not slot.is_empty() else "", slot)
	drop_hint = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_hint = ""
		if is_instance_valid(preview):
			preview.text = ""


func _process(_delta: float) -> void:
	if not visible:
		return
	var combat := sector.session.combat
	if not sector.session.active or sector.session.menu.visible or inventory().is_empty():
		hide()
		return
	navigation_bar.visible = not sector.preflight
	fit_window()
	refresh_inventory()
	update_stats()
	var blocked := StationUi.blocker(sector)
	activate_button.disabled = not blocked.is_empty() or ship_choice.selected < 0 or owned_ships[ship_choice.selected] == inventory()["active_ship"]
	activate_button.tooltip_text = blocked if not blocked.is_empty() else "Switch for free. Fittings and cargo stay with each ship; switching does not repair hull or recharge shields."
	activate_button.text = "ACTIVE" if ship_choice.selected >= 0 and owned_ships[ship_choice.selected] == inventory()["active_ship"] else "ACTIVATE"
	remove_button.visible = not selected_item.is_empty() and not inventory()["items"].get(selected_item, {}).get("ship", "").is_empty()
	remove_button.disabled = selected_item.is_empty() or not reason(selected_item, "").is_empty()
	remove_button.tooltip_text = "Select an installed item to remove it." if selected_item.is_empty() else reason(selected_item, "")
	status.text = blocked if not blocked.is_empty() else (drop_hint if not drop_hint.is_empty() else combat.station_message)
	status.visible = not status.text.is_empty()
	preview.visible = not preview.text.is_empty()
	detail.visible = not selected_item.is_empty()
