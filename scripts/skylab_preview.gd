class_name SkylabPreview
extends TextureRect
## Approved original station illustration; live navigation is drawn separately.

const SCENE = preload("res://assets/ui/skylab/station.png")
const POSITIONS := {
	"solar": Vector2(.50, .15), "basic": Vector2(.50, .75),
	"storage": Vector2(.32, .69), "transport": Vector2(.20, .84),
	"prometiumCollector": Vector2(.33, .275), "enduriumCollector": Vector2(.33, .405), "terbiumCollector": Vector2(.33, .535),
	"prometidRefinery": Vector2(.635, .30), "duraniumRefinery": Vector2(.635, .43),
	"promeriumRefinery": Vector2(.635, .57), "xeno": Vector2(.78, .565), "sepromRefinery": Vector2(.665, .72),
}
var connectors: Dictionary = {}
var selected := ""


func _ready() -> void:
	texture = SCENE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func image_rect() -> Rect2:
	var ratio := SCENE.get_size()
	var fitted := ratio * maxf(size.x / ratio.x, size.y / ratio.y)
	return Rect2((size - fitted) / 2, fitted)


func point(id: String) -> Vector2:
	var bounds := image_rect()
	return bounds.position + POSITIONS[id] * bounds.size


func set_connectors(value: Dictionary, module: String) -> void:
	if connectors == value and selected == module: return
	connectors = value
	selected = module
	queue_redraw()


func _draw() -> void:
	for id: String in connectors:
		var start: Vector2 = connectors[id]
		var end := point(id)
		var direction := 1.0 if end.x > start.x else -1.0
		var elbow := Vector2(start.x + direction * 18, start.y)
		var tint := StationUi.AMBER if id == selected else Color("7d909d", .75)
		draw_polyline(PackedVector2Array([start, elbow, end]), tint, 1.0, true)
		draw_circle(end, 2.4, StationUi.AMBER)
		if id == selected: draw_arc(end, 16, 0, TAU, 48, StationUi.AMBER, 1.2, true)
