class_name GateMenu
extends PanelContainer
## Galaxy Gates station page: gate parts, the Signal Anomaly operation and the
## open run. The server validates every action and owns the gate run.

const SIZE := Vector2(1150, 690)
var sector: Sector
var summary: Label
var parts_label: Label
var parts_bar: ProgressBar
var run_label: Label
var assemble_button: Button
var preview_button: Button
var signal_state: Label
var signal_progress: ProgressBar
var accept_button: Button
var status: Label


func _ready() -> void:
	StationUi.frame(self, SIZE)
	var rows := StationUi.rows(self, 16)
	rows.add_theme_constant_override("separation", 10)
	var header := StationUi.header_row(StationUi.header(rows, "GALAXY GATES", "OPERATIONS"))
	summary = StationUi.heading(header, "", 17, StationUi.MUTED)
	summary.size_flags_vertical = Control.SIZE_SHRINK_END
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)

	var gate := StationUi.card(body)
	gate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gate_rows := StationUi.rows(gate, 16)
	gate_rows.add_theme_constant_override("separation", 10)
	StationUi.heading(gate_rows, "VASHAR FACTION", 13, VasharModels.GLOW).add_theme_font_override("font", StationUi.tracked(true, 3))
	StationUi.heading(gate_rows, GalaxyGates.NAME.to_upper(), 30)
	var lore := StationUi.text(gate_rows, "The occupying aliens are smuggling gate parts through our sectors to summon their Vashar allies. Capture enough parts and assemble the gate ourselves: it opens near Outpost 01 and leads straight into the Vashar staging fleet. Destroy the mothership to set back their invasion.", 16)
	lore.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_label = StationUi.heading(gate_rows, "", 18)
	parts_bar = ProgressBar.new()
	parts_bar.custom_minimum_size.y = 10
	parts_bar.show_percentage = false
	parts_bar.max_value = GalaxyGates.PARTS_REQUIRED
	gate_rows.add_child(parts_bar)
	StationUi.text(gate_rows, "%d waves, ending with the Vashar mothership  /  %d lives per pilot  /  any pilot may join\nVictory pays every participant %s." % [GalaxyGates.WAVES.size(), GalaxyGates.LIVES, Story.reward_text(GalaxyGates.REWARD["credits"], GalaxyGates.REWARD["research"])], 15, StationUi.MUTED)
	run_label = StationUi.text(gate_rows, "", 16, VasharModels.GLOW)
	assemble_button = StationUi.button(gate_rows, "ASSEMBLE AND OPEN GATE", func(): act("gate_assemble"))
	StationUi.primary(assemble_button)
	preview_button = StationUi.button(gate_rows, "Preview: open gate without parts", func(): act("gate_preview"))
	preview_button.hide()

	var operation := StationUi.card(body)
	operation.custom_minimum_size.x = 420
	var op_rows := StationUi.rows(operation, 16)
	op_rows.add_theme_constant_override("separation", 10)
	StationUi.heading(op_rows, "RESEARCH OPERATION", 13, StationUi.MUTED).add_theme_font_override("font", StationUi.tracked(true, 3))
	StationUi.heading(op_rows, str(GalaxyGates.SIGNAL["title"]).to_upper(), 26)
	var speaker := HBoxContainer.new()
	speaker.add_theme_constant_override("separation", 14)
	op_rows.add_child(speaker)
	var portrait := TextureRect.new()
	portrait.texture = StorySites.portrait(GalaxyGates.SIGNAL["contact"])
	portrait.custom_minimum_size = Vector2(96, 96)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	speaker.add_child(portrait)
	var briefing := StationUi.text(speaker, "%s\n%s" % [Story.CONTACTS[GalaxyGates.SIGNAL["contact"]]["name"].to_upper(), GalaxyGates.SIGNAL["briefing"]], 15)
	briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	StationUi.text(op_rows, "Each M2 kill you contribute to carries a gate part. Recover %d parts to decode the courier cache: +%d gate parts and %s. Other aliens beyond Outpost 01 sometimes carry parts too." % [GalaxyGates.SIGNAL["required"], GalaxyGates.SIGNAL["parts"], Story.reward_text(GalaxyGates.SIGNAL["credits"], GalaxyGates.SIGNAL["research"])], 15, StationUi.MUTED)
	signal_state = StationUi.heading(op_rows, "", 17)
	signal_progress = ProgressBar.new()
	signal_progress.custom_minimum_size.y = 8
	signal_progress.show_percentage = false
	signal_progress.max_value = GalaxyGates.SIGNAL["required"]
	op_rows.add_child(signal_progress)
	accept_button = StationUi.button(op_rows, "ACCEPT OPERATION", func(): act("gate_signal"))
	StationUi.primary(accept_button)
	status = StationUi.text(rows, "", 16, StationUi.AMBER)
	status.custom_minimum_size.y = 26
	get_viewport().size_changed.connect(fit_window)
	fit_window()
	hide()


func gates() -> Dictionary:
	var inventory := StationUi.inventory(sector)
	return GalaxyGates.empty() if inventory.is_empty() else GalaxyGates.state(inventory)


func act(action: String) -> void:
	var button := {"gate_assemble": assemble_button, "gate_preview": preview_button, "gate_signal": accept_button}[action] as Button
	if not button.disabled and button.visible:
		sector.session.combat.request_station(action, "")


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
	var data := gates()
	var parts := int(data["parts"])
	var run: Dictionary = sector.session.combat.gate_summary
	StationUi.set_text(summary, "%d / %d GATE PARTS" % [parts, GalaxyGates.PARTS_REQUIRED])
	StationUi.set_text(parts_label, "GATE PARTS  %d / %d" % [parts, GalaxyGates.PARTS_REQUIRED])
	parts_bar.value = mini(parts, GalaxyGates.PARTS_REQUIRED)
	var run_text := ""
	if run.get("active", false):
		if run["phase"] == "victory":
			run_text = "The mothership is down. The rift closes shortly."
		elif run["phase"] == "waiting":
			run_text = "GATE OPEN near Outpost 01, assembled by %s. Fly through it to join; the first wave starts when a pilot arrives." % run["builder"]
		else:
			run_text = "GATE OPEN near Outpost 01. Wave %d of %d in progress, %d pilots inside. Your lives: %d." % [run["wave"], run["waves"], run["pilots"], run["lives"]]
	StationUi.set_text(run_label, run_text)
	var station := StationUi.blocker(sector)
	var reason := station
	if reason.is_empty() and run.get("active", false):
		reason = "A %s run is already open." % GalaxyGates.NAME
	if reason.is_empty():
		reason = GalaxyGates.assemble_blocker(data)
	assemble_button.disabled = not reason.is_empty()
	assemble_button.tooltip_text = reason if not reason.is_empty() else "Consumes %d parts and opens the gate for everyone near Outpost 01." % GalaxyGates.PARTS_REQUIRED
	preview_button.visible = not StationUi.offline_preview(sector) and sector.session.combat.preview_tools_available
	preview_button.disabled = not station.is_empty() or run.get("active", false)
	preview_button.tooltip_text = "Opens the gate on an authorized preview server without consuming parts."
	match data["signal"]:
		"active":
			StationUi.set_text(signal_state, GalaxyGates.signal_objective(data))
		"done":
			StationUi.set_text(signal_state, "Cache decoded. Assemble the gate to trace the next signal.")
		_:
			StationUi.set_text(signal_state, "Available")
	signal_progress.value = int(data["progress"])
	signal_progress.visible = data["signal"] == "active"
	var accept_reason := station if not station.is_empty() else GalaxyGates.accept_blocker(data)
	accept_button.disabled = not accept_reason.is_empty()
	accept_button.tooltip_text = accept_reason
	StationUi.set_text(status, station if not station.is_empty() else sector.session.combat.station_message)
