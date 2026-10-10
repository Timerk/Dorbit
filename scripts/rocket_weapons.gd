class_name RocketWeapons
extends RefCounted
## Authority-only simulation. Inventory includes loaded reservations until firing;
## available() excludes them. Releasing a reservation never needs a save or refund.

signal launched(event: Dictionary)
signal resolved(id: String, location: Vector3, hit: bool)

const LOAD_INTERVAL: float = 1.0
const LAUNCHER_COOLDOWN: float = 3.0
const MAX_FLIGHT_TIME: float = 8.0
var ship: Pilot
var single_type: String = "r-310"
var launcher_type: String = "eco-10"
var single_cooldown: float = 0.0
var launcher_cooldown: float = 0.0
var capacity: int = 0
var loaded: int = 0
var loading: bool = false
var load_clock: float = 0.0
var debit: Callable
var pending: Array[Dictionary] = []
var sequence: int = 0
var rng := RandomNumberGenerator.new()


func available(kind: String) -> int:
	return int(ship.ammo.get(kind, 0)) - (loaded if kind == launcher_type else 0)


func unload() -> void:
	loaded = 0
	loading = false
	load_clock = 0.0


func equip(value: int) -> void:
	if value != capacity:
		unload()
	capacity = value


func select(kind: String) -> bool:
	if not ship.simulation_authority or not Ammunition.ROCKETS.has(kind):
		return false
	if Ammunition.ROCKETS[kind]["launcher"]:
		if kind != launcher_type:
			unload()
		launcher_type = kind
	else:
		single_type = kind
	return true


func target_blocker(target: SpaceShip, kind: String) -> String:
	if not ship.alive or ship.get_meta("docked", false) or not is_instance_valid(target) or not target.alive:
		return "INVALID TARGET"
	# The current sector is cooperative: only available aliens are attackable.
	if not target is Alien or target.get_parent() != ship.get_parent() or ship.get_world_3d() != target.get_world_3d():
		return "INVALID TARGET"
	if not target.available():
		return "TARGET RETURNING"
	if ship.position.distance_to(Sector.STATION_POSITION) <= Sector.PROTECTION_RADIUS:
		return "STATION PROTECTION"
	if ship.global_position.distance_to(target.global_position) > float(Ammunition.ROCKETS[kind]["range"]):
		return "OUT OF RANGE"
	return ""


func spend(kind: String, count: int) -> bool:
	if int(ship.ammo.get(kind, 0)) < count or (debit.is_valid() and not debit.call(kind, count)):
		return false
	ship.ammo[kind] -= count
	if not debit.is_valid():
		ResourceBoosts.consume_rockets(ship.resource_boosts, count)
	return true


func fire_single(target: SpaceShip) -> String:
	if not ship.simulation_authority:
		return "WAITING FOR SERVER"
	var blocker := target_blocker(target, single_type)
	if not blocker.is_empty():
		return blocker
	if single_cooldown > 0.0:
		return "ROCKET COOLDOWN"
	if available(single_type) < 1:
		return "NO ROCKET AMMUNITION"
	var bonus := ResourceBoosts.bonus(ship.resource_boosts, "rockets")
	if not spend(single_type, 1):
		return "AMMUNITION SAVE FAILED"
	single_cooldown = Ammunition.ROCKETS[single_type]["cooldown"]
	launch(target, single_type, 0, 1, bonus)
	return ""


func activate(target: SpaceShip) -> String:
	if not ship.simulation_authority or not ship.alive or ship.get_meta("docked", false):
		return "CANNOT ACTIVATE LAUNCHER"
	if capacity == 0:
		return "NO LAUNCHER EQUIPPED"
	if launcher_cooldown > 0.0:
		return "LAUNCHER COOLDOWN"
	if loaded == 0:
		if available(launcher_type) < 1:
			return "NO LAUNCHER AMMUNITION"
		if not loading:
			loading = true
			load_clock = LOAD_INTERVAL
		return "LOADING LAUNCHER"
	var blocker := target_blocker(target, launcher_type)
	if not blocker.is_empty():
		return blocker
	var count := loaded
	var boosted := int(ResourceBoosts.remaining(ship.resource_boosts, "rockets"))
	var bonus := ResourceBoosts.bonus(ship.resource_boosts, "rockets")
	if not spend(launcher_type, count):
		return "AMMUNITION SAVE FAILED"
	unload()
	launcher_cooldown = LAUNCHER_COOLDOWN
	for index in range(count):
		launch(target, launcher_type, index, count, bonus if index < boosted else 0.0)
	return ""


func launch(target: Alien, kind: String, index: int, count: int, bonus: float = 0.0) -> void:
	sequence += 1
	var info: Dictionary = Ammunition.ROCKETS[kind]
	var id := "%d-%d" % [ship.get_instance_id(), sequence]
	var origin := ship.global_position - ship.global_basis.z * 3.0 + ship.global_basis.x * (index - (count - 1) * 0.5) * 1.2
	var event := {"id": id, "origin": origin, "target": target.alien_id, "life": target.life, "kind": kind, "index": index, "count": count}
	pending.append({"id": id, "target": weakref(target), "life": target.life, "attacker_life": ship.get_meta("life", 0), "position": origin, "age": 0.0, "kind": kind, "hit": rng.randf() < float(info["accuracy"]), "damage": float(info["damage"]) * rng.randf_range(info["minimum"], info["maximum"]) * (1.0 + bonus)})
	launched.emit(event)


func tick(delta: float) -> void:
	if not ship.simulation_authority:
		return
	single_cooldown = maxf(0.0, single_cooldown - delta)
	launcher_cooldown = maxf(0.0, launcher_cooldown - delta)
	if loading and ship.alive and not ship.get_meta("docked", false):
		load_clock -= delta
		while loading and load_clock <= 0.0:
			if loaded < capacity and available(launcher_type) > 0:
				loaded += 1
			load_clock += LOAD_INTERVAL
			loading = loaded < capacity and available(launcher_type) > 0
	for index in range(pending.size() - 1, -1, -1):
		var projectile := pending[index]
		var target := projectile["target"].get_ref() as Alien
		projectile["age"] += delta
		var valid: bool = is_instance_valid(target) and target.available() and target.life == projectile["life"] and ship.get_meta("life", 0) == projectile["attacker_life"] and target.get_parent() == ship.get_parent() and ship.get_world_3d() == target.get_world_3d() and not ship.get_meta("docked", false)
		if not valid or projectile["age"] > MAX_FLIGHT_TIME:
			pending.remove_at(index)
			resolved.emit(projectile["id"], projectile["position"], false)
			continue
		var step := float(Ammunition.ROCKETS[projectile["kind"]]["speed"]) * delta
		if projectile["position"].distance_to(target.global_position) <= step:
			pending.remove_at(index) # Retire before damage callbacks; never hit twice.
			var hit: bool = projectile["hit"] and ship.position.distance_to(Sector.STATION_POSITION) > Sector.PROTECTION_RADIUS
			resolved.emit(projectile["id"], target.global_position, hit)
			if hit:
				target.take_damage(projectile["damage"], ship)
		else:
			projectile["position"] = projectile["position"].move_toward(target.global_position, step)


func state() -> Dictionary:
	return {"single_type": single_type, "launcher_type": launcher_type, "single_cooldown": single_cooldown, "launcher_cooldown": launcher_cooldown, "capacity": capacity, "loaded": loaded, "loading": loading, "load_clock": load_clock}


func apply_state(data: Dictionary) -> void:
	single_type = data["single_type"]
	launcher_type = data["launcher_type"]
	single_cooldown = data["single_cooldown"]
	launcher_cooldown = data["launcher_cooldown"]
	capacity = data["capacity"]
	loaded = data["loaded"]
	loading = data["loading"]
	load_clock = data["load_clock"]
