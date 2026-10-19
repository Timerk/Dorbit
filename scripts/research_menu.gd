class_name ResearchMenu
extends PanelContainer
## Skill tree page. The server validates points, prerequisites and Skylab stock.

const SIZE := Vector2(1150, 690)
const ROW_COLORS := {"defense": FlightHud.CYAN, "economy": Color("c99bff"), "offense": Color("ff7a5c")}
var sector: Sector
var selected := "reinforced_plating"
var nodes: Dictionary[String, Button] = {}
var levels: Dictionary[String, Label] = {}
var connectors: Dictionary[String, ColorRect] = {}
var summary: Label
var detail_title: Label
var detail_row: Label
var detail_image: TextureRect
var artwork: Dictionary[String, Texture2D] = {}
var detail_effect: Label
var detail_cost: Label
var learn_button: Button
var reset_button: Button
var test_points_button: Button
var stock_label: Label
var status: Label


func _ready() -> void:
	StationUi.frame(self, SIZE)
	var rows := StationUi.rows(self, 16)
	rows.add_theme_constant_override("separation", 10)
	var header := StationUi.header_row(StationUi.header(rows, "RESEARCH", "PILOT SKILLS"))
	summary = StationUi.heading(header, "", 17, StationUi.MUTED)
	summary.size_flags_vertical = Control.SIZE_SHRINK_END
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	var tree := StationUi.card(body)
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_stretch_ratio = 1.8
	var tree_rows := StationUi.rows(tree, 16)
	tree_rows.add_theme_constant_override("separation", 14)
	for row: String in Research.ROWS:
		StationUi.heading(tree_rows, Research.ROW_NAMES[row].to_upper(), 14, ROW_COLORS[row]).add_theme_font_override("font", StationUi.tracked(true, 3))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		tree_rows.add_child(line)
		for id: String in Research.ROWS[row]:
			if line.get_child_count() > 0:
				var connector := ColorRect.new()
				connector.custom_minimum_size = Vector2(18, 3)
				connector.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				connector.mouse_filter = Control.MOUSE_FILTER_IGNORE
				line.add_child(connector)
				connectors[id] = connector
			skill_node(line, id, row)
	var detail := StationUi.card(body)
	detail.custom_minimum_size.x = 340
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail_rows := StationUi.rows(detail, 16)
	detail_rows.add_theme_constant_override("separation", 10)
	detail_row = StationUi.heading(detail_rows, "", 13, StationUi.MUTED)
	detail_title = StationUi.heading(detail_rows, "", 26)
	detail_image = TextureRect.new()
	detail_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	detail_image.custom_minimum_size = Vector2(0, 128)
	detail_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_rows.add_child(detail_image)
	detail_effect = StationUi.text(detail_rows, "", 16)
	detail_cost = StationUi.text(detail_rows, "", 16, StationUi.MUTED)
	detail_cost.size_flags_vertical = Control.SIZE_EXPAND_FILL
	learn_button = StationUi.button(detail_rows, "RESEARCH", learn)
	StationUi.primary(learn_button)
	reset_button = StationUi.button(detail_rows, "RESET TREE", func(): sector.session.combat.request_station("research_reset", ""))
	test_points_button = StationUi.button(detail_rows, "Preview: +%d research points" % PilotStore.PREVIEW_RESEARCH_GRANT, func(): sector.session.combat.request_station("test_research", ""))
	test_points_button.tooltip_text = "Adds saved test research points on an authorized preview server."
	test_points_button.hide()
	stock_label = StationUi.text(rows, "", 15, StationUi.MUTED)
	status = StationUi.text(rows, "", 16, StationUi.AMBER)
	status.custom_minimum_size.y = 26
	get_viewport().size_changed.connect(fit_window)
	fit_window()
	hide()


func skill_node(parent: Node, id: String, row: String) -> void:
	var button := StationUi.button(parent, "", func(): selected = id)
	button.custom_minimum_size = Vector2(128, 148)
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var rows := VBoxContainer.new()
	button.add_child(rows)
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 8
	rows.offset_right = -8
	rows.offset_top = 8
	rows.offset_bottom = -8
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork[id] = load("res://assets/ui/research/%s.png" % id)
	var illustration := TextureRect.new()
	illustration.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	illustration.texture = artwork[id]
	illustration.custom_minimum_size = Vector2(0, 64)
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(illustration)
	var name_label := StationUi.text(rows, Research.SKILLS[id]["name"].to_upper(), 14, ROW_COLORS[row])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	levels[id] = StationUi.heading(rows, "", 18)
	levels[id].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	levels[id].mouse_filter = Control.MOUSE_FILTER_IGNORE
	nodes[id] = button


func research() -> Dictionary:
	return Research.state(StationUi.inventory(sector))


func stock() -> Dictionary:
	return {} if StationUi.offline_preview(sector) else sector.session.combat.lab_snapshot.get("inventory", {})


func learn() -> void:
	if not learn_button.disabled:
		sector.session.combat.request_station("research", selected)


func fit_window() -> void:
	if is_instance_valid(sector.main_menu) and sector.main_menu.visible:
		sector.main_menu.fit_panel(self, SIZE)
	else:
		StationUi.centered(self, SIZE)


func open() -> void:
	if not StationUi.can_open(sector, false):
		return
	if sector.main_menu.route_page("research"):
		return
	sector.set_paused(true)
	fit_window()
	show()
	# Refresh lab stock, which only arrives with station replies.
	sector.session.combat.request_lab()


func close() -> void:
	hide()
	sector.set_paused(false)


func _process(_delta: float) -> void:
	if not visible:
		return
	var data := research()
	var lab := stock()
	var spent := Research.spent(data)
	StationUi.set_text(summary, "%d RESEARCH POINTS  /  %d OF %d LEVELS" % [int(data["points"]), spent, Research.SPENT_CAP])
	for id: String in nodes:
		var current := Research.level(data, id)
		var previous := Research.previous_skill(id)
		var unlocked := previous.is_empty() or Research.level(data, previous) >= Research.MAX_LEVEL
		nodes[id].set_pressed_no_signal(id == selected)
		nodes[id].modulate = Color.WHITE if unlocked else Color(1, 1, 1, 0.45)
		StationUi.set_text(levels[id], "%d / %d" % [current, Research.MAX_LEVEL])
		if connectors.has(id):
			connectors[id].color = ROW_COLORS[Research.row(id)] if unlocked else StationUi.LINE
	var skill: Dictionary = Research.SKILLS[selected]
	var row := Research.row(selected)
	var current := Research.level(data, selected)
	StationUi.set_text(detail_row, "%s  /  LEVEL %d OF %d" % [Research.ROW_NAMES[row].to_upper(), current, Research.MAX_LEVEL])
	StationUi.set_text(detail_title, skill["name"].to_upper())
	if detail_image.texture != artwork[selected]:
		detail_image.texture = artwork[selected]
	StationUi.set_text(detail_effect, Research.describe(selected, current))
	var cost := Research.cost(data, selected)
	var lines: PackedStringArray = []
	if cost.is_empty():
		lines.append("Fully researched.")
	else:
		lines.append("NEXT LEVEL COSTS\n1 research point  /  %d held" % int(data["points"]))
		for resource: String in cost:
			lines.append("%d %s  /  %d in Skylab" % [cost[resource], CargoResources.TYPES[resource]["name"], int(lab.get(resource, 0))])
	var previous := Research.previous_skill(selected)
	if not previous.is_empty():
		lines.append("\nRequires %s at level %d." % [Research.SKILLS[previous]["name"], Research.MAX_LEVEL])
	StationUi.set_text(detail_cost, "\n".join(lines))
	var reason := StationUi.blocker(sector)
	if reason.is_empty():
		reason = Research.learn_blocker(data, selected, lab)
	learn_button.disabled = not reason.is_empty()
	learn_button.tooltip_text = reason
	var price := Research.reset_price(data)
	reset_button.text = "RESET TREE  /  %s CR" % StationShop.credits_text(price)
	var reset_reason := StationUi.blocker(sector)
	if reset_reason.is_empty() and spent == 0:
		reset_reason = "No skills to reset."
	if reset_reason.is_empty() and sector.credits < price:
		reset_reason = "Insufficient credits."
	reset_button.disabled = not reset_reason.is_empty()
	reset_button.tooltip_text = reset_reason if not reset_reason.is_empty() else "Refund every research point. Consumed Skylab materials are not returned; the next reset costs twice as much."
	test_points_button.visible = not StationUi.offline_preview(sector) and sector.session.combat.preview_tools_available
	var points_reason := StationUi.blocker(sector)
	if points_reason.is_empty() and int(data["points"]) >= Research.MAX_POINTS:
		points_reason = "Research point limit reached."
	test_points_button.disabled = not points_reason.is_empty()
	test_points_button.tooltip_text = points_reason if not points_reason.is_empty() else "Adds saved test research points on an authorized preview server."
	var held: PackedStringArray = []
	for resource: String in ["prometid", "duranium", "promerium", "seprom"]:
		held.append("%s %d" % [CargoResources.TYPES[resource]["name"], int(lab.get(resource, 0))])
	StationUi.set_text(stock_label, "SKYLAB STOCK  /  " + "  ·  ".join(held) + "  /  Earn research points from station quests.")
	var station := StationUi.blocker(sector)
	StationUi.set_text(status, station if not station.is_empty() else sector.session.combat.station_message)
