class_name SkylabMenu
extends PanelContainer
## Server snapshots drive every value; local time animates countdowns only.

class OreAmount extends LineEdit:
	var value: float:
		get: return float(text.to_int()) if valid_amount() else 0.0
		set(amount): text = str(int(amount))
	func valid_amount() -> bool:
		return text.is_valid_int() and text.to_int() >= 0 and text.to_int() <= Skylab.LIMIT
	func apply() -> void:
		if not valid_amount(): text = "0"

const CAPTIONS := {
	"solar": Vector2(.63, .018), "basic": Vector2(.54, .90), "storage": Vector2(.03, .66), "transport": Vector2(.08, .92),
	"prometiumCollector": Vector2(.03, .22), "enduriumCollector": Vector2(.03, .39), "terbiumCollector": Vector2(.03, .55),
	"prometidRefinery": Vector2(.80, .27), "duraniumRefinery": Vector2(.80, .43), "promeriumRefinery": Vector2(.80, .51),
	"xeno": Vector2(.82, .65), "sepromRefinery": Vector2(.80, .82),
}
var sector: Sector
var art: SkylabPreview
var canvas: Control
var ore_strip: HBoxContainer
var ore_labels: Dictionary = {}
var buttons: Dictionary = {}
var detail: PanelContainer
var tabs: TabContainer
var selected := "basic"
var snapshot: Dictionary = {}
var received_at := 0
var refresh_clock := 0.0
var power_label: Label
var status: Label
var detail_title: Label
var info: Label
var info_rows: VBoxContainer
var overview: GridContainer
var overview_values: Dictionary = {}
var flow: VBoxContainer
var flow_cards: Dictionary = {}
var upgrade_info: Label
var upgrade_grid: GridContainer
var upgrade_values: Dictionary = {}
var progress: ProgressBar
var enable: Button
var module_level: Label
var module_power: Label
var module_productivity: Label
var build: Button
var instant: Button
var finish: Button
var cancel: Button
var basic_link: Button
var robot_info: Label
var robot_summary: Label
var robot_amount: SpinBox
var credit_robot: Button
var advanced_robot: Button
var transport_info: Label
var transport_rows: VBoxContainer
var amounts: Dictionary = {}
var send: Button
var instant_send: Button
var finish_send: Button
var cancel_dialog: ConfirmationDialog


func _ready() -> void:
	StationUi.frame(self, Vector2(1150, 760))
	var rows := StationUi.rows(self, 0)
	rows.add_theme_constant_override("separation", 0)
	ore_strip = HBoxContainer.new()
	ore_strip.add_theme_constant_override("separation", 0)
	rows.add_child(ore_strip)
	for resource: String in Skylab.RESOURCES:
		var cell := StationUi.card(ore_strip)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var content := StationUi.rows(cell, 7)
		var header := HBoxContainer.new()
		content.add_child(header)
		mineral(header, resource, Vector2(25, 27))
		var name_label := StationUi.text(header, CargoResources.TYPES[resource]["name"], 15)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		ore_labels[resource] = StationUi.text(content, "", 15, StationUi.MUTED)
		ore_labels[resource].autowrap_mode = TextServer.AUTOWRAP_OFF
	canvas = Control.new()
	canvas.custom_minimum_size = Vector2(1100, 625)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(canvas)
	art = SkylabPreview.new()
	canvas.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var nearest := 48.0
			var chosen := ""
			for id: String in Skylab.MODULES:
				var distance := canvas.get_local_mouse_position().distance_to(art.point(id))
				if distance < nearest:
					nearest = distance
					chosen = id
			if not chosen.is_empty(): select_module(chosen))
	for id: String in Skylab.MODULES:
		var button := Button.new()
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16)
		button.custom_minimum_size = Vector2(174, 42)
		for state: String in ["normal", "pressed", "disabled"]:
			var surface := StationUi.style(Color("0b1115", .62), Color.TRANSPARENT)
			surface.set_content_margin_all(4)
			button.add_theme_stylebox_override(state, surface)
		button.tooltip_text = "Completed level, instantaneous power and productivity. Select the label or station module for details."
		button.pressed.connect(func(): select_module(id))
		canvas.add_child(button)
		buttons[id] = button
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	rows.add_child(footer)
	power_label = StationUi.text(footer, "", 16, StationUi.AMBER)
	power_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status = StationUi.text(footer, "", 15, StationUi.MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	StationUi.button(footer, "Refresh", func(): sector.session.combat.request_lab())
	build_detail()
	cancel_dialog = ConfirmationDialog.new()
	cancel_dialog.title = "Cancel upgrade?"
	cancel_dialog.dialog_text = "Paid credits and raw ore are forfeited. The completed level is kept."
	cancel_dialog.confirmed.connect(func(): command("cancel"))
	add_child(cancel_dialog)
	hide()


func mineral(parent: Node, resource: String, dimensions := Vector2(28, 28)) -> void:
	var image := TextureRect.new()
	image.texture = load("res://assets/ui/resources/%s.png" % resource)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = dimensions
	parent.add_child(image)


func page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var rows := StationUi.rows(scroll, 10)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rows


func grid(parent: Node, columns: int) -> GridContainer:
	var value := GridContainer.new()
	value.columns = columns
	value.add_theme_constant_override("h_separation", 14)
	value.add_theme_constant_override("v_separation", 6)
	parent.add_child(value)
	return value


func cell(parent: Node, text: String, color := StationUi.MUTED) -> Label:
	var label := StationUi.text(parent, text, 17, color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


func build_detail() -> void:
	detail = PanelContainer.new()
	StationUi.frame(detail, Vector2(488, 610))
	canvas.add_child(detail)
	var rows := StationUi.rows(detail, 6)
	var heading := HBoxContainer.new()
	rows.add_child(heading)
	detail_title = StationUi.text(heading, "", 25, StationUi.AMBER)
	detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	StationUi.button(heading, "Close", func(): detail.hide())
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(tabs)
	info_rows = page("Info")
	info = StationUi.text(info_rows, "", 17)
	info.custom_minimum_size.x = 408
	overview = grid(info_rows, 3)
	flow = VBoxContainer.new()
	info_rows.add_child(flow)
	build_transport()
	var upgrade_rows := page("Upgrade")
	upgrade_info = StationUi.text(upgrade_rows, "", 17)
	upgrade_info.custom_minimum_size.x = 408
	basic_link = StationUi.button(upgrade_rows, "Open Basic module →", func(): select_module("basic"); tabs.current_tab = 1)
	upgrade_grid = grid(upgrade_rows, 3)
	for text: String in ["REQUIREMENT", "INSTANT", "NORMAL"]: cell(upgrade_grid, text, StationUi.AMBER)
	for key: String in ["credits", "time", "prometium", "endurium", "terbium"]:
		cell(upgrade_grid, {"credits": "Credits", "time": "Time"}.get(key, key.capitalize()))
		upgrade_values[key] = [cell(upgrade_grid, "", Color.WHITE), cell(upgrade_grid, "", Color.WHITE)]
	var builds := HBoxContainer.new()
	upgrade_rows.add_child(builds)
	instant = StationUi.button(builds, "Instant build", func(): command("build_instant"))
	build = StationUi.button(builds, "Build", func(): command("upgrade"))
	instant.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 28
	progress.show_percentage = true
	upgrade_rows.add_child(progress)
	var job_actions := HBoxContainer.new()
	upgrade_rows.add_child(job_actions)
	finish = StationUi.button(job_actions, "Finish now", func(): command("finish_upgrade"))
	cancel = StationUi.button(job_actions, "Cancel upgrade", func(): cancel_dialog.popup_centered())
	finish.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	StationUi.text(upgrade_rows, "Canceling forfeits paid credits and raw ore.", 15, StationUi.MUTED)
	build_robots(page("Productivity"))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	rows.add_child(footer)
	enable = StationUi.button(footer, "ON", func(): command("enable", {"enabled": not snapshot["modules"][selected]["enabled"]}))
	enable.custom_minimum_size.x = 65
	module_level = StationUi.text(footer, "", 18)
	module_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	module_power = StationUi.text(footer, "", 18, StationUi.AMBER)
	module_power.autowrap_mode = TextServer.AUTOWRAP_OFF
	module_level.autowrap_mode = TextServer.AUTOWRAP_OFF
	module_productivity = StationUi.text(footer, "", 18)
	module_productivity.autowrap_mode = TextServer.AUTOWRAP_OFF
	detail.hide()


func build_robots(rows: VBoxContainer) -> void:
	(rows.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(tabs.get_child(2) as ScrollContainer).vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	robot_summary = StationUi.text(rows, "", 18)
	var choices := HBoxContainer.new()
	rows.add_child(choices)
	for kind: String in ["credit", "advanced"]:
		var card := StationUi.card(choices)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var content := StationUi.rows(card, 8)
		var image := TextureRect.new()
		image.texture = load("res://assets/ui/skylab/robot-advanced.png" if kind == "advanced" else "res://assets/ui/skylab/robot-standard.png")
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(110, 112)
		content.add_child(image)
		var name_label := StationUi.text(content, "Advanced +4%" if kind == "advanced" else "Standard +1%", 18)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var button := StationUi.button(content, "", func(): buy_robots(kind))
		if kind == "credit": credit_robot = button
		else: advanced_robot = button
	var quantity := HBoxContainer.new()
	rows.add_child(quantity)
	StationUi.text(quantity, "Quantity", 17).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	robot_amount = SpinBox.new()
	robot_amount.min_value = 1
	robot_amount.max_value = 1000000
	robot_amount.value = 1
	quantity.add_child(robot_amount)
	robot_info = StationUi.text(rows, "", 16, StationUi.MUTED)
	StationUi.text(rows, "48-hour lifetime · Advanced activates first", 15, StationUi.MUTED)


func build_transport() -> void:
	transport_rows = VBoxContainer.new()
	transport_rows.add_theme_constant_override("separation", 6)
	info_rows.add_child(transport_rows)
	transport_info = StationUi.text(transport_rows, "", 17)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	transport_rows.add_child(body)
	var inputs := grid(body, 3)
	inputs.add_theme_constant_override("v_separation", 2)
	inputs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for resource: String in Skylab.RESOURCES:
		mineral(inputs, resource, Vector2(22, 24))
		cell(inputs, CargoResources.TYPES[resource]["name"])
		var amount := OreAmount.new()
		amount.value = 0
		amount.custom_minimum_size = Vector2(80, 26)
		amount.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.add_theme_font_size_override("font_size", 16)
		var input_style := StationUi.style(Color("111a20"), StationUi.LINE)
		input_style.set_content_margin_all(3)
		amount.add_theme_stylebox_override("normal", input_style)
		amount.add_theme_stylebox_override("focus", input_style)
		inputs.add_child(amount)
		amounts[resource] = amount
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 150
	body.add_child(actions)
	var route := StationUi.text(actions, "SKYLAB\n↓\nSHIP CARGO", 21, StationUi.AMBER)
	route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route.custom_minimum_size.y = 92
	instant_send = StationUi.button(actions, "Instant send", func(): dispatch(true))
	StationUi.text(actions, "125,000 CR\nFlat fee · any amount", 16, StationUi.MUTED)
	send = StationUi.button(actions, "Send", func(): dispatch(false))
	finish_send = StationUi.button(transport_rows, "Deliver now · 125,000 CR", func(): command("finish_shipment"))


func open() -> void:
	show()
	if StationUi.offline_preview(sector):
		var pilot := {"equipment": Equipment.starter(), "cargo": {"starter": {}}, "credits": 0, "premium": false, "skylab": Skylab.bootstrap(Skylab.now())}
		snapshot = Skylab.snapshot(pilot, Skylab.now())
		received_at = Time.get_ticks_msec()
	else: sector.session.combat.request_lab()
	received()
	layout()


func received() -> void:
	if not StationUi.offline_preview(sector): snapshot = sector.session.combat.lab_snapshot
	received_at = Time.get_ticks_msec()
	refresh_clock = 0.0


func server_time() -> int:
	return int(snapshot.get("server_time", 0)) + int((Time.get_ticks_msec() - received_at) / 1000)


func duration(seconds: int) -> String:
	seconds = maxi(0, seconds)
	return "%dh %02dm %02ds" % [int(seconds / 3600), int(seconds / 60) % 60, seconds % 60]


func money(value: int) -> String:
	return StationShop.credits_text(value) + " CR"


func command(action: String, payload: Dictionary = {}) -> void:
	if StationUi.offline_preview(sector): return
	payload = payload.duplicate()
	payload["module"] = selected
	sector.session.combat.request_lab(action, payload)


func buy_robots(kind: String) -> void:
	robot_amount.apply()
	command("robots", {"kind": kind, "amount": int(robot_amount.value)})


func dispatch(immediate: bool = false) -> void:
	var manifest := {}
	for resource: String in amounts:
		amounts[resource].apply()
		var amount := int(amounts[resource].value)
		if amount > 0: manifest[resource] = amount
	command("ship_instant" if immediate else "ship", {"manifest": manifest})


func select_module(id: String) -> void:
	selected = id
	tabs.set_tab_hidden(2, not Skylab.COLLECTORS.has(id))
	tabs.current_tab = 0
	rebuild_info()
	(tabs.get_child(0) as ScrollContainer).scroll_vertical = 0
	detail.show()
	update_detail()
	layout()


func rebuild_info() -> void:
	for node: Node in overview.get_children(): overview.remove_child(node); node.queue_free()
	for node: Node in flow.get_children(): flow.remove_child(node); node.queue_free()
	overview_values.clear()
	flow_cards.clear()
	transport_rows.visible = selected == "transport"
	info.visible = selected != "transport"
	if selected == "basic":
		for title: String in ["FACILITY", "LEVEL TRACK", "LEVEL"]: cell(overview, title, StationUi.AMBER)
		for id: String in Skylab.MODULES:
			if id == "transport": continue
			cell(overview, Skylab.MODULES[id])
			var bar := ProgressBar.new()
			bar.max_value = 20
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(86, 10)
			var track := StationUi.style(Color("18252e"), StationUi.LINE)
			track.set_content_margin_all(0)
			var fill := track.duplicate() as StyleBoxFlat
			fill.bg_color = StationUi.AMBER
			bar.add_theme_stylebox_override("background", track)
			bar.add_theme_stylebox_override("fill", fill)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			overview.add_child(bar)
			overview_values[id] = [bar, cell(overview, "", Color.WHITE)]
	elif selected == "solar":
		for title: String in ["FACILITY", "POWER", "STATE"]: cell(overview, title, StationUi.AMBER)
		for id: String in Skylab.MODULES:
			if id == "solar": continue
			cell(overview, Skylab.MODULES[id])
			overview_values[id] = [cell(overview, "", Color.WHITE), cell(overview, "")]
	elif selected == "storage":
		for title: String in ["RESOURCE", "STOCK / CAPACITY", "NET / H"]: cell(overview, title, StationUi.AMBER)
		for resource: String in Skylab.RESOURCES:
			cell(overview, resource.capitalize())
			overview_values[resource] = [cell(overview, "", Color.WHITE), cell(overview, "")]
	elif selected == "xeno":
		for title: String in ["XENO SUPPORT", "ACTIVE", "INACTIVE"]: cell(overview, title, StationUi.AMBER)
		for key: String in ["Catalyst / hour", "Real Xenomit / output", "Power"]:
			cell(overview, key)
			overview_values[key] = [cell(overview, "", Color.WHITE), cell(overview, "")]
	elif Skylab.RECIPES.has(selected) or Skylab.COLLECTORS.has(selected):
		var sources := HBoxContainer.new()
		flow.add_child(sources)
		if Skylab.RECIPES.has(selected):
			for resource: String in Skylab.RECIPES[selected]: flow_card(sources, resource, "input")
			if selected == "promeriumRefinery": flow_card(sources, "xenomit", "catalyst")
		var convert := StationUi.text(flow, "↓   REFINING   ↓" if Skylab.RECIPES.has(selected) else "COLLECTION", 22, StationUi.AMBER)
		convert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var output := HBoxContainer.new()
		flow.add_child(output)
		flow_card(output, Skylab.OUTPUT.get(selected, Skylab.COLLECTORS.get(selected, "")), "output")


func flow_card(parent: Node, resource: String, role: String) -> void:
	var card := StationUi.card(parent)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows := StationUi.rows(card, 6)
	mineral(rows, resource, Vector2(48, 48))
	var name_label := StationUi.text(rows, resource.capitalize(), 20, CargoResources.TYPES[resource]["color"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var value := StationUi.text(rows, "", 16)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flow_cards[resource] = {"label": value, "role": role}


func layout() -> void:
	if not visible: return
	# Fill the navigation content area, retaining readable logical UI dimensions.
	var area := sector.main_menu.content_rect()
	var minimum := Vector2(1150, 760).max(get_combined_minimum_size())
	var factor := minf(1.0, minf(area.size.x / minimum.x, area.size.y / minimum.y))
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2.ONE * factor
	size = area.size / factor
	position = area.position
	var connectors := {}
	for id: String in buttons:
		var button: Button = buttons[id]
		button.size = Vector2(174, 42)
		button.position = (CAPTIONS[id] * canvas.size).clamp(Vector2(3, 3), canvas.size - button.size - Vector2(3, 3))
		var anchor := button.position + Vector2(button.size.x if button.position.x < art.point(id).x else 0, 30)
		connectors[id] = anchor
	art.set_connectors(connectors, selected if detail.visible else "")
	detail.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	detail.size = Vector2(488, minf(610, canvas.size.y - 16))
	detail.position = Vector2(canvas.size.x - detail.size.x - 14, 12)


func _process(delta: float) -> void:
	if not visible: return
	layout()
	refresh_clock += delta
	if refresh_clock >= 15 and not StationUi.offline_preview(sector):
		refresh_clock = 0
		sector.session.combat.request_lab()
	if snapshot.is_empty(): status.text = "Waiting for Skylab snapshot..."; return
	for resource: String in Skylab.RESOURCES:
		ore_labels[resource].text = "%s / %s" % [StationShop.credits_text(int(snapshot["inventory"][resource])), StationShop.credits_text(int(snapshot["capacities"][resource]))]
		ore_labels[resource].tooltip_text = "Separate capacity · Last-minute net: %+.1f / hour" % snapshot["net_per_hour"][resource]
	for id: String in buttons:
		var module: Dictionary = snapshot["modules"][id]
		var level := "Lv %d" % module["level"]
		if module["upgrade"] != null: level += " → %d" % module["upgrade"]["targetLevel"]
		buttons[id].text = "%s\n%s · %d P%s" % [Skylab.MODULES[id], level, module["power"], " · %.0f%%" % module["productivity"] if Skylab.RECIPES.has(id) else ""]
		buttons[id].set_pressed_no_signal(detail.visible and selected == id)
	power_label.text = "POWER %d / %d" % [snapshot["power"]["demand"], snapshot["power"]["capacity"]]
	power_label.tooltip_text = "Power is instantaneous capacity. All Skylab purchases use credits."
	status.text = StationUi.OFFLINE_BLOCKER if StationUi.offline_preview(sector) else sector.session.combat.station_message
	if status.text.is_empty(): status.text = "Ore settles each minute · Rates show the last completed minute"
	if detail.visible: update_detail()


func update_detail() -> void:
	if snapshot.is_empty(): return
	var module: Dictionary = snapshot["modules"][selected]
	var blocked := StationUi.offline_preview(sector) or sector.session.combat.station_pending
	var at := server_time()
	var wallet := int(snapshot["credits"])
	detail_title.text = Skylab.MODULES[selected]
	var reasons := PackedStringArray(module["blockers"])
	var state := ", ".join(reasons).replace("blocked-", "").replace("-", " ") if not reasons.is_empty() else "Running"
	info.text = state.capitalize()
	info.add_theme_color_override("font_color", StationUi.MUTED if reasons.is_empty() else StationUi.AMBER)
	module_level.text = "Lv %d" % module["level"]
	if module["upgrade"] != null: module_level.text += " → %d" % module["upgrade"]["targetLevel"]
	module_power.text = "%d P" % module["power"]
	module_power.tooltip_text = "Instantaneous power demand · Missing: %d" % module["missing_power"]
	module_productivity.text = "%.0f%%" % module["productivity"] if Skylab.RECIPES.has(selected) or Skylab.COLLECTORS.has(selected) else ""
	module_productivity.tooltip_text = "Production effectiveness, separate from construction progress."
	enable.text = "ON" if module["enabled"] else "OFF"
	enable.disabled = blocked or selected == "basic" or module["level"] == 0
	enable.tooltip_text = "Basic is always on." if selected == "basic" else "Toggle output and power. Construction and robot expiry continue."
	update_info(module)
	update_upgrade(module, blocked, wallet, at)
	if Skylab.COLLECTORS.has(selected): update_robots(blocked, wallet, at)
	if selected == "transport": update_transport(blocked, wallet, at)


func update_info(module: Dictionary) -> void:
	if selected == "basic":
		info.text += " · Other modules cannot exceed completed Basic level %d." % module["level"]
		for id: String in overview_values:
			var item: Dictionary = snapshot["modules"][id]
			overview_values[id][0].value = item["level"]
			overview_values[id][1].text = "%d%s" % [item["level"], " → %d" % item["upgrade"]["targetLevel"] if item["upgrade"] != null else ""]
	elif selected == "solar":
		info.text += " · Total demand %d / %d capacity" % [snapshot["power"]["demand"], snapshot["power"]["capacity"]]
		for id: String in overview_values:
			var item: Dictionary = snapshot["modules"][id]
			overview_values[id][0].text = str(item["power"])
			overview_values[id][1].text = "No power" if "blocked-no-power" in item["blockers"] else ("On" if item["enabled"] else "Off")
	elif selected == "storage":
		info.text += " · Independent capacity for each resource"
		for resource: String in overview_values:
			overview_values[resource][0].text = "%s / %s" % [StationShop.credits_text(int(snapshot["inventory"][resource])), StationShop.credits_text(int(snapshot["capacities"][resource]))]
			overview_values[resource][1].text = "%+.0f" % snapshot["net_per_hour"][resource]
	elif selected == "xeno":
		info.text += "\nVirtual catalyst supports Promerium; it creates no stored Xenomit."
		overview_values["Catalyst / hour"][0].text = "%.0f" % module["nominal_per_hour"]
		overview_values["Catalyst / hour"][1].text = "0"
		overview_values["Real Xenomit / output"][0].text = "0 if covered"
		overview_values["Real Xenomit / output"][1].text = "1"
		overview_values["Power"][0].text = str(Skylab.table("xeno", int(module["level"]))["power"])
		overview_values["Power"][1].text = "0"
	elif not flow_cards.is_empty():
		var gross: float = module["gross_per_hour"]
		for resource: String in flow_cards:
			var card: Dictionary = flow_cards[resource]
			if card["role"] == "input":
				card["label"].text = "%d per output\n%.0f / hour" % [Skylab.RECIPES[selected][resource], gross * Skylab.RECIPES[selected][resource]]
			elif card["role"] == "catalyst": card["label"].text = "1 catalyst\nXeno first"
			else:
				card["label"].text = "Gross %.0f / h\nNet %+.0f / h" % [gross, snapshot["net_per_hour"][resource]]
		info.text += "\nNominal output %.0f / hour" % module["nominal_per_hour"]
		if selected == "promeriumRefinery": info.text += " · Xeno or real Xenomit"


func update_upgrade(module: Dictionary, blocked: bool, wallet: int, at: int) -> void:
	var job: Variant = module["upgrade"]
	var entry: Dictionary = module["next"]
	progress.visible = job != null
	upgrade_grid.visible = job == null and not entry.is_empty()
	build.visible = job == null and not entry.is_empty()
	instant.visible = build.visible
	finish.visible = job != null
	cancel.visible = job != null
	basic_link.visible = job == null and module["upgrade_blocker"].contains("Basic")
	cancel.disabled = blocked
	if job != null:
		var price := Skylab.speed_price(job, int(entry["instant_credits"]), at)
		upgrade_info.text = "Completed: %d → Target: %d\nRemaining: %s\nComplete this construction now for %s." % [module["level"], job["targetLevel"], duration(job["finishesAt"] - at), money(price)]
		progress.value = clampf(100.0 * (at - job["startedAt"]) / (job["finishesAt"] - job["startedAt"]), 0, 100)
		finish.text = "Finish · " + money(price)
		finish.disabled = blocked or wallet < price
		return
	if entry.is_empty(): upgrade_info.text = module["upgrade_blocker"]; return
	var ordinary := int(entry["credits"])
	var total := ordinary + int(entry["instant_credits"])
	upgrade_values["credits"][0].text = money(total)
	upgrade_values["credits"][1].text = money(ordinary)
	upgrade_values["time"][0].text = "0:00"
	upgrade_values["time"][1].text = duration(int(entry["duration"]))
	var enough := true
	for resource: String in ["prometium", "endurium", "terbium"]:
		var cost := int(entry["ores"].get(resource, 0))
		for label: Label in upgrade_values[resource]:
			label.text = str(cost)
			label.add_theme_color_override("font_color", Color.WHITE if snapshot["inventory"][resource] >= cost else StationUi.AMBER)
		enough = enough and snapshot["inventory"][resource] >= cost
	upgrade_info.text = "Next level: %d · Power %d → %d" % [entry["level"], module["power"], entry["power"]]
	if selected == "solar": upgrade_info.text += "\nCapacity %d → %d power" % [snapshot["power"]["capacity"], entry["solar_capacity"]]
	elif selected == "storage": upgrade_info.text += "\nIndependent capacities increase for all eight ores."
	elif float(entry["rate_per_hour"]) > 0: upgrade_info.text += "\nOutput %.0f → %.0f / hour" % [module["nominal_per_hour"], entry["rate_per_hour"]]
	var reason: String = module["upgrade_blocker"]
	if reason.contains("Basic"): reason = "Requires Basic level %d. Upgrade Basic and wait for completion." % entry["level"]
	elif reason.is_empty() and not enough: reason = "Insufficient lab ore."
	elif reason.is_empty() and wallet < ordinary: reason = "Insufficient credits."
	if not reason.is_empty(): upgrade_info.text += "\n" + reason
	build.text = "Build · " + money(ordinary)
	instant.text = "Instant · " + money(total)
	build.disabled = blocked or not module["upgrade_blocker"].is_empty() or not enough or wallet < ordinary
	instant.disabled = build.disabled or wallet < total
	instant.tooltip_text = "Includes ordinary construction plus %s acceleration. The same raw ore is required." % money(int(entry["instant_credits"]))


func update_robots(blocked: bool, wallet: int, at: int) -> void:
	var robots: Dictionary = snapshot["robots"][selected]
	var boost := 0
	var expiries := PackedStringArray()
	for robot: Dictionary in robots["active"]:
		boost += 4 if robot["kind"] == "advanced" else 1
		expiries.append("%s · %s" % ["Advanced" if robot["kind"] == "advanced" else "Standard", duration(robot["expiresAt"] - at)])
	robot_summary.text = "Bonus +%d%% · Active %d / 12" % [boost, robots["active"].size()]
	robot_info.text = "Queue: %d standard · %d advanced" % [robots["credit"], robots["advanced"]]
	if not robots["active"].is_empty():
		var next_expiry := 10_000_000_000
		for robot: Dictionary in robots["active"]: next_expiry = mini(next_expiry, int(robot["expiresAt"]))
		robot_info.text += "\nNext expiry: " + duration(next_expiry - at)
	robot_info.tooltip_text = "\n".join(expiries)
	var standard := int(robot_amount.value) * int(Skylab.data()["policies"]["robot_credit_price"])
	var advanced := int(robot_amount.value) * int(Skylab.data()["policies"]["robot_advanced_price"])
	credit_robot.text = "Buy · " + money(standard)
	advanced_robot.text = "Buy · " + money(advanced)
	credit_robot.disabled = blocked or wallet < standard
	advanced_robot.disabled = blocked or wallet < advanced


func update_transport(blocked: bool, wallet: int, at: int) -> void:
	var requested := 0
	var enough := true
	for resource: String in amounts:
		requested += int(amounts[resource].value)
		enough = enough and amounts[resource].valid_amount() and amounts[resource].value <= snapshot["inventory"][resource]
		amounts[resource].tooltip_text = "Lab stock: %s" % StationShop.credits_text(int(snapshot["inventory"][resource]))
	var free := maxi(0, sector.cargo_capacity - CargoResources.units(sector.cargo))
	var shipment: Variant = snapshot["shipment"]
	var seconds := maxi(int(Skylab.data()["policies"]["minimum_shipment_seconds"]), requested * int(Skylab.data()["policies"]["seconds_per_cargo_unit"]))
	if snapshot["premium"]: seconds = ceili(seconds * .5)
	transport_info.text = "Free cargo %d / %d · Requested %d\nNormal arrival: %s" % [free, sector.cargo_capacity, requested, duration(seconds)]
	if shipment != null: transport_info.text = "In flight to %s · Arrival in %s\n%s" % [shipment["recipientId"], duration(shipment["arrivesAt"] - at), CargoResources.describe(shipment["manifest"])]
	var transport: Dictionary = snapshot["modules"]["transport"]
	if not transport["blockers"].is_empty(): transport_info.text += "\n" + ", ".join(transport["blockers"])
	send.disabled = blocked or shipment != null or requested < 1 or requested > free or not enough or not transport["enabled"] or "blocked-no-power" in transport["blockers"]
	instant_send.disabled = send.disabled or wallet < int(Skylab.data()["policies"]["instant_shipment_credits"])
	instant_send.tooltip_text = "Delivers this manifest immediately for a flat 125,000 CR. Normal stock and free-cargo limits apply."
	finish_send.visible = shipment != null
	finish_send.disabled = blocked or wallet < int(Skylab.data()["policies"]["instant_shipment_credits"])
