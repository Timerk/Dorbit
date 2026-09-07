class_name SessionCombat
extends Node
## Host-owned encounter state. Clients send intent and receive snapshots, never damage or money.

var session: FlightSession
var records: Dictionary[int, Dictionary] = {}
var contributors: Array[int] = []
var encounter: int = 0
var alien_respawn: float = 0.0
var solo: Dictionary = {}
var alien_goal: Dictionary = {}


func begin() -> void:
	var sector := session.sector
	solo = {"credits": sector.credits, "kills": sector.kills, "stage": sector.objective_stage}
	records.clear()
	contributors.clear()
	encounter = 0
	alien_respawn = 0.0
	alien_goal.clear()
	sector.credits = 0
	sector.kills = 0
	sector.objective_stage = 0
	sector.player_respawn = 0.0
	sector.alien_respawn = 0.0
	sector.player.simulation_authority = multiplayer.is_server()
	sector.alien.simulation_authority = multiplayer.is_server()
	sector.alien.position = sector.alien.home_position
	sector.alien.patrol_time = 0.0
	sector.alien.reset_health()
	if not sector.alien.damaged.is_connected(record_damage):
		sector.alien.damaged.connect(record_damage)
	sector.notify("Shared encounter. Select the Sentinel and hunt together. F7 opens the session menu.")


func add_player(id: int, location: Vector3) -> void:
	var ship := session.ships[id]
	ship.simulation_authority = multiplayer.is_server()
	ship.set_meta("life", 0)
	if multiplayer.is_server():
		records[id] = {"credits": 0, "kills": 0, "stage": 0, "respawn": 0.0, "life": 0, "spawn": location}


func remove_player(id: int) -> void:
	records.erase(id)
	contributors.erase(id)


func record_damage(_ship: SpaceShip, attacker: SpaceShip) -> void:
	if not session.active or not multiplayer.is_server():
		return
	var id: Variant = session.ships.find_key(attacker)
	if id != null and id not in contributors:
		contributors.append(id)


func tick(delta: float) -> void:
	var sector := session.sector
	for id: int in records:
		var ship := session.ships[id]
		ship.tick_combat(delta)
		if not ship.alive:
			records[id]["respawn"] = maxf(0.0, records[id]["respawn"] - delta)
			if records[id]["respawn"] <= 0.0:
				ship.reset_health()
				ship.energy = 100.0
				ship.position = records[id]["spawn"]
				ship.rotation = Vector3.ZERO
				records[id]["life"] += 1
				ship.set_meta("life", records[id]["life"])
				session.commands.erase(id)
			continue
		if ship.position.distance_to(Sector.STATION_POSITION) > 75.0:
			records[id]["stage"] = maxi(records[id]["stage"], 1)
		var firing := sector.auto_fire and sector.target == sector.alien and not sector.paused if id == 1 else remote_firing(id)
		if firing:
			records[id]["stage"] = maxi(records[id]["stage"], 2)
			ship.try_fire(sector.alien)
	sector.alien.tick_combat(delta)
	if sector.alien.alive:
		sector.alien.fly(delta, choose_target(), Sector.STATION_POSITION)
	else:
		alien_respawn = maxf(0.0, alien_respawn - delta)
		if alien_respawn <= 0.0:
			encounter += 1
			contributors.clear()
			sector.alien.position = sector.alien.home_position
			sector.alien.reset_health()
	update_local(records[1])
	sector.alien_respawn = alien_respawn


func remote_firing(id: int) -> bool:
	var command: Dictionary = session.commands.get(id, {})
	return not command.is_empty() and command.get("fire", false) and command.get("encounter", -1) == encounter and Time.get_ticks_msec() - command["time"] < FlightSession.COMMAND_TIMEOUT * 1000


func choose_target() -> Pilot:
	var target: Pilot = null
	var nearest := 260.0
	for ship: Pilot in session.ships.values():
		if not ship.alive or ship.position.distance_to(Sector.STATION_POSITION) <= 75.0:
			continue
		var distance := ship.position.distance_to(session.sector.alien.position)
		if distance < nearest:
			target = ship
			nearest = distance
	return target


func destroyed(ship: SpaceShip) -> void:
	if not multiplayer.is_server():
		return
	show_explosion.rpc(ship.position)
	if ship == session.sector.alien:
		# Integer credits: conserve the 75-credit pool and distribute the remainder in peer-ID order.
		contributors.sort()
		for index in range(contributors.size()):
			var id := contributors[index]
			var reward := int(Sector.KILL_REWARD / contributors.size()) + (1 if index < Sector.KILL_REWARD % contributors.size() else 0)
			records[id]["credits"] += reward
			records[id]["kills"] += 1
			records[id]["stage"] = maxi(records[id]["stage"], 3)
			message(id, "Alien destroyed. Your share: +%d credits. Return to repair." % reward)
		contributors.clear()
		alien_respawn = 12.0
		session.sector.select_target(null)
		for id: int in session.commands:
			session.commands[id]["fire"] = false
	else:
		var id: int = session.ships.find_key(ship)
		var fee := mini(records[id]["credits"], Sector.RESPAWN_FEE)
		records[id]["credits"] -= fee
		records[id]["respawn"] = 3.0
		session.commands.erase(id)
		if ship == session.sector.player:
			session.sector.select_target(null)
			ship.release_mouse()
		message(id, "Ship lost. Recovery cost: %d credits. Rescue in three seconds." % fee)


func request_repair() -> bool:
	session.sector.auto_fire = false
	if multiplayer.is_server():
		return repair(1, records[1]["life"])
	repair_request.rpc_id(1, int(session.sector.player.get_meta("life", 0)))
	return false # Host confirms the result asynchronously.


@rpc("any_peer", "call_remote", "reliable")
func repair_request(life: int) -> void:
	if session.active and multiplayer.is_server():
		repair(multiplayer.get_remote_sender_id(), life)


func repair(id: int, life: int) -> bool:
	if not records.has(id) or records[id]["life"] != life:
		return false
	var ship := session.ships[id]
	var blocker := session.sector.repair_blocker(ship)
	if not blocker.is_empty():
		message(id, blocker)
		return false
	var cost := session.sector.repair_cost(ship, records[id]["credits"])
	records[id]["credits"] -= cost
	ship.reset_health()
	ship.energy = 100.0
	session.commands.erase(id)
	if records[id]["stage"] >= 3:
		records[id]["stage"] = 4
	message(id, "Repairs complete. Cost: %d credits." % cost)
	if id == 1:
		session.sector.auto_fire = false
	return true


func health(ship: SpaceShip) -> Dictionary:
	return {"hull": ship.hull, "shield": ship.shield, "alive": ship.alive, "since_hit": ship.time_since_hit}


func pack_player(id: int) -> Dictionary:
	var data := health(session.ships[id])
	data.merge(records[id])
	return data


func pack_alien() -> Dictionary:
	var data := health(session.sector.alien)
	data.merge({"position": session.sector.alien.position, "rotation": session.sector.alien.rotation, "respawn": alien_respawn, "encounter": encounter})
	return data


func apply_health(ship: SpaceShip, data: Dictionary) -> void:
	ship.hull = data["hull"]
	ship.shield = data["shield"]
	ship.alive = data["alive"]
	ship.time_since_hit = data["since_hit"]
	ship.visible = ship.alive
	ship.set_collision_layer_value(2, ship.alive)
	if not ship.alive:
		ship.velocity = Vector3.ZERO


func apply_player(id: int, data: Dictionary) -> bool:
	var ship := session.ships[id]
	var reset: bool = int(ship.get_meta("life", 0)) != data["life"] or ship.alive != data["alive"]
	ship.set_meta("life", data["life"])
	apply_health(ship, data)
	if ship == session.sector.player:
		update_local(data)
		if reset:
			session.sector.select_target(null)
			ship.release_mouse()
	return reset


func update_local(data: Dictionary) -> void:
	session.sector.credits = data["credits"]
	session.sector.kills = data["kills"]
	session.sector.objective_stage = maxi(session.sector.objective_stage, data["stage"])
	session.sector.player_respawn = data["respawn"]


func apply_alien(data: Dictionary) -> void:
	var alien := session.sector.alien
	if encounter != data["encounter"] or not data["alive"]:
		session.sector.select_target(null)
	if encounter != data["encounter"] or alien.alive != data["alive"] or alien_goal.is_empty():
		alien.position = data["position"]
		alien.rotation = data["rotation"]
	encounter = data["encounter"]
	apply_health(alien, data)
	alien_goal = data
	session.sector.alien_respawn = data["respawn"]


func interpolate(delta: float) -> void:
	if alien_goal.is_empty():
		return
	var alien := session.sector.alien
	alien.position = alien.position.lerp(alien_goal["position"], minf(1.0, delta * 15.0))
	var angles: Vector3 = alien_goal["rotation"]
	for axis in range(3):
		alien.rotation[axis] = lerp_angle(alien.rotation[axis], angles[axis], minf(1.0, delta * 15.0))


func message(id: int, text: String) -> void:
	if id == 1:
		receive_message(text)
	else:
		receive_message.rpc_id(id, text)


@rpc("authority", "call_remote", "reliable")
func receive_message(text: String) -> void:
	if session.active:
		session.sector.notify(text)


@rpc("authority", "call_local", "unreliable", 3)
func show_laser(start: Vector3, finish: Vector3, hostile: bool) -> void:
	if session.active:
		SectorVisuals.laser(session.sector, start, finish, hostile)


@rpc("authority", "call_local", "reliable")
func show_explosion(location: Vector3) -> void:
	if session.active:
		SectorVisuals.explosion(session.sector, location)


func finish() -> void:
	if not solo.is_empty():
		session.sector.credits = solo["credits"]
		session.sector.kills = solo["kills"]
		session.sector.objective_stage = solo["stage"]
	solo.clear()
	records.clear()
	contributors.clear()
	alien_goal.clear()
	session.sector.player.simulation_authority = true
	session.sector.alien.simulation_authority = true
