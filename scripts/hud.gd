class_name FlightHud
extends Control

const INK := Color("e3edf7")
const MUTED := Color("93a5b5")
const AMBER := Color("ff880b")
const LINE := Color("34434b")
const CYAN := Color("66e2ee")
const GREEN := Color("6ae9bb")
const RED := Color("ff8176")
const PANEL := Color(0.047, 0.071, 0.090, 0.92)
const TOP_MARGIN := 24.0
const SIDE_MARGIN := 32.0
const BOTTOM_MARGIN := 71.0

var sector: Sector
var font: Font = StationUi.FONT
var background: StyleBoxFlat
var marker_labels: Array[Rect2] = []
var contract_panel: PanelContainer
var contract_status: Label
var contract_choices: Dictionary[String, Button] = {}
var contract_tabs: Array[Button] = []
var contract_selected := "scout"
var contract_active_only := false
var contract_title: Label
var contract_objective: Label
var contract_progress: ProgressBar
var contract_reward: Label
var contract_slots: Label
var contract_empty: Label
var contract_accept: Button
var contract_abandon: Button
var contract_preview: ContractPreview
var contract_back: Button
var navigation: FlightNavigation
var ammo_bar: AmmoBar
var layout: HudLayout


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = StationUi.menu_theme()
	background = panel_style()
	build_contract_panel()
	navigation = FlightNavigation.new()
	navigation.sector = sector
	add_child(navigation)
	ammo_bar = AmmoBar.new()
	ammo_bar.sector = sector
	add_child(ammo_bar)
	layout = HudLayout.new()
	layout.hud = self
	add_child(layout)


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
	StationUi.frame(contract_panel, Vector2(1150, 690))
	add_child(contract_panel)
	var rows := StationUi.rows(contract_panel, 16)
	StationUi.text(rows, "QUESTS", 28)
	# Development listen-host fixtures can open contracts without a persistent inventory.
	contract_back = StationUi.button(rows, "Back [C / Esc]", toggle_contracts)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	var sidebar := StationUi.card(body)
	sidebar.custom_minimum_size.x = 400
	var left := StationUi.rows(sidebar, 14)
	var tabs := HBoxContainer.new()
	left.add_child(tabs)
	for active_only: bool in [false, true]:
		var tab := StationUi.button(tabs, "Active" if active_only else "Hunting", func(): filter_contracts(active_only))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		contract_tabs.append(tab)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	var offers := VBoxContainer.new()
	offers.add_theme_constant_override("separation", 12)
	offers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(offers)
	for offer: String in HuntingContracts.OFFERS:
		var button := StationUi.button(offers, "", func(): select_contract(offer))
		button.custom_minimum_size.y = 110
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 22)
		contract_choices[offer] = button
	contract_empty = StationUi.text(offers, "No active quests", 20, StationUi.MUTED)
	var detail := StationUi.card(body)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := StationUi.rows(detail, 18)
	contract_title = StationUi.text(right, "", 30)
	contract_preview = ContractPreview.new()
	right.add_child(contract_preview)
	contract_objective = StationUi.text(right, "", 22)
	contract_progress = ProgressBar.new()
	contract_progress.custom_minimum_size.y = 8
	contract_progress.show_percentage = false
	contract_progress.add_theme_stylebox_override("background", StationUi.style(Color("253139"), StationUi.LINE))
	contract_progress.add_theme_stylebox_override("fill", StationUi.style(StationUi.AMBER, StationUi.AMBER))
	contract_progress.get_theme_stylebox("background").set_content_margin_all(0)
	contract_progress.get_theme_stylebox("fill").set_content_margin_all(0)
	right.add_child(contract_progress)
	right.add_child(HSeparator.new())
	contract_reward = StationUi.text(right, "", 26, StationUi.AMBER)
	contract_slots = StationUi.text(left, "", 16, StationUi.MUTED)
	contract_slots.tooltip_text = "Rewards pay automatically. Death keeps progress; abandoning has no penalty."
	contract_accept = StationUi.button(right, "ACCEPT", func(): act_on_contract("accept"))
	StationUi.primary(contract_accept)
	contract_abandon = StationUi.button(right, "ABANDON", func(): act_on_contract("abandon"))
	contract_abandon.custom_minimum_size.y = 48
	contract_status = StationUi.text(rows, "", 16, RED)
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
	if not StationUi.offline_preview(sector) and not blocker.is_empty():
		sector.notify(blocker)
		return
	if sector.main_menu.route_page("quests"):
		return
	sector.session.menu.hide()
	sector.shop.hide()
	sector.equipment_menu.hide()
	sector.set_paused(true)
	contract_panel.scale = Vector2.ONE
	StationUi.frame(contract_panel, Vector2(1150, 690))
	contract_panel.show()
	update_contract_panel()


func update_contract_panel() -> void:
	if not contract_panel.visible:
		return
	if not sector.session.active and not StationUi.offline_preview(sector):
		contract_panel.hide()
		return
	contract_back.visible = not sector.main_menu.visible
	if not sector.main_menu.visible:
		StationUi.centered(contract_panel, Vector2(1150, 690))
	var blocker := StationUi.OFFLINE_BLOCKER if StationUi.offline_preview(sector) else sector.repair_blocker()
	contract_status.text = blocker.replace("to repair.", "to manage contracts.").replace("Repairs available", "Contract actions available")
	contract_status.visible = not blocker.is_empty()
	contract_slots.text = "%d / %d active" % [sector.active_contracts.size(), HuntingContracts.OFFERS.size()]
	contract_tabs[0].set_pressed_no_signal(not contract_active_only)
	contract_tabs[1].set_pressed_no_signal(contract_active_only)
	var visible_offers: Array[String] = []
	for offer: String in HuntingContracts.OFFERS:
		var current: Dictionary = sector.active_contracts.get(offer, {})
		var listed_terms: Dictionary = current if not current.is_empty() else HuntingContracts.OFFERS[offer]
		var button := contract_choices[offer]
		button.visible = not contract_active_only or not current.is_empty()
		if button.visible:
			visible_offers.append(offer)
		var state := "Available"
		if not current.is_empty():
			state = "Reward pending" if HuntingContracts.ready(current) else "Active / %d of %d" % [current["progress"], current["required"]]
		button.text = "%s hunt\n%d kills   /   %d CR\n%s" % [offer.capitalize(), listed_terms["required"], listed_terms["reward"], state]
	if not visible_offers.has(contract_selected):
		contract_selected = visible_offers[0] if not visible_offers.is_empty() else ""
	for offer: String in contract_choices:
		contract_choices[offer].set_pressed_no_signal(offer == contract_selected)
	contract_empty.visible = visible_offers.is_empty()
	contract_progress.visible = not contract_selected.is_empty()
	contract_preview.visible = not contract_selected.is_empty()
	if contract_selected.is_empty():
		contract_accept.hide()
		contract_abandon.hide()
		contract_title.text = "No active contracts"
		contract_objective.text = "No hunt selected."
		contract_reward.text = "Credits / --"
		return
	var current: Dictionary = sector.active_contracts.get(contract_selected, {})
	var terms: Dictionary = current if not current.is_empty() else HuntingContracts.OFFERS[contract_selected]
	contract_preview.show_kind(contract_selected.capitalize())
	contract_title.text = contract_selected.capitalize() + " hunt"
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


func text_at(point: Vector2, text: String, size_px: int = 16, color: Color = INK, width: float = -1.0) -> void:
	# Fit long contact names and rebound keys without drawing outside their card.
	while width > 0 and size_px > 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > width:
		size_px -= 1
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, color)


func panel(rect: Rect2, accent: Color = AMBER) -> void:
	draw_style_box(background, rect)
	draw_line(rect.position + Vector2(2, 2), Vector2(rect.position.x + 2, rect.end.y - 2), accent, 3.0)


func card_title(rect: Rect2, title: String, accent: Color = AMBER) -> void:
	panel(rect, accent)
	text_at(rect.position + Vector2(18, 27), title, 18, AMBER, rect.size.x - 36)
	draw_line(rect.position + Vector2(18, 40), Vector2(rect.end.x - 18, rect.position.y + 40), LINE)


static func number(value: float) -> String:
	var digits := str(ceili(value))
	var offset := digits.length() - 3
	while offset > 0:
		digits = digits.insert(offset, ",")
		offset -= 3
	return digits


func ship_rect() -> Rect2:
	return Rect2(SIDE_MARGIN, size.y - BOTTOM_MARGIN - 174, 290, 174)


func target_rect() -> Rect2:
	return Rect2(size.x - SIDE_MARGIN - 290, size.y - BOTTOM_MARGIN - 174, 290, 174)


func objectives_rect() -> Rect2:
	var shared := sector.session.active
	var rows := sector.active_contracts.size() if shared else 0
	return Rect2(SIDE_MARGIN, TOP_MARGIN, 280, 48 + rows * 34 if rows > 0 else 110)


func paragraph(point: Vector2, content: String, width: float, pixels: int = 16, color: Color = INK) -> Vector2:
	var dimensions := font.get_multiline_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, width, pixels)
	draw_multiline_string(font, point, content, HORIZONTAL_ALIGNMENT_LEFT, width, pixels, -1, color)
	return dimensions


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style


func meter(point: Vector2, title: String, value: float, maximum: float, color: Color) -> void:
	text_at(point, title, 16, MUTED)
	var value_text := number(value)
	var value_width := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	text_at(point + Vector2(250 - value_width, 0), value_text, 18, color)
	var bar := Rect2(point + Vector2(0, 10), Vector2(250, 5))
	draw_rect(bar, LINE)
	bar.size.x *= clampf(value / maxf(maximum, 1.0), 0.0, 1.0)
	draw_rect(bar, color)


func draw_objectives() -> void:
	var rect := objectives_rect()
	card_title(rect, "HUNTING CONTRACTS" if sector.session.active else "OBJECTIVE")
	if sector.session.active and not sector.active_contracts.is_empty():
		var row := rect.position + Vector2(18, 66)
		for kind: String in HuntingContracts.OFFERS:
			if not sector.active_contracts.has(kind):
				continue
			var contract: Dictionary = sector.active_contracts[kind]
			text_at(row, kind.capitalize(), 18)
			var pending := HuntingContracts.ready(contract)
			var progress := "%d / %d" % [contract["progress"], contract["required"]]
			if pending:
				progress = "REWARD PENDING"
			var pixels := 13 if pending else 18
			var width := font.get_string_size(progress, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
			text_at(Vector2(rect.end.x - 18 - width, row.y), progress, pixels, AMBER if pending else INK)
			row.y += 34
			if row.y < rect.end.y:
				draw_line(Vector2(rect.position.x + 18, row.y - 23), Vector2(rect.end.x - 18, row.y - 23), LINE)
	else:
		var objective: String = [
			"Leave the outpost. %s to fly forward." % GameSettings.binding_text("forward"),
			"Find an alien. %s or %s to select." % [GameSettings.binding_text("cycle_target"), GameSettings.binding_text("select_target")],
			"%s to fire. Keep the alien ahead and in range." % GameSettings.binding_text("fire"),
			"Return to Outpost 01. Slow down and press %s to repair." % GameSettings.binding_text("repair"),
			"Encounter complete. Hunt another alien.",
		][sector.objective_stage]
		if sector.session.active:
			objective = "No active hunts. Choose contracts at Outpost 01 [C]."
		paragraph(rect.position + Vector2(18, 64), objective, rect.size.x - 36)


func draw_controls() -> void:
	var point := Vector2(SIDE_MARGIN, size.y - 28)
	var pixels := 14 if size.x < 1200 else 16
	for entry: Array in [["steer", "Steer"], ["cycle_target", "Target"], ["fire", "Fire"], ["boost", "Boost"], ["repair", "Repair"], ["sector_map", "Map"], ["pause_game", "Menu"]]:
		var key := GameSettings.binding_text(entry[0])
		var key_width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x + 14
		draw_style_box(background, Rect2(point - Vector2(0, 18), Vector2(key_width, 26)))
		text_at(point + Vector2(7, 0), key, pixels)
		point.x += key_width + 8
		text_at(point, entry[1], pixels, MUTED)
		point.x += font.get_string_size(entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x + 20


func draw_context() -> void:
	if not layout.begin_draw(self, "context"):
		return
	var point := Vector2(SIDE_MARGIN, objectives_rect().end.y + 12)
	var messages: Array[String] = []
	if CargoResources.units(sector.cargo) >= sector.cargo_capacity:
		messages.append("CARGO FULL / SELL AT OUTPOST 01 [B]")
	if sector.toast_time > 0:
		messages.append(sector.toast)
	if sector.client_only and not sector.session.active:
		messages.append("DISCONNECTED / " + sector.session.status)
	if layout.editing and messages.is_empty():
		messages.append("Notifications appear here.")
	for message: String in messages:
		var width := minf(440, size.x - 2 * SIDE_MARGIN - 322)
		var dimensions := font.get_multiline_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, width - 24, 16)
		var rect := Rect2(point, Vector2(width, dimensions.y + 16))
		draw_style_box(background, rect)
		paragraph(point + Vector2(12, 20), message, width - 24, 16, AMBER)
		marker_labels.append(layout.transform_rect("context", rect))
		point.y = rect.end.y + 8
	layout.end_draw(self)


func draw_performance() -> void:
	if (sector.show_performance or layout.editing) and layout.begin_draw(self, "performance"):
		var point := layout.default_rect("performance").position
		var fps := Engine.get_frames_per_second()
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		text_at(point + Vector2(0, 18), "%d FPS / %.1f ms / %d draws / %s" % [fps, 1000.0 / maxf(fps, 1), draws, ["AA OFF", "2x MSAA", "4x MSAA", "8x MSAA"][sector.settings.msaa_3d]], 14, MUTED)
		layout.end_draw(self)
		marker_labels.append(layout.rect_for("performance"))


func draw_station_actions() -> void:
	var player := sector.player
	if not layout.editing and (not player.alive or player.global_position.distance_to(Sector.STATION_POSITION) > Sector.REPAIR_RADIUS):
		return
	if not layout.begin_draw(self, "station"):
		return
	var rect := Rect2(target_rect().position - Vector2(0, 88 if sector.session.active else 66), Vector2(290, 78 if sector.session.active else 56))
	draw_style_box(background, rect)
	text_at(rect.position + Vector2(12, 21), "B  SHOP / CARGO     I  EQUIPMENT", 16, AMBER)
	var label := "%s  REPAIR / %s CR" % [GameSettings.binding_text("repair"), number(sector.repair_cost())]
	if player.velocity.length() > 8.0:
		label = "SLOW DOWN TO REPAIR"
	elif player.time_since_hit < 5.0:
		label = "REPAIR IN %d s" % ceili(5.0 - player.time_since_hit)
	text_at(rect.position + Vector2(12, 43), label, 16, GREEN, 266)
	if sector.session.active:
		text_at(rect.position + Vector2(12, 65), "C  HUNTING CONTRACTS", 16, AMBER)
	layout.end_draw(self)
	marker_labels.append(layout.rect_for("station"))


func _draw() -> void:
	marker_labels.clear()
	update_contract_panel()
	if sector.preflight or (is_instance_valid(sector.main_menu) and sector.main_menu.visible) or not is_instance_valid(sector.player):
		return
	var player := sector.player
	for id: String in ["objectives", "radar", "ship", "target", "guidance"]:
		if layout.shown(id):
			marker_labels.append(layout.rect_for(id))
	if ammo_bar.visible:
		marker_labels.append(ammo_bar.get_global_rect())
	if navigation.autopilot_status.visible:
		marker_labels.append(navigation.autopilot_status.get_rect().grow(3))
	if layout.begin_draw(self, "objectives"):
		draw_objectives()
		layout.end_draw(self)
	draw_context()
	draw_performance()
	if layout.begin_draw(self, "ship"):
		draw_ship_panel()
		layout.end_draw(self)
	if layout.begin_draw(self, "speed"):
		draw_speed()
		layout.end_draw(self)
		marker_labels.append(layout.rect_for("speed"))
	if layout.begin_draw(self, "target"):
		draw_target_panel()
		layout.end_draw(self)
	draw_station_actions()
	if layout.begin_draw(self, "controls"):
		draw_controls()
		layout.end_draw(self)
	var center := size * 0.5
	if layout.begin_draw(self, "reticle"):
		draw_line(center - Vector2(8, 0), center - Vector2(3, 0), Color(INK, 0.5))
		draw_line(center + Vector2(3, 0), center + Vector2(8, 0), Color(INK, 0.5))
		draw_circle(center, 2.0, AMBER)
		layout.end_draw(self)
	marker(Sector.STATION_POSITION, "OUTPOST 01", GREEN, false)
	if is_instance_valid(sector.target):
		alien_marker(sector.target as Alien)
	for id: int in sector.loot.drops:
		if sector.loot.is_presented(id):
			var drop: Dictionary = sector.loot.drops[id]
			marker(drop["position"], "LOOT %d UNITS / FLY CLOSE" % CargoResources.units(drop["resources"]), AMBER, false, null, false)
	for enemy: Alien in sector.aliens.values():
		if enemy != sector.target and enemy.alive and enemy.visible:
			alien_marker(enemy)
	if sector.session.active:
		for ship: Pilot in sector.session.ships.values():
			if ship != player and ship.alive:
				marker(ship.global_position, "FRIEND %s" % sector.session.ships.find_key(ship), CYAN, false, ship)
	if not player.alive:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.025, 0.04, 0.65))
		text_at(center + Vector2(-150, -20), "RESCUE INBOUND", 30, RED)
		text_at(center + Vector2(-150, 15), "Returning to the outpost in %d..." % ceili(sector.player_respawn), 18)
	if sector.paused and not layout.editing:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.012, 0.025, 0.88))
	draw_boundary_warning()


func draw_ship_panel() -> void:
	var player := sector.player
	var rect := ship_rect()
	card_title(rect, ShipCatalog.info(player.ship_model)["name"].to_upper())
	meter(rect.position + Vector2(18, 64), "SHIELD", player.shield, player.max_shield, CYAN)
	meter(rect.position + Vector2(18, 107), "HULL", player.hull, player.max_hull, GREEN if player.hull > player.max_hull * 0.3 else RED)
	meter(rect.position + Vector2(18, 150), "BOOST", player.energy, 100.0, AMBER)


func draw_speed() -> void:
	var player := sector.player
	var speed := layout.default_rect("speed").position + Vector2(0, 24)
	text_at(speed, "%d m/s" % roundi(player.velocity.length()), 24)
	text_at(speed + Vector2(0, 22), "BOOST" if player.boosting else "FLIGHT ASSIST", 12, MUTED)


func draw_target_panel() -> void:
	var rect := target_rect()
	var enemy := sector.target as Alien
	card_title(rect, "%s %d / %d m" % [enemy.kind.to_upper(), enemy.alien_id + 1, sector.player.global_position.distance_to(enemy.global_position)] if is_instance_valid(enemy) else "NO TARGET", RED if is_instance_valid(enemy) else MUTED)
	var origin := rect.position + Vector2(18, 64)
	if not is_instance_valid(sector.target) or not sector.target.alive:
		paragraph(origin, "%s or %s to lock" % [GameSettings.binding_text("cycle_target"), GameSettings.binding_text("select_target")], 250)
		text_at(origin + Vector2(0, 42), "%d ALIENS DESTROYED" % sector.kills, 16, MUTED)
		text_at(origin + Vector2(0, 86), "M / Choose a contact on the map", 16, MUTED, 250)
		return
	meter(origin, "SHIELD", enemy.shield, enemy.max_shield, CYAN)
	meter(origin + Vector2(0, 43), "HULL", enemy.hull, enemy.max_hull, RED)
	paragraph(origin + Vector2(0, 81), fire_feedback(), 250, 16, RED if sector.auto_fire and not sector.weapon_status.is_empty() else MUTED)


func alien_marker(enemy: Alien) -> void:
	marker(enemy.global_position, "HOSTILE %s %d%s" % [enemy.kind.to_upper(), enemy.alien_id + 1, " / RETURNING" if enemy.returning else ""], AMBER if sector.target == enemy else enemy.tuning()["color"], sector.target == enemy, null, sector.target == enemy)


func draw_boundary_warning() -> void:
	var player := sector.player
	if not player.alive or (sector.client_only and not sector.session.active):
		return
	var remaining := Sector.MAP_RADIUS - player.position.length()
	if remaining > Sector.BOUNDARY_WARNING_DISTANCE and not layout.editing:
		return
	var outside := remaining < 0.0
	var color := RED if outside else AMBER
	if outside:
		# One soft pulse per second keeps the scene and instruments readable.
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * TAU / 1000.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.01, 0.02, 0.025 + pulse * 0.09))
		draw_rect(Rect2(3, 3, size.x - 6, size.y - 6), Color(RED, 0.35 + pulse * 0.6), false, 6)
	if layout.begin_draw(self, "radiation"):
		var rect := Rect2(maxf(SIDE_MARGIN, (size.x - 764) * 0.5), 248, 410, 62 if outside else 42)
		panel(rect, color)
		var caption := "RADIATION ZONE / RETURN TO SAFE SPACE" if outside else "SECTOR EDGE / %d m / RADIATION AHEAD" % ceili(remaining)
		if layout.editing and remaining > Sector.BOUNDARY_WARNING_DISTANCE:
			caption = "RADIATION ALERT / PREVIEW"
		text_at(rect.position + Vector2(14, 23), caption, 15, color)
		if outside:
			var rate := (Sector.RADIATION_BASE_RATE + Sector.RADIATION_RAMP_RATE * player.radiation_exposure) * 100.0
			text_at(rect.position + Vector2(14, 46), "%d m outside / %.1f s exposed / %.1f%% max hull/s" % [ceili(-remaining), player.radiation_exposure, rate], 12, INK)
		layout.end_draw(self)
		marker_labels.append(layout.rect_for("radiation"))
	if outside:
		var safe_point := player.position.normalized() * (Sector.MAP_RADIUS - 50.0)
		marker(safe_point, "RETURN TO SAFE SPACE", RED, false)


func marker(location: Vector3, label: String, color: Color, selected: bool, teammate: Pilot = null, priority: bool = true) -> void:
	var camera := sector.player.camera
	var point := camera.unproject_position(location)
	var behind := camera.is_position_behind(location)
	var bounds := Rect2(38, TOP_MARGIN, size.x - 76, size.y - TOP_MARGIN - 245)
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
	var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var origin := Vector2(clampf(point.x - text_size.x * 0.5 - 5, 12, size.x - text_size.x - 22), point.y - 16)
	var bounds := Rect2(12, TOP_MARGIN, size.x - 24, size.y - TOP_MARGIN - BOTTOM_MARGIN - 8)
	# Check every reserved card after each move. Moving past one card must not
	# place a priority caption inside another card at small window sizes.
	for step in range(1 + ceili(bounds.size.y / 28) * 2 if priority else 1):
		var offset := ceilf(step / 2.0) * 28 * (1 if step % 2 == 1 else -1)
		var rect := Rect2(origin + Vector2(0, offset), text_size + Vector2(10, 6))
		if not bounds.encloses(rect) or marker_labels.any(func(occupied: Rect2): return occupied.intersects(rect)):
			continue
		marker_labels.append(rect)
		draw_style_box(background, rect)
		text_at(rect.position + Vector2(5, 16), caption, 14, color)
		return
