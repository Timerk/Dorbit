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


func _ready() -> void:
	StationUi.frame(self, Vector2(880, 530))
	var rows := StationUi.rows(self)
	StationUi.navigation(rows, sector, "shop", close)
	summary = StationUi.text(rows, "", 24, FlightHud.CYAN)
	var tabs := HBoxContainer.new()
	rows.add_child(tabs)
	StationUi.button(tabs, "Equipment", func(): equipment_page.show(); cargo_page.hide())
	StationUi.button(tabs, "Cargo / sell resources", func(): equipment_page.hide(); cargo_page.show())
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
	for resource: String in CargoResources.TYPES:
		sells[resource] = StationUi.button(cargo_page, "", func(): sector.session.combat.request_station("sell", resource))
		sells[resource].add_theme_color_override("font_color", CargoResources.TYPES[resource]["color"])
	sell_all = StationUi.button(cargo_page, "", func(): sector.session.combat.request_station("sell", "all"))
	cargo_page.hide()
	status = StationUi.text(rows, "", 14, FlightHud.CYAN)
	status.custom_minimum_size.y = 36
	test_credits_button = StationUi.button(rows, "Preview: add 100,000 test credits", func(): sector.session.combat.request_station("test_credits", ""))
	test_credits_button.tooltip_text = "Adds saved test credits to your pilot on this preview server."
	test_credits_button.hide()
	hide()


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
		var shortfall := maxi(0, int(Equipment.MODELS[model]["price"]) - sector.credits)
		buys[model].disabled = not blocked.is_empty() or shortfall > 0
		var reason := blocked if not blocked.is_empty() else ("Need %d more CR" % shortfall if shortfall > 0 else "Delivered to inventory")
		buys[model].tooltip_text = reason
		availability[model].text = "Need %d more CR" % shortfall if shortfall > 0 else "Delivered to inventory"
	status.text = blocked if not blocked.is_empty() else combat.station_message
