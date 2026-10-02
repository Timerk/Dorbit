class_name StationShop
extends PanelContainer
## Purchases send intent; the server replies with the committed inventory.

var sector: Sector
var summary: Label
var status: Label
var test_credits_button: Button
var buys: Dictionary[String, Button] = {}
var availability: Dictionary[String, Label] = {}
var equipment_page: VBoxContainer
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


func _ready() -> void:
	StationUi.frame(self, Vector2(920, 570))
	var rows := StationUi.rows(self, 12)
	rows.add_theme_constant_override("separation", 6)
	StationUi.navigation(rows, sector, "shop", close)
	summary = StationUi.text(rows, "", 24, FlightHud.CYAN)
	var tabs := HBoxContainer.new()
	rows.add_child(tabs)
	StationUi.button(tabs, "Equipment", func(): equipment_page.show(); cargo_page.hide())
	StationUi.button(tabs, "Trade raw materials", func(): equipment_page.hide(); cargo_page.show())
	equipment_page = VBoxContainer.new()
	equipment_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(equipment_page)
	var catalog := HBoxContainer.new()
	catalog.add_theme_constant_override("separation", 14)
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipment_page.add_child(catalog)
	for model: String in Equipment.MODELS:
		var info: Dictionary = Equipment.MODELS[model]
		var card := StationUi.card(catalog)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var content := StationUi.rows(card, 8)
		StationUi.art(content, model, Vector2(100, 100))
		StationUi.text(content, info["name"], 19)
		StationUi.text(content, StationUi.bonus(model), 14, StationUi.accent(model))
		StationUi.text(content, "%s slot" % info["kind"].capitalize(), 13, FlightHud.MUTED)
		buys[model] = StationUi.button(content, "Buy / %s CR" % info["price"], func(): sector.session.combat.request_station("buy", model))
		availability[model] = StationUi.text(content, "", 13, FlightHud.MUTED)
	cargo_page = VBoxContainer.new()
	cargo_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(cargo_page)
	cargo_summary = StationUi.text(cargo_page, "")
	build_resource_cards()
	var trading_note := StationUi.text(cargo_page, "This location offers free ore trading. Select a quantity to sell.", 14, FlightHud.MUTED)
	trading_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_all = StationUi.button(cargo_page, "", func(): sector.session.combat.request_station("sell", "all"))
	cargo_page.hide()
	status = StationUi.text(rows, "", 14, FlightHud.CYAN)
	status.custom_minimum_size.y = 24
	test_credits_button = StationUi.button(rows, "Preview: add 100,000 test credits", func(): sector.session.combat.request_station("test_credits", ""))
	test_credits_button.tooltip_text = "Adds saved test credits to your pilot on this preview server."
	test_credits_button.hide()
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


func open() -> void:
	if not StationUi.can_open(sector):
		return
	sector.equipment_menu.hide()
	sector.session.menu.hide()
	sector.hud.contract_panel.hide()
	sector.set_paused(true)
	show()


func close() -> void:
	hide()
	sector.set_paused(false)


func _process(_delta: float) -> void:
	if not visible:
		return
	var combat := sector.session.combat
	if not sector.session.active or sector.session.menu.visible or combat.inventory.is_empty():
		hide()
		return
	summary.text = "OUTPOST 01 / STATION SHOP    /    %s CR" % sector.credits
	var blocked := StationUi.blocker(sector)
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
		var shortfall := maxi(0, int(Equipment.MODELS[model]["price"]) - sector.credits)
		buys[model].disabled = not blocked.is_empty() or shortfall > 0
		var reason := blocked if not blocked.is_empty() else ("Need %d more CR" % shortfall if shortfall > 0 else "Delivered to inventory")
		buys[model].tooltip_text = reason
		availability[model].text = "Need %d more CR" % shortfall if shortfall > 0 else "Delivered to inventory"
	status.text = blocked if not blocked.is_empty() else combat.station_message
