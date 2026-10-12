class_name RepairBotVisual
extends Node3D
## Presentation follows the replicated working flag on every rendered pilot.

const MODEL_SCALE := 0.3

var ship: Pilot
var robot := Node3D.new()
var beams: Array[MeshInstance3D] = []
var contacts: Array[MeshInstance3D] = []
var tool_tips: Array[Node3D] = []
var model_id := ""
var phase := 0.0


func material(color: Color, glowing: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = 0.75 if not glowing else 0.0
	result.roughness = 0.24
	if glowing:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = 2.0
	return result


func part(parent: Node3D, mesh: Mesh, surface: Material, at: Vector3) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.material_override = surface
	result.position = at
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result


func update_model() -> void:
	# Full-repair duration already replicates to every observer. Both fitted robot
	# tiers have unique durations, so their art needs no extra network/save field.
	var equipped := "rep-2" if is_equal_approx(ship.repair_seconds, float(Equipment.MODELS["rep-2"]["repair_seconds"])) else "rep-1"
	if model_id == equipped:
		return
	model_id = equipped
	for child in robot.get_children():
		robot.remove_child(child)
		child.queue_free()
	for effect in beams + contacts:
		remove_child(effect)
		effect.queue_free()
	beams.clear()
	contacts.clear()
	tool_tips.clear()
	var scene := load("res://assets/extras/%s.glb" % model_id) as PackedScene
	var model := scene.instantiate() as Node3D
	robot.add_child(model)
	SectorVisuals.configure_texture_filtering(model, SectorVisuals.texture_filtering_enabled(self))
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var amber := material(Color("ffb34d"), true)
	for index in (4 if model_id == "rep-2" else 2):
		tool_tips.append(model.find_child("ToolTip%d" % index, true, false) as Node3D)
		var ray := CylinderMesh.new()
		ray.top_radius = 0.009
		ray.bottom_radius = 0.018
		ray.radial_segments = 6
		beams.append(part(self, ray, amber, Vector3.ZERO))
		var spark := SphereMesh.new()
		spark.radius = 0.055
		spark.height = 0.11
		contacts.append(part(self, spark, amber, Vector3.ZERO))


func _ready() -> void:
	name = "RepairBot"
	ship = get_parent() as Pilot
	robot.name = "RobotModel"
	robot.scale = Vector3.ONE * MODEL_SCALE
	add_child(robot)
	update_model()
	hide()


func _process(delta: float) -> void:
	visible = ship.alive and ship.robot_repairing and not ship.get_meta("docked", false)
	if not visible:
		return
	update_model()
	phase += delta
	var factor := clampf(float(ShipCatalog.info(ship.ship_model).get("visual_diameter", 7.0)) / 7.0, 0.5, 1.0)
	scale = Vector3.ONE * factor
	robot.position = Vector3(sin(phase * 0.55) * 1.5, 2.0 + sin(phase * 2.5) * 0.12, cos(phase * 0.55) * 1.3)
	# Face the trailing flight camera while making a slow inspection sweep.
	robot.rotation.y = PI + sin(phase * 0.55) * 0.35
	for index in beams.size():
		var side := -1.0 if index % 2 == 0 else 1.0
		var start := to_local(tool_tips[index].global_position)
		var end := Vector3(side * 0.65 + sin(phase * 1.7) * 0.3, 0.45, cos(phase * 1.3 + index) * 0.8)
		var direction := end - start
		beams[index].position = (start + end) * 0.5
		beams[index].basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
		beams[index].scale.y = direction.length() / 2.0
		contacts[index].position = end
		contacts[index].scale = Vector3.ONE * (0.8 + sin(phase * 14.0 + index) * 0.3)
