class_name SectorBackdrop
extends RefCounted
## Client-only scenery for the reclamation campaign. No physics or mission state.

const THEMES := [
	{"planet": Vector3(-1900, 1050, -3400), "radius": 1300.0, "ocean": Color("164a70"), "land": Color("637457"), "atmosphere": Color("4789d4"), "water": 1.0, "clouds": 0.65, "mining": 0.0, "cool": Color("215d93"), "warm": Color("347c91"), "light": Color("74b7ce")},
	{"planet": Vector3(2000, 1020, -3550), "radius": 1350.0, "ocean": Color("554632"), "land": Color("b48a56"), "atmosphere": Color("b68d52"), "water": 0.0, "clouds": 0.08, "mining": 1.0, "cool": Color("80653a"), "warm": Color("c48a3c"), "light": Color("e0b46a")},
	{"planet": Vector3(-2150, 1200, -3750), "radius": 1150.0, "ocean": Color("382c29"), "land": Color("916957"), "atmosphere": Color("b36045"), "water": 0.0, "clouds": 0.04, "mining": 0.8, "cool": Color("68362e"), "warm": Color("bc5940"), "light": Color("d98660")},
	{"planet": Vector3(2050, 1100, -3500), "radius": 1350.0, "ocean": Color("1d263c"), "land": Color("555265"), "atmosphere": Color("557ca7"), "water": 0.2, "clouds": 0.18, "mining": 1.0, "cool": Color("454980"), "warm": Color("9161b2"), "light": Color("558fac")},
]


const CLOUD_COUNT: int = 40

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
			var front_a := Vector3(a.x*0.88,a.y*0.88,0.5)
			var front_b := Vector3(b.x*0.88,b.y*0.88,0.5)
			var rim_a := Vector3(a.x,a.y,0.42)
			var rim_b := Vector3(b.x,b.y,0.42)
			var back_a := Vector3(a.x*0.88,a.y*0.88,-0.5)
			var back_b := Vector3(b.x*0.88,b.y*0.88,-0.5)
			var rear_a := Vector3(a.x,a.y,-0.42)
			var rear_b := Vector3(b.x,b.y,-0.42)
			for vertex: Vector3 in [Vector3(0,0,0.5),front_b,front_a,Vector3(0,0,-0.5),back_a,back_b,front_a,front_b,rim_b,front_a,rim_b,rim_a,rim_a,rim_b,rear_b,rim_a,rear_b,rear_a,rear_a,rear_b,back_b,rear_a,back_b,back_a]:
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
	wreckage_field(root, map)
	nebula_clouds(root, map)
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
		carrier(root, wreck, Vector3(0.15, -1.3, 0.22))
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
	surface.set_shader_parameter("panorama_rotation", float(map)*0.73)
	# Match the metal and rock highlights to the sector's stellar light.
	var sun := parent.get_node("Sun") as DirectionalLight3D
	var fill := parent.get_node("Fill") as DirectionalLight3D
	sun.light_color = Color("ffdfbd") if map == 0 else (theme["light"] as Color).lerp(Color.WHITE,0.45)
	surface.set_shader_parameter("sun_color", sun.light_color)
	fill.light_color = Color("6e9edb") if map == 0 else (theme["cool"] as Color).lerp(Color.WHITE,0.35)


static func planet(parent: Node3D, label: String, location: Vector3, radius: float, theme: Dictionary, seed_value: float, settlements: float = 1.0) -> void:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius*2.0
	shape.radial_segments = 96
	shape.rings = 48
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://shaders/planet.gdshader")
	surface.set_shader_parameter("surface_map", load("res://assets/sector/colony-surface-war.png" if theme["water"] == 1.0 else "res://assets/sector/mineral-surface.png"))
	surface.set_shader_parameter("war_damage", 1.0 if theme["water"] == 1.0 else 0.0)
	var tint := Color.WHITE
	if theme["water"] != 1.0:
		tint = Color("d6b18a") if seed_value < 4.0 else (Color("bd8874") if seed_value < 6.0 else Color("8992b3"))
	if label == "DistantMoon":
		tint = Color("a1a9b5")
	surface.set_shader_parameter("surface_tint", tint)
	surface.set_shader_parameter("surface_desaturation", 0.9 if seed_value > 6.0 else 0.0)
	# Put the colony's bombarded continent on the visible, sunlit hemisphere.
	surface.set_shader_parameter("surface_rotation", 0.16 if theme["water"] == 1.0 else seed_value*0.17)
	surface.set_shader_parameter("atmosphere_color", theme["atmosphere"])
	surface.set_shader_parameter("mining_amount", theme["mining"])
	surface.set_shader_parameter("terrain_seed", seed_value)
	surface.set_shader_parameter("settlement_amount", settlements)
	var instance := SectorVisuals.mesh(parent, shape, location, surface)
	instance.name = label
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A separate thin shell carries the luminous atmosphere beyond the solid limb.
	if label == "ColonyPlanet":
		var shell := SphereMesh.new()
		shell.radius = radius*1.018
		shell.height = shell.radius*2.0
		shell.radial_segments = 96
		shell.rings = 48
		var haze := ShaderMaterial.new()
		haze.shader = preload("res://shaders/atmosphere.gdshader")
		haze.set_shader_parameter("tint", theme["atmosphere"])
		var atmosphere := SectorVisuals.mesh(parent, shell, location, haze)
		atmosphere.name = "Atmosphere"
		atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func palette(alien: bool = false) -> Array[Material]:
	var hull := SectorVisuals.material(Color("142732") if alien else Color("4c5866"))
	hull.metallic = 0.65
	hull.albedo_texture = load("res://assets/sector/station-panels.png")
	hull.uv1_triplanar = true
	hull.uv1_scale = Vector3.ONE*0.035
	hull.roughness = 0.55 if not alien else 0.32
	var frame := SectorVisuals.material(Color("38545d") if alien else Color("7c807d"))
	frame.albedo_texture = hull.albedo_texture
	frame.uv1_triplanar = true
	frame.uv1_scale = hull.uv1_scale
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
		for depth: float in [-42.0, 42.0]:
			geometry.tube(center-tangent*radius*0.066+Vector3(0,0,depth), center+tangent*radius*0.066+Vector3(0,0,depth), 7.0, 1)
		geometry.box(center, Vector3(radius*0.125, 46, 84), 0, Vector3(0,0,angle+PI/2))
		for rib in range(5):
			var offset := tangent*(float(rib)-2.0)*radius*0.024
			geometry.box(center+offset, Vector3(5, 62, 96), 1, Vector3(0,0,angle+PI/2))
			geometry.box(center+offset+Vector3(0,0,50), Vector3(3, 22, 2), 3, Vector3(0,0,angle+PI/2))
		geometry.tube(center-tangent*radius*0.062+Vector3(0,0,48), center+tangent*radius*0.062+Vector3(0,0,48), 1.5, 3)
		geometry.box(center+radial*35, Vector3(32, 50, 36), 2, Vector3(0,0,angle+PI/2))
		geometry.tube(center-radial*38, center+radial*48, 5.0, 1)
		if index % 4 == 0:
			geometry.box(center+radial*75, Vector3(62, 105, 72), 0, Vector3(0,0,angle))
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
	# An open processing throat joins the articulated claws into one machine.
	for segment in range(24):
		var angle := float(segment)*TAU/24.0
		var point := Vector3(cos(angle),sin(angle),0)*radius*0.34
		geometry.box(point,Vector3(radius*0.1,radius*0.055,radius*0.22),2,Vector3(0,0,angle+PI/2))
		geometry.box(point+Vector3(0,0,radius*0.115),Vector3(radius*0.075,radius*0.012,radius*0.01),3,Vector3(0,0,angle+PI/2))
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
			# Recessed ribs, layered armor and fine seams keep the claws legible in silhouette.
			geometry.box(point+Vector3(0,0,radius*0.11), Vector3(radius*0.15,radius*0.065,radius*0.025), 2, Vector3(0.12,0,angle+PI/2))
			geometry.box(point+Vector3(0,0,radius*0.128), Vector3(radius*0.105,radius*0.012,radius*0.008), 3, Vector3(0,0,angle+PI/2))
		var angle := start_angle
		geometry.tube(Vector3(cos(angle),sin(angle),0)*radius, Vector3(cos(angle),sin(angle),0)*radius*0.4, radius*0.045, 2)
		geometry.box(Vector3(cos(angle),sin(angle),0)*radius*1.22, Vector3(radius*0.28,radius*0.38,radius*0.4), 0, Vector3(0.15,0,angle))
	return geometry.finish(parent, label, location, rotation, palette(true))


static func planet_collectors(parent: Node3D, center: Vector3, radius: float, count: int) -> void:
	var target := center+Vector3(-0.12,0.08,1.0).normalized()*radius
	for index in range(count):
		var location := center+Vector3((float(index)-float(count-1)*0.5)*380-380, -280+index*90, radius+330)
		var collector := alien_collar(parent, location, 340+index*45, Vector3(0.15,-0.1,index*0.45))
		collector.set_meta("extraction_target", target)
		var geometry := Geometry.new()
		geometry.tube(location, target, 4.0, 3)
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
	surface.albedo_texture = load("res://assets/sector/belt-rock.png")
	surface.albedo_color = Color("778698")
	surface.normal_scale = 1.3
	surface.uv1_scale = Vector3.ONE*0.8
	for variant in range(3):
		var source := (load("res://assets/sector/asteroid-%d.glb" % variant) as PackedScene).instantiate()
		var shape := (source.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D).mesh
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = shape
		instances.instance_count = 160
		for index in range(instances.instance_count):
			var angle := rng.randf_range(0,TAU)
			var distance := rng.randf_range(1950,2600)
			var location := Vector3(cos(angle)*distance,rng.randf_range(-640,-220)+sin(angle*2.0)*140.0,sin(angle)*distance)
			var radius := rng.randf_range(8,45) if index % 16 != 0 else rng.randf_range(65,110)
			var basis := Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3.ONE*radius)
			instances.set_instance_transform(index,Transform3D(basis,location))
		var belt := MultiMeshInstance3D.new()
		belt.multimesh = instances
		belt.material_override = surface
		belt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(belt)
		source.free()


static func nebula_clouds(parent: Node3D, map: int) -> void:
	# Gas wisps inside and around the flight sphere give the painted sky parallax.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9203+map*67
	var theme: Dictionary = THEMES[map]
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://shaders/nebula_cloud.gdshader")
	surface.set_shader_parameter("gas_cool", theme["cool"])
	surface.set_shader_parameter("gas_light", theme["light"])
	var card := QuadMesh.new()
	card.size = Vector2.ONE
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = card
	instances.instance_count = CLOUD_COUNT
	var largest := 0.0
	for index in range(CLOUD_COUNT):
		var direction := Vector3(rng.randf_range(-1,1),rng.randf_range(-0.35,0.35),rng.randf_range(-1,1)).normalized()
		var size := rng.randf_range(260,560)
		largest = maxf(largest, size)
		instances.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),direction*rng.randf_range(350,1500)))
		instances.set_instance_custom_data(index,Color(rng.randf(),0,0,0))
	var clouds := MultiMeshInstance3D.new()
	clouds.name = "NebulaClouds"
	clouds.multimesh = instances
	clouds.material_override = surface
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader billboards each card, so culling uses its full rotated extent.
	clouds.extra_cull_margin = largest
	parent.add_child(clouds)


static func wreckage_field(parent: Node3D, map: int) -> void:
	# Clustered salvage frames flank the forward view; no scenery crosses the flight sphere.
	var rng := RandomNumberGenerator.new()
	rng.seed = 8130+map*53
	for side: float in [-1.0, 1.0]:
		var geometry := Geometry.new()
		for piece in range(55):
			var point := Vector3(rng.randf_range(-260,260),rng.randf_range(-240,180),rng.randf_range(-350,350))
			var size := rng.randf_range(12,70)
			var rotation := Vector3(rng.randf()*PI,rng.randf()*PI,rng.randf()*PI)
			geometry.box(point,Vector3(size,size*0.14,size*0.45),0,rotation)
			if piece % 4 == 0:
				geometry.tube(point,point+Vector3(size*0.4,size*1.5,size*0.3),2.5,1)
				geometry.box(point+Vector3(0,size*0.2,0),Vector3(size*0.5,2,2),3,rotation)
		geometry.finish(parent,"BattlefieldDebris",Vector3(side*1800,-300,-2100),Vector3.ZERO,palette())
	# A large snapped patrol-defense frame supplies a foreground scale reference.
	var frame := Geometry.new()
	for level in range(9):
		var y := float(level)*55-220
		for side: float in [-1,1]:
			frame.tube(Vector3(side*70,y,-40),Vector3(side*70,y+55,-40),5,1)
			frame.tube(Vector3(-70,y,-40),Vector3(70,y+55,-40),3,1)
			frame.box(Vector3(side*100,y,0),Vector3(70,48,100),0,Vector3(0.1,0,side*0.1))
			frame.box(Vector3(side*100,y,52),Vector3(54,32,4),2)
			for rib in range(3):
				frame.box(Vector3(side*100,y-12+rib*12,56),Vector3(54,2,4),1)
			if level % 3 == 0:
				frame.box(Vector3(side*102,y,52),Vector3(4,24,2),3)
	frame.tube(Vector3(-350,45,0),Vector3(340,45,0),14,0)
	frame.box(Vector3(175,-150,0),Vector3(210,105,110),0,Vector3(0.04,0,-0.12))
	frame.box(Vector3(175,-147,58),Vector3(155,60,4),2,Vector3(0,0,-0.12))
	for index in range(13):
		var x := float(index)*52-310
		frame.tube(Vector3(x,15,-30),Vector3(x+50,65,-30),3,1)
		frame.tube(Vector3(x,15,30),Vector3(x+50,65,30),3,1)
	frame.finish(parent,"LostDefensePlatform",Vector3(-1600,30,-1900),Vector3(0.1,0.15,-0.25),palette())


static func carrier(parent: Node3D, location: Vector3, rotation: Vector3) -> void:
	var geometry := Geometry.new()
	# Exposed transverse ribs, interrupted armored decks and torn longitudinal spars.
	for bay in range(22):
		var z := float(bay)*52-570
		for rib in range(12):
			var angle := float(rib)*TAU/12.0
			var next := angle+TAU/12.0
			var a := Vector3(cos(angle)*125,sin(angle)*100,z)
			var b := Vector3(cos(next)*125,sin(next)*100,z)
			if (bay+rib*3)%11 == 0:
				continue
			geometry.tube(a,b,4,1)
			geometry.tube(a,a+Vector3(0,0,48),3,2)
			if (bay*3+rib)%7 < 4:
				geometry.box(a,Vector3(54,8,46),0,Vector3(0,0,angle-PI/2))
			if rib in [0,5] and bay%3 == 0:
				geometry.box(a+Vector3(0,0,18),Vector3(2,2,16),3)
		geometry.box(Vector3(0,-65,z),Vector3(180,6,44),2)
	for side: float in [-1,1]:
		geometry.box(Vector3(side*175,-10,370),Vector3(120,90,260),0,Vector3(0,side*0.2,0))
		geometry.tube(Vector3(side*160,-20,420),Vector3(side*160,-20,590),45,2)
		geometry.tube(Vector3(side*160,-20,540),Vector3(side*160,-20,570),51,1)
	geometry.box(Vector3(0,120,230),Vector3(150,50,200),0)
	geometry.box(Vector3(0,120,333),Vector3(100,14,2),2)
	geometry.finish(parent,"BrokenCarrier",location,rotation,palette()).scale = Vector3.ONE*1.5
