class_name ResourceWorkshop
extends PanelContainer
## Refining and equipment boosts share a station console and cargo artwork.

const SIZE := Vector2(1150, 690)
const BOOST_TEXT := {
	"prometid": "Lasers / rockets +15%",
	"duranium": "Shields +10% / engines +10%",
	"promerium": "Lasers / rockets +30%\nShields +20% / engines +20%",
	"seprom": "Lasers / rockets +60%\nShields +40% / no engine boost",
}
var sector: Sector
var tabs: Dictionary[String, Button] = {}
var pages: Dictionary[String, Control] = {}
var page := "refining"
var output := "prometid"
var group := "lasers"
var resource := "prometid"
var resource_cards: Dictionary[String, Button] = {}
var counts: Dictionary[String, Label] = {}
var upgrade_cards: Dictionary[String, Button] = {}
var groups: Dictionary[String, Button] = {}
var reserve_labels: Dictionary[String, Label] = {}
var refine_title: Label
var recipe: Label
var refine_amount: SpinBox
var refine_button: Button
var upgrade_title: Label
var upgrade_description: Label
var upgrade_amount: SpinBox
var upgrade_button: Button
var replace_warning: CheckButton
var status: Label
var cargo_summary: Label
var last_replacement := ""


func _ready() -> void:
	StationUi.frame(self, SIZE)
	var rows := StationUi.rows(self, 16)
	var header := HBoxContainer.new()
	rows.add_child(header)
	StationUi.text(header, "REFINING & UPGRADES", 28).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cargo_summary = StationUi.text(header, "", 18, StationUi.MUTED)
	cargo_summary.autowrap_mode = TextServer.AUTOWRAP_OFF
	var tab_row := HBoxContainer.new()
	rows.add_child(tab_row)
	for entry: Array in [["refining", "REFINING"], ["update", "UPDATE"]]:
		var key: String = entry[0]
		tabs[key] = StationUi.button(tab_row, entry[1], func(): select_tab(key))
		tabs[key].toggle_mode = true
		tabs[key].custom_minimum_size.x = 150
	build_refining(rows)
	build_update(rows)
	status = StationUi.text(rows, "", 16, StationUi.AMBER)
	status.custom_minimum_size.y = 26
	get_viewport().size_changed.connect(fit_window)
	select_tab("refining")
	fit_window()
	hide()


func art(parent: Node, key: String, minimum: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = load("res://assets/ui/resources/%s.png" % key)
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = minimum
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image


func card(parent: Node, key: String, action: Callable, minimum: Vector2) -> Button:
	var button := StationUi.button(parent, "", action)
	button.custom_minimum_size = minimum
	button.toggle_mode = true
	var rows := VBoxContainer.new()
	button.add_child(rows)
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 8
	rows.offset_right = -8
	rows.offset_top = 8
	rows.offset_bottom = -8
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := StationUi.text(rows, CargoResources.TYPES[key]["name"].to_upper(), 18, CargoResources.TYPES[key]["color"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art(rows, key, Vector2(80, 56)).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var count := StationUi.text(rows, "", 17, StationUi.MUTED)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counts["%s:%s" % [parent.name, key]] = count
	return button


func amount_control(parent: Node, caption: String, maximum: Callable) -> SpinBox:
	StationUi.text(parent, caption, 16, StationUi.MUTED)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 9999
	spin.step = 1
	spin.value = 1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.get_line_edit().select_all_on_focus = true
	row.add_child(spin)
	StationUi.button(row, "MAX", func(): spin.value = maxi(1, maximum.call()))
	return spin


func build_refining(parent: Node) -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(body)
	pages["refining"] = body
	var tree_card := StationUi.card(body)
	tree_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tree_rows := StationUi.rows(tree_card, 12)
	StationUi.text(tree_rows, "RAW ORE → REFINED RESOURCES", 18, StationUi.MUTED)
	var tree := Control.new()
	tree.name = "RefiningTree"
	tree.custom_minimum_size = Vector2(650, 460)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_rows.add_child(tree)
	var positions := {
		"prometium": Vector2(18, 4), "endurium": Vector2(236, 4), "terbium": Vector2(454, 4),
		"prometid": Vector2(126, 165), "duranium": Vector2(344, 165), "promerium": Vector2(236, 326),
	}
	tree.draw.connect(func():
		for link: Array in [["prometium", "prometid"], ["endurium", "prometid"], ["endurium", "duranium"], ["terbium", "duranium"], ["prometid", "promerium"], ["duranium", "promerium"]]:
			tree.draw_line(positions[link[0]] + Vector2(82, 132), positions[link[1]] + Vector2(82, 0), StationUi.LINE.lightened(0.25), 2, true))
	for key: String in positions:
		var button := card(tree, key, func(): select_output(key), Vector2(164, 132))
		button.position = positions[key]
		button.size = Vector2(164, 132)
		resource_cards[key] = button
		button.tooltip_text = "Select to refine " + CargoResources.TYPES[key]["name"] if ResourceBoosts.RECIPES.has(key) else "Raw ore collected from alien cargo."
	StationUi.text(tree_rows, "Seprom production comes later with Skylab. Seprom in cargo can already boost equipment.", 15, StationUi.MUTED)
	var detail := StationUi.card(body)
	detail.custom_minimum_size.x = 340
	var rows := StationUi.rows(detail, 16)
	refine_title = StationUi.text(rows, "", 26)
	StationUi.text(rows, "Choose an output, enter an amount, then confirm refining. Ingredients come from this ship's cargo.", 17, StationUi.MUTED)
	refine_amount = amount_control(rows, "UNITS TO PRODUCE", func(): return ResourceBoosts.maximum(sector.cargo, output))
	rows.add_child(HSeparator.new())
	recipe = StationUi.text(rows, "", 19)
	recipe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	refine_button = StationUi.button(rows, "REFINE", refine)
	StationUi.primary(refine_button)


func build_update(parent: Node) -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(body)
	pages["update"] = body
	var group_row := HBoxContainer.new()
	body.add_child(group_row)
	for key: String in ResourceBoosts.GROUPS:
		groups[key] = StationUi.button(group_row, ResourceBoosts.GROUPS[key].to_upper() + (" · LATER" if key == "rockets" else ""), func(): select_group(key))
		groups[key].toggle_mode = true
		groups[key].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var resources := VBoxContainer.new()
	resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(resources)
	StationUi.text(resources, "CHOOSE A BOOST RESOURCE", 18, StationUi.MUTED)
	var cards := HBoxContainer.new()
	cards.name = "UpgradeCards"
	cards.add_theme_constant_override("separation", 6)
	resources.add_child(cards)
	for key: String in ResourceBoosts.BONUSES:
		upgrade_cards[key] = card(cards, key, func(): select_resource(key), Vector2(162, 172))
		upgrade_cards[key].tooltip_text = BOOST_TEXT[key]
	StationUi.text(resources, "ACTIVE BOOSTS · THIS SHIP", 18, StationUi.MUTED)
	for key: String in ResourceBoosts.GROUPS:
		var panel := StationUi.card(resources)
		var row := HBoxContainer.new()
		panel.add_child(row)
		StationUi.text(row, ResourceBoosts.GROUPS[key].to_upper(), 17, StationUi.MUTED).custom_minimum_size.x = 100
		reserve_labels[key] = StationUi.text(row, "", 18)
		reserve_labels[key].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	StationUi.text(resources, "One unit = 10 individual laser rounds or 10 minutes for shields / engines. Timers count while online in this ship, including menus and rescue; disconnecting preserves unused time.", 16, StationUi.MUTED)
	var detail := StationUi.card(columns)
	detail.custom_minimum_size.x = 340
	var rows := StationUi.rows(detail, 16)
	upgrade_title = StationUi.text(rows, "", 26)
	upgrade_description = StationUi.text(rows, "", 18)
	upgrade_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upgrade_amount = amount_control(rows, "RESOURCE UNITS TO APPLY", func(): return int(sector.cargo.get(resource, 0)))
	replace_warning = CheckButton.new()
	replace_warning.text = "Replace remaining boost"
	replace_warning.tooltip_text = "The current resource's remaining rounds or time will be discarded."
	rows.add_child(replace_warning)
	upgrade_button = StationUi.button(rows, "APPLY BOOST", upgrade)
	StationUi.primary(upgrade_button)


func select_tab(key: String) -> void:
	page = key
	for entry: String in pages:
		pages[entry].visible = entry == key
	for entry: String in tabs:
		tabs[entry].set_pressed_no_signal(entry == key)
	fit_window()


func select_output(key: String) -> void:
	if ResourceBoosts.RECIPES.has(key):
		output = key
		refine_amount.value = 1


func select_group(key: String) -> void:
	group = key
	if not ResourceBoosts.BONUSES[resource].has(key):
		for candidate: String in ResourceBoosts.BONUSES:
			if ResourceBoosts.BONUSES[candidate].has(key):
				resource = candidate
				break
	replace_warning.button_pressed = false


func select_resource(key: String) -> void:
	resource = key
	upgrade_amount.value = 1
	replace_warning.button_pressed = false


func refine() -> void:
	refine_amount.apply()
	if not refine_button.disabled:
		sector.session.combat.request_station("refine", "%s:%d" % [output, int(refine_amount.value)])


func upgrade() -> void:
	upgrade_amount.apply()
	if not upgrade_button.disabled:
		sector.session.combat.request_station("replace_boost" if replace_warning.button_pressed else "boost", "%s:%d" % [resource, int(upgrade_amount.value)], group)


func fit_window() -> void:
	if is_instance_valid(sector.main_menu) and sector.main_menu.visible:
		sector.main_menu.fit_panel(self, SIZE)
	else:
		StationUi.centered(self, SIZE)


func open() -> void:
	if not StationUi.can_open(sector):
		return
	if sector.main_menu.route_page("refining"):
		return
	sector.shop.hide()
	sector.equipment_menu.hide()
	sector.hud.contract_panel.hide()
	sector.session.menu.hide()
	sector.set_paused(true)
	replace_warning.button_pressed = false
	fit_window()
	show()


func close() -> void:
	hide()
	sector.set_paused(false)


func _process(_delta: float) -> void:
	if not visible:
		return
	var blocked := StationUi.blocker(sector)
	cargo_summary.text = "CARGO %d / %d" % [CargoResources.units(sector.cargo), sector.cargo_capacity]
	for key: String in counts:
		counts[key].text = "CARGO %d" % int(sector.cargo.get(key.get_slice(":", 1), 0))
	for key: String in resource_cards:
		resource_cards[key].set_pressed_no_signal(key == output)
	refine_title.text = "REFINE " + CargoResources.TYPES[output]["name"].to_upper()
	var ingredients: PackedStringArray = []
	for key: String in ResourceBoosts.RECIPES[output]:
		ingredients.append("%d %s  /  %d held" % [int(ResourceBoosts.RECIPES[output][key]) * int(refine_amount.value), CargoResources.TYPES[key]["name"], sector.cargo.get(key, 0)])
	recipe.text = "CONSUMES\n" + "\n".join(ingredients) + "\n\nPRODUCES\n%d %s\n\nMaximum now: %d" % [int(refine_amount.value), CargoResources.TYPES[output]["name"], ResourceBoosts.maximum(sector.cargo, output)]
	refine_button.text = "REFINE %d UNITS" % int(refine_amount.value)
	refine_button.disabled = not blocked.is_empty() or int(refine_amount.value) > ResourceBoosts.maximum(sector.cargo, output)
	refine_button.tooltip_text = blocked if not blocked.is_empty() else ("Not enough ingredients." if refine_button.disabled else "Consume these ingredients and add the selected output to cargo.")
	var boosts := sector.player.resource_boosts
	for key: String in groups:
		groups[key].set_pressed_no_signal(key == group)
	for key: String in upgrade_cards:
		upgrade_cards[key].disabled = not ResourceBoosts.BONUSES[key].has(group)
		upgrade_cards[key].set_pressed_no_signal(key == resource)
	for key: String in reserve_labels:
		var left := ResourceBoosts.remaining(boosts, key)
		var entry: Dictionary = boosts.get(key, {})
		var remaining_text := "%d rounds" % int(left) if key in ["lasers", "rockets"] else "%d:%02d remaining" % [int(ceil(left)) / 60, int(ceil(left)) % 60]
		reserve_labels[key].text = "%s +%d%% · %s" % [CargoResources.TYPES[entry["resource"]]["name"], roundi(ResourceBoosts.bonus(boosts, key) * 100), remaining_text] if left > 0 else ("Coming later · rocket weapons" if key == "rockets" else "No active boost")
	var percent: float = ResourceBoosts.BONUSES[resource].get(group, 0.0)
	var replacement: bool = ResourceBoosts.remaining(boosts, group) > 0 and boosts[group]["resource"] != resource
	var signature := "%s:%s:%s" % [group, resource, boosts.get(group, {}).get("resource", "")]
	if signature != last_replacement:
		replace_warning.button_pressed = false
		last_replacement = signature
	replace_warning.visible = replacement
	upgrade_title.text = ResourceBoosts.GROUPS[group].to_upper() + " +%d%%" % roundi(percent * 100)
	var amount := int(upgrade_amount.value)
	upgrade_description.text = "%s\n\n%s\n\n%s" % [CargoResources.TYPES[resource]["name"], ("Adds %d boosted rounds. Each installed laser uses one round per shot; the final volley may be partly boosted." % (amount * 10) if group == "lasers" else "Adds %d minutes at the same bonus." % (amount * 10)), ("WARNING: applying this resource discards the current boost's remaining rounds or time." if replacement else "Applying the same resource extends its reserve. The percentage does not stack.")]
	if group == "rockets":
		upgrade_description.text = "Rocket weapons are coming later.\n\nEach resource unit will provide 10 boosted rockets at the listed damage bonus."
	var reason := blocked
	if reason.is_empty() and group == "rockets":
		reason = "Rocket boosts are coming later."
	if reason.is_empty() and percent <= 0:
		reason = "That resource cannot boost this equipment."
	if reason.is_empty() and amount > int(sector.cargo.get(resource, 0)):
		reason = "Not enough of this resource in cargo."
	if reason.is_empty() and replacement and not replace_warning.button_pressed:
		reason = "Confirm replacement to discard the current boost."
	upgrade_button.disabled = not reason.is_empty()
	upgrade_button.tooltip_text = reason
	upgrade_button.text = "REPLACE BOOST" if replacement else "APPLY BOOST"
	status.text = blocked if not blocked.is_empty() else sector.session.combat.station_message
