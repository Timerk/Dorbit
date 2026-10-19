class_name StorySites
extends Node3D
## Client-only presentation of the pilot's story chapter: the current objective site,
## the approach beacon and contact transmissions when the saved step changes.
## The server decides progress; the local scan timer only drives the display.

const GOLD := Color("ffd36b")
const COMM_SECONDS := 26.0
const BEACON_DARK := Color("6b2a24")
const BEACON_LIT := Color("7dffd1")

var sector: Sector
var ring: MeshInstance3D
var recorder: Node3D
var beacon: Node3D
var beacon_lamp: StandardMaterial3D
var beacon_light: OmniLight3D
var beacon_lit := false
var seen_step := -1
var scan_seconds := 0.0
var comm := ""
var comm_time := 0.0


func _ready() -> void:
	ring = MeshInstance3D.new()
	ring.mesh = TorusMesh.new()
	ring.material_override = glow(GOLD, 0.55)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	recorder = Node3D.new()
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	(box.mesh as BoxMesh).size = Vector3(1.6, 1.0, 2.2)
	box.material_override = glow(Color("ff9a3c"), 1.0)
	recorder.add_child(box)
	var light := OmniLight3D.new()
	light.light_color = Color("ff9a3c")
	light.omni_range = 14.0
	light.light_energy = 2.0
	recorder.add_child(light)
	add_child(recorder)
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
	ring.hide()
	recorder.hide()
	beacon.hide()


func _process(delta: float) -> void:
	comm_time = maxf(0.0, comm_time - delta)
	var story := sector.story_state()
	if story.is_empty():
		seen_step = -1
		scan_seconds = 0.0
		hide_sites()
		return
	observe(story)
	var step := Story.site(story, sector.map_id)
	beacon.visible = sector.map_id == 0
	if beacon_lit != (int(story["step"]) > Story.BEACON_STEP):
		set_lit(not beacon_lit)
	ring.visible = not step.is_empty() and step["type"] != "recover"
	recorder.visible = not step.is_empty() and step["type"] == "recover"
	if step.is_empty():
		scan_seconds = 0.0
		return
	var location := Story.site_position(step)
	var player := sector.player
	var inside: bool = player.alive and player.map_id == step["map"] and player.position.distance_to(location) <= step["radius"]
	scan_seconds = scan_seconds + delta if inside and step["type"] == "scan" else 0.0
	if ring.visible:
		ring.position = location
		var torus := ring.mesh as TorusMesh
		if not is_equal_approx(torus.outer_radius, step["radius"]):
			torus.inner_radius = 0.0
			torus.outer_radius = step["radius"]
			torus.inner_radius = step["radius"] - 1.2
		# Waypoints stand up as hoops visible from afar; scan fields lie flat.
		ring.rotation.x = PI / 2 if step["type"] == "reach" else 0.0
		ring.rotation.y = wrapf(ring.rotation.y + delta * 0.4, 0.0, TAU)
	else:
		recorder.position = location
		recorder.rotate_y(delta * 1.2)


func observe(story: Dictionary) -> void:
	var step := int(story["step"])
	if step == seen_step:
		return
	comm = ""
	if seen_step >= 0 and step == seen_step + 1:
		comm = Story.completion_notice(Story.STEPS[seen_step], story)
		SectorVisuals.sound(sector, "purchase", sector.player.position)
	elif not Story.complete(story):
		comm = Story.transmission(Story.current(story))
	comm_time = COMM_SECONDS if not comm.is_empty() else 0.0
	seen_step = step
	scan_seconds = 0.0
