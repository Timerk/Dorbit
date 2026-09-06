class_name FlightHud
extends Control

const INK := Color("e3edf7")
const MUTED := Color("869bb0")
const CYAN := Color("66e2ee")
const GREEN := Color("6ae9bb")
const RED := Color("ff8176")
const PANEL := Color(0.023, 0.042, 0.069, 0.92)

var sector: Sector
var font: Font = ThemeDB.fallback_font
var background: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	background = panel_style()


func text_at(point: Vector2, text: String, size_px: int = 16, color: Color = INK) -> void:
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, color)


func panel(rect: Rect2, accent: Color = CYAN) -> void:
	draw_style_box(background, rect)
	draw_line(rect.position, rect.position + Vector2(3.0, rect.size.y), accent, 3.0)


func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = Color(0.25, 0.4, 0.55, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func meter(point: Vector2, title: String, value: float, maximum: float, color: Color) -> void:
	text_at(point, title, 12, MUTED)
	text_at(point + Vector2(218, 0), "%03d" % ceili(value), 14, color)
	var bar := Rect2(point + Vector2(0, 10), Vector2(250, 5))
	draw_rect(bar, Color(0.18, 0.26, 0.34, 0.6))
	bar.size.x *= clampf(value / maximum, 0.0, 1.0)
	draw_rect(bar, color)


func _draw() -> void:
	if not is_instance_valid(sector.player):
		return
	var width := size.x
	var height := size.y
	var player := sector.player
	# Keep the HUD usable when the window is resized down to its minimum size.
	var compact := width < 1200.0
	text_at(Vector2(32, 42), "D O R B I T", 26)
	text_at(Vector2(33, 65), "OUTPOST 01  /  FIRST CONTACT", 11, CYAN)
	text_at(Vector2(width - 200, 36), "%05d  CR" % sector.credits, 22, GREEN)
	text_at(Vector2(width - 200, 60), "LOCAL SECTOR  /  SOLO", 11, MUTED)
	draw_line(Vector2(32, 82), Vector2(width - 32, 82), Color(0.3, 0.5, 0.65, 0.25), 1.0)
	var objective: String = [
		"Leave the outpost. W to fly forward.",
		"Find the alien. Tab or click to select.",
		"Space to fire. Keep the alien ahead and within 170 m.",
		"Return to Outpost 01. Slow down and press R to repair.",
		"Encounter complete. Keep exploring or hunt another alien.",
	][sector.objective_stage]
	text_at(Vector2(33, 113), "OBJECTIVE", 11, GREEN)
	text_at(Vector2(33, 137), objective, 14 if compact else 17)
	if sector.toast_time > 0.0:
		text_at(Vector2(33, 169), sector.toast, 12 if compact else 14, CYAN)
	if sector.alien.alive:
		marker(sector.alien.global_position, "SENTINEL", RED, sector.target == sector.alien)
	marker(Sector.STATION_POSITION, "OUTPOST 01", GREEN, false)
	var center := size * 0.5
	draw_line(center - Vector2(8, 0), center - Vector2(3, 0), Color(0.7, 0.85, 0.95, 0.5), 1.0)
	draw_line(center + Vector2(3, 0), center + Vector2(8, 0), Color(0.7, 0.85, 0.95, 0.5), 1.0)
	draw_circle(center, 1.0, CYAN)
	panel(Rect2(32, height - 245, 290, 174))
	text_at(Vector2(50, height - 218), "PATHFINDER  /  LIGHT FIGHTER", 12, CYAN)
	meter(Vector2(50, height - 190), "SHIELD", player.shield, player.max_shield, CYAN)
	meter(Vector2(50, height - 145), "HULL", player.hull, player.max_hull, GREEN if player.hull > 35.0 else RED)
	meter(Vector2(50, height - 100), "BOOST", player.energy, 100.0, Color("e3b777"))
	text_at(Vector2(343, height - 100), "%03d" % roundi(player.velocity.length()), 32)
	text_at(Vector2(343, height - 79), "m/s  /  " + ("BOOST" if player.boosting else "FLIGHT ASSIST"), 10, MUTED)
	draw_target_panel(width, height)
	var distance := player.global_position.distance_to(Sector.STATION_POSITION)
	if distance <= Sector.REPAIR_RADIUS and player.alive:
		var label := "R  REPAIR / %d CR" % sector.repair_cost()
		if player.velocity.length() > 8.0:
			label = "SLOW DOWN TO REPAIR"
		elif player.time_since_hit < 5.0:
			label = "REPAIRS AVAILABLE IN %d s" % ceili(5.0 - player.time_since_hit)
		text_at(Vector2(width - 310, height - 256), label, 14, GREEN)
	var controls := "WASD  Move    Q/E  Rise / descend    RMB  Steer    Tab  Target    Space  Fire    Shift  Boost    R  Repair    Esc  Pause"
	text_at(Vector2(33, height - 28), controls, 11 if compact else 13, MUTED)
	if sector.show_performance:
		var fps := Engine.get_frames_per_second()
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		text_at(Vector2(33, 202), "%d FPS  /  %.1f ms  /  %d draw calls  /  %s" % [fps, 1000.0 / maxf(fps, 1), draws, "LOW" if sector.low_quality else "HIGH"], 13, GREEN)
	if not player.alive:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.025, 0.04, 0.65))
		text_at(center + Vector2(-150, -20), "RESCUE INBOUND", 30, RED)
		text_at(center + Vector2(-150, 15), "Returning to the outpost in %d..." % ceili(sector.player_respawn), 17)
	if sector.paused:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.012, 0.025, 0.88))
		panel(Rect2(center - Vector2(280, 160), Vector2(560, 360)))
		text_at(center + Vector2(-248, -103), "FLIGHT PAUSED", 29)
		text_at(center + Vector2(-248, -62), "Esc        Resume flight", 18, CYAN)
		text_at(center + Vector2(-248, -23), "F11        Toggle fullscreen", 17)
		text_at(center + Vector2(-248, 16), "F3          Performance overlay", 17)
		text_at(center + Vector2(-248, 55), "F4          Antialiasing: " + ("Off" if sector.low_quality else "4x MSAA"), 17)
		var pixels := DisplayServer.window_get_size()
		text_at(center + Vector2(-248, 94), "F5 / F6  Window resolution: %d x %d" % [pixels.x, pixels.y], 17)
		text_at(center + Vector2(-248, 120), "Changing resolution switches to windowed mode.", 13, MUTED)
		text_at(center + Vector2(-248, 163), "F10        Quit to desktop", 17, MUTED)


func draw_target_panel(width: float, height: float) -> void:
	panel(Rect2(width - 322, height - 245, 290, 174), RED if sector.target != null else MUTED)
	var origin := Vector2(width - 304, height - 218)
	if not is_instance_valid(sector.target) or not sector.target.alive:
		text_at(origin, "NO TARGET", 13, MUTED)
		text_at(origin + Vector2(0, 34), "Tab or click an alien to lock", 15)
		text_at(origin + Vector2(0, 64), "%02d  ALIENS DESTROYED" % sector.kills, 12, MUTED)
		if sector.alien_respawn > 0.0:
			text_at(origin + Vector2(0, 104), "New contact in %d s" % ceili(sector.alien_respawn), 13, CYAN)
		return
	var enemy := sector.target
	text_at(origin, "SENTINEL  /  HOSTILE", 12, RED)
	meter(origin + Vector2(0, 28), "SHIELD", enemy.shield, enemy.max_shield, CYAN)
	meter(origin + Vector2(0, 72), "HULL", enemy.hull, enemy.max_hull, RED)
	var blocker := sector.weapon_status
	var status := blocker if not blocker.is_empty() else ("LASERS ACTIVE" if sector.auto_fire else "SPACE TO ENGAGE")
	text_at(origin + Vector2(0, 128), status, 12, RED if not blocker.is_empty() else GREEN)


func marker(location: Vector3, label: String, color: Color, selected: bool) -> void:
	var camera := sector.player.camera
	var point := camera.unproject_position(location)
	var behind := camera.is_position_behind(location)
	var bounds := Rect2(38, 205, size.x - 76, size.y - 480)
	var distance := sector.player.global_position.distance_to(location)
	if behind or not bounds.has_point(point):
		var direction := point - size * 0.5
		if behind:
			direction = -direction
		if direction.length_squared() < 0.01:
			direction = Vector2.DOWN
		direction = direction.normalized()
		point = size * 0.5 + direction * Vector2(size.x * 0.40, size.y * 0.23)
		draw_circle(point, 4.0, color)
		draw_line(point, point - direction * 15.0, color, 2.0)
		text_at(point + Vector2(-42, 25), "%s / %d m" % [label, distance], 11, color)
		return
	var radius := 25.0 if selected else 12.0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var start: Vector2 = point + corner * radius
		draw_line(start, start - Vector2(corner.x * 8, 0), color, 2.0)
		draw_line(start, start - Vector2(0, corner.y * 8), color, 2.0)
	text_at(point + Vector2(-35, radius + 20), "%s / %d m" % [label, distance], 12, color)
