class_name GateMenu
extends PanelContainer
## Galaxy Gates station page: per-gate parts, operation and the open run. Tabs
## select a gate. The server validates every action and owns the gate run.

const SIZE := Vector2(1150, 690)
var sector: Sector
var selected: String = GalaxyGates.ORDER[0]
var tabs: Dictionary[String, Button] = {}
var summary: Label
var faction: Label
var title: Label
var lore: Label
var parts_label: Label
var parts_bar: ProgressBar
var facts: Label
var run_label: Label
var assemble_button: Button
var preview_button: Button
var operation_title: Label
var portrait: TextureRect
var briefing: Label
var operation_rules: Label
var signal_state: Label
var signal_progress: ProgressBar
var accept_button: Button
var status: Label
var shown := ""


func _ready() -> void:
	StationUi.frame(self, SIZE)
	var rows := StationUi.rows(self, 16)
	rows.add_theme_constant_override("separation", 10)
	var header := StationUi.header_row(StationUi.header(rows, "GALAXY GATES", "OPERATIONS"))
	summary = StationUi.heading(header, "", 17, StationUi.MUTED)
	summary.size_flags_vertical = Control.SIZE_SHRINK_END
	var tab_row := HBoxContainer.new()
	rows.add_child(tab_row)
	for gate: String in GalaxyGates.ORDER:
		var tab := StationUi.button(tab_row, GalaxyGates.info(gate)["name"], func(): select(gate))
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		StationUi.tab(tab)
		tabs[gate] = tab
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)

	var gate_card := StationUi.card(body)
	gate_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gate_rows := StationUi.rows(gate_card, 16)
	gate_rows.add_theme_constant_override("separation", 10)
	faction = StationUi.heading(gate_rows, "", 13)
	faction.add_theme_font_override("font", StationUi.tracked(true, 3))
	title = StationUi.heading(gate_rows, "", 30)
	lore = StationUi.text(gate_rows, "", 16)
	lore.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_label = StationUi.heading(gate_rows, "", 18)
	parts_bar = ProgressBar.new()
	parts_bar.custom_minimum_size.y = 10
	parts_bar.show_percentage = false
	gate_rows.add_child(parts_bar)
	facts = StationUi.text(gate_rows, "", 15, StationUi.MUTED)
	run_label = StationUi.text(gate_rows, "", 16)
	assemble_button = StationUi.button(gate_rows, "ASSEMBLE AND OPEN GATE", func(): act("gate_assemble"))
	StationUi.primary(assemble_button)
	preview_button = StationUi.button(gate_rows, "Preview: open gate without parts", func(): act("gate_preview"))
	preview_button.hide()

	var operation := StationUi.card(body)
	operation.custom_minimum_size.x = 420
	var op_rows := StationUi.rows(operation, 16)
	op_rows.add_theme_constant_override("separation", 10)
	StationUi.heading(op_rows, "PARTS OPERATION", 13, StationUi.MUTED).add_theme_font_override("font", StationUi.tracked(true, 3))
	operation_title = StationUi.heading(op_rows, "", 26)
	var speaker := HBoxContainer.new()
	speaker.add_theme_constant_override("separation", 14)
	op_rows.add_child(speaker)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(96, 96)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	speaker.add_child(portrait)
	briefing = StationUi.text(speaker, "", 15)
	briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	operation_rules = StationUi.text(op_rows, "", 15, StationUi.MUTED)
	signal_state = StationUi.heading(op_rows, "", 17)
	signal_progress = ProgressBar.new()
	signal_progress.custom_minimum_size.y = 8
	signal_progress.show_percentage = false
	op_rows.add_child(signal_progress)
	accept_button = StationUi.button(op_rows, "ACCEPT OPERATION", func(): act("gate_signal"))
	StationUi.primary(accept_button)
	status = StationUi.text(rows, "", 16, StationUi.AMBER)
	status.custom_minimum_size.y = 26
	get_viewport().size_changed.connect(fit_window)
	fit_window()
	hide()


func select(gate: String) -> void:
	selected = gate


# Static texts change only when another gate is selected.
func show_gate() -> void:
	shown = selected
	var definition := GalaxyGates.info(selected)
	var operation: Dictionary = definition["signal"]
	var reward: Dictionary = definition["reward"]
	for gate: String in tabs:
		tabs[gate].set_pressed_no_signal(gate == selected)
	faction.text = definition["faction"].to_upper() + " FACTION"
	faction.add_theme_color_override("font_color", definition["glow"])
	run_label.add_theme_color_override("font_color", definition["glow"])
	title.text = definition["name"].to_upper()
	lore.text = definition["summary"]
	parts_bar.max_value = definition["parts_required"]
	facts.text = "%d waves, ending with the %s  /  %d lives per pilot  /  any pilot may join\nVictory pays every participant %s, with a %d%% chance of an %s." % [
		definition["waves"].size(), definition["boss"], definition["lives"], GalaxyGates.reward_text(selected, false),
		roundi(reward["item_chance"] * 100), GalaxyGates.item_name(selected)]
	operation_title.text = str(operation["title"]).to_upper()
	portrait.texture = StorySites.portrait(operation["contact"])
	briefing.text = "%s\n%s" % [Story.CONTACTS[operation["contact"]]["name"].to_upper(), operation["briefing"]]
	operation_rules.text = "Each %s kill you contribute to carries a %s part. Recover %d parts to complete the operation: +%d gate parts and %s. Other aliens sometimes carry parts too." % [
		SectorMaps.code(operation["map"]), definition["faction"], operation["required"], operation["parts"],
		Story.reward_text(operation["credits"], operation["research"])]
	signal_progress.max_value = operation["required"]


func gates() -> Dictionary:
	var inventory := StationUi.inventory(sector)
	return GalaxyGates.empty() if inventory.is_empty() else GalaxyGates.state(inventory, selected)


func act(action: String) -> void:
	var button := {"gate_assemble": assemble_button, "gate_preview": preview_button, "gate_signal": accept_button}[action] as Button
	if not button.disabled and button.visible:
		sector.session.combat.request_station(action, selected)


func fit_window() -> void:
	if is_instance_valid(sector.main_menu) and sector.main_menu.visible:
		sector.main_menu.fit_panel(self, SIZE)
	else:
		StationUi.centered(self, SIZE)


func open() -> void:
	if sector.main_menu.route_page("gates"):
		return
	sector.set_paused(true)
	fit_window()
	show()


func close() -> void:
	hide()
	sector.set_paused(false)


func _process(_delta: float) -> void:
	if not visible:
		return
	if shown != selected:
		show_gate()
	var definition := GalaxyGates.info(selected)
	var required: int = definition["parts_required"]
	var data := gates()
	var parts := int(data["parts"])
	var run: Dictionary = sector.session.combat.gate_summary
	StationUi.set_text(summary, "%d / %d %s PARTS" % [parts, required, definition["faction"].to_upper()])
	StationUi.set_text(parts_label, "GATE PARTS  %d / %d" % [parts, required])
	parts_bar.value = mini(parts, required)
	var run_text := ""
	if run.get("active", false):
		var open_name: String = GalaxyGates.info(run["gate"])["name"]
		if run["phase"] == "victory":
			run_text = "The %s boss is down. The arena closes shortly." % open_name
		elif run["phase"] == "waiting":
			run_text = "%s OPEN near Outpost 01, assembled by %s. Fly through it to join; the first wave starts when a pilot arrives." % [open_name.to_upper(), run["builder"]]
		else:
			var progress := "Wave %d of %d in progress" % [run["wave"], run["waves"]] if run["phase"] == "fighting" else "Wave %d of %d cleared, next wave incoming" % [run["wave"], run["waves"]]
			run_text = "%s OPEN near Outpost 01. %s, %d pilots inside. Your lives: %d." % [open_name.to_upper(), progress, run["pilots"], run["lives"]]
	StationUi.set_text(run_label, run_text)
	var station := StationUi.blocker(sector)
	var reason := station
	if reason.is_empty() and run.get("active", false):
		reason = "A %s run is already open." % GalaxyGates.info(run["gate"])["name"]
	if reason.is_empty():
		reason = GalaxyGates.assemble_blocker(data, selected)
	assemble_button.disabled = not reason.is_empty()
	assemble_button.tooltip_text = reason if not reason.is_empty() else "Consumes %d parts and opens the gate for everyone near Outpost 01." % required
	preview_button.visible = not StationUi.offline_preview(sector) and sector.session.combat.preview_tools_available
	preview_button.disabled = not station.is_empty() or run.get("active", false)
	preview_button.tooltip_text = "Opens the gate on an authorized preview server without consuming parts."
	match data["signal"]:
		"active":
			StationUi.set_text(signal_state, GalaxyGates.signal_objective(data, selected))
		"done":
			StationUi.set_text(signal_state, "Operation complete. Assemble the gate to start the next one.")
		_:
			StationUi.set_text(signal_state, "Available")
	signal_progress.value = int(data["progress"])
	signal_progress.visible = data["signal"] == "active"
	var accept_reason := station if not station.is_empty() else GalaxyGates.accept_blocker(data, selected)
	accept_button.disabled = not accept_reason.is_empty()
	accept_button.tooltip_text = accept_reason
	StationUi.set_text(status, station if not station.is_empty() else sector.session.combat.station_message)
