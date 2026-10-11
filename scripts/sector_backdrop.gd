class_name SectorBackdrop
extends RefCounted
## Client-only scenery for the reclamation campaign. No physics or mission state.

const THEMES := [
	{"planet": Vector3(-1900, 780, -3400), "radius": 1050.0, "ocean": Color("164a70"), "land": Color("637457"), "atmosphere": Color("4789d4"), "water": 1.0, "clouds": 0.65, "mining": 0.0, "cool": Color("215d93"), "warm": Color("347c91"), "light": Color("74b7ce")},
	{"planet": Vector3(2000, 720, -3550), "radius": 1100.0, "ocean": Color("554632"), "land": Color("b48a56"), "atmosphere": Color("b68d52"), "water": 0.0, "clouds": 0.08, "mining": 1.0, "cool": Color("80653a"), "warm": Color("c48a3c"), "light": Color("e0b46a")},
	{"planet": Vector3(-2150, 900, -3750), "radius": 1000.0, "ocean": Color("382c29"), "land": Color("916957"), "atmosphere": Color("b36045"), "water": 0.0, "clouds": 0.04, "mining": 0.8, "cool": Color("68362e"), "warm": Color("bc5940"), "light": Color("d98660")},
	{"planet": Vector3(2050, 800, -3500), "radius": 1130.0, "ocean": Color("1d263c"), "land": Color("555265"), "atmosphere": Color("557ca7"), "water": 0.2, "clouds": 0.18, "mining": 1.0, "cool": Color("454980"), "warm": Color("9161b2"), "light": Color("558fac")},
]


# Merge repeated model parts by material, keeping each landmark to four draw calls.
class Geometry:
	extends RefCounted
	var surfaces: Array[SurfaceTool] = []
	var cylinder := CylinderMesh.new()
	var sphere := SphereMesh.new()
	var panel: ArrayMesh

	func _init() -> void:
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = 1.0
		cylinder.radial_segments = 10
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		panel = beveled_panel()
		for index in range(4):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces.append(surface)

	func part(shape: Mesh, transform: Transform3D, material_index: int) -> void:
		surfaces[material_index].append_from(shape, 0, transform)

	func box(location: Vector3, size: Vector3, material_index: int, rotation: Vector3 = Vector3.ZERO) -> void:
		part(panel, Transform3D(Basis.from_euler(rotation).scaled_local(size), location), material_index)

	func beveled_panel() -> ArrayMesh:
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var outline: Array[Vector2] = [Vector2(-0.38,-0.5),Vector2(0.38,-0.5),Vector2(0.5,-0.38),Vector2(0.5,0.38),Vector2(0.38,0.5),Vector2(-0.38,0.5),Vector2(-0.5,0.38),Vector2(-0.5,-0.38)]
		for index in outline.size():
			var a := outline[index]
			var b := outline[(index+1)%outline.size()]
			var front_a := Vector3(a.x,a.y,0.5)
			var front_b := Vector3(b.x,b.y,0.5)
			var back_a := Vector3(a.x,a.y,-0.5)
			var back_b := Vector3(b.x,b.y,-0.5)
			for vertex: Vector3 in [Vector3(0,0,0.5),front_b,front_a,Vector3(0,0,-0.5),back_a,back_b,front_a,front_b,back_b,front_a,back_b,back_a]:
				builder.set_uv(Vector2(vertex.x+0.5,vertex.y+0.5))
				builder.add_vertex(vertex)
		builder.generate_normals()
		return builder.commit()

	func ball(location: Vector3, radius: float, material_index: int) -> void:
		part(sphere, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*radius), location), material_index)

	func tube(start: Vector3, finish: Vector3, radius: float, material_index: int) -> void:
		var direction := finish - start
		if direction.length() < 0.01:
			return
		var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
		part(cylinder, Transform3D(basis.scaled_local(Vector3(radius, direction.length(), radius)), (start+finish)*0.5), material_index)

	func finish(parent: Node3D, label: String, location: Vector3, rotation: Vector3, materials: Array[Material]) -> Node3D:
		var node := Node3D.new()
		node.name = label
		node.position = location
		node.rotation = rotation
		parent.add_child(node)
		for index in surfaces.size():
			var shape := surfaces[index].commit()
			if shape == null or shape.get_surface_count() == 0:
				continue
			var instance := SectorVisuals.mesh(node, shape, Vector3.ZERO, materials[index])
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return node


static func build(parent: Node3D, map: int) -> Node3D:
	var root := Node3D.new()
	root.name = "DistantScenery" if map == 0 else "Map%dBackdrop" % (map+1)
	root.position = SectorMaps.origin(map)
	parent.add_child(root)
	var theme: Dictionary = THEMES[map]
	var planet_position: Vector3 = theme["planet"]
	var radius: float = theme["radius"]
	planet(root, "ColonyPlanet", planet_position, radius, theme, float(map)*2.3)
	var moon_theme: Dictionary = theme.duplicate()
	moon_theme["water"] = 0.0
	moon_theme["clouds"] = 0.0
	moon_theme["mining"] = 0.0
	moon_theme["land"] = Color("555861")
	planet(root, "DistantMoon", Vector3(-planet_position.x*0.45, 1250, -4600), 280.0, moon_theme, 13.0, 0.0)
	asteroid_belt(root, map)
	if map == 0:
		human_ring(root, planet_position, radius*1.22, Vector3(0.18, -0.18, -0.35), false)
		derelict(root, Vector3(-1450, -240, -1600), Vector3(0.2, -0.45, 0.3), 2.2)
		derelict(root, Vector3(1000, 430, 1700), Vector3(-0.3, 0.6, -0.2), 1.5)
		reconstruction(root)
	elif map == 1:
		planet_collectors(root, planet_position, radius, 2)
		human_relay(root, Vector3(-1500, 80, -2100), 1.3)
		derelict(root, Vector3(-1800, -410, -1600), Vector3(0.3, 0.7, 0.5), 2.8)
		derelict(root, Vector3(1350, 180, 1500), Vector3(0.1, -0.6, 0.25), 1.5)
	elif map == 2:
		planet_collectors(root, planet_position, radius, 1)
		var wreck := Vector3(1550, 160, -2300)
		derelict(root, wreck, Vector3(0.2, -1.15, 0.3), 10.0)
		salvage_rig(root, wreck + Vector3(150, 80, 180))
		human_relay(root, Vector3(-1450, -280, -1500), 1.5)
		human_ring(root, Vector3(-1800, 500, 1800), 330.0, Vector3(0.3, -0.7, 0.4), false)
	else:
		human_ring(root, planet_position, radius*1.3, Vector3(0.18, 0.32, -0.4), true)
		planet_collectors(root, planet_position, radius, 3)
		alien_relay(root, Vector3(-1650, 120, -2450))
		human_relay(root, Vector3(-1500, -160, -2150), 1.0)
		alien_relay(root, Vector3(1750, -250, 1800), 0.55)
	return root


static func activate(parent: Node3D, map: int) -> void:
	var world := parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null:
		return
	var surface := world.environment.sky.sky_material as ShaderMaterial
	var theme: Dictionary = THEMES[map]
	surface.set_shader_parameter("nebula_cool", theme["cool"])
	surface.set_shader_parameter("nebula_warm", theme["warm"])
	surface.set_shader_parameter("nebula_light", theme["light"])
	surface.set_shader_parameter("cloud_offset", Vector3(5+map*7, 1+map*3, 9-map*2))


static func planet(parent: Node3D, label: String, location: Vector3, radius: float, theme: Dictionary, seed_value: float, settlements: float = 1.0) -> void:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius*2.0
	shape.radial_segments = 96
	shape.rings = 48
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://shaders/planet.gdshader")
	for parameter: String in ["ocean", "land", "atmosphere"]:
		surface.set_shader_parameter(parameter+"_color", theme[parameter])
	surface.set_shader_parameter("ocean_amount", theme["water"])
	surface.set_shader_parameter("cloud_amount", theme["clouds"])
	surface.set_shader_parameter("mining_amount", theme["mining"])
	surface.set_shader_parameter("terrain_seed", seed_value)
	surface.set_shader_parameter("settlement_amount", settlements)
	var instance := SectorVisuals.mesh(parent, shape, location, surface)
	instance.name = label
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func palette(alien: bool = false) -> Array[Material]:
	var hull := SectorVisuals.material(Color("273d48") if alien else Color("4c5866"))
	hull.metallic = 0.35
	hull.albedo_texture = load("res://assets/sector/station-panels.png")
	hull.roughness = 0.7 if not alien else 0.42
	var frame := SectorVisuals.material(Color("687f86") if alien else Color("7c807d"))
	frame.albedo_texture = hull.albedo_texture
	var dark := SectorVisuals.material(Color("10222b") if alien else Color("222b32"))
	var light := SectorVisuals.material(Color("41cfc5") if alien else Color("ae814c"), true)
	return [hull, frame, dark, light]


static func human_ring(parent: Node3D, location: Vector3, radius: float, rotation: Vector3, captured: bool) -> void:
	var geometry := Geometry.new()
	for index in range(40):
		if index % 10 in [0, 1, 2]:
			continue # Broken spans expose the original defense structure.
		var angle := float(index)*TAU/40.0
		var radial := Vector3(cos(angle), sin(angle), 0)
		var tangent := Vector3(-sin(angle), cos(angle), 0)
		var center := radial*radius
		for depth: float in [-28.0, 28.0]:
			geometry.tube(center-tangent*radius*0.066+Vector3(0,0,depth), center+tangent*radius*0.066+Vector3(0,0,depth), 7.0, 1)
		geometry.box(center, Vector3(radius*0.125, 28, 48), 0, Vector3(0,0,angle+PI/2))
		geometry.box(center+radial*35, Vector3(32, 50, 36), 2, Vector3(0,0,angle+PI/2))
		geometry.tube(center-radial*38, center+radial*48, 5.0, 1)
		if index % 4 == 0:
			geometry.box(center+radial*75, Vector3(38, 70, 46), 0, Vector3(0,0,angle))
			geometry.tube(center+radial*85, center+radial*155, 8.0, 2)
	var node := geometry.finish(parent, "CapturedHumanRing" if captured else "ShatteredDefenses", location, rotation, palette())
	if captured:
		for angle: float in [0.5, 2.3, 3.6, 5.4]:
			alien_collar(node, Vector3(cos(angle), sin(angle), 0)*radius, 150, Vector3(0.1, 0.2, angle), "OccupationClamp")


static func human_relay(parent: Node3D, location: Vector3, scale_factor: float) -> void:
	var geometry := Geometry.new()
	geometry.box(Vector3.ZERO, Vector3(100, 45, 140), 0)
	for side: float in [-1, 1]:
		geometry.tube(Vector3(side*35,0,0), Vector3(side*35,270,-35), 7, 1)
		for step in range(5):
			geometry.tube(Vector3(-35,step*48,0), Vector3(35,(step+1)*48,-12), 3, 1)
		geometry.box(Vector3(side*140,90,20), Vector3(155, 8, 100), 2, Vector3(0.1,0,side*0.2))
		for panel in range(7):
			geometry.box(Vector3(side*(75+panel*20),96,20), Vector3(12, 2, 92), 0)
	geometry.tube(Vector3(0,80,0), Vector3(0,330,-30), 5, 2)
	for index in range(12):
		var angle := float(index)*TAU/12.0
		geometry.tube(Vector3(0,200,-40), Vector3(cos(angle)*65,200+sin(angle)*65,-5), 3, 1)
	geometry.box(Vector3(25,15,73), Vector3(30,18,3), 2)
	var node := geometry.finish(parent, "AbandonedReceiver", location, Vector3(0.1,0.1,-0.16), palette())
	node.scale = Vector3.ONE*scale_factor


static func alien_collar(parent: Node3D, location: Vector3, radius: float, rotation: Vector3, label: String = "AlienCollector") -> Node3D:
	var geometry := Geometry.new()
	for claw in range(3):
		var start_angle := float(claw)*TAU/3.0
		for segment in range(10):
			var angle := start_angle+float(segment)*0.115
			var next := angle+0.1
			var reach := radius*(1.0-float(segment)*0.026)
			var point := Vector3(cos(angle)*reach,sin(angle)*reach,-float(segment)*radius*0.018)
			var finish := Vector3(cos(next)*reach,sin(next)*reach,-float(segment+1)*radius*0.018)
			geometry.box(point, Vector3(radius*0.19,radius*0.14,radius*0.18), 0, Vector3(0.12,0,angle+PI/2))
			geometry.tube(point+Vector3(0,0,radius*0.085), finish+Vector3(0,0,radius*0.085), radius*0.009, 3)
			geometry.box(point*1.1, Vector3(radius*0.06,radius*0.07,radius*0.2), 1, Vector3(0,0,angle+PI/2))
		var angle := start_angle
		geometry.tube(Vector3(cos(angle),sin(angle),0)*radius, Vector3(cos(angle),sin(angle),0)*radius*0.4, radius*0.045, 2)
		geometry.box(Vector3(cos(angle),sin(angle),0)*radius*1.22, Vector3(radius*0.28,radius*0.38,radius*0.4), 0, Vector3(0.15,0,angle))
	return geometry.finish(parent, label, location, rotation, palette(true))


static func planet_collectors(parent: Node3D, center: Vector3, radius: float, count: int) -> void:
	var target := center+Vector3(-0.12,0.08,1.0).normalized()*radius
	for index in range(count):
		var location := center+Vector3((float(index)-float(count-1)*0.5)*380-380, -280+index*90, radius+330)
		var collector := alien_collar(parent, location, 200+index*30, Vector3(0.15,-0.1,index*0.45))
		collector.set_meta("extraction_target", target)
		var geometry := Geometry.new()
		geometry.tube(location, target, 2.8, 3)
		for step in range(8):
			var point := target.lerp(location, (float(step)+0.5)/8.0)
			geometry.ball(point+Vector3(sin(float(step)*1.7)*6,cos(float(step))*6,0), 4.5, 3)
		var materials := palette(true)
		var stream := ShaderMaterial.new()
		stream.shader = preload("res://shaders/mining_stream.gdshader")
		materials[3] = stream
		geometry.finish(parent, "ExtractionStream%d" % index, Vector3.ZERO, Vector3.ZERO, materials)
		cargo_pods(parent, location+Vector3(300,100,80), index+3)


static func salvage_rig(parent: Node3D, location: Vector3) -> void:
	alien_collar(parent, location, 230, Vector3(0.4,0.6,0.3), "AlienSalvageRig")
	var geometry := Geometry.new()
	for side: float in [-1,1]:
		var base := Vector3(side*170,60,0)
		var elbow := Vector3(side*270,200,90)
		var claw := Vector3(side*110,190,240)
		geometry.tube(base,elbow,14,0)
		geometry.tube(elbow,claw,10,1)
		geometry.ball(elbow,22,2)
		geometry.tube(elbow+Vector3(0,0,14),claw+Vector3(0,0,14),2,3)
		geometry.box(claw,Vector3(90,12,140),1,Vector3(0.3,side*0.5,0.2))
		for finger: float in [-1,1]:
			geometry.tube(claw+Vector3(finger*45,0,0),claw+Vector3(finger*26,-60,15),6,0)
	geometry.finish(parent,"SalvageArms",location,Vector3.ZERO,palette(true))
	cargo_pods(parent,location+Vector3(-480,140,0),7)


static func alien_relay(parent: Node3D, location: Vector3, scale_factor: float = 1.0) -> void:
	var relay := alien_collar(parent, location, 420, Vector3(-0.1,0.3,0.15), "AlienRelay")
	relay.scale = Vector3.ONE*scale_factor
	var geometry := Geometry.new()
	for side: float in [-1,1]:
		for step in range(7):
			geometry.box(Vector3(side*(300-step*14),step*70-170,-80),Vector3(52+step*3,80,90),0,Vector3(0,0,side*0.18))
			geometry.box(Vector3(side*(300-step*14)-8,step*70-170,-32),Vector3(4,55,2),3,Vector3(0,0,side*0.18))
	geometry.finish(relay,"SensorPylons",Vector3.ZERO,Vector3.ZERO,palette(true))
	cargo_pods(parent,location+Vector3(450,-250,150),11)


static func cargo_pods(parent: Node3D, location: Vector3, seed_value: int) -> void:
	var geometry := Geometry.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in range(6):
		var point := Vector3(index*62,rng.randf_range(-25,25),index*35)
		geometry.box(point,Vector3(18,12,32),0,Vector3(0.2,0.3,0.1))
		geometry.box(point+Vector3(0,0,17),Vector3(10,4,2),3)
	geometry.finish(parent,"OreTransport",location,Vector3.ZERO,palette(true))


static func derelict(parent: Node3D, location: Vector3, rotation: Vector3, scale_factor: float) -> void:
	var wreck := (load("res://assets/sector/derelict.glb") as PackedScene).instantiate() as Node3D
	wreck.position = location
	wreck.rotation = rotation
	wreck.scale = Vector3.ONE*scale_factor
	SectorVisuals.configure_texture_filtering(wreck)
	for part: MeshInstance3D in wreck.find_children("*", "MeshInstance3D", true, false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(wreck)


static func reconstruction(parent: Node3D) -> void:
	# Beyond the boundary, this is a supply staging silhouette, not a new service dock.
	var geometry := Geometry.new()
	for side: float in [-1,1]:
		for level in range(4):
			geometry.tube(Vector3(side*85,level*40,-40),Vector3(side*85,(level+1)*40,-40),3,1)
			geometry.tube(Vector3(-85,level*40,-40),Vector3(85,(level+1)*40,-40),2,1)
		geometry.box(Vector3(side*105,60,0),Vector3(40,100,70),0)
		geometry.box(Vector3(side*105,60,36),Vector3(4,65,2),3)
	geometry.box(Vector3(0,145,0),Vector3(165,20,65),0)
	geometry.finish(parent,"SupplyStaging",Vector3(1250,-220,-1100),Vector3(0,-0.5,0),palette())


static func asteroid_belt(parent: Node3D, map: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4671+map*41
	var surface := SectorVisuals.asteroid_surface()
	for variant in range(3):
		var source := (load("res://assets/sector/asteroid-%d.glb" % variant) as PackedScene).instantiate()
		var shape := (source.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D).mesh
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = shape
		instances.instance_count = 48
		for index in range(instances.instance_count):
			var angle := rng.randf_range(0,TAU)
			var distance := rng.randf_range(1950,2600)
			var location := Vector3(cos(angle)*distance,rng.randf_range(-550,-300),sin(angle)*distance)
			var radius := rng.randf_range(10,36)
			var basis := Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3.ONE*radius)
			instances.set_instance_transform(index,Transform3D(basis,location))
		var belt := MultiMeshInstance3D.new()
		belt.multimesh = instances
		belt.material_override = surface
		belt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(belt)
		source.free()
