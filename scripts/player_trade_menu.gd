class_name PlayerTradeMenu
extends PanelContainer
## Modal trade review using private server offers. Editing is local until Update
## offer is pressed; confirmation is disabled while those edits are unsent.

var sector: Sector
var shade: ColorRect
var partner: Label
var pilots: OptionButton
var invite_button: Button
var refresh_button: Button
var columns: HBoxContainer
var own_items: VBoxContainer
var other_items: VBoxContainer
var credits: SpinBox
var other_credits: Label
var own_status: Label
var other_status: Label
var status: Label
var update_button: Button
var confirm_button: Button
var selected: Dictionary = {}
var last_state: Dictionary = {}
var last_candidates: Array = []
var last_revision := -1
var dirty := false
var rebuilding := false


func _ready() -> void:
	# The Hangar attaches the input blocker before this panel so it stays behind
	# the controls for both drawing and input, without deferred orphan nodes.
	visibility_changed.connect(func(): shade.visible = visible)
	theme = StationUi.menu_theme()
	StationUi.frame(self, Vector2(880, 610))
	get_viewport().size_changed.connect(fit_window)
	var rows := StationUi.rows(self, 18)
	StationUi.header(rows, "PLAYER TRADE", "OUTPOST 01", 30)
	partner = StationUi.text(rows, "Choose a pilot at Outpost 01.", 19)
	var selection := HBoxContainer.new()
	rows.add_child(selection)
	pilots = OptionButton.new()
	pilots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection.add_child(pilots)
	invite_button = StationUi.button(selection, "INVITE", invite)
	refresh_button = StationUi.button(selection, "REFRESH PILOTS", func(): sector.session.combat.request_trade("snapshot"))
	columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	rows.add_child(columns)
	for own: bool in [true, false]:
		var card := StationUi.card(columns)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_stretch_ratio = 1.0
		var content := StationUi.rows(card, 12)
		StationUi.heading(content, "YOUR OFFER" if own else "THEIR OFFER", 20)
		if own:
			credits = SpinBox.new()
			credits.min_value = 0
			credits.max_value = PilotStore.MAX_CREDITS
			credits.step = 1
			credits.suffix = " CR"
			content.add_child(credits)
			credits.value_changed.connect(func(_value: float): mark_dirty())
			StationUi.text(content, "Select up to %d stored items." % PlayerTrading.MAX_ITEMS, 15, StationUi.MUTED)
		else:
			other_credits = StationUi.text(content, "0 CR", 22, StationUi.AMBER)
			StationUi.text(content, "Review every item before confirming.", 15, StationUi.MUTED)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		content.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		scroll.add_child(list)
		var confirmation := StationUi.text(content, "Not confirmed", 17, StationUi.MUTED)
		if own:
			own_items = list
			own_status = confirmation
		else:
			other_items = list
			other_status = confirmation
	StationUi.text(rows, "Both pilots must confirm. Updating either offer clears both confirmations.", 16, StationUi.MUTED)
	status = StationUi.text(rows, "", 16, StationUi.AMBER)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	update_button = StationUi.button(buttons, "UPDATE OFFER", update_offer)
	confirm_button = StationUi.button(buttons, "CONFIRM TRADE", confirm)
	StationUi.primary(confirm_button)
	StationUi.button(buttons, "CANCEL / CLOSE", close)
	fit_window()
	hide()
	shade.hide()


func fit_window() -> void:
	StationUi.centered(self, Vector2(880, 610))


func open() -> void:
	if not StationUi.blocker(sector).is_empty(): return
	last_revision = -1
	dirty = false
	show()
	fit_window()
	sector.session.combat.request_trade("snapshot")
	refresh()
	if confirm_button.visible: confirm_button.grab_focus()
	else: pilots.grab_focus()


func close() -> void:
	var combat := sector.session.combat
	if sector.session.active and not combat.trade_state.is_empty():
		# Cancel can safely race a pending offer; reliable delivery preserves order.
		combat.trade_request.rpc_id(1, "cancel", combat.trade_state["token"], combat.trade_state["version"], {}, int(sector.player.get_meta("life", 0)))
	hide()


func _input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		# Keep Tab navigation inside the modal instead of reaching Hangar actions.
		var controls: Array[Control] = []
		for control: Control in find_children("*", "Control", true, false):
			if control.focus_mode != Control.FOCUS_ALL or not control.is_visible_in_tree(): continue
			if control is BaseButton and control.disabled: continue
			if control is LineEdit and not control.editable: continue
			controls.append(control)
		if not controls.is_empty():
			var index := controls.find(get_viewport().gui_get_focus_owner())
			index = posmod(index + (-1 if event.is_action_pressed("ui_focus_prev") else 1), controls.size())
			controls[index].grab_focus()
		get_viewport().set_input_as_handled()


func mark_dirty() -> void:
	if not rebuilding: dirty = true


func invite() -> void:
	if pilots.selected >= 0:
		sector.session.combat.request_trade("invite", {"peer": pilots.get_item_id(pilots.selected)})


func update_offer() -> void:
	credits.apply()
	dirty = false
	sector.session.combat.request_trade("offer", {"items": selected.keys(), "credits": int(credits.value)})


func confirm() -> void:
	# A typed SpinBox value may not have lost focus when the button is pressed.
	credits.apply()
	if dirty: return
	var state := sector.session.combat.trade_state
	sector.session.combat.request_trade("join" if not state.get("joined", false) else "confirm")


func clear_rows(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func item_text(item: Dictionary) -> String:
	var text: String = Equipment.MODELS[item["model"]]["name"]
	if item.has("enabled"):
		text += " / " + ("Auto on" if item["enabled"] else "Auto off")
	if item.has("ammo_type"): text += " / " + item["ammo_type"]
	return text


func refresh() -> void:
	var combat := sector.session.combat
	var state := combat.trade_state
	var active := not state.is_empty()
	var joined: bool = state.get("joined", false)
	var revision := int(combat.inventory.get("revision", -1))
	if not is_same(last_candidates, combat.trade_candidates):
		var chosen := pilots.get_selected_id() if pilots.selected >= 0 else -1
		pilots.clear()
		for pilot: Dictionary in combat.trade_candidates:
			pilots.add_item(pilot["name"], pilot["peer"])
			if pilot["peer"] == chosen: pilots.select(pilots.item_count - 1)
		if pilots.item_count == 0: pilots.text = "No available pilots. Refresh to check again."
		last_candidates = combat.trade_candidates
	var changed := not is_same(last_state, state) or revision != last_revision
	if changed:
		rebuilding = true
		if state.get("token", "") != last_state.get("token", "") or revision != last_revision:
			dirty = false
		if not dirty:
			selected.clear()
			for id: String in state.get("own", {}).get("items", []): selected[id] = true
			credits.set_value_no_signal(state.get("own", {}).get("credits", 0))
		clear_rows(own_items)
		for id: String in combat.inventory.get("items", {}):
			var item: Dictionary = combat.inventory["items"][id]
			if not item["ship"].is_empty(): continue
			var check := CheckButton.new()
			check.text = item_text(item)
			check.icon = StationUi.texture(item["model"])
			check.expand_icon = true
			check.add_theme_constant_override("icon_max_width", 42)
			check.tooltip_text = StationUi.bonus(item["model"])
			check.button_pressed = selected.has(id)
			check.toggled.connect(func(on: bool):
				if on: selected[id] = true
				else: selected.erase(id)
				mark_dirty())
			own_items.add_child(check)
		if own_items.get_child_count() == 0:
			StationUi.text(own_items, "No stored equipment. Remove fitted items in the Hangar first.", 16, StationUi.MUTED)
		clear_rows(other_items)
		for item: Dictionary in state.get("other", {}).get("items", []):
			var row := HBoxContainer.new()
			other_items.add_child(row)
			StationUi.art(row, item["model"], Vector2(42, 42)).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			var label := StationUi.text(row, item_text(item), 17)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.tooltip_text = StationUi.bonus(item["model"])
		if other_items.get_child_count() == 0:
			StationUi.text(other_items, "No items offered", 16, StationUi.MUTED)
		other_credits.text = StationShop.credits_text(state.get("other", {}).get("credits", 0)) + " CR"
		last_state = state
		last_revision = revision
		rebuilding = false
	partner.text = "Trading with %s" % state["partner"] if active else "Choose a pilot at Outpost 01."
	pilots.get_parent().visible = not active
	columns.visible = active
	var waiting := combat.trade_pending or combat.station_pending
	var blocked := StationUi.blocker(sector)
	invite_button.disabled = waiting or pilots.item_count == 0 or not blocked.is_empty()
	refresh_button.disabled = waiting
	credits.editable = joined and not waiting and not state.get("confirmed", false)
	for child in own_items.get_children():
		if child is CheckButton: child.disabled = not joined or waiting or state.get("confirmed", false)
	update_button.visible = joined
	update_button.disabled = waiting or not dirty or selected.size() > PlayerTrading.MAX_ITEMS or not blocked.is_empty()
	confirm_button.visible = active and (joined or not state["inviter"])
	confirm_button.text = "ACCEPT INVITATION" if not joined else "CONFIRM TRADE"
	confirm_button.disabled = waiting or dirty or state.get("confirmed", false) or not blocked.is_empty()
	own_status.text = "Confirmed" if state.get("confirmed", false) else "Not confirmed"
	other_status.text = "Confirmed" if state.get("other_confirmed", false) else "Not confirmed"
	own_status.modulate = Color("a7e277") if state.get("confirmed", false) else Color.WHITE
	other_status.modulate = Color("a7e277") if state.get("other_confirmed", false) else Color.WHITE
	var hint := "Update your offer to send these changes." if dirty else ("Waiting for invitation acceptance." if active and not joined else "")
	if state.get("confirmed", false): hint = "Waiting for the other pilot. Cancel to withdraw your confirmation."
	if selected.size() > PlayerTrading.MAX_ITEMS: hint = "Select at most %d items." % PlayerTrading.MAX_ITEMS
	status.text = blocked if not blocked.is_empty() else (combat.trade_message if not combat.trade_message.is_empty() else hint)
	status.visible = not status.text.is_empty()


func _process(_delta: float) -> void:
	if not visible: return
	if not sector.session.active or not sector.equipment_menu.visible:
		close()
		return
	refresh()
	fit_window()
