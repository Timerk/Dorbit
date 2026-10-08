class_name QuickslotTile
extends Button
## Drag payloads are accepted only by their own bar, in slot-edit mode.

var bar: AmmoBar
var slot := -1
var action_id := ""
var key_label: Label
var title: Label
var art: TextureRect
var amount: Label
var selected_style: StyleBoxFlat
var normal_style: StyleBoxFlat
var last_selected := false


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	toggle_mode = true
	selected_style = StationUi.style(Color("172b3b"), FlightHud.AMBER)
	normal_style = StationUi.style(Color("0c141e"), FlightHud.LINE)
	for style_name: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(style_name, normal_style)
	var rows := VBoxContainer.new()
	add_child(rows)
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 4
	rows.offset_right = -4
	rows.offset_top = 2
	rows.offset_bottom = -2
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 0)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(header)
	key_label = StationUi.text(header, "", 12, FlightHud.MUTED)
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title = StationUi.text(header, "", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_stretch_ratio = 3.0
	for label: Label in [key_label, title]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
	art = TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(art)
	amount = StationUi.text(rows, "", 13)
	amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	amount.clip_text = true
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pressed.connect(func():
		if bar.slot_editing:
			if slot >= 0:
				bar.select_slot(slot)
			elif bar.selected_slot >= 0:
				bar.assign_selected(action_id)
			else:
				bar.activate(action_id)
		else:
			bar.activate(action_id))


func refresh(state: Dictionary, shortcut: String) -> void:
	key_label.text = shortcut
	title.text = state.get("name", "Empty")
	art.texture = state.get("icon")
	var compact: bool = bar.config.vertical and slot >= 0
	amount.text = state.get("compact", state.get("count", "")).replace("\n", " ") if compact else state.get("count", "")
	amount.add_theme_font_size_override("font_size", 11 if compact else 13)
	amount.add_theme_color_override("font_color", state.get("color", FlightHud.INK))
	set_pressed_no_signal(state.get("active", false))
	disabled = not bar.slot_editing and (bar.sector.hud.layout.editing or not state.get("available", true))
	tooltip_text = state.get("tooltip", "Empty slot") + ("\nPress %s or click." % shortcut if not shortcut.is_empty() else "")
	if bar.slot_editing:
		tooltip_text += "\nDrag to assign or swap. Click a slot, then an item to assign."
	var selected: bool = state.get("active", false) or (bar.slot_editing and slot >= 0 and slot == bar.selected_slot)
	if selected != last_selected:
		last_selected = selected
		for style_name: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			add_theme_stylebox_override(style_name, selected_style if selected else normal_style)


func _get_drag_data(_position: Vector2) -> Variant:
	if not bar.slot_editing or action_id.is_empty():
		return null
	set_drag_preview(make_drag_preview())
	return {"bar": bar, "slot": slot, "action": action_id}


func make_drag_preview() -> Control:
	# Copy the displayed contents, without the live tile's script or callbacks.
	var preview := Control.new()
	preview.name = "QuickslotDragPreview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.z_as_relative = false
	preview.z_index = 100 # Above the category picker and HUD instruments.
	var tile := Button.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.focus_mode = Control.FOCUS_NONE
	tile.size = size
	tile.scale = get_global_transform().get_scale()
	tile.position = -tile.size * tile.scale * 0.5
	for style_name: String in ["normal", "hover", "pressed", "disabled"]:
		tile.add_theme_stylebox_override(style_name, get_theme_stylebox("normal"))
	preview.add_child(tile)
	tile.add_child(get_child(0).duplicate())
	return preview


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return bar.slot_editing and slot >= 0 and data is Dictionary and data.get("bar") == bar and Quickslots.valid_id(data.get("action"))


func _drop_data(_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_position, data):
		return
	if data.get("slot", -1) >= 0:
		bar.config.swap(data["slot"], slot)
	else:
		bar.config.assign(slot, data["action"])
