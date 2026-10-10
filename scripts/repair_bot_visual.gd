class_name RepairBotVisual
extends Node3D
## Presentation follows the replicated working flag on every rendered pilot.

var ship: Pilot
var robot := Node3D.new()
var beams: Array[MeshInstance3D] = []
var contacts: Array[MeshInstance3D] = []
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


func box(parent: Node3D, dimensions: Vector3, surface: Material, at: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return part(parent, mesh, surface, at)


func _ready() -> void:
	name = "RepairBot"
	ship = get_parent() as Pilot
	add_child(robot)
	var silver := material(Color("b9c8d4"))
	var dark := material(Color("243342"))
	var amber := material(Color("e9a54b"))
	var cyan := material(Color("55eeff"), true)
	box(robot, Vector3(0.8, 0.3, 0.6), silver, Vector3.ZERO)
	box(robot, Vector3(0.55, 0.18, 0.5), dark, Vector3(0, 0.2, 0))
	box(robot, Vector3(0.36, 0.09, 0.04), cyan, Vector3(0, 0.04, -0.32))
	box(robot, Vector3(0.18, 0.025, 0.38), amber, Vector3(0, 0.3, 0))
	for side: float in [-1.0, 1.0]:
		box(robot, Vector3(0.38, 0.1, 0.14), dark, Vector3(side * 0.49, -0.06, -0.12)).rotation.z = side * -0.3
		box(robot, Vector3(0.12, 0.28, 0.12), silver, Vector3(side * 0.62, -0.22, -0.12))
		box(robot, Vector3(0.16, 0.08, 0.18), cyan, Vector3(side * 0.62, -0.38, -0.12))
		box(robot, Vector3(0.12, 0.16, 0.26), cyan, Vector3(side * 0.26, -0.23, 0.17))
		var ray := CylinderMesh.new()
		ray.top_radius = 0.014
		ray.bottom_radius = 0.024
		ray.radial_segments = 6
		beams.append(part(self, ray, cyan, Vector3.ZERO))
		var spark := SphereMesh.new()
		spark.radius = 0.07
		spark.height = 0.14
		contacts.append(part(self, spark, cyan, Vector3.ZERO))
	hide()


func _process(delta: float) -> void:
	visible = ship.alive and ship.robot_repairing and not ship.get_meta("docked", false)
	if not visible:
		return
	phase += delta
	var factor := clampf(float(ShipCatalog.info(ship.ship_model).get("visual_diameter", 7.0)) / 7.0, 0.5, 1.0)
	scale = Vector3.ONE * factor
	robot.position = Vector3(sin(phase * 0.55) * 1.5, 2.4 + sin(phase * 2.5) * 0.12, cos(phase * 0.55) * 1.3)
	robot.rotation.y = -phase * 0.55
	for index in beams.size():
		var side := -1.0 if index == 0 else 1.0
		var start: Vector3 = robot.transform * Vector3(side * 0.62, -0.38, -0.12)
		var end := Vector3(side * 0.65 + sin(phase * 1.7) * 0.3, 0.45, cos(phase * 1.3) * 0.8)
		var direction := end - start
		beams[index].position = (start + end) * 0.5
		beams[index].basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
		beams[index].scale.y = direction.length() / 2.0
		contacts[index].position = end
		contacts[index].scale = Vector3.ONE * (0.8 + sin(phase * 14.0 + index) * 0.3)
