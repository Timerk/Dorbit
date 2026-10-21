class_name FlightHud
extends Control

const INK := Color("e3edf7")
const MUTED := Color("93a5b5")
const AMBER := Color("ff880b")
const LINE := Color("34434b")
const CYAN := Color("66e2ee")
const GREEN := Color("6ae9bb")
const RED := Color("ff8176")
const GOLD := StorySites.GOLD
const PORTRAIT := 64.0
const PANEL := Color(0.047, 0.071, 0.090, 0.92)
const TOP_MARGIN := 24.0
const SIDE_MARGIN := 32.0
const BOTTOM_MARGIN := 71.0
const CARDS := ["objectives", "radar", "ship", "target", "guidance"]
const CORNERS := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
const CONTROL_HINTS := [["steer", "Steer"], ["cycle_target", "Target"], ["fire", "Fire"], ["boost", "Boost"], ["repair", "Repair"], ["sector_map", "Map"], ["pause_game", "Menu"]]
const NO_FIT := []
# Fitted sizes per string: [requested size, width, fitted size], cleared at 256 entries.
static var fitted: Dictionary[String, Array] = {}

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
var story_tab: Button
var story_view := false
var story_choices: Array[Button] = []
var story_selected := 0
var story_briefing: Label
var story_speaker: HBoxContainer
var story_portrait: TextureRect
var story_tip: Label
var story_deliver: Button
var story_skip: Button
var story_skip_armed := false
# The flight card's hint height changes only with the step or the bindings.
var story_hint := ""
var story_hint_key := Vector2i(-2, -1)
var story_hint_height := 0.0
# Key-cap labels and widths for the controls pop-up, rebuilt after rebinding.
var tip_keys: Array[Array] = []
var tip_keys_key := Vector2i(-1, -1)
var navigation: FlightNavigation
var ammo_bar: AmmoBar
var layout: HudLayout
# Binding phrases and control hints are rebuilt after any rebind.
var phrases: Dictionary[String, String] = {}
var phrases_revision := -1
var control_hints: Array[Array] = []
var control_hints_state := Vector3i(-1, -1, -1)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = StationUi.menu_theme()
	# Portraits shrink from 512 px sources; mipmaps keep the small faces smooth.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
		return bound("AUTO FIRE OFF / %s TO ENGAGE", "fire")
	if sector.weapon_status == "TURN TOWARD TARGET":
		return "OUTSIDE FIRING ARC"
	return sector.weapon_status if not sector.weapon_status.is_empty() else "AUTO FIRE ACTIVE"


func build_contract_panel() -> void:
	contract_panel = PanelContainer.new()
	StationUi.frame(contract_panel, Vector2(1150, 690))
	add_child(contract_panel)
	var rows := StationUi.rows(contract_panel, 16)
	rows.add_theme_constant_override("separation", 10)
	StationUi.header(rows, "QUESTS", "OPERATIONS")
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
	story_tab = StationUi.button(tabs, "Story", show_story)
	story_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_tab.toggle_mode = true
	StationUi.tab(story_tab)
	for active_only: bool in [false, true]:
		var tab := StationUi.button(tabs, "Active" if active_only else "Hunting", func(): filter_contracts(active_only))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		StationUi.tab(tab)
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
	for index in Story.STEPS.size():
		var button := StationUi.button(offers, "", func(): select_story(index))
		button.custom_minimum_size.y = 64
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		story_choices.append(button)
	var detail := StationUi.card(body)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := StationUi.rows(detail, 18)
	contract_title = StationUi.heading(right, "", 32)
	contract_preview = ContractPreview.new()
	right.add_child(contract_preview)
	contract_objective = StationUi.text(right, "", 22)
	contract_progress = ProgressBar.new()
	contract_progress.custom_minimum_size.y = 8
	contract_progress.show_percentage = false
	right.add_child(contract_progress)
	story_speaker = HBoxContainer.new()
	story_speaker.add_theme_constant_override("separation", 16)
	right.add_child(story_speaker)
	story_portrait = TextureRect.new()
	story_portrait.custom_minimum_size = Vector2(112, 112)
	story_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	story_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	story_speaker.add_child(story_portrait)
	story_briefing = StationUi.text(story_speaker, "", 17)
	story_briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_tip = StationUi.text(right, "", 15, StationUi.MUTED)
	right.add_child(HSeparator.new())
	contract_reward = StationUi.text(right, "", 26, StationUi.AMBER)
	contract_reward.add_theme_font_override("font", StationUi.BOLD)
	contract_slots = StationUi.text(left, "", 16, StationUi.MUTED)
	contract_slots.tooltip_text = "Rewards pay automatically. Death keeps progress; abandoning has no penalty."
	contract_accept = StationUi.button(right, "ACCEPT", func(): act_on_contract("accept"))
	StationUi.primary(contract_accept)
	contract_abandon = StationUi.button(right, "ABANDON", func(): act_on_contract("abandon"))
	contract_abandon.custom_minimum_size.y = 48
	story_deliver = StationUi.button(right, "DELIVER", func(): act_on_story("story_deliver"))
	StationUi.primary(story_deliver)
	story_skip = StationUi.button(right, "SKIP PROLOGUE", func(): act_on_story("story_skip"))
	story_skip.custom_minimum_size.y = 48
	story_skip.tooltip_text = "Completes the chapter and pays every remaining step reward."
	contract_status = StationUi.text(rows, "", 16, RED)
	contract_panel.hide()


func select_contract(offer: String) -> void:
	contract_selected = offer
	update_contract_panel()


func filter_contracts(active_only: bool) -> void:
	story_view = false
	contract_active_only = active_only
	update_contract_panel()


func show_story() -> void:
	story_view = true
	story_skip_armed = false
	story_selected = mini(int(sector.story_state().get("step", 0)), Story.STEPS.size() - 1)
	update_contract_panel()


func select_story(index: int) -> void:
	story_selected = index
	story_skip_armed = false
	update_contract_panel()


# Skipping needs a second press; both actions use the station transaction rules.
func act_on_story(action: String) -> void:
	var button := story_deliver if action == "story_deliver" else story_skip
	if not contract_panel.visible or not story_view or not button.visible or button.disabled:
		return
	if action == "story_skip" and not story_skip_armed:
		story_skip_armed = true
		update_contract_panel()
		return
	story_skip_armed = false
	sector.session.combat.request_station(action, "")


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
	# Open on the story when the current step is handed in at this board.
	if Story.current(sector.story_state()).get("type", "") == "deliver":
		show_story()
	story_skip_armed = false
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
	story_tab.set_pressed_no_signal(story_view)
	contract_tabs[0].set_pressed_no_signal(not story_view and not contract_active_only)
	contract_tabs[1].set_pressed_no_signal(not story_view and contract_active_only)
	for button: Button in story_choices:
		button.visible = story_view
	for control: Control in [story_speaker, story_tip, story_deliver, story_skip]:
		control.visible = story_view
	if story_view:
		update_story_panel(blocker)
		return
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


func update_story_panel(blocker: String) -> void:
	var live := sector.story_state()
	var story := Story.empty() if live.is_empty() else live
	var reached := int(story["step"])
	contract_slots.text = "%s / %d of %d complete" % [Story.CHAPTER, reached, Story.STEPS.size()]
	for offer: String in contract_choices:
		contract_choices[offer].hide()
	contract_empty.hide()
	contract_accept.hide()
	contract_abandon.hide()
	story_selected = clampi(story_selected, 0, mini(reached, Story.STEPS.size() - 1))
	for index in story_choices.size():
		var state := "Complete" if index < reached else ("Current" if index == reached else "Locked")
		story_choices[index].text = "%d. %s\n%s" % [index + 1, Story.STEPS[index]["title"], state]
		story_choices[index].disabled = index > reached
		story_choices[index].set_pressed_no_signal(index == story_selected)
	var step: Dictionary = Story.STEPS[story_selected]
	var current := story_selected == reached
	contract_title.text = step["title"]
	contract_preview.visible = step.has("kind")
	if step.has("kind"):
		contract_preview.show_kind(step["kind"])
	contract_progress.visible = true
	contract_progress.max_value = step["required"]
	if current:
		var scan := sector.story_sites.scan_seconds if is_instance_valid(sector.story_sites) else 0.0
		contract_objective.text = Story.objective(story, scan)
		contract_progress.value = minf(scan, step["required"]) if step["type"] == "scan" else story["progress"]
	else:
		contract_objective.text = step["objective"] + "  /  COMPLETE"
		contract_progress.value = step["required"]
	story_briefing.text = "%s\n%s" % [Story.CONTACTS[step["contact"]]["name"].to_upper(), step["briefing"]]
	story_portrait.texture = StorySites.portrait(step["contact"])
	story_tip.text = "TIP: " + Story.hint(step) if current else step["done"]
	contract_reward.text = "Reward    " + Story.reward_text(step["credits"], step["research"])
	var pending := sector.session.combat.station_pending
	story_deliver.visible = current and step["type"] == "deliver"
	var status := blocker
	if story_deliver.visible:
		var needed := CargoResources.describe({step["resource"]: step["required"]})
		story_deliver.text = "DELIVER " + needed.to_upper()
		if status.is_empty() and int(sector.cargo.get(step["resource"], 0)) < int(step["required"]):
			status = "Need %s in your active ship's cargo." % needed
	story_deliver.disabled = not status.is_empty() or pending
	story_skip.visible = not Story.complete(story)
	story_skip.text = "CONFIRM SKIP / PAY REMAINING REWARDS" if story_skip_armed else "SKIP PROLOGUE"
	story_skip.disabled = not blocker.is_empty() or pending
	contract_status.text = status.replace("to repair.", "to manage quests.").replace("Repairs available", "Quest actions available")
	contract_status.visible = not status.is_empty()
	story_deliver.tooltip_text = contract_status.text


func text_at(point: Vector2, text: String, size_px: int = 16, color: Color = INK, width: float = -1.0) -> void:
	# Fit long contact names and rebound keys without drawing outside their card.
	if width > 0:
		size_px = fit_pixels(text, size_px, width)
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, color)


static func fit_pixels(text: String, pixels: int, width: float) -> int:
	# Largest size down to 12 px that fits; measured again only for new text or bounds.
	var entry: Array = fitted.get(text, NO_FIT)
	if not entry.is_empty() and entry[0] == pixels and entry[1] == width:
		return entry[2]
	var result := pixels
	while result > 12 and StationUi.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, result).x > width:
		result -= 1
	if fitted.size() >= 256:
		fitted.clear()
	fitted[text] = [pixels, width, result]
	return result


func bound(template: String, first: String, second: String = "") -> String:
	# Each template names the same actions wherever it is used.
	if phrases_revision != GameSettings.binding_revision:
		phrases.clear()
		phrases_revision = GameSettings.binding_revision
	var text: String = phrases.get(template, "")
	if text.is_empty():
		text = template % GameSettings.binding_text(first) if second.is_empty() else template % [GameSettings.binding_text(first), GameSettings.binding_text(second)]
		phrases[template] = text
	return text


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
	var story := story_height()
	if story > 0.0:
		return Rect2(SIDE_MARGIN, TOP_MARGIN, 280, 48 + story + (rows * 34 if rows > 0 else 14))
	return Rect2(SIDE_MARGIN, TOP_MARGIN, 280, 48 + rows * 34 if rows > 0 else 110)


# Height of the flight card's story section, or zero without a current step.
func story_height() -> float:
	var story := sector.story_state()
	if story.is_empty() or Story.complete(story):
		return 0.0
	var key := Vector2i(int(story["step"]), GameSettings.binding_revision)
	if key != story_hint_key:
		story_hint_key = key
		story_hint = Story.hint(Story.current(story))
		story_hint_height = font.get_multiline_string_size(story_hint, HORIZONTAL_ALIGNMENT_LEFT, 244, 14).y
	return 58.0 + story_hint_height


func draw_story(rect: Rect2) -> void:
	var story := sector.story_state()
	var step := Story.current(story)
	text_at(rect.position + Vector2(18, 66), "%d / %d  %s" % [int(story["step"]) + 1, Story.STEPS.size(), str(step["title"]).to_upper()], 16, GOLD, 244)
	text_at(rect.position + Vector2(18, 90), Story.objective(story, sector.story_sites.scan_seconds), 15, INK, 244)
	paragraph(rect.position + Vector2(18, 112), story_hint, 244, 14, MUTED)


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
	var story := story_height()
	card_title(rect, "OPERATIONS" if story > 0.0 else ("HUNTING CONTRACTS" if sector.session.active else "OBJECTIVE"))
	if story > 0.0:
		draw_story(rect)
		if sector.active_contracts.is_empty():
			return
	if sector.session.active and not sector.active_contracts.is_empty():
		var row := rect.position + Vector2(18, 66 + story)
		if story > 0.0:
			draw_line(Vector2(rect.position.x + 18, row.y - 23), Vector2(rect.end.x - 18, row.y - 23), LINE)
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
		var objective := "No active hunts. Choose contracts at Outpost 01 [C]."
		if not sector.session.active:
			match sector.objective_stage:
				0: objective = bound("Leave the outpost. %s to fly forward.", "forward")
				1: objective = bound("Find an alien. %s or %s to select.", "cycle_target", "select_target")
				2: objective = bound("%s to fire. Keep the alien ahead and in range.", "fire")
				3: objective = bound("Return to Outpost 01. Slow down and press %s to repair.", "repair")
				_: objective = "Encounter complete. Hunt another alien."
		paragraph(rect.position + Vector2(18, 64), objective, rect.size.x - 36)


func refresh_control_hints(pixels: int) -> void:
	var state := Vector3i(GameSettings.binding_revision, int(sector.map_id == 0), pixels)
	if state == control_hints_state:
		return
	# Keys and widths change only with bindings, the home map or text size.
	control_hints_state = state
	control_hints.clear()
	for entry: Array in CONTROL_HINTS:
		if entry[0] == "repair" and sector.map_id != 0:
			entry = ["jump_gate", "Jump"]
		var key := GameSettings.binding_text(entry[0])
		control_hints.append([key, font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x + 14, entry[1], font.get_string_size(entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x])


func draw_controls() -> void:
	var point := Vector2(SIDE_MARGIN, size.y - 28)
	var pixels := 14 if size.x < 1200 else 16
	refresh_control_hints(pixels)
	for hint: Array in control_hints:
		var key_width: float = hint[1]
		draw_style_box(background, Rect2(point - Vector2(0, 18), Vector2(key_width, 26)))
		text_at(point + Vector2(7, 0), hint[0], pixels)
		point.x += key_width + 8
		text_at(point, hint[2], pixels, MUTED)
		point.x += hint[3] + 20


func draw_context() -> void:
	if not layout.begin_draw(self, "context"):
		return
	var point := Vector2(SIDE_MARGIN, objectives_rect().end.y + 12)
	var width := minf(440, size.x - 2 * SIDE_MARGIN - 322)
	if is_instance_valid(sector.story_sites) and sector.story_sites.comm_time > 0.0:
		# Contact transmissions stay on screen independently of ordinary notices.
		# Each speaker's line sits beside their portrait.
		var lines: Array = sector.story_sites.comm_lines
		var text_x := 12.0 + PORTRAIT + 12.0
		var text_width := width - text_x - 12.0
		var heights: Array[float] = []
		var total := 32.0
		for line: Array in lines:
			var height := maxf(PORTRAIT, 22.0 + font.get_multiline_string_size(line[1], HORIZONTAL_ALIGNMENT_LEFT, text_width, 15).y)
			heights.append(height)
			total += height + 10.0
		var comm_rect := Rect2(point, Vector2(width, total))
		panel(comm_rect, CYAN)
		text_at(point + Vector2(12, 18), "INCOMING TRANSMISSION", 12, CYAN)
		var row := point.y + 30.0
		for index in lines.size():
			var contact: String = lines[index][0]
			var frame := Rect2(point.x + 12, row, PORTRAIT, PORTRAIT)
			draw_texture_rect(StorySites.portrait(contact), frame, false)
			draw_rect(frame, Color(CYAN, 0.75), false, 1.0)
			text_at(Vector2(point.x + text_x, row + 12), Story.CONTACTS[contact]["name"].to_upper(), 12, CYAN, text_width)
			paragraph(Vector2(point.x + text_x, row + 32), lines[index][1], text_width, 15, INK)
			row += heights[index] + 10.0
		marker_labels.append(layout.transform_rect("context", comm_rect))
		point.y = comm_rect.end.y + 8
	var messages: Array[String] = []
	for destination: int in SectorMaps.links(sector.map_id):
		if sector.player.position.distance_to(SectorMaps.gate_position(sector.map_id, destination)) <= SectorMaps.JUMP_RADIUS:
			var place := "THE VASHAR RIFT" if destination == GalaxyGates.MAP else SectorMaps.code(destination)
			messages.append("%s / JUMP TO %s / GATE PROTECTED" % [GameSettings.binding_text("jump_gate"), place])
	var run := gate_status()
	if not run.is_empty():
		messages.append(run)
	if CargoResources.units(sector.cargo) >= sector.cargo_capacity:
		messages.append("CARGO FULL / SELL AT OUTPOST 01 [B]")
	if sector.toast_time > 0:
		messages.append(sector.toast)
	if sector.client_only and not sector.session.active:
		messages.append("DISCONNECTED / " + sector.session.status)
	if layout.editing and messages.is_empty():
		messages.append("Notifications appear here.")
	for message: String in messages:
		var dimensions := font.get_multiline_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, width - 24, 16)
		var rect := Rect2(point, Vector2(width, dimensions.y + 16))
		draw_style_box(background, rect)
		paragraph(point + Vector2(12, 20), message, width - 24, 16, AMBER)
		marker_labels.append(layout.transform_rect("context", rect))
		point.y = rect.end.y + 8
	layout.end_draw(self)


# Centered under the destination card, clear of the side cards and the reticle.
func tutorial_rect() -> Rect2:
	return Rect2((size.x - 300) * 0.5, navigation.guidance_rect().end.y + 12, 300, 130)


func draw_tutorial() -> void:
	var sites := sector.story_sites
	var live := is_instance_valid(sites) and not sites.tips.is_empty()
	if not live and not layout.editing:
		return
	# The editor previews the first step's rows when no pop-up is open.
	var tips: Array = sites.tips if live else Story.CONTROLS["comms_check"]
	if not layout.begin_draw(self, "tutorial"):
		return
	var rect := tutorial_rect()
	card_title(rect, "CONTROLS", CYAN)
	var key := Vector2i(sites.seen_step if live else -1, GameSettings.binding_revision)
	if key != tip_keys_key:
		tip_keys_key = key
		tip_keys.clear()
		for row: Array in tips:
			var labels: PackedStringArray = []
			for action: String in row[0]:
				labels.append(GameSettings.binding_text(action))
			var caption := " / ".join(labels)
			tip_keys.append([caption, font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14])
	var point := rect.position + Vector2(18, 64)
	for index in tips.size():
		var done: bool = live and sites.tips_used[index]
		var key_width: float = tip_keys[index][1]
		draw_style_box(background, Rect2(point - Vector2(0, 17), Vector2(key_width, 24)))
		text_at(point + Vector2(7, 0), tip_keys[index][0], 14, GREEN if done else INK)
		var label_x := key_width + 10
		text_at(point + Vector2(label_x, 0), tips[index][1], 14, GREEN if done else MUTED, rect.size.x - 36 - label_x - 20)
		if done:
			var mark := Vector2(rect.end.x - 30, point.y - 6)
			draw_polyline(PackedVector2Array([mark, mark + Vector2(4, 4), mark + Vector2(11, -5)]), GREEN, 2.0)
		point.y += 26
	layout.end_draw(self)
	marker_labels.append(layout.rect_for("tutorial"))


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
	var away := player.map_id != 0 or player.global_position.distance_to(Sector.STATION_POSITION) > Sector.REPAIR_RADIUS
	if not layout.editing and (not player.alive or (away and player.repair_seconds <= 0.0)):
		return
	if not layout.begin_draw(self, "station"):
		return
	var rect := Rect2(target_rect().position - Vector2(0, 88 if sector.session.active else 66), Vector2(290, 78 if sector.session.active else 56))
	draw_style_box(background, rect)
	if away and not layout.editing:
		text_at(rect.position + Vector2(12, 21), bound("%s  REPAIR ROBOT", "repair"), 16, AMBER)
		text_at(rect.position + Vector2(12, 43), "REPAIRING HULL" if player.robot_repairing else "Stay outside combat", 16, GREEN, 266)
		layout.end_draw(self)
		marker_labels.append(layout.rect_for("station"))
		return
	text_at(rect.position + Vector2(12, 21), "B  SHOP / CARGO     I  EQUIPMENT", 16, AMBER)
	var label := "%s / %s CR" % [bound("%s  REPAIR", "repair"), number(sector.repair_cost())]
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
	for id: String in CARDS:
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
	draw_tutorial()
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
	if sector.map_id == 0:
		marker(Sector.STATION_POSITION, "OUTPOST 01", GREEN, false)
	var site := Story.site(sector.story_state(), sector.map_id)
	if not site.is_empty():
		marker(Story.site_position(site), "OBJECTIVE / " + str(site["site"]).to_upper(), GOLD, false)
	for destination: int in SectorMaps.links(sector.map_id):
		marker(SectorMaps.gate_position(sector.map_id, destination), SectorMaps.gate_label(destination), SectorMaps.MAPS[destination]["color"], false, null, false)
	if is_instance_valid(sector.target):
		alien_marker(sector.target as Alien)
	for id: int in sector.loot.drops:
		if sector.loot.is_presented(id):
			var drop: Dictionary = sector.loot.drops[id]
			var parts := int(drop.get("parts", 0))
			marker(drop["position"], "LOOT %d UNITS%s / FLY CLOSE" % [CargoResources.units(drop["resources"]), " + %d GATE PART%s" % [parts, "" if parts == 1 else "S"] if parts > 0 else ""], VasharModels.GLOW if parts > 0 else AMBER, false, null, false)
	for alien_id: int in sector.aliens:
		var enemy := sector.aliens[alien_id]
		if enemy != sector.target and enemy.alive and enemy.visible:
			alien_marker(enemy)
	if sector.session.active:
		for id: int in sector.session.ships:
			var ship := sector.session.ships[id]
			if ship != player and ship.alive and ship.map_id == sector.map_id and not ship.get_meta("docked", false):
				marker(ship.global_position, "FRIEND %s" % id, CYAN, false, ship)
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
	card_title(rect, "%s %d / %d m" % [enemy.kind.to_upper(), enemy.alien_id % 100 + 1, sector.player.global_position.distance_to(enemy.global_position)] if is_instance_valid(enemy) else "NO TARGET", RED if is_instance_valid(enemy) else MUTED)
	var origin := rect.position + Vector2(18, 64)
	if not is_instance_valid(sector.target) or not sector.target.alive:
		paragraph(origin, bound("%s or %s to lock", "cycle_target", "select_target"), 250)
		text_at(origin + Vector2(0, 42), "%d ALIENS DESTROYED" % sector.kills, 16, MUTED)
		text_at(origin + Vector2(0, 86), "M / Choose a contact on the map", 16, MUTED, 250)
		return
	meter(origin, "SHIELD", enemy.shield, enemy.max_shield, CYAN)
	meter(origin + Vector2(0, 43), "HULL", enemy.hull, enemy.max_hull, RED)
	paragraph(origin + Vector2(0, 81), fire_feedback(), 250, 16, RED if sector.auto_fire and not sector.weapon_status.is_empty() else MUTED)


func alien_marker(enemy: Alien) -> void:
	marker(enemy.global_position, "HOSTILE %s %d%s" % [enemy.kind.to_upper(), enemy.alien_id % 100 + 1, " / RETURNING" if enemy.returning else ""], AMBER if sector.target == enemy else enemy.tuning()["color"], sector.target == enemy, null, sector.target == enemy)


func draw_boundary_warning() -> void:
	var player := sector.player
	if not player.alive or (sector.client_only and not sector.session.active):
		return
	var local := player.position - SectorMaps.origin(sector.map_id)
	var remaining := Sector.MAP_RADIUS - local.length()
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
		var safe_point := SectorMaps.origin(sector.map_id) + local.normalized() * (Sector.MAP_RADIUS - 50.0)
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
	for corner: Vector2 in CORNERS:
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
		if not bounds.encloses(rect) or occupied(rect):
			continue
		marker_labels.append(rect)
		draw_style_box(background, rect)
		text_at(rect.position + Vector2(5, 16), caption, 14, color)
		return


func occupied(rect: Rect2) -> bool:
	for label: Rect2 in marker_labels:
		if label.intersects(rect):
			return true
	return false


# One-line Vashar Gate run status: wave and lives inside the rift, an invitation at M1.
func gate_status() -> String:
	var run: Dictionary = sector.session.combat.gate_summary if is_instance_valid(sector.session) else {}
	if not run.get("active", false):
		return ""
	if sector.map_id == GalaxyGates.MAP:
		if run["phase"] == "victory":
			return "VASHAR GATE CLEARED / RETURN THROUGH THE GATE"
		var wave := "FIRST WAVE INCOMING" if run["phase"] == "waiting" else "WAVE %d OF %d" % [run["wave"], run["waves"]]
		return "VASHAR GATE / %s / %d LIVES" % [wave, run["lives"]]
	if sector.map_id == 0 and run.get("open", false):
		return "VASHAR GATE OPEN NEAR OUTPOST 01 / %d LIVES" % run["lives"] if run["lives"] > 0 else "VASHAR GATE OPEN / NO LIVES LEFT"
	return ""
