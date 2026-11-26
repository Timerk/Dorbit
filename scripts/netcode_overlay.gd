class_name NetcodeOverlay
extends Control
## F8 netcode overlay: live NetStats readings, network simulator sliders and a
## translucent ghost at the last authoritative position of the local ship.
## Client-side diagnostics only; nothing here is sent to the server.

const SIZE := Vector2(340, 372)
# Readings start here; the controls sit below them.
const LINE_HEIGHT := 16
const CONTROLS_TOP := 162
const REFRESH := 0.25
const DIRECTION_LABELS := ["Both ways (round trip)", "Upstream only", "Downstream only"]
# Slider limits per mode: [round trip, one way].
const DELAY_MAX := [600.0, 300.0]
const JITTER_MAX := [200.0, 100.0]

var hud: FlightHud
var show_ghost := true
var ghost: Node3D
var ghost_model := ""
var refresh_clock := 0.0
var direction: OptionButton
var sliders: Dictionary[String, HSlider] = {}
var values: Dictionary[String, Label] = {}
var titles: Dictionary[String, Label] = {}
var ghost_toggle: CheckBox
var next_toggle: CheckBox
var note: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = SIZE
	var rows := VBoxContainer.new()
	rows.position = Vector2(12, CONTROLS_TOP)
	rows.size = Vector2(SIZE.x - 24, SIZE.y - CONTROLS_TOP - 8)
	rows.add_theme_constant_override("separation", 2)
	add_child(rows)
	direction = OptionButton.new()
	for entry: String in DIRECTION_LABELS:
		direction.add_item(entry)
	direction.focus_mode = Control.FOCUS_NONE
	direction.add_theme_font_size_override("font_size", 14)
	direction.item_selected.connect(func(_index: int): sync_sliders())
	rows.add_child(direction)
	for key: String in ["latency_ms", "jitter_ms", "loss_percent", "duplicate_percent"]:
		add_slider(rows, key)
	var tools := HBoxContainer.new()
	rows.add_child(tools)
	ghost_toggle = add_check(tools, "Server ghost", show_ghost, func(value: bool): show_ghost = value)
	var reset := Button.new()
	reset.text = "Reset max"
	reset.focus_mode = Control.FOCUS_NONE
	reset.mouse_filter = Control.MOUSE_FILTER_PASS
	reset.add_theme_font_size_override("font_size", 14)
	reset.pressed.connect(func(): session().net_stats.reset_extremes(); queue_redraw())
	tools.add_child(reset)
	next_toggle = add_check(rows, "Use simulator on next connection", false, func(value: bool): session().use_net_simulator = value)
	note = Label.new()
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", FlightHud.AMBER)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(note)
	visible = false


func add_slider(parent: Node, key: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var title := Label.new()
	title.custom_minimum_size.x = 112
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", FlightHud.MUTED)
	row.add_child(title)
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Mouse-only: flight keys keep working, and right-drag steering passes through.
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_filter = Control.MOUSE_FILTER_PASS
	slider.step = 5.0 if key.ends_with("_ms") else 0.5
	slider.max_value = 30.0 if key == "loss_percent" else 20.0
	slider.value_changed.connect(func(_value: float): apply_sliders())
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 64
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 14)
	row.add_child(value)
	sliders[key] = slider
	values[key] = value
	titles[key] = title


func add_check(parent: Node, title: String, pressed: bool, action: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = title
	check.button_pressed = pressed
	check.focus_mode = Control.FOCUS_NONE
	check.mouse_filter = Control.MOUSE_FILTER_PASS
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.add_theme_font_size_override("font_size", 14)
	check.toggled.connect(action)
	parent.add_child(check)
	return check


func session() -> FlightSession:
	return hud.sector.session


## Simulator direction the sliders edit, or NetSimulator.BOTH.
func edited_direction() -> int:
	return [NetSimulator.BOTH, NetSimulator.UP, NetSimulator.DOWN][direction.selected]


func sync_sliders() -> void:
	var round_trip := edited_direction() == NetSimulator.BOTH
	var mode := 0 if round_trip else 1
	var current := session().net_simulator.conditions(NetSimulator.DOWN if edited_direction() == NetSimulator.DOWN else NetSimulator.UP)
	sliders["latency_ms"].max_value = DELAY_MAX[mode]
	sliders["jitter_ms"].max_value = JITTER_MAX[mode]
	var factor := 2.0 if round_trip else 1.0
	sliders["latency_ms"].set_value_no_signal(current["latency_ms"] * factor)
	sliders["jitter_ms"].set_value_no_signal(current["jitter_ms"] * factor)
	sliders["loss_percent"].set_value_no_signal(current["loss_percent"])
	sliders["duplicate_percent"].set_value_no_signal(current["duplicate_percent"])
	titles["latency_ms"].text = "Added RTT" if round_trip else "One-way delay"
	titles["jitter_ms"].text = "RTT jitter ±" if round_trip else "Jitter ±"
	titles["loss_percent"].text = "Loss"
	titles["duplicate_percent"].text = "Duplicates"
	update_values()


func apply_sliders() -> void:
	var simulator := session().net_simulator
	var delay := sliders["latency_ms"].value
	var jitter := sliders["jitter_ms"].value
	var loss := sliders["loss_percent"].value
	var duplicate := sliders["duplicate_percent"].value
	if edited_direction() == NetSimulator.BOTH:
		simulator.set_round_trip(delay, jitter, loss, duplicate)
	else:
		simulator.configure(edited_direction(), delay, jitter, loss, duplicate)
	update_values()


func update_values() -> void:
	values["latency_ms"].text = "%d ms" % sliders["latency_ms"].value
	values["jitter_ms"].text = "%d ms" % sliders["jitter_ms"].value
	values["loss_percent"].text = "%.1f %%" % sliders["loss_percent"].value
	values["duplicate_percent"].text = "%.1f %%" % sliders["duplicate_percent"].value


func wanted() -> bool:
	var sector := hud.sector
	if sector.preflight or not is_instance_valid(sector.player) or (is_instance_valid(sector.main_menu) and sector.main_menu.visible):
		return false
	if hud.navigation.overview.visible:
		return false
	return (sector.show_netcode or hud.layout.editing) and hud.layout.shown("netcode")


func _process(delta: float) -> void:
	var shown := wanted()
	if shown != visible:
		visible = shown
		if shown:
			sync_sliders()
			queue_redraw()
	if shown:
		var rect := hud.layout.rect_for("netcode")
		size = SIZE
		position = rect.position
		scale = Vector2.ONE * (rect.size.x / SIZE.x)
		next_toggle.set_pressed_no_signal(session().use_net_simulator)
		var running := session().net_simulator.is_running()
		note.visible = not running
		note.text = "Simulator not in the path. Enable it, then reconnect (%s)." % GameSettings.binding_text("multiplayer_menu") if session().active else "Simulator not in the path. Enable it, then connect."
		refresh_clock += delta
		if refresh_clock >= REFRESH:
			refresh_clock = 0.0
			queue_redraw()
	update_ghost(shown)


func _draw() -> void:
	var font := hud.font
	draw_style_box(hud.background, Rect2(Vector2.ZERO, SIZE))
	var stats := session().net_stats
	var simulator := session().net_simulator
	draw_string(StationUi.tracked(true, 1), Vector2(12, 20), "NETCODE  /  %s" % GameSettings.binding_text("netcode"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FlightHud.AMBER)
	var state := "SIMULATOR ON" if simulator.is_running() else "DIRECT"
	draw_string(font, Vector2(12, 20), state, HORIZONTAL_ALIGNMENT_RIGHT, SIZE.x - 24, 14, FlightHud.GREEN if simulator.is_running() else FlightHud.MUTED)
	var lines: Array[String] = []
	if not session().active or session().multiplayer.is_server():
		lines.append("Not connected to a server.")
	else:
		var jitter := stats.snapshot_jitter()
		lines.append("RTT  %d ms    Up  %s/s    Down  %s/s" % [roundi(stats.rtt_ms), String.humanize_size(int(stats.up_bytes_per_second)), String.humanize_size(int(stats.down_bytes_per_second))])
		lines.append("Snapshot jitter  %.1f / %.1f ms max,  clock drift %+d ms" % [jitter.x, jitter.y, roundi(stats.clock_drift_ms)])
		lines.append("Inputs  %d unacked,  replayed %d (max %d)" % [stats.unacked_inputs, stats.replayed_ticks, stats.max_replayed_ticks])
		lines.append("Ack lag  %d ticks,  server buffer %s" % [stats.ack_lag_ticks, str(stats.server_input_depth) if stats.server_input_depth >= 0 else "-"])
		lines.append("Sim error  %.2f / %.2f m max,  offset %.2f m" % [stats.latest_error_m, stats.max_error_m, stats.latest_offset_m])
		var depth := stats.buffer_depth()
		lines.append("Interp %d ms, buffer %d/%d ms, extrap %.1f%%, %d dry" % [roundi(stats.interpolation_delay_ms), roundi(depth.x), roundi(depth.y), stats.extrapolation_share() * 100.0, stats.underruns])
		var inputs := stats.server_inputs
		lines.append("Server  lost %d  late %d  dup %d  starved %d" % [inputs.get("lost", 0), inputs.get("late", 0), inputs.get("duplicates", 0), inputs.get("starved", 0)])
		if simulator.is_running():
			var relay := simulator.stats()
			lines.append("Relay lost  %d up / %d down,  dup %d / %d" % [relay["up"]["dropped_packets"], relay["down"]["dropped_packets"], relay["up"]["duplicated_packets"], relay["down"]["duplicated_packets"]])
	for index in lines.size():
		draw_string(font, Vector2(12, 44 + index * LINE_HEIGHT), lines[index], HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 24, 14, FlightHud.INK if index == 0 else FlightHud.MUTED)


func update_ghost(shown: bool) -> void:
	var sector := hud.sector
	var stats := session().net_stats
	var wanted_ghost: bool = shown and show_ghost and session().active and not session().multiplayer.is_server() and stats.has_server_state and sector.player.alive and not sector.player.get_meta("docked", false)
	if not wanted_ghost:
		if is_instance_valid(ghost):
			ghost.hide()
		return
	if not is_instance_valid(ghost) or ghost_model != sector.player.ship_model:
		if is_instance_valid(ghost):
			ghost.queue_free()
		ghost_model = sector.player.ship_model
		ghost = Node3D.new()
		ghost.name = "ServerGhost"
		var model := ShipCatalog.model_scene(ghost_model)
		var surface := StandardMaterial3D.new()
		surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		surface.albedo_color = Color(FlightHud.CYAN, 0.3)
		surface.cull_mode = BaseMaterial3D.CULL_DISABLED
		SectorVisuals.apply_surface(model, surface)
		ghost.add_child(model)
		sector.add_child(ghost)
	ghost.show()
	ghost.position = stats.server_position
	ghost.rotation = stats.server_rotation


func _exit_tree() -> void:
	if is_instance_valid(ghost):
		ghost.queue_free()
