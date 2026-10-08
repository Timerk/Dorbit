extends SceneTree
## External export smoke test: the actual --offline launch and Windows key events.

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func modifier(code: Key, pressed: bool, other_held: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.location = KEY_LOCATION_LEFT
	event.pressed = pressed
	# Godot's Windows backend excludes a modifier's own flag.
	event.ctrl_pressed = other_held and code == KEY_ALT
	event.alt_pressed = other_held and code == KEY_CTRL
	root.push_input(event)
	await process_frame


func run() -> void:
	var sector: Sector = load("res://scenes/sector.tscn").instantiate()
	root.add_child(sector)
	sector.set_physics_process(false)
	await process_frame
	await process_frame
	sector.hud.layout.save_path = "user://hud-shortcut-export-test.cfg"
	check(sector.offline and sector.preflight, "The exported client starts in the offline main menu")
	sector.main_menu.start_button.pressed.emit()
	await process_frame
	check(not sector.preflight and not sector.paused, "Offline Start launches flight")
	await modifier(KEY_CTRL, true)
	check(not sector.hud.layout.editing, "Control alone cannot open the editor")
	await modifier(KEY_ALT, true, true)
	check(sector.hud.layout.editing and sector.hud.layout.sidebar.visible, "Native Ctrl-then-Alt opens the exported offline HUD editor")
	var layout := sector.hud.layout
	layout.entries["reticle"] = {"position": Vector2(0.9, 0.1), "scale": 2.0, "visible": true}
	check(layout.rect_for("reticle").get_center().is_equal_approx(layout.size * 0.5), "The exported reticle ignores saved position and stays centered")
	check(layout.rect_for("reticle").size.is_equal_approx(layout.default_rect("reticle").size * 2.0), "The exported reticle still supports custom sizing")
	layout.entries.erase("reticle")
	await modifier(KEY_ALT, false, true)
	await modifier(KEY_CTRL, false)
	await modifier(KEY_ALT, true)
	await modifier(KEY_CTRL, true, true)
	check(not sector.hud.layout.editing and not sector.paused, "Native Alt-then-Ctrl finishes editing and resumes offline flight")
	await modifier(KEY_CTRL, false, true)
	await modifier(KEY_ALT, false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sector.hud.layout.save_path))
	print("Exported HUD shortcut: %d passed, %d failed" % [checks - failures, failures])
	sector.free()
	quit(0 if failures == 0 else 1)
