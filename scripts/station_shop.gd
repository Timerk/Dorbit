class_name StationShop
extends PanelContainer
## Catalog selection is local. Purchases use the authoritative station request.

const CATEGORIES := {"all": "All equipment", "ships": "Ships", "weapons": "Weapons", "generators": "Generators", "shields": "Shields", "engines": "Engines"}
const DESCRIPTIONS := {
	"weapons": "A tracking laser for alien hunting. Each installed laser adds damage to every shot.",
	"shields": "A defensive generator that adds shield capacity. Added capacity recharges through normal shield recovery.",
	"engines": "A drive that raises both cruise and boost speed. Acceleration stays the same.",
}

var sector: Sector
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
var categories: Dictionary[String, Button] = {}
var cards: Dictionary[String, Button] = {}
var category: String = "all"
var selected_model: String = "laser"
var empty_catalog: Label
var grid: GridContainer
var product_title: Label
var product_art: TextureRect
var description: String
var bonus: Label
var slot_hint: String
var price: Label
var ownership: Label
var balance: Label
var availability: Label
var delivery: String
var products: Dictionary = {}
var product_rows: VBoxContainer
var page_title: Label


func catalog() -> Dictionary:
	if not products.is_empty():
		return products
	for model: String in Equipment.catalog_models():
		products[model] = Equipment.MODELS[model]
	for id: String in ShipCatalog.MODELS:
		products[id] = ShipCatalog.info(id).duplicate()
		products[id]["price"] = ShipCatalog.price(id)
	return products


func _ready() -> void:
	StationUi.frame(self, Vector2(1150, 690))
	var rows := padded_rows(self, 16)
	var header := HBoxContainer.new()
	rows.add_child(header)
	page_title = text(header, "SHOP", 28)
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_page = HBoxContainer.new()
	equipment_page.add_theme_constant_override("separation", 16)
	equipment_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(equipment_page)
	build_catalog(equipment_page)
	build_product(equipment_page)
	build_order(product_rows)
	cargo_page = VBoxContainer.new()
	cargo_page.add_theme_constant_override("separation", 14)
	cargo_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(cargo_page)
	cargo_summary = StationUi.text(cargo_page, "", 20, StationUi.MUTED)
	build_resource_cards()
	sell_all = StationUi.button(cargo_page, "", func(): sector.session.combat.request_station("sell", "all"))
	StationUi.primary(sell_all)
	cargo_page.hide()
	status = text(rows, "", 16, StationUi.AMBER)
	test_credits_button = button(rows, "Preview: +100,000,000 CR", func(): sector.session.combat.request_station("test_credits", ""))
	test_credits_button.tooltip_text = "Adds 100,000,000 saved test credits on an authorized preview server."
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
		var frame := StationUi.style(Color("0c1217"), StationUi.LINE)
		frame.set_border_width_all(1)
		frame.set_content_margin_all(4)
		card.add_theme_stylebox_override("panel", frame)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 4)
		card.add_child(content)
		var unit_price := trade_readout(content, "%d CR / unit" % info["price"], 16)
		unit_price.add_theme_color_override("font_color", StationUi.MUTED)
		var name_label := StationUi.text(content, info["name"].to_upper(), 18, info["color"])
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var image := TextureRect.new()
		image.texture = load("res://assets/ui/resources/%s.png" % resource)
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(88, 72)
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(image)
		held[resource] = StationUi.text(content, "", 18, StationUi.MUTED)
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
		var input_frame := StationUi.style(Color("0b1115"), StationUi.LINE)
		input_frame.set_content_margin_all(3)
		input.add_theme_stylebox_override("normal", input_frame)
		input.add_theme_stylebox_override("read_only", input_frame)
		input.max_length = 4
		input.select_all_on_focus = true
		input.tooltip_text = "Quantity of %s to sell" % info["name"]
		controls.add_child(input)
		quantities[resource] = input
		selected[resource] = 0
		input.text_changed.connect(func(value: String): edit_quantity(resource, value))
		input.focus_exited.connect(func(): input.text = str(selected[resource]))
		increases[resource] = quantity_button(controls, "+", func(): set_quantity(resource, selected[resource] + 1))
		totals[resource] = trade_readout(content, "0 CR", 22)
		sells[resource] = StationUi.button(content, "SELL", func(): sector.session.combat.request_station("sell", "%s:%d" % [resource, selected[resource]]))
		sells[resource].custom_minimum_size.y = 42


func trade_readout(parent: Node, content: String, font_size: int) -> Label:
	var panel := PanelContainer.new()
	var frame := StationUi.style(Color("0b1115"), StationUi.LINE)
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
		var frame := StationUi.style(Color("111a20"), StationUi.LINE)
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
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	parent.add_child(tabs)
	for id: String in CATEGORIES:
		var entry := button(tabs, "All" if id == "all" else CATEGORIES[id], func(): select_category(id))
		entry.add_theme_font_size_override("font_size", 16)
		entry.toggle_mode = true
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		categories[id] = entry


func build_catalog(parent: Node) -> void:
	var rows := column(parent, 540, true)
	build_categories(rows)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for model: String in catalog():
		var info: Dictionary = catalog()[model]
		var card := button(grid, "", func(): select_model(model))
		card.custom_minimum_size = Vector2(230, 190)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.toggle_mode = true
		var offer := "%s CR" % credits_text(info["price"]) if ShipCatalog.MODELS.has(model) or Equipment.purchase_blocker(model).is_empty() else "Unavailable"
		card.tooltip_text = "%s / %s\n%s" % [info["name"], offer, StationUi.bonus(model) if Equipment.MODELS.has(model) else "%s hull" % credits_text(int(info["hull"]))]
		var content := padded_rows(card, 8)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := text(content, info["name"], 20)
		title.custom_minimum_size.y = 34
		var art := StationUi.art(content, model, Vector2(0, 60))
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text(content, offer, 20, StationUi.AMBER)
		cards[model] = card
	empty_catalog = text(rows, "No items in this category.", 14, FlightHud.MUTED)
	empty_catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL


func build_product(parent: Node) -> void:
	product_rows = column(parent, 360, true)
	product_title = text(product_rows, "", 30)
	product_art = StationUi.art(product_rows, "laser", Vector2(0, 160))
	product_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bonus = text(product_rows, "", 22)


func build_order(parent: Node) -> void:
	parent.add_child(HSeparator.new())
	price = text(parent, "", 30, StationUi.AMBER)
	ownership = text(parent, "", 16, StationUi.MUTED)
	balance = text(parent, "", 18, StationUi.MUTED)
	availability = text(parent, "", 16, StationUi.MUTED)
	for model: String in catalog():
		var buy := button(parent, "BUY", func(): purchase(model))
		StationUi.primary(buy)
		buys[model] = buy


func layout() -> void:
	if is_instance_valid(sector.main_menu) and sector.main_menu.visible:
		sector.main_menu.fit_panel(self, Vector2(1150, 690))
		return
	StationUi.centered(self, Vector2(1150, 690))



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
	panel.add_theme_stylebox_override("panel", StationUi.style(StationUi.SURFACE, StationUi.LINE))
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
	result.add_theme_font_size_override("font_size", 18)
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
	if id == "ships":
		for model: String in ShipCatalog.MODELS:
			result.append(model)
		return result
	for model: String in Equipment.catalog_models():
		if id == "all" or id == Equipment.category(model) or (id == "generators" and Equipment.MODELS[model]["kind"] == "generator"):
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
	select_model(selected_model if selected_model in models else (models[0] if not models.is_empty() else ""))


func select_model(model: String) -> void:
	selected_model = model
	for key: String in cards:
		cards[key].set_pressed_no_signal(key == model)
	var available := not model.is_empty()
	product_art.texture = StationUi.texture(model if available else "ship")
	product_title.text = catalog()[model]["name"] if available else "No selection"
	var is_ship := ShipCatalog.MODELS.has(model)
	description = "An owned hull with its own fitting and cargo. Purchases do not switch your active ship." if is_ship else (DESCRIPTIONS[Equipment.category(model)] if available else "")
	if is_ship:
		var entry := ShipCatalog.info(model)
		bonus.text = "%s hull\n%d m/s base cruise\n%d cargo units" % [credits_text(int(entry["hull"])), entry["speed"] * ShipCatalog.SPEED_SCALE, entry["cargo"]]
		slot_hint = "%d laser / %d shared generator / %d extra slots" % [entry["lasers"], entry["generators"], entry["extras"]]
	elif available:
		bonus.text = StationUi.bonus(model)
		slot_hint = "Laser slot. Bonuses stack per installed item." if Equipment.MODELS[model]["kind"] == "laser" else "Generator slot. Shields and engines share these slots."
	else:
		bonus.text = ""
		slot_hint = ""
	price.text = ("%s CR" % credits_text(int(catalog()[model]["price"])) if is_ship or Equipment.purchase_blocker(model).is_empty() else "Not for sale") if available else ""
	refresh()


func purchase(model: String) -> void:
	if not purchase_blocker(model).is_empty():
		return
	sector.session.combat.request_station("buy_ship" if ShipCatalog.MODELS.has(model) else "buy", model)
	refresh()


func purchase_blocker(model: String) -> String:
	if StationUi.offline_preview(sector):
		return StationUi.OFFLINE_BLOCKER
	var supply := "" if ShipCatalog.MODELS.has(model) else Equipment.purchase_blocker(model)
	if not supply.is_empty():
		return supply
	if not sector.session.active or sector.session.combat.inventory.is_empty():
		return "Connect to a persistent server."
	if sector.session.combat.station_pending:
		return "Waiting for server..."
	var reason := sector.repair_blocker()
	if not reason.is_empty():
		return reason
	if ShipCatalog.MODELS.has(model) and not ShipCatalog.owned_id(sector.session.combat.inventory, model).is_empty():
		return "Already owned. Activate in Ship equipment."
	var shortfall := int(catalog()[model]["price"]) - sector.credits
	return "Need %s more CR" % credits_text(shortfall) if shortfall > 0 else ""


func select_cargo(cargo: bool) -> void:
	equipment_page.visible = not cargo
	cargo_page.visible = cargo
	page_title.text = "CARGO TRADE" if cargo else "SHOP"


func open() -> void:
	if not StationUi.can_open(sector):
		return
	if sector.main_menu.route_page("shop"):
		return
	sector.equipment_menu.hide()
	sector.session.menu.hide()
	sector.hud.contract_panel.hide()
	sector.set_paused(true)
	layout()
	show()
	refresh()


func close() -> void:
	hide()
	sector.set_paused(false)


func _process(_delta: float) -> void:
	if not visible:
		return
	if (not sector.session.active and not StationUi.offline_preview(sector)) or sector.session.menu.visible or StationUi.inventory(sector).is_empty():
		hide()
		return
	layout()
	refresh()


func refresh() -> void:
	var combat := sector.session.combat
	var blocked := StationUi.blocker(sector)
	var inventory := StationUi.inventory(sector)
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
		held[resource].text = "%d held" % amount
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
		buys[model].tooltip_text = reason if not reason.is_empty() else "Buy %s" % catalog()[model]["name"]
	if selected_model.is_empty():
		ownership.text = ""
		balance.text = ""
		delivery = "Not available"
		availability.text = "Select a product to preview it."
		availability.add_theme_color_override("font_color", FlightHud.MUTED)
	elif ShipCatalog.MODELS.has(selected_model):
		var owned := ShipCatalog.owned_id(inventory, selected_model)
		ownership.text = "Not owned" if owned.is_empty() else ("Active ship" if owned == inventory.get("active_ship") else "Owned / available to activate")
		delivery = "Empty hull to hangar\nActivate and fit in Ship equipment."
		var remaining := sector.credits - ShipCatalog.price(selected_model)
		balance.text = "" if not owned.is_empty() else "After: %s" % ("%s CR" % credits_text(remaining) if remaining >= 0 else "Insufficient funds")
		var reason := purchase_blocker(selected_model)
		availability.text = reason if not reason.is_empty() else "Ready to purchase"
		availability.add_theme_color_override("font_color", FlightHud.MUTED if not owned.is_empty() else (FlightHud.RED if not reason.is_empty() else FlightHud.GREEN))
	else:
		var for_sale := Equipment.purchase_blocker(selected_model).is_empty()
		delivery = "1 item to storage" if for_sale else "Not available"
		var stored := 0
		var installed := 0
		for item: Dictionary in inventory.get("items", {}).values():
			if item["model"] == selected_model:
				if item["ship"].is_empty():
					stored += 1
				else:
					installed += 1
		ownership.text = "OWNED %d   /   %d in storage   /   %d installed" % [stored + installed, stored, installed]
		var remaining := sector.credits - int(Equipment.MODELS[selected_model]["price"])
		balance.text = "After: %s" % ("%s CR" % credits_text(remaining) if remaining >= 0 else "Insufficient funds") if for_sale else ""
		var reason := purchase_blocker(selected_model)
		availability.text = reason if not reason.is_empty() else "Ready to purchase"
		availability.add_theme_color_override("font_color", FlightHud.RED if not reason.is_empty() else FlightHud.GREEN)
	status.text = blocked if not blocked.is_empty() else combat.station_message
	status.visible = not status.text.is_empty() and (not StationUi.offline_preview(sector) or cargo_page.visible)
	availability.visible = not selected_model.is_empty() and not purchase_blocker(selected_model).is_empty()
	balance.visible = not balance.text.is_empty()
	product_title.tooltip_text = description + "\n" + slot_hint + "\n" + delivery
	product_title.mouse_filter = Control.MOUSE_FILTER_PASS
