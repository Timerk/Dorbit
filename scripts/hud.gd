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
var contract_panel: PanelContainer
var contract_status: Label
var contract_choices: Dictionary[String, Button] = {}
var contract_tabs: Array[Button] = []
var contract_selected := "scout"
var contract_active_only := false
var contract_title: Label
var contract_briefing: Label
var contract_objective: Label
var contract_progress: ProgressBar
var contract_reward: Label
var contract_slots: Label
var contract_empty: Label
var contract_accept: Button
var contract_abandon: Button

const CONTRACT_GOLD := Color("f4cf65")
const CONTRACT_BRIEFINGS: Dictionary = {
	"scout": "Scouts patrol the sector. Locate their numbered contacts on the navigation maps and clear these light encounters. A good first assignment for the Liberator.",
	"sentinel": "Sentinels patrol the hunting grounds. Use the navigation maps to find them. Expect stronger shields and sustained laser fire.",
	"heavy": "A Heavy roams the sector. Find its purple contact on the navigation maps. Bring upgraded equipment or allies to take down this armored encounter.",
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	background = panel_style()
	build_contract_panel()


func fire_feedback() -> String:
	if not is_instance_valid(sector.target) or not sector.target.alive:
		return "NO TARGET"
	if not sector.auto_fire:
		return "AUTO FIRE OFF / %s TO ENGAGE" % GameSettings.binding_text("fire")
	if sector.weapon_status == "TURN TOWARD TARGET":
		return "OUTSIDE FIRING ARC"
	return sector.weapon_status if not sector.weapon_status.is_empty() else "AUTO FIRE ACTIVE"


func build_contract_panel() -> void:
	contract_panel = PanelContainer.new()
	StationUi.frame(contract_panel, Vector2(880, 560))
	add_child(contract_panel)
	var rows := StationUi.rows(contract_panel, 12)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := StationUi.text(header, "COMMUNICATION WINDOW / MISSION CONTROL", 19, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	StationUi.button(header, "Close [C / Esc]", toggle_contracts)
	var tabs := HBoxContainer.new()
	rows.add_child(tabs)
	for active_only: bool in [false, true]:
		var tab := StationUi.button(tabs, "Active contracts" if active_only else "Hunting contracts", func(): filter_contracts(active_only))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		tab.add_theme_stylebox_override("pressed", StationUi.style(Color("29516b"), CYAN))
		contract_tabs.append(tab)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	var sidebar := StationUi.card(body)
	sidebar.custom_minimum_size.x = 280
	var left := StationUi.rows(sidebar, 4)
	var transmission := StationUi.card(left)
	var signal_rows := StationUi.rows(transmission, 2)
	StationUi.text(signal_rows, "OUTPOST 01 / SECURE UPLINK", 12, CYAN)
	StationUi.art(signal_rows, "ship", Vector2(240, 96))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	var offers := VBoxContainer.new()
	offers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(offers)
	for offer: String in HuntingContracts.OFFERS:
		var button := StationUi.button(offers, "", func(): select_contract(offer))
		button.custom_minimum_size.y = 52
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.add_theme_color_override("font_pressed_color", CONTRACT_GOLD)
		button.add_theme_stylebox_override("pressed", StationUi.style(Color("284553"), CYAN))
		contract_choices[offer] = button
	contract_empty = StationUi.text(offers, "No active contracts.\nChoose a hunt to get started.", 14, MUTED)
	var detail := StationUi.card(body)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := StationUi.rows(detail, 8)
	right.add_theme_constant_override("separation", 6)
	contract_title = StationUi.text(right, "", 24, CONTRACT_GOLD)
	contract_briefing = StationUi.text(right, "", 15)
	contract_briefing.custom_minimum_size.y = 64
	StationUi.text(right, "Overview", 17, CONTRACT_GOLD)
	var overview := StationUi.card(right)
	var objective_rows := StationUi.rows(overview, 4)
	contract_objective = StationUi.text(objective_rows, "", 15)
	contract_progress = ProgressBar.new()
	contract_progress.custom_minimum_size.y = 8
	contract_progress.show_percentage = false
	contract_progress.add_theme_stylebox_override("background", StationUi.style(Color("172c40"), Color("263e53")))
	contract_progress.add_theme_stylebox_override("fill", StationUi.style(CYAN, CYAN))
	contract_progress.get_theme_stylebox("background").set_content_margin_all(0)
	contract_progress.get_theme_stylebox("fill").set_content_margin_all(0)
	objective_rows.add_child(contract_progress)
	StationUi.text(right, "Reward", 17, CONTRACT_GOLD)
	contract_reward = StationUi.text(StationUi.card(right), "", 18, CYAN)
	StationUi.text(right, "Rewards pay automatically after the final kill.\nDeath keeps progress. Abandoning has no penalty.", 13, MUTED)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(space)
	var footer := StationUi.card(rows)
	var footer_rows := VBoxContainer.new()
	footer.add_child(footer_rows)
	var actions := HBoxContainer.new()
	footer_rows.add_child(actions)
	contract_slots = StationUi.text(actions, "", 14, MUTED)
	contract_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contract_accept = StationUi.button(actions, "Accept contract", func(): act_on_contract("accept"))
	contract_accept.custom_minimum_size.x = 190
	contract_accept.add_theme_stylebox_override("normal", StationUi.style(Color("2c5835"), Color("78b760")))
	contract_accept.add_theme_stylebox_override("hover", StationUi.style(Color("3c7144"), GREEN))
	contract_abandon = StationUi.button(actions, "Abandon contract", func(): act_on_contract("abandon"))
	contract_abandon.custom_minimum_size.x = 190
	contract_status = StationUi.text(footer_rows, "", 13, RED)
	contract_panel.hide()


func select_contract(offer: String) -> void:
	contract_selected = offer
	update_contract_panel()


func filter_contracts(active_only: bool) -> void:
	contract_active_only = active_only
	update_contract_panel()


func act_on_contract(action: String) -> void:
	var button := contract_accept if action == "accept" else contract_abandon
	if contract_panel.visible and button.visible and not button.disabled and not contract_selected.is_empty():
		sector.session.combat.request_contract(action, contract_selected)


func toggle_contracts() -> void:
	if contract_panel.visible:
		contract_panel.hide()
		sector.set_paused(false)
		return
	var blocker := sector.repair_blocker()
	if not blocker.is_empty():
		sector.notify(blocker)
		return
	sector.session.menu.hide()
	sector.shop.hide()
	sector.equipment_menu.hide()
	sector.set_paused(true)
	contract_panel.show()
	update_contract_panel()


func update_contract_panel() -> void:
	if not contract_panel.visible:
		return
	if not sector.session.active:
		contract_panel.hide()
		return
	var blocker := sector.repair_blocker()
	contract_status.text = blocker.replace("to repair.", "to manage contracts.").replace("Repairs available", "Contract actions available")
	contract_status.visible = not blocker.is_empty()
	contract_slots.text = "%d contract slots remaining / %d active" % [HuntingContracts.OFFERS.size() - sector.active_contracts.size(), sector.active_contracts.size()]
	contract_tabs[0].set_pressed_no_signal(not contract_active_only)
	contract_tabs[1].set_pressed_no_signal(contract_active_only)
	var visible_offers: Array[String] = []
	for offer: String in HuntingContracts.OFFERS:
		var current: Dictionary = sector.active_contracts.get(offer, {})
		var button := contract_choices[offer]
		button.visible = not contract_active_only or not current.is_empty()
		if button.visible:
			visible_offers.append(offer)
		var state := "Available"
		if not current.is_empty():
			state = "Reward pending" if HuntingContracts.ready(current) else "Active / %d of %d" % [current["progress"], current["required"]]
		button.text = "%s hunt\n%s" % [offer.capitalize(), state]
	if not visible_offers.has(contract_selected):
		contract_selected = visible_offers[0] if not visible_offers.is_empty() else ""
	for offer: String in contract_choices:
		contract_choices[offer].set_pressed_no_signal(offer == contract_selected)
	contract_empty.visible = visible_offers.is_empty()
	contract_progress.visible = not contract_selected.is_empty()
	if contract_selected.is_empty():
		contract_accept.hide()
		contract_abandon.hide()
		contract_title.text = "No active contracts"
		contract_briefing.text = "Mission Control is ready when you are. Open Hunting contracts to choose your next assignment."
		contract_objective.text = "No hunt selected."
		contract_reward.text = "Credits / --"
		return
	var current: Dictionary = sector.active_contracts.get(contract_selected, {})
	var terms: Dictionary = current if not current.is_empty() else HuntingContracts.OFFERS[contract_selected]
	contract_title.text = contract_selected.capitalize() + " hunt"
	contract_briefing.text = CONTRACT_BRIEFINGS[contract_selected]
	contract_objective.text = "Destroy %s%s    /    %d / %d" % [contract_selected.capitalize(), "s" if terms["required"] > 1 else "", terms.get("progress", 0), terms["required"]]
	contract_progress.max_value = terms["required"]
	contract_progress.value = terms.get("progress", 0)
	contract_reward.text = "Credits    %d%s" % [terms["reward"], " / reward pending: wallet full" if HuntingContracts.ready(current) else ""]
	contract_accept.visible = current.is_empty()
	contract_abandon.visible = not current.is_empty()
	contract_accept.disabled = not blocker.is_empty()
	contract_abandon.disabled = not blocker.is_empty()
	contract_accept.tooltip_text = contract_status.text
	contract_abandon.tooltip_text = contract_status.text


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
	bar.size.x *= clampf(value / maxf(maximum, 1.0), 0.0, 1.0)
	draw_rect(bar, color)


func _draw() -> void:
	marker_labels.clear()
	if not is_instance_valid(sector.player):
		return
	var width := size.x
	update_contract_panel()
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
	var cargo_used := CargoResources.units(sector.cargo)
	text_at(Vector2(width - 390, 60), "CARGO %d / %d%s" % [cargo_used, sector.cargo_capacity, " FULL" if cargo_used >= sector.cargo_capacity else ""], 11, RED if cargo_used >= sector.cargo_capacity else GREEN)
	draw_line(Vector2(32, 82), Vector2(width - 32, 82), Color(0.3, 0.5, 0.65, 0.25), 1.0)
	var objective: String = [
		"Leave the outpost. %s to fly forward." % GameSettings.binding_text("forward"),
		"Find the alien. %s or %s to select." % [GameSettings.binding_text("cycle_target"), GameSettings.binding_text("select_target")],
		"%s to fire. Keep the alien ahead and within 170 m." % GameSettings.binding_text("fire"),
		"Return to Outpost 01. Slow down and press %s to repair." % GameSettings.binding_text("repair"),
		"Encounter complete. Keep exploring or hunt another alien.",
	][sector.objective_stage]
	if shared:
		objective = "C  Choose hunting contracts at Outpost 01. Rewards pay automatically."
	text_at(Vector2(33, 113), "HUNTING CONTRACTS" if shared else "OBJECTIVE", 11, GREEN)
	var objective_y := 137.0
	if shared and not sector.active_contracts.is_empty():
		for kind: String in HuntingContracts.OFFERS:
			if sector.active_contracts.has(kind):
				text_at(Vector2(33, objective_y), HuntingContracts.objective(sector.active_contracts[kind]), 14 if compact else 17)
				objective_y += 22
	else:
		text_at(Vector2(33, objective_y), objective, 14 if compact else 17)
		objective_y += 22
	if sector.toast_time > 0.0:
		text_at(Vector2(33, objective_y + 10), sector.toast, 12 if compact else 14, CYAN)
	marker(Sector.STATION_POSITION, "[+] OUTPOST 01", GREEN, false)
	if is_instance_valid(sector.target):
		alien_marker(sector.target as Alien)
	for drop: Dictionary in sector.loot.drops.values():
		marker(drop["position"], "LOOT %d UNITS / FLY CLOSE" % CargoResources.units(drop["resources"]), Color("ffc55d"), false, null, false)
	for enemy: Alien in sector.aliens.values():
		if enemy != sector.target and enemy.alive and enemy.visible:
			alien_marker(enemy)
	if shared:
		for ship: Pilot in sector.session.ships.values():
			if ship != player and ship.alive:
				marker(ship.global_position, "FRIEND %s" % sector.session.ships.find_key(ship), CYAN, false, ship)
	var center := size * 0.5
	draw_line(center - Vector2(8, 0), center - Vector2(3, 0), Color(0.7, 0.85, 0.95, 0.5), 1.0)
	draw_line(center + Vector2(3, 0), center + Vector2(8, 0), Color(0.7, 0.85, 0.95, 0.5), 1.0)
	draw_circle(center, 1.0, CYAN)
	panel(Rect2(32, height - 245, 290, 174))
	text_at(Vector2(50, height - 218), "%s  /  ACTIVE SHIP" % ShipCatalog.info(sector.player.ship_model)["name"].to_upper(), 12, CYAN)
	meter(Vector2(50, height - 190), "SHIELD", player.shield, player.max_shield, CYAN)
	meter(Vector2(50, height - 145), "HULL", player.hull, player.max_hull, GREEN if player.hull > player.max_hull * 0.3 else RED)
	meter(Vector2(50, height - 100), "BOOST", player.energy, 100.0, Color("e3b777"))
	text_at(Vector2(343, height - 100), "%03d" % roundi(player.velocity.length()), 32)
	text_at(Vector2(343, height - 79), "m/s  /  " + ("BOOST" if player.boosting else "FLIGHT ASSIST"), 10, MUTED)
	draw_target_panel(width, height)
	draw_navigation()
	var distance := player.global_position.distance_to(Sector.STATION_POSITION)
	if distance <= Sector.REPAIR_RADIUS and player.alive:
		if shared:
			text_at(Vector2(width - 310, height - 280), "C  HUNTING CONTRACTS", 14, GREEN)
		var label := "%s  REPAIR / %d CR" % [GameSettings.binding_text("repair"), sector.repair_cost()]
		if player.velocity.length() > 8.0:
			label = "SLOW DOWN TO REPAIR"
		elif player.time_since_hit < 5.0:
			label = "REPAIRS AVAILABLE IN %d s" % ceili(5.0 - player.time_since_hit)
		text_at(Vector2(width - 310, height - 256), label, 14, GREEN)
		text_at(Vector2(width - 310, height - 304), "B  SHOP / CARGO     I  EQUIPMENT", 14, CYAN)
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
	draw_boundary_warning()


func draw_target_panel(width: float, height: float) -> void:
	panel(Rect2(width - 322, height - 245, 290, 174), RED if sector.target != null else MUTED)
	var origin := Vector2(width - 304, height - 218)
	if not is_instance_valid(sector.target) or not sector.target.alive:
		text_at(origin, "NO TARGET", 13, MUTED)
		text_at(origin + Vector2(0, 34), "%s or %s to lock" % [GameSettings.binding_text("cycle_target"), GameSettings.binding_text("select_target")], 15)
		text_at(origin + Vector2(0, 64), "%02d  ALIENS DESTROYED" % sector.kills, 12, MUTED)
		text_at(origin + Vector2(0, 104), "Find contacts on the navigation maps", 12, CYAN)
		return
	var enemy := sector.target as Alien
	text_at(origin, "%s %d / %d m" % [enemy.kind.to_upper(), enemy.alien_id + 1, sector.player.global_position.distance_to(enemy.global_position)], 12, enemy.tuning()["color"])
	meter(origin + Vector2(0, 28), "SHIELD", enemy.shield, enemy.max_shield, CYAN)
	meter(origin + Vector2(0, 72), "HULL", enemy.hull, enemy.max_hull, RED)
	text_at(origin + Vector2(0, 128), fire_feedback(), 12, RED if sector.auto_fire and not sector.weapon_status.is_empty() else GREEN)


func alien_marker(enemy: Alien) -> void:
	marker(enemy.global_position, "HOSTILE %s %d%s" % [enemy.kind.to_upper(), enemy.alien_id + 1, " / RETURNING" if enemy.returning else ""], enemy.tuning()["color"], sector.target == enemy, null, sector.target == enemy)


static func map_projection(location: Vector3, side_view: bool) -> Vector2:
	# Fixed world axes avoid a map that flips when the pilot pitches or turns.
	return Vector2(location.x, -location.y if side_view else location.z) / Sector.MAP_RADIUS


func map_contact(center: Vector2, location: Vector3, side_view: bool, color: Color, label: String = "", selected: bool = false) -> void:
	var point := center + map_projection(location, side_view).limit_length() * 53.0
	draw_circle(point, 3.0, color)
	if selected:
		draw_arc(point, 6.0, 0, TAU, 24, Color.WHITE, 1.5, true)
	if not label.is_empty():
		text_at(point + Vector2(5, -3), label, 10, color)


func draw_navigation() -> void:
	var origin := Vector2(size.x - 322, 96)
	panel(Rect2(origin, Vector2(290, 182)))
	text_at(origin + Vector2(14, 20), "SECTOR MAP / %.1f km ACROSS" % (Sector.MAP_RADIUS * 0.002), 11, CYAN)
	for side_view: bool in [false, true]:
		var center := origin + Vector2(76 if not side_view else 214, 88)
		draw_circle(center, 54, Color(0.07, 0.12, 0.17, 0.8))
		draw_arc(center, 54, 0, TAU, 64, MUTED, 1, true)
		draw_line(center - Vector2(54, 0), center + Vector2(54, 0), Color(MUTED, 0.2))
		draw_line(center - Vector2(0, 54), center + Vector2(0, 54), Color(MUTED, 0.2))
		text_at(center + Vector2(-48, -40), "+Y" if side_view else "-Z", 9, MUTED)
		text_at(center + Vector2(36, 10), "+X", 9, MUTED)
		map_contact(center, Sector.STATION_POSITION, side_view, GREEN, "+")
		for enemy: Alien in sector.aliens.values():
			if enemy.alive and enemy.visible:
				map_contact(center, enemy.position, side_view, enemy.tuning()["color"], str(enemy.alien_id + 1), sector.target == enemy)
		if sector.session.active:
			for ship: Pilot in sector.session.ships.values():
				if ship != sector.player and ship.alive:
					map_contact(center, ship.position, side_view, CYAN)
		var player_point := center + map_projection(sector.player.position, side_view).limit_length() * 53.0
		var forward := map_projection(-sector.player.global_basis.z, side_view).normalized()
		if forward.length_squared() > 0.01:
			var side := forward.orthogonal() * 3.5
			draw_colored_polygon(PackedVector2Array([player_point + forward * 6, player_point - forward * 4 + side, player_point - forward * 4 - side]), Color.WHITE)
		else:
			draw_circle(player_point, 4, Color.WHITE)
		text_at(center + Vector2(-42, 68), "SIDE / X-Y" if side_view else "TOP / X-Z", 10, MUTED)
	var altitude := "Y %+.0f m" % sector.player.position.y
	if is_instance_valid(sector.target):
		altitude += " / target %+.0f m" % (sector.target.position.y - sector.player.position.y)
	text_at(origin + Vector2(14, 176), "YOU: white  BASE: green  " + altitude, 10, INK)


func draw_boundary_warning() -> void:
	var player := sector.player
	if not player.alive or (sector.client_only and not sector.session.active):
		return
	var remaining := Sector.MAP_RADIUS - player.position.length()
	if remaining > Sector.BOUNDARY_WARNING_DISTANCE:
		return
	var outside := remaining < 0.0
	var color := RED if outside else Color("e3b777")
	if outside:
		# One soft pulse per second keeps the scene and instruments readable.
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * TAU / 1000.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.01, 0.02, 0.025 + pulse * 0.09))
		draw_rect(Rect2(3, 3, size.x - 6, size.y - 6), Color(RED, 0.35 + pulse * 0.6), false, 6)
	var rect := Rect2(maxf(32, (size.x - 764) * 0.5), 220, 410, 62 if outside else 42)
	panel(rect, color)
	text_at(rect.position + Vector2(14, 23), "RADIATION ZONE / RETURN TO SAFE SPACE" if outside else "SECTOR EDGE / %d m / RADIATION AHEAD" % ceili(remaining), 15, color)
	if outside:
		var rate := (Sector.RADIATION_BASE_RATE + Sector.RADIATION_RAMP_RATE * player.radiation_exposure) * 100.0
		text_at(rect.position + Vector2(14, 46), "%d m outside / %.1f s exposed / %.1f%% max hull/s" % [ceili(-remaining), player.radiation_exposure, rate], 12, INK)
		var safe_point := player.position.normalized() * (Sector.MAP_RADIUS - 50.0)
		marker(safe_point, "RETURN TO SAFE SPACE", RED, false)


func marker(location: Vector3, label: String, color: Color, selected: bool, teammate: Pilot = null, priority: bool = true) -> void:
	var camera := sector.player.camera
	var point := camera.unproject_position(location)
	var behind := camera.is_position_behind(location)
	var bounds := Rect2(38, 205, size.x - 76, size.y - 480)
	var distance := sector.player.global_position.distance_to(location)
	if behind or not bounds.has_point(point):
		if teammate != null or not priority:
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
	marker_caption(point + Vector2(0, radius + 20), "%s%s / %d m" % ["LOCK / " if selected else "", label, distance], color, priority and teammate == null)


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
