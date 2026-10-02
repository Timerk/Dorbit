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
var test_credits_button: Button
var buys: Dictionary[String, Button] = {}
var item_ids: Array[String] = []
var destinations: Array[Dictionary] = []
var last_inventory: Dictionary = {}
var equipment_page: VBoxContainer
var cargo_page: VBoxContainer
var cargo_summary: Label
var sell_all: Button
var sells: Dictionary[String, Button] = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -430
	offset_right = 430
	offset_top = -280
	offset_bottom = 280
	add_theme_stylebox_override("panel", FlightHud.panel_style())
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "OUTPOST 01 / EQUIPMENT, FITTING & CARGO"
	title.add_theme_font_size_override("font_size", 21)
	rows.add_child(title)
	summary = label(rows)
	var tabs := HBoxContainer.new()
	rows.add_child(tabs)
	sector.session.add_button(tabs, "Equipment & fitting", func(): equipment_page.show(); cargo_page.hide())
	sector.session.add_button(tabs, "Cargo / sell resources", func(): equipment_page.hide(); cargo_page.show())
	equipment_page = VBoxContainer.new()
	equipment_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(equipment_page)
	for model: String in Equipment.MODELS:
		var info: Dictionary = Equipment.MODELS[model]
		var button := sector.session.add_button(equipment_page, "", func(): sector.session.combat.request_station("buy", model))
		button.tooltip_text = "%s: +%.0f damage, +%.0f shield, +%.0f cruise and boost speed" % [info["name"], info["damage"], info["shield"], info["speed"]]
		buys[model] = button
	label(equipment_page).text = "Owned items / select an item to fit or remove. Fitting is free."
	items = ItemList.new()
	items.custom_minimum_size.y = 72
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipment_page.add_child(items)
	var controls := HBoxContainer.new()
	equipment_page.add_child(controls)
	destination = OptionButton.new()
	destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(destination)
	fit_button = sector.session.add_button(controls, "Install / transfer", fit_selected)
	remove_button = sector.session.add_button(controls, "Move to storage", func(): sector.session.combat.request_station("fit", selected_item()))
	preview = label(equipment_page)
	cargo_page = VBoxContainer.new()
	cargo_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(cargo_page)
	cargo_summary = label(cargo_page)
	for resource: String in CargoResources.TYPES:
		var button := sector.session.add_button(cargo_page, "", func(): sector.session.combat.request_station("sell", resource))
		button.add_theme_color_override("font_color", CargoResources.TYPES[resource]["color"])
		sells[resource] = button
	sell_all = sector.session.add_button(cargo_page, "", func(): sector.session.combat.request_station("sell", "all"))
	label(cargo_page).text = "Fly within 12 m of loot to collect it. Each resource uses 1 cargo unit."
	cargo_page.hide()
	status = label(rows)
	status.custom_minimum_size.y = 24
	var footer := HBoxContainer.new()
	rows.add_child(footer)
	var back_button := sector.session.add_button(footer, "Back to flight [B / Esc]", close)
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_credits_button = sector.session.add_button(footer, "Preview: add 100,000 test credits", func(): sector.session.combat.request_station("test_credits", ""))
	test_credits_button.tooltip_text = "Adds saved test credits to your pilot on this preview server."
	test_credits_button.hide()
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
	summary.text = "%d CR | Cargo %d / %d | Pathfinder: 2 laser + 2 shared generator slots\nCurrent: %s" % [sector.credits, CargoResources.units(sector.cargo), sector.cargo_capacity, stats_text(Equipment.stats(data))]
	var blocked := sector.repair_blocker()
	if combat.station_pending:
		blocked = "Waiting for server..."
	cargo_summary.text = "SHIP CARGO / %d of %d units / %d CR sale value" % [CargoResources.units(sector.cargo), sector.cargo_capacity, CargoResources.value(sector.cargo)]
	for resource: String in sells:
		var info: Dictionary = CargoResources.TYPES[resource]
		var amount := int(sector.cargo.get(resource, 0))
		var proceeds := amount * int(info["price"])
		sells[resource].text = "%s x%d / %d CR each / Sell for %d CR" % [info["name"], amount, info["price"], proceeds]
		sells[resource].disabled = not blocked.is_empty() or amount == 0 or proceeds > PilotStore.MAX_CREDITS - sector.credits
		sells[resource].tooltip_text = blocked if not blocked.is_empty() else ("Sale exceeds the credit limit." if proceeds > PilotStore.MAX_CREDITS - sector.credits else "Sell this resource from the active ship.")
	var total := CargoResources.value(sector.cargo)
	sell_all.text = "Sell all cargo / +%d CR" % total
	sell_all.disabled = not blocked.is_empty() or total == 0 or total > PilotStore.MAX_CREDITS - sector.credits
	sell_all.tooltip_text = blocked if not blocked.is_empty() else ("Sale exceeds the credit limit." if total > PilotStore.MAX_CREDITS - sector.credits else "Sell every resource in the active ship.")
	test_credits_button.visible = combat.preview_tools_available
	test_credits_button.disabled = not blocked.is_empty() or sector.credits >= PilotStore.MAX_CREDITS
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
