class_name EquipmentTile
extends Button
## One owned item or one empty slot. All moves use the equipment screen's rules.

var screen: ShipEquipment
var item_id: String = ""
var slot: String = ""
var compact: bool = false
var caption: Label
var artwork: TextureRect


func _ready() -> void:
	custom_minimum_size = Vector2(72, 64 if compact else 86)
	add_theme_stylebox_override("normal", StationUi.style(Color("102235"), Color("37546c")))
	add_theme_stylebox_override("hover", StationUi.style(Color("1c3548"), FlightHud.CYAN))
	add_theme_stylebox_override("focus", StationUi.style(Color(0, 0, 0, 0), FlightHud.CYAN))
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 6
	rows.offset_right = -6
	rows.offset_top = 5
	rows.offset_bottom = -5
	add_child(rows)
	artwork = TextureRect.new()
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.custom_minimum_size.y = 32 if compact else 50
	artwork.size_flags_vertical = Control.SIZE_EXPAND_FILL
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(artwork)
	caption = StationUi.text(rows, "", 12)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pressed.connect(func(): screen.choose(self))
	mouse_entered.connect(func(): screen.inspect_tile(self))
	focus_entered.connect(func(): screen.inspect_tile(self))
	refresh()


func refresh() -> void:
	var item: Dictionary = screen.inventory().get("items", {}).get(item_id, {})
	if item.is_empty():
		var kind: String = screen.slots_kind(slot)
		if kind == "extra":
			artwork.texture = null
			caption.text = "EXTRA"
			tooltip_text = "Extra slot reserved for future equipment."
			return
		artwork.texture = StationUi.texture("laser" if kind == "laser" else "shield")
		artwork.modulate = Color(1, 1, 1, 0.18)
		caption.text = "EMPTY"
		tooltip_text = "Empty %s slot. Drag compatible equipment here." % kind
		add_theme_stylebox_override("normal", StationUi.style(Color("0b1928"), Color("294156")))
	else:
		var model: String = item["model"]
		artwork.modulate = Color.WHITE
		artwork.texture = StationUi.texture(model)
		caption.text = "ION" if model == "engine" else Equipment.MODELS[model]["name"]
		tooltip_text = "%s\n%s\n%s" % [Equipment.MODELS[model]["name"], StationUi.bonus(model), "In inventory / Shift-click to equip" if slot.is_empty() else slot.capitalize()]
		add_theme_stylebox_override("normal", StationUi.style(Color("102235"), StationUi.accent(model).darkened(0.5)))
	# The selected tile keeps a visible outline after focus moves to a destination.
	if not item_id.is_empty() and item_id == screen.selected_item:
		add_theme_stylebox_override("normal", StationUi.style(Color("1a3547"), FlightHud.CYAN))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.shift_pressed and slot.is_empty() and not item_id.is_empty():
		screen.quick_equip(item_id)
		accept_event()


func _get_drag_data(_position: Vector2) -> Variant:
	if item_id.is_empty() or not StationUi.blocker(screen.sector).is_empty():
		return null
	screen.select_item(item_id)
	var preview := TextureRect.new()
	preview.texture = artwork.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(72, 72)
	set_drag_preview(preview)
	return {"equipment_item": item_id, "screen": screen}


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return screen.can_drop(data, slot)


func _drop_data(_position: Vector2, data: Variant) -> void:
	screen.drop_item(data, slot)
