class_name StationShop
extends PanelContainer
## Catalog selection is local. Purchases use the authoritative station request.

const CATEGORIES := {"all": "All equipment", "ships": "Ships", "weapons": "Weapons", "generators": "Generators", "shields": "Shields", "engines": "Engines"}
const DESCRIPTIONS := {
	"laser": "A tracking pulse laser for alien hunting. Each installed laser adds damage to every shot.",
	"shield": "A defensive generator that adds shield capacity. Added capacity recharges through normal shield recovery.",
	"engine": "An ion drive that raises both cruise and boost speed. Acceleration stays the same.",
}

var sector: Sector
var summary: Label
var status: Label
var test_credits_button: Button
var buys: Dictionary[String, Button] = {}
var equipment_page: HBoxContainer
var cargo_page: VBoxContainer
var cargo_summary: Label
var sell_all: Button
var sells: Dictionary[String, Button] = {}
var quantities: Dictionary[String, LineEdit] = {}
var selected: Dictionary[String, int] = {}
var held: Dictionary[String, Label] = {}
var totals: Dictionary[String, Label] = {}
var decreases: Dictionary[String, Button] = {}
var increases: Dictionary[String, Button] = {}
var last_cargo: Dictionary = {}
var cargo_button: Button
var catalog_button: Button
var categories: Dictionary[String, Button] = {}
var cards: Dictionary[String, Button] = {}
var category: String = "all"
var selected_model: String = "laser"
var catalog_title: Label
var catalog_count: Label
var empty_catalog: Label
var grid: GridContainer
var product_title: Label
var product_art: TextureRect
var description: Label
var bonus: Label
var slot_hint: Label
var order_title: Label
var price: Label
var ownership: Label
var balance: Label
var availability: Label
var delivery: Label
var equipment_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_theme_stylebox_override("panel", style(Color("111c29"), Color("526779"), 2))
	add_theme_color_override("font_color", FlightHud.INK)
	var rows := padded_rows(self, 8)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	text(heading, "OUTPOST 01 / STATION SERVICES", 11, FlightHud.MUTED)
	text(heading, "STATION SHOP", 26)
	summary = text(header, "", 19, FlightHud.CYAN)
	summary.custom_minimum_size.x = 150
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var navigation := HBoxContainer.new()
	rows.add_child(navigation)
	catalog_button = button(navigation, "Equipment", func(): equipment_page.show(); cargo_page.hide())
	equipment_button = button(navigation, "Ship equipment [I]", open_equipment)
	button(navigation, "Contracts [C]", sector.hud.toggle_contracts)
	cargo_button = button(navigation, "Trade raw materials", func(): equipment_page.hide(); cargo_page.show())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(spacer)
	button(navigation, "Back to flight [Esc]", close)
	var body := HBoxContainer.new()
	equipment_page = body
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	build_categories(body)
	build_catalog(body)
	build_product(body)
	build_order(body)
	cargo_page = VBoxContainer.new()
	cargo_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(cargo_page)
	cargo_summary = StationUi.text(cargo_page, "")
	build_resource_cards()
	var trading_note := StationUi.text(cargo_page, "This location offers free ore trading. Select a quantity to sell.", 14, FlightHud.MUTED)
	trading_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_all = StationUi.button(cargo_page, "", func(): sector.session.combat.request_station("sell", "all"))
	cargo_page.hide()
	status = text(rows, "", 13, FlightHud.CYAN)
	status.custom_minimum_size.y = 22
	var footer := HBoxContainer.new()
	rows.add_child(footer)
	var note := text(footer, "Purchases go to storage. Fit owned items in Ship equipment.", 12, FlightHud.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_credits_button = button(footer, "Preview: +100,000 CR", func(): sector.session.combat.request_station("test_credits", ""))
	test_credits_button.tooltip_text = "Adds 100,000 saved test credits on an authorized preview server."
	test_credits_button.hide()
	get_viewport().size_changed.connect(layout)
	layout()
	select_category("all")
	hide()


func build_resource_cards() -> void:
	var catalog := HBoxContainer.new()
	catalog.add_theme_constant_override("separation", 6)
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cargo_page.add_child(catalog)
	for resource: String in CargoResources.TYPES:
		var info: Dictionary = CargoResources.TYPES[resource]
		var card := StationUi.card(catalog)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var frame := StationUi.style(Color("182730"), Color("7a8790"))
		frame.set_border_width_all(2)
		frame.set_content_margin_all(4)
		card.add_theme_stylebox_override("panel", frame)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 4)
		card.add_child(content)
		trade_readout(content, "%d CR / unit" % info["price"], 12)
		var name_label := StationUi.text(content, info["name"].to_upper(), 12, info["color"])
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var image := TextureRect.new()
		image.texture = load("res://assets/ui/resources/%s.png" % resource)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(88, 72)
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(image)
		held[resource] = StationUi.text(content, "", 12, FlightHud.MUTED)
		held[resource].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var controls := HBoxContainer.new()
		controls.add_theme_constant_override("separation", 2)
		content.add_child(controls)
		decreases[resource] = quantity_button(controls, "-", func(): set_quantity(resource, selected[resource] - 1))
		var input := LineEdit.new()
		input.text = "0"
		input.alignment = HORIZONTAL_ALIGNMENT_CENTER
		input.custom_minimum_size.x = 38
		input.add_theme_constant_override("minimum_character_width", 2)
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.add_theme_font_size_override("font_size", 14)
		var input_frame := StationUi.style(Color("060d12"), Color("63717b"))
		input_frame.set_content_margin_all(3)
		input.add_theme_stylebox_override("normal", input_frame)
		input.add_theme_stylebox_override("read_only", input_frame)
		input.max_length = 3
		input.select_all_on_focus = true
		input.tooltip_text = "Quantity of %s to sell" % info["name"]
		controls.add_child(input)
		quantities[resource] = input
		selected[resource] = 0
		input.text_changed.connect(func(value: String): edit_quantity(resource, value))
		input.focus_exited.connect(func(): input.text = str(selected[resource]))
		increases[resource] = quantity_button(controls, "+", func(): set_quantity(resource, selected[resource] + 1))
		totals[resource] = trade_readout(content, "0 CR", 14)
		sells[resource] = StationUi.button(content, "SELL", func(): sector.session.combat.request_station("sell", "%s:%d" % [resource, selected[resource]]))
		sells[resource].add_theme_stylebox_override("normal", StationUi.style(Color("354650"), Color("9ca6ad")))
		sells[resource].add_theme_stylebox_override("disabled", StationUi.style(Color("222e36"), Color("46525b")))


func trade_readout(parent: Node, content: String, font_size: int) -> Label:
	var panel := PanelContainer.new()
	var frame := StationUi.style(Color("060d12"), Color("63717b"))
	frame.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", frame)
	parent.add_child(panel)
	var label := StationUi.text(panel, content, font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


func quantity_button(parent: Node, caption: String, action: Callable) -> Button:
	var button := StationUi.button(parent, caption, action)
	button.custom_minimum_size = Vector2(22, 28)
	for state in ["normal", "hover", "disabled", "focus"]:
		var frame := StationUi.style(Color("172c36"), Color("63717b"))
		frame.set_content_margin_all(2)
		button.add_theme_stylebox_override(state, frame)
	return button


func set_quantity(resource: String, amount: int) -> void:
	selected[resource] = clampi(amount, 0, int(sector.cargo.get(resource, 0)))
	quantities[resource].text = str(selected[resource])


func edit_quantity(resource: String, value: String) -> void:
	selected[resource] = clampi(value.to_int() if value.is_valid_int() else 0, 0, int(sector.cargo.get(resource, 0)))
	# Leave an empty field editable so clearing and typing a new number works normally.
	if not value.is_empty() and value != str(selected[resource]):
		var caret := quantities[resource].caret_column
		quantities[resource].text = str(selected[resource])
		quantities[resource].caret_column = mini(caret, quantities[resource].text.length())


func build_categories(parent: Node) -> void:
	var rows := column(parent, 132)
	text(rows, "CATEGORIES", 11, FlightHud.MUTED)
	for id: String in CATEGORIES:
		var title: String = CATEGORIES[id]
		if id in ["shields", "engines"]:
			title = "   / " + title
		var entry := button(rows, title, func(): select_category(id))
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.toggle_mode = true
		entry.custom_minimum_size.y = 34
		categories[id] = entry
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	text(rows, "LOCAL SUPPLY", 11, FlightHud.CYAN)


func build_catalog(parent: Node) -> void:
	var rows := column(parent, 244)
	catalog_title = text(rows, "", 16)
	catalog_count = text(rows, "", 11, FlightHud.MUTED)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for model: String in Equipment.MODELS:
		var info: Dictionary = Equipment.MODELS[model]
		var card := button(grid, "", func(): select_model(model))
		card.custom_minimum_size = Vector2(102, 142)
		card.toggle_mode = true
		card.tooltip_text = "%s / %s CR" % [info["name"], credits_text(info["price"])]
		var content := padded_rows(card, 8)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := text(content, info["name"], 12)
		title.custom_minimum_size.y = 34
		var art := StationUi.art(content, model, Vector2(0, 60))
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text(content, "%s CR" % credits_text(info["price"]), 12, FlightHud.CYAN)
		cards[model] = card
	empty_catalog = text(rows, "No ships for sale yet.\n\nThe Pathfinder is your starter ship. Buy equipment in the other categories.", 14, FlightHud.MUTED)
	empty_catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL


func build_product(parent: Node) -> void:
	var rows := column(parent, 210, true)
	text(rows, "ITEM PREVIEW", 11, FlightHud.MUTED)
	product_title = text(rows, "", 22)
	product_art = StationUi.art(rows, "laser", Vector2(0, 100))
	product_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description = text(rows, "", 14, FlightHud.MUTED)
	bonus = text(rows, "", 18, FlightHud.CYAN)
	slot_hint = text(rows, "", 12, FlightHud.MUTED)


func build_order(parent: Node) -> void:
	var rows := column(parent, 180)
	text(rows, "ORDER SUMMARY", 11, FlightHud.MUTED)
	order_title = text(rows, "", 17)
	price = text(rows, "", 23, FlightHud.GREEN)
	ownership = text(rows, "", 12, FlightHud.MUTED)
	rows.add_child(HSeparator.new())
	balance = text(rows, "", 13)
	text(rows, "DELIVERY", 11, FlightHud.MUTED)
	delivery = text(rows, "1 item to storage", 13)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	availability = text(rows, "", 13, FlightHud.MUTED)
	availability.custom_minimum_size.y = 34
	for model: String in Equipment.MODELS:
		var buy := button(rows, "Buy item", func(): purchase(model))
		buy.custom_minimum_size.y = 44
		buy.add_theme_stylebox_override("normal", style(Color("264e34"), Color("79c888")))
		buy.add_theme_stylebox_override("hover", style(Color("356545"), FlightHud.GREEN))
		buys[model] = buy


func layout() -> void:
	var dimensions := get_viewport_rect().size - Vector2(32, 32)
	dimensions.x = minf(dimensions.x, 1160)
	dimensions.y = minf(dimensions.y, 680)
	offset_left = -dimensions.x / 2
	offset_right = dimensions.x / 2
	offset_top = -dimensions.y / 2
	offset_bottom = dimensions.y / 2


static func style(background: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = background
	result.border_color = border
	result.set_border_width_all(width)
	result.set_corner_radius_all(3)
	result.set_content_margin_all(6)
	return result


static func padded_rows(parent: Node, padding: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, padding)
	parent.add_child(margin)
	if not parent is Container:
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)
	return rows


static func column(parent: Node, minimum: float, expand: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minimum
	if expand:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", style(Color("09131f"), Color("2d4356")))
	parent.add_child(panel)
	return padded_rows(panel, 8)


static func text(parent: Node, content: String, font_size: int = 14, color: Color = FlightHud.INK) -> Label:
	var result := Label.new()
	result.text = content
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result


static func button(parent: Node, content: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = content
	result.custom_minimum_size.y = 32
	result.add_theme_font_size_override("font_size", 13)
	result.add_theme_stylebox_override("normal", style(Color("192838"), Color("3c5163")))
	result.add_theme_stylebox_override("hover", style(Color("233c50"), FlightHud.CYAN))
	result.add_theme_stylebox_override("pressed", style(Color("164358"), FlightHud.CYAN, 2))
	result.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), FlightHud.CYAN))
	result.add_theme_stylebox_override("disabled", style(Color("111e2a"), Color("293b4b")))
	result.pressed.connect(action)
	parent.add_child(result)
	return result


static func credits_text(value: int) -> String:
	var digits := str(value)
	var result := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits[index]
	return result


func models_in_category(id: String) -> Array[String]:
	var result: Array[String] = []
	for model: String in Equipment.MODELS:
		if id == "all" or (id == "weapons" and model == "laser") or (id == "generators" and Equipment.MODELS[model]["kind"] == "generator") or (id == "shields" and model == "shield") or (id == "engines" and model == "engine"):
			result.append(model)
	return result


func select_category(id: String) -> void:
	category = id
	var models := models_in_category(id)
	for key: String in categories:
		categories[key].set_pressed_no_signal(key == id)
	for model: String in cards:
		cards[model].visible = model in models
	grid.visible = not models.is_empty()
	empty_catalog.visible = models.is_empty()
	catalog_title.text = CATEGORIES[id]
	catalog_count.text = "%02d ITEMS" % models.size()
	select_model(selected_model if selected_model in models else (models[0] if not models.is_empty() else ""))


func select_model(model: String) -> void:
	selected_model = model
	for key: String in cards:
		cards[key].set_pressed_no_signal(key == model)
	var available := not model.is_empty()
	product_art.texture = StationUi.texture(model if available else "ship")
	product_title.text = Equipment.MODELS[model]["name"] if available else "Pathfinder"
	description.text = DESCRIPTIONS[model] if available else "Your starter hull has two laser slots and two generator slots. Ships are not sold at this station yet."
	if available:
		bonus.text = StationUi.bonus(model)
		slot_hint.text = "Laser slot. Bonuses stack per installed item." if model == "laser" else "Generator slot. Shields and engines share these slots."
	else:
		bonus.text = "120 base hull"
		slot_hint.text = "2 laser slots / 2 shared generator slots"
	order_title.text = product_title.text
	price.text = "%s CR" % credits_text(Equipment.MODELS[model]["price"]) if available else "Not for sale"
	refresh()


func purchase(model: String) -> void:
	if not purchase_blocker(model).is_empty():
		return
	sector.session.combat.request_station("buy", model)
	refresh()


func purchase_blocker(model: String) -> String:
	if not sector.session.active or sector.session.combat.inventory.is_empty():
		return "Connect to a persistent server."
	if sector.session.combat.station_pending:
		return "Waiting for server..."
	var reason := sector.repair_blocker()
	if not reason.is_empty():
		return reason
	var shortfall := int(Equipment.MODELS[model]["price"]) - sector.credits
	return "Need %s more CR" % credits_text(shortfall) if shortfall > 0 else ""


func open_equipment() -> void:
	sector.equipment_menu.open()


func open() -> void:
	if not sector.session.active or sector.session.combat.inventory.is_empty():
		sector.notify("The station shop is available on a persistent dedicated server.")
		return
	var blocker := sector.repair_blocker()
	if not blocker.is_empty():
		sector.notify(blocker)
		return
	sector.equipment_menu.hide()
	sector.session.menu.hide()
	sector.hud.contract_panel.hide()
	sector.set_paused(true)
	show()
	refresh()


func close() -> void:
	hide()
	sector.set_paused(false)


func _process(_delta: float) -> void:
	if not visible:
		return
	if not sector.session.active or sector.session.menu.visible or sector.session.combat.inventory.is_empty():
		hide()
		return
	refresh()


func refresh() -> void:
	var combat := sector.session.combat
	summary.text = "%s CR" % credits_text(sector.credits)
	var blocked := "Waiting for server..." if combat.station_pending else sector.repair_blocker()
	cargo_summary.text = "CARGO %d / %d units / %d CR" % [CargoResources.units(sector.cargo), sector.cargo_capacity, CargoResources.value(sector.cargo)]
	if last_cargo != sector.cargo:
		for resource: String in selected:
			var amount := int(sector.cargo.get(resource, 0))
			# Default new cargo to a full sale; preserve a pilot's smaller selection.
			set_quantity(resource, amount if not last_cargo.has(resource) or selected[resource] == int(last_cargo.get(resource, 0)) else selected[resource])
		last_cargo = sector.cargo.duplicate()
	for resource: String in sells:
		var info: Dictionary = CargoResources.TYPES[resource]
		var amount := int(sector.cargo.get(resource, 0))
		var proceeds := selected[resource] * int(info["price"])
		held[resource].text = "In hold: %d" % amount
		totals[resource].text = "%d CR" % proceeds
		quantities[resource].editable = blocked.is_empty() and amount > 0
		decreases[resource].disabled = not blocked.is_empty() or selected[resource] == 0
		increases[resource].disabled = not blocked.is_empty() or selected[resource] >= amount
		sells[resource].disabled = not blocked.is_empty() or selected[resource] == 0 or proceeds > PilotStore.MAX_CREDITS - sector.credits
		sells[resource].tooltip_text = blocked if not blocked.is_empty() else ("Sale exceeds the credit limit." if proceeds > PilotStore.MAX_CREDITS - sector.credits else "Sell %d units of %s." % [selected[resource], info["name"]])
	var total := CargoResources.value(sector.cargo)
	sell_all.text = "Sell all cargo / +%d CR" % total
	sell_all.disabled = not blocked.is_empty() or total == 0 or total > PilotStore.MAX_CREDITS - sector.credits
	sell_all.tooltip_text = blocked if not blocked.is_empty() else ("Sale exceeds the credit limit." if total > PilotStore.MAX_CREDITS - sector.credits else "Sell every resource in the active ship.")
	test_credits_button.visible = combat.preview_tools_available
	test_credits_button.disabled = not blocked.is_empty() or sector.credits >= PilotStore.MAX_CREDITS
	for model: String in buys:
		var reason := purchase_blocker(model)
		buys[model].visible = model == selected_model
		buys[model].disabled = not reason.is_empty()
		buys[model].tooltip_text = reason if not reason.is_empty() else "Buy one %s into storage" % Equipment.MODELS[model]["name"]
	if selected_model.is_empty():
		ownership.text = "Starter hull / already owned"
		balance.text = "Wallet\n%s CR" % credits_text(sector.credits)
		delivery.text = "Not available"
		availability.text = "Ship purchases are not available yet."
		availability.add_theme_color_override("font_color", FlightHud.MUTED)
	else:
		delivery.text = "1 item to storage"
		var stored := 0
		var installed := 0
		for item: Dictionary in combat.inventory.get("items", {}).values():
			if item["model"] == selected_model:
				if item["ship"].is_empty():
					stored += 1
				else:
					installed += 1
		ownership.text = "OWNED %d\n%d in storage\n%d installed" % [stored + installed, stored, installed]
		var remaining := sector.credits - int(Equipment.MODELS[selected_model]["price"])
		balance.text = "Wallet: %s CR\nAfter: %s" % [credits_text(sector.credits), "%s CR" % credits_text(remaining) if remaining >= 0 else "Insufficient funds"]
		var reason := purchase_blocker(selected_model)
		availability.text = reason if not reason.is_empty() else "Ready to purchase"
		availability.add_theme_color_override("font_color", FlightHud.RED if not reason.is_empty() else FlightHud.GREEN)
	status.text = blocked if not blocked.is_empty() else combat.station_message
