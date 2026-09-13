class_name StationShop
extends PanelContainer
## Station actions send intent; the server replies with the committed inventory.

var sector: Sector
var summary: Label
var status: Label
var items: ItemList
var destination: OptionButton
var preview: Label
var fit_button: Button
var remove_button: Button
var buys: Dictionary[String, Button] = {}
var item_ids: Array[String] = []
var destinations: Array[Dictionary] = []
var last_inventory: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -430
	offset_right = 430
	offset_top = -260
	offset_bottom = 260
	add_theme_stylebox_override("panel", FlightHud.panel_style())
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "OUTPOST 01 / EQUIPMENT & FITTING"
	title.add_theme_font_size_override("font_size", 23)
	rows.add_child(title)
	summary = label(rows)
	for model: String in Equipment.MODELS:
		var info: Dictionary = Equipment.MODELS[model]
		var button := sector.session.add_button(rows, "", func(): sector.session.combat.request_station("buy", model))
		button.tooltip_text = "%s: +%.0f damage, +%.0f shield, +%.0f cruise and boost speed" % [info["name"], info["damage"], info["shield"], info["speed"]]
		buys[model] = button
	label(rows).text = "Owned items / select an item to fit or remove. Fitting is free."
	items = ItemList.new()
	items.custom_minimum_size.y = 100
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(items)
	var controls := HBoxContainer.new()
	rows.add_child(controls)
	destination = OptionButton.new()
	destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(destination)
	fit_button = sector.session.add_button(controls, "Install / transfer", fit_selected)
	remove_button = sector.session.add_button(controls, "Move to storage", func(): sector.session.combat.request_station("fit", selected_item()))
	preview = label(rows)
	status = label(rows)
	status.custom_minimum_size.y = 24
	sector.session.add_button(rows, "Back to flight [B / Esc]", close)
	hide()


func label(parent: Node) -> Label:
	var value := Label.new()
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(value)
	return value


func open() -> void:
	if not sector.session.active or sector.session.combat.inventory.is_empty():
		sector.notify("Equipment is available on a persistent dedicated server.")
		return
	var blocker := sector.repair_blocker()
	if not blocker.is_empty():
		sector.notify(blocker)
		return
	sector.session.menu.hide()
	sector.hud.contract_panel.hide()
	sector.set_paused(true)
	show()


func close() -> void:
	hide()
	sector.set_paused(false)


func selected_item() -> String:
	var selected := items.get_selected_items()
	return item_ids[selected[0]] if not selected.is_empty() else ""


func fit_selected() -> void:
	if destination.selected < 0:
		return
	var target := destinations[destination.selected]
	sector.session.combat.request_station("fit", selected_item(), target["ship"], target["slot"])


static func stats_text(values: Dictionary) -> String:
	return "%.0f damage/shot | %.0f shield | %.0f m/s cruise | %.0f m/s boost" % [values["damage"], values["shield"], values["speed"], values["boost"]]


func _process(_delta: float) -> void:
	if not visible:
		return
	var combat := sector.session.combat
	if not sector.session.active or sector.session.menu.visible or combat.inventory.is_empty():
		hide()
		return
	var data := combat.inventory
	if data != last_inventory:
		var selection := selected_item()
		var selected_destination := destination.selected
		last_inventory = data.duplicate(true)
		items.clear()
		item_ids.clear()
		for id: String in data["items"]:
			var item: Dictionary = data["items"][id]
			item_ids.append(id)
			items.add_item("%s / %s / %s" % [Equipment.MODELS[item["model"]]["name"], id, "Storage" if item["ship"] == "" else item["ship"] + " / " + item["slot"]])
		if not item_ids.is_empty():
			items.select(maxi(0, item_ids.find(selection)))
		destination.clear()
		destinations.clear()
		for ship: String in data["ships"]:
			for slot: String in Equipment.SLOTS:
				var content := "Empty"
				for item: Dictionary in data["items"].values():
					if item["ship"] == ship and item["slot"] == slot:
						content = Equipment.MODELS[item["model"]]["name"]
				destination.add_item("%s / %s: %s" % [ship, slot, content])
				destinations.append({"ship": ship, "slot": slot})
		destination.select(clampi(selected_destination, 0, destinations.size() - 1))
	summary.text = "%d CR | Pathfinder: 2 laser + 2 shared generator slots\nCurrent: %s" % [sector.credits, stats_text(Equipment.stats(data))]
	var blocked := sector.repair_blocker()
	if combat.station_pending:
		blocked = "Waiting for server..."
	for model: String in buys:
		var info: Dictionary = Equipment.MODELS[model]
		var shortfall := maxi(0, int(info["price"]) - sector.credits)
		buys[model].text = "Buy %s / %d CR / +%.0f %s%s" % [info["name"], info["price"], info["damage"] + info["shield"] + info["speed"], "damage" if model == "laser" else ("shield" if model == "shield" else "m/s cruise & boost"), " / Need %d more CR" % shortfall if shortfall > 0 else ""]
		buys[model].disabled = not blocked.is_empty() or shortfall > 0
	var id := selected_item()
	var fit_reason := "Select an owned item."
	var remove_reason := fit_reason
	preview.text = ""
	if not id.is_empty() and destination.selected >= 0:
		var target := destinations[destination.selected]
		fit_reason = Equipment.fitting_blocker(data, id, target["ship"], target["slot"])
		remove_reason = Equipment.fitting_blocker(data, id, "", "")
		var proposed := data.duplicate(true)
		if fit_reason.is_empty():
			proposed["items"][id]["ship"] = target["ship"]
			proposed["items"][id]["slot"] = target["slot"]
			preview.text = "After install: " + stats_text(Equipment.stats(proposed))
		else:
			preview.text = fit_reason
		proposed = data.duplicate(true)
		proposed["items"][id]["ship"] = ""
		proposed["items"][id]["slot"] = ""
		preview.text += "\nAfter removal: " + stats_text(Equipment.stats(proposed))
	fit_button.disabled = not blocked.is_empty() or not fit_reason.is_empty()
	fit_button.tooltip_text = blocked if not blocked.is_empty() else fit_reason
	remove_button.disabled = not blocked.is_empty() or not remove_reason.is_empty()
	remove_button.tooltip_text = blocked if not blocked.is_empty() else remove_reason
	status.text = blocked if not blocked.is_empty() else combat.station_message
