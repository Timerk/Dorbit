class_name ShipExhaust
extends Node3D
## Presentation-only ion drive plumes behind each modeled nozzle. Thrust is
## inferred from rendered motion, so remote pilots animate without network state.

const PLUME_SHADER := preload("res://shaders/ion_exhaust.gdshader")
const IDLE_THROTTLE: float = 0.12 # Nozzles keep a faint glow while drifting or parked.
const CRUISE_THROTTLE: float = 0.3 # Holding cruise speed sustains a short plume.
const FULL_THRUST_ACCELERATION: float = 30.0 # Flight acceleration is 40 m/s².
const RISE_RATE: float = 12.0
const FALL_RATE: float = 3.0
const BOOST_HOLD: float = 0.25 # Remote energy only updates with each snapshot.
const TELEPORT_SPEED: float = 400.0 # Rescues, jumps and corrections reset tracking.
const GLOW_TINT := Color(0.45, 0.85, 1.0)
const BOOST_GLOW_TINT := Color(0.8, 0.55, 1.0)

var ship: Pilot
var throttle: float = IDLE_THROTTLE
var boost: float = 0.0
var nozzles: Array[Vector4] = [] # Model-space position and nozzle radius.
var plumes: Array[MeshInstance3D] = []
var flares: Array[MeshInstance3D] = []
var engine_light: OmniLight3D # Lights the aft hull on High effects.
var plume_surface := ShaderMaterial.new()
var tracking: bool = false
var last_position: Vector3
var last_energy: float
var boost_clock: float = 0.0
var forward_speed: float = 0.0
var forward_acceleration: float = 0.0


static func attach(model: Node3D, pilot: Pilot) -> ShipExhaust:
	var exhaust := ShipExhaust.new()
	exhaust.ship = pilot
	exhaust.name = "Exhaust"
	for entry: Array in ShipCatalog.info(pilot.ship_model).get("exhausts", []):
		exhaust.nozzles.append(Vector4(entry[0], entry[1], entry[2], entry[3]))
	model.add_child(exhaust)
	return exhaust


func _ready() -> void:
	plume_surface.shader = PLUME_SHADER
	var cone := CylinderMesh.new()
	cone.top_radius = 1.0
	cone.bottom_radius = 0.3
	cone.height = 1.0
	cone.radial_segments = 12
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	for nozzle in nozzles:
		var plume := SectorVisuals.mesh(self, cone, Vector3.ZERO, plume_surface)
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plume.rotation.x = -PI / 2.0 # The cone's wide +Y end sits on the nozzle; the tail extends aft (+Z).
		plumes.append(plume)
		# Flares share the combat glow mesh and material; present() sets per-instance tint and fade.
		var flare := SectorVisuals.effect_mesh(self, "glow", "glow_material", Vector3(nozzle.x, nozzle.y, nozzle.z + nozzle.w * 0.5), Vector3.ONE)
		flares.append(flare)
	if not nozzles.is_empty():
		var center := Vector3.ZERO
		var radius := 0.0
		for nozzle in nozzles:
			center += Vector3(nozzle.x, nozzle.y, nozzle.z)
			radius = maxf(radius, nozzle.w)
		engine_light = OmniLight3D.new()
		engine_light.name = "EngineLight"
		engine_light.position = center / nozzles.size() + Vector3(0, 0, radius * 2.0)
		engine_light.omni_range = maxf(radius * 14.0, 6.0)
		engine_light.omni_attenuation = 1.6
		add_child(engine_light)
	present()


func _process(delta: float) -> void:
	if delta > 0.0 and is_instance_valid(ship):
		track(delta)
		present()


func track(delta: float) -> void:
	var location := ship.global_position
	if not tracking or location.distance_to(last_position) > TELEPORT_SPEED * delta:
		tracking = true
		last_position = location
		last_energy = ship.energy
		forward_speed = 0.0
		forward_acceleration = 0.0
		return
	var speed := (location - last_position).dot(-ship.global_basis.z) / delta
	var smoothed := lerpf(forward_speed, speed, 1.0 - exp(-delta * 10.0))
	forward_acceleration = lerpf(forward_acceleration, (smoothed - forward_speed) / delta, 1.0 - exp(-delta * 8.0))
	forward_speed = smoothed
	last_position = location
	boost_clock = BOOST_HOLD if ship.boosting or ship.energy < last_energy - 0.001 else maxf(0.0, boost_clock - delta)
	last_energy = ship.energy
	var cruise := IDLE_THROTTLE + (CRUISE_THROTTLE - IDLE_THROTTLE) * clampf(forward_speed / maxf(ship.cruise_speed, 1.0), 0.0, 1.0)
	var target := maxf(cruise, clampf(forward_acceleration / FULL_THRUST_ACCELERATION, 0.0, 1.0))
	var boost_target := 1.0 if boost_clock > 0.0 else 0.0
	if boost_target > 0.0:
		target = 1.0
	throttle = lerpf(throttle, target, 1.0 - exp(-delta * (RISE_RATE if target > throttle else FALL_RATE)))
	boost = lerpf(boost, boost_target, 1.0 - exp(-delta * (RISE_RATE if boost_target > boost else FALL_RATE)))


func present() -> void:
	plume_surface.set_shader_parameter("throttle", throttle)
	plume_surface.set_shader_parameter("boost", boost)
	var tint := GLOW_TINT.lerp(BOOST_GLOW_TINT, boost)
	var opacity := 0.35 + 0.65 * throttle
	if engine_light != null:
		engine_light.visible = SectorVisuals.effects_quality(self) > 1
		engine_light.light_color = tint
		engine_light.light_energy = (0.4 + 2.2 * throttle) * (1.0 + 0.5 * boost)
	for index in nozzles.size():
		var nozzle := nozzles[index]
		var length := nozzle.w * (4.0 + 22.0 * throttle) * (1.0 + 0.7 * boost)
		var width := nozzle.w * (0.85 + 0.3 * throttle)
		plumes[index].position = Vector3(nozzle.x, nozzle.y, nozzle.z + length * 0.5)
		plumes[index].scale = Vector3(width, length, width)
		flares[index].scale = Vector3.ONE * nozzle.w * (3.0 + 5.0 * throttle) * (1.0 + 0.4 * boost)
		flares[index].set_instance_shader_parameter("tint", tint)
		flares[index].set_instance_shader_parameter("opacity", opacity)
