extends SceneTree
## Loaded from outside the pack; compare exported simulation data with the source.

var failures: int = 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)


func run() -> void:
	var packed := "--expect-export" in OS.get_cmdline_user_args()
	var skylab_balance := Skylab.data()
	check(not skylab_balance.is_empty(), "Skylab balance data survives export")
	check(not packed or OS.has_feature("dedicated_server"), "Pack has dedicated-server feature")
	if packed:
		for directory: String in ["res://docs/ammo-art", "res://docs/sector-art"]:
			check(not DirAccess.dir_exists_absolute(directory), "Documentation artwork stays outside the server pack: " + directory)
	var scene: PackedScene = load("res://scenes/sector.tscn")
	var sector := scene.instantiate() as Sector
	sector.dedicated_server = true
	root.add_child(sector)
	check(sector.session.active, "Exported scene starts its server")
	check(sector.player == null and sector.hud == null and sector.audio == null, "Server has no local pilot, HUD or audio")
	check(sector.find_children("*", "VisualInstance3D", true, false).is_empty(), "Server creates no visual nodes")
	var colliders: Array = []
	for body: StaticBody3D in sector.find_children("*", "StaticBody3D", true, false):
		for collider: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
			var shape := collider.shape
			colliders.append([str(collider.global_transform), shape.get_class(),
				shape.radius if shape is SphereShape3D else str(shape.size)])
	check(colliders.size() == 77, "All 24 asteroids and 53 station colliders survive export")
	for model: String in ShipCatalog.MODELS:
		var pilot := Pilot.new()
		pilot.render_enabled = false
		pilot.ship_model = model
		sector.add_child(pilot)
		check(pilot.get_child(0) is CollisionShape3D, "Hull retains its simulation collider: " + model)
		pilot.free()
	if packed:
		var texture: Texture2D = load("res://assets/ui/equipment-atlas.png")
		check(texture is PlaceholderTexture2D, "Export strips texture pixels while preserving resource references")
	await physics_frame
	await physics_frame
	var space := sector.get_world_3d().direct_space_state
	var center := Sector.STATION_POSITION
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(0, 0, 45), center, 1)).is_empty(), "Station service hangar remains open")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(14, 0, 20), center + Vector3(14, 0, -20), 1)).is_empty(), "Station structure still blocks weapons and ships")
	print("DORBIT_SERVER_EXPORT=" + JSON.stringify({"protocol": sector.session.protocol_fingerprint(),
		"colliders": colliders, "catalog": ShipCatalog.MODELS, "skylab_balance": skylab_balance}))
	sector.free()
	quit(0 if failures == 0 else 1)
