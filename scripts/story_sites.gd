class_name StorySites
extends Node3D
## Client-only presentation of the pilot's story chapter: the current objective site,
## the approach beacon and contact transmissions when the saved step changes.
## The server decides progress; the local scan timer only drives the display.

const GOLD := Color("ffd36b")
const COMM_SECONDS := 26.0
const BEACON_DARK := Color("6b2a24")
const BEACON_LIT := Color("7dffd1")
const GATE_SHADER := preload("res://shaders/objective_gate.gdshader")
const BEAM_SHADER := preload("res://shaders/objective_beam.gdshader")
const FIELD_SHADER := preload("res://shaders/objective_field.gdshader")
const BURST_SECONDS := 0.9
# Gate quads extend past the hoop, which sits at 72% of the quad's radius.
const GATE_SCALE := 1.0 / 0.72
const RECORDER_GATE_RADIUS := 7.0
const BEAM_HALF_HEIGHT := 260.0
# The controls pop-up lingers briefly after every row has been tried.
const TIPS_LINGER := 1.5

var sector: Sector
# The current objective: a waypoint gate or scan field, plus a locator beam.
var site: Node3D
var gate: MeshInstance3D
var field: MeshInstance3D
var field_material: ShaderMaterial
var beam: MeshInstance3D
var recorder: Node3D
var beacon: Node3D
var beacon_lamp: StandardMaterial3D
var beacon_light: OmniLight3D
var beacon_lit := false
var seen_step := -1
var scan_seconds := 0.0
var comm := ""
var comm_time := 0.0
# Rows of the current step's controls pop-up and whether each has been pressed.
var tips: Array = []
var tips_used: Array[bool] = []
var tips_linger := -1.0


func _ready() -> void:
	site = Node3D.new()
	add_child(site)
	gate = effect(GATE_SHADER)
	field = MeshInstance3D.new()
	field.mesh = SphereMesh.new()
	(field.mesh as SphereMesh).radial_segments = 64
	(field.mesh as SphereMesh).rings = 32
	field_material = ShaderMaterial.new()
	field_material.shader = FIELD_SHADER
	field.material_override = field_material
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site.add_child(field)
	beam = effect(BEAM_SHADER)
	beam.scale = Vector3(2.4, BEAM_HALF_HEIGHT, 1.0)
	recorder = Node3D.new()
	var shell := MeshInstance3D.new()
	shell.mesh = BoxMesh.new()
	(shell.mesh as BoxMesh).size = Vector3(1.6, 1.0, 2.2)
	var casing := StandardMaterial3D.new()
	casing.albedo_color = Color("3a4048")
	casing.metallic = 0.85
	casing.roughness = 0.35
	shell.material_override = casing
	recorder.add_child(shell)
	var strip := MeshInstance3D.new()
	strip.mesh = BoxMesh.new()
	(strip.mesh as BoxMesh).size = Vector3(1.7, 0.16, 2.3)
	strip.material_override = glow(Color("ff9a3c"), 1.0)
	recorder.add_child(strip)
	var light := OmniLight3D.new()
	light.light_color = Color("ff9a3c")
	light.omni_range = 14.0
	light.light_energy = 2.0
	recorder.add_child(light)
	site.add_child(recorder)
	beacon = Node3D.new()
	var mast := MeshInstance3D.new()
	mast.mesh = CylinderMesh.new()
	(mast.mesh as CylinderMesh).top_radius = 0.35
	(mast.mesh as CylinderMesh).bottom_radius = 0.8
	(mast.mesh as CylinderMesh).height = 16.0
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("59626b")
	metal.metallic = 0.8
	metal.roughness = 0.4
	mast.material_override = metal
	beacon.add_child(mast)
	var lamp := MeshInstance3D.new()
	lamp.mesh = SphereMesh.new()
	(lamp.mesh as SphereMesh).radius = 1.3
	(lamp.mesh as SphereMesh).height = 2.6
	lamp.position.y = 9.0
	beacon_lamp = glow(BEACON_DARK, 1.0)
	lamp.material_override = beacon_lamp
	beacon.add_child(lamp)
	beacon_light = OmniLight3D.new()
	beacon_light.position.y = 9.0
	beacon_light.omni_range = 60.0
	beacon_light.light_color = BEACON_LIT
	beacon.add_child(beacon_light)
	beacon.position = Story.site_position(Story.STEPS[Story.BEACON_STEP])
	add_child(beacon)
	set_lit(false)
	hide_sites()


# Camera-facing shader quad. Its vertex shader turns the quad, so the cull
# bounds must cover every orientation.
func effect(shader: Shader, parent: Node3D = site) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = shader
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


static func glow(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func set_lit(lit: bool) -> void:
	beacon_lit = lit
	beacon_lamp.albedo_color = BEACON_LIT if lit else BEACON_DARK
	beacon_lamp.emission = beacon_lamp.albedo_color
	beacon_light.visible = lit


func hide_sites() -> void:
	site.hide()
	beacon.hide()


# A short flash and expanding ring where a completed objective stood.
func burst(location: Vector3, radius: float) -> void:
	var flash := effect(GATE_SHADER, self)
	flash.position = location
	flash.scale = Vector3.ONE * radius * GATE_SCALE
	flash.set_instance_shader_parameter("burst", 0.0)
	var tween := flash.create_tween()
	tween.tween_method(func(value: float): flash.set_instance_shader_parameter("burst", value), 0.0, 1.0, BURST_SECONDS)
	tween.tween_callback(flash.queue_free)


func _process(delta: float) -> void:
	comm_time = maxf(0.0, comm_time - delta)
	var story := sector.story_state()
	if story.is_empty():
		seen_step = -1
		scan_seconds = 0.0
		tips = []
		hide_sites()
		return
	observe(story)
	track_tips(delta)
	var step := Story.site(story, sector.map_id)
	beacon.visible = sector.map_id == 0
	if beacon_lit != (int(story["step"]) > Story.BEACON_STEP):
		set_lit(not beacon_lit)
	site.visible = not step.is_empty()
	if step.is_empty():
		scan_seconds = 0.0
		return
	var location := Story.site_position(step)
	var player := sector.player
	var inside: bool = player.alive and player.map_id == step["map"] and player.position.distance_to(location) <= step["radius"]
	scan_seconds = scan_seconds + delta if inside and step["type"] == "scan" else 0.0
	site.position = location
	var scanning: bool = step["type"] == "scan"
	var extent := RECORDER_GATE_RADIUS if step["type"] == "recover" else float(step["radius"])
	(beam.material_override as ShaderMaterial).set_shader_parameter("gap", extent * 1.1 / BEAM_HALF_HEIGHT)
	gate.visible = not scanning
	field.visible = scanning
	recorder.visible = step["type"] == "recover"
	if scanning:
		field.scale = Vector3.ONE * float(step["radius"])
		field_material.set_shader_parameter("progress", scan_seconds / float(step["required"]))
	else:
		gate.scale = Vector3.ONE * extent * GATE_SCALE
	if recorder.visible:
		recorder.rotate_y(delta * 1.2)


func track_tips(delta: float) -> void:
	if not tips.is_empty() and tips_linger >= 0.0:
		tips_linger -= delta
		if tips_linger < 0.0:
			tips = []


# Events rather than polled state, so a quick tap between frames still counts.
func _input(event: InputEvent) -> void:
	if tips.is_empty() or tips_linger >= 0.0 or event.is_echo():
		return
	for index in tips.size():
		for action: String in tips[index][0]:
			if not tips_used[index] and event.is_action_pressed(action):
				tips_used[index] = true
	if not tips_used.has(false):
		tips_linger = TIPS_LINGER


func open_tips(story: Dictionary) -> void:
	tips = Story.CONTROLS.get(Story.current(story).get("id", ""), [])
	tips_used.clear()
	tips_used.resize(tips.size())
	tips_used.fill(false)
	tips_linger = -1.0


func observe(story: Dictionary) -> void:
	var step := int(story["step"])
	if step == seen_step:
		return
	comm = ""
	if seen_step >= 0 and step == seen_step + 1:
		var finished: Dictionary = Story.STEPS[seen_step]
		comm = Story.completion_notice(finished, story)
		if finished["type"] in Story.POSITIONAL and finished["map"] == sector.map_id:
			burst(Story.site_position(finished), RECORDER_GATE_RADIUS if finished["type"] == "recover" else float(finished["radius"]))
		SectorVisuals.sound(sector, "purchase", sector.player.position)
	elif not Story.complete(story):
		comm = Story.transmission(Story.current(story))
	comm_time = COMM_SECONDS if not comm.is_empty() else 0.0
	open_tips(story)
	seen_step = step
	scan_seconds = 0.0
