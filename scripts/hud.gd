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
var marker_labels: Array[Rect2] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	background = panel_style()


func fire_feedback() -> String:
	if not is_instance_valid(sector.target) or not sector.target.alive:
		return "NO TARGET"
	if not sector.auto_fire:
		return "AUTO FIRE OFF / %s TO ENGAGE" % GameSettings.binding_text("fire")
	if sector.weapon_status == "TURN TOWARD TARGET":
		return "OUTSIDE FIRING ARC"
	return sector.weapon_status if not sector.weapon_status.is_empty() else "AUTO FIRE ACTIVE"


func text_at(point: Vector2, text: String, size_px: int = 16, color: Color = INK) -> void:
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, color)


func panel(rect: Rect2, accent: Color = CYAN) -> void:
	draw_style_box(background, rect)
	draw_line(rect.position, rect.position + Vector2(3.0, rect.size.y), accent, 3.0)


static func panel_style() -> StyleBoxFlat:
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
	marker_labels.clear()
	if not is_instance_valid(sector.player):
		return
	var width := size.x
	var height := size.y
	var player := sector.player
	var shared := is_instance_valid(sector.session) and sector.session.active
	# Keep the HUD usable when the window is resized down to its minimum size.
	var compact := width < 1200.0
	text_at(Vector2(32, 42), "D O R B I T", 26)
	text_at(Vector2(33, 65), "OUTPOST 01  /  FIRST CONTACT", 11, CYAN)
	text_at(Vector2(width - 200, 36), "%05d  CR" % sector.credits, 22, GREEN)
	var connection := "CO-OP  /  %d PILOTS" % sector.session.ships.size() if shared else ("DISCONNECTED" if sector.client_only else "LOCAL SECTOR  /  SOLO")
	text_at(Vector2(width - 200, 60), connection, 11, MUTED)
	draw_line(Vector2(32, 82), Vector2(width - 32, 82), Color(0.3, 0.5, 0.65, 0.25), 1.0)
	var objective: String = [
		"Leave the outpost. %s to fly forward." % GameSettings.binding_text("forward"),
		"Find the alien. %s or %s to select." % [GameSettings.binding_text("cycle_target"), GameSettings.binding_text("select_target")],
		"%s to fire. Keep the alien ahead and within 170 m." % GameSettings.binding_text("fire"),
		"Return to Outpost 01. Slow down and press %s to repair." % GameSettings.binding_text("repair"),
		"Encounter complete. Keep exploring or hunt another alien.",
	][sector.objective_stage]
	text_at(Vector2(33, 113), "OBJECTIVE", 11, GREEN)
	text_at(Vector2(33, 137), objective, 14 if compact else 17)
	if sector.toast_time > 0.0:
		text_at(Vector2(33, 169), sector.toast, 12 if compact else 14, CYAN)
	marker(Sector.STATION_POSITION, "[+] OUTPOST 01", GREEN, false)
	if sector.alien.alive:
		marker(sector.alien.global_position, "HOSTILE SENTINEL", RED, sector.target == sector.alien)
	if shared:
		for ship: Pilot in sector.session.ships.values():
			if ship != player and ship.alive:
				marker(ship.global_position, "FRIEND %s" % sector.session.ships.find_key(ship), CYAN, false, ship)
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
		var label := "%s  REPAIR / %d CR" % [GameSettings.binding_text("repair"), sector.repair_cost()]
		if player.velocity.length() > 8.0:
			label = "SLOW DOWN TO REPAIR"
		elif player.time_since_hit < 5.0:
			label = "REPAIRS AVAILABLE IN %d s" % ceili(5.0 - player.time_since_hit)
		text_at(Vector2(width - 310, height - 256), label, 14, GREEN)
	var controls := "%s Steer    %s Target    %s Fire    %s Boost    %s Repair    Esc Menu / controls" % [
		GameSettings.binding_text("steer"), GameSettings.binding_text("cycle_target"),
		GameSettings.binding_text("fire"), GameSettings.binding_text("boost"), GameSettings.binding_text("repair")]
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


func draw_target_panel(width: float, height: float) -> void:
	panel(Rect2(width - 322, height - 245, 290, 174), RED if sector.target != null else MUTED)
	var origin := Vector2(width - 304, height - 218)
	if not is_instance_valid(sector.target) or not sector.target.alive:
		text_at(origin, "NO TARGET", 13, MUTED)
		text_at(origin + Vector2(0, 34), "%s or %s to lock" % [GameSettings.binding_text("cycle_target"), GameSettings.binding_text("select_target")], 15)
		text_at(origin + Vector2(0, 64), "%02d  ALIENS DESTROYED" % sector.kills, 12, MUTED)
		if sector.alien_respawn > 0.0:
			text_at(origin + Vector2(0, 104), "New contact in %d s" % ceili(sector.alien_respawn), 13, CYAN)
		return
	var enemy := sector.target
	text_at(origin, "SELECTED SENTINEL / %d m" % sector.player.global_position.distance_to(enemy.global_position), 12, RED)
	meter(origin + Vector2(0, 28), "SHIELD", enemy.shield, enemy.max_shield, CYAN)
	meter(origin + Vector2(0, 72), "HULL", enemy.hull, enemy.max_hull, RED)
	text_at(origin + Vector2(0, 128), fire_feedback(), 12, RED if sector.auto_fire and not sector.weapon_status.is_empty() else GREEN)


func marker(location: Vector3, label: String, color: Color, selected: bool, teammate: Pilot = null) -> void:
	var camera := sector.player.camera
	var point := camera.unproject_position(location)
	var behind := camera.is_position_behind(location)
	var bounds := Rect2(38, 205, size.x - 76, size.y - 480)
	var distance := sector.player.global_position.distance_to(location)
	if behind or not bounds.has_point(point):
		if teammate != null:
			return
		var direction := point - size * 0.5
		if behind:
			direction = -direction
		if direction.length_squared() < 0.01:
			direction = Vector2.DOWN
		direction = direction.normalized()
		var center := bounds.get_center()
		var extent := bounds.size * 0.5
		var reach := minf(extent.x / maxf(absf(direction.x), 0.001), extent.y / maxf(absf(direction.y), 0.001))
		point = center + direction * reach
		var side := direction.orthogonal() * 6
		draw_line(point, point - direction * 14 + side, color, 2.5)
		draw_line(point, point - direction * 14 - side, color, 2.5)
		marker_caption(point + Vector2(0, 24), "%s / %d m" % [label, distance], color, true)
		return
	var radius := 25.0 if selected else 12.0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var start: Vector2 = point + corner * radius
		draw_line(start, start - Vector2(corner.x * 8, 0), color, 2.0)
		draw_line(start, start - Vector2(0, corner.y * 8), color, 2.0)
	marker_caption(point + Vector2(0, radius + 20), "%s%s / %d m" % ["LOCK / " if selected else "", label, distance], color, teammate == null)


func marker_caption(point: Vector2, caption: String, color: Color, priority: bool) -> void:
	var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var rect := Rect2(Vector2(clampf(point.x - text_size.x * 0.5 - 5, 12, size.x - text_size.x - 22), point.y - 14), text_size + Vector2(10, 6))
	for occupied in marker_labels:
		if occupied.intersects(rect):
			if not priority:
				return
			rect.position.y = occupied.end.y + 3
	marker_labels.append(rect)
	draw_style_box(background, rect)
	text_at(rect.position + Vector2(5, 14), caption, 12, color)
