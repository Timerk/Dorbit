class_name SessionCombat
extends Node
## Host-owned encounter state. Clients send intent and receive snapshots, never damage or money.

var session: FlightSession
var records: Dictionary[int, Dictionary] = {}
var solo: Dictionary = {}
var inventory: Dictionary = {}
var station_pending: bool = false
var station_message: String = ""


func begin() -> void:
	var sector := session.sector
	sector.active_contract = {}
	solo = {"credits": sector.credits, "kills": sector.kills, "stage": sector.objective_stage}
	records.clear()
	sector.credits = 0
	sector.kills = 0
	sector.objective_stage = 0
	sector.player_respawn = 0.0
	if not sector.dedicated_server:
		sector.player.simulation_authority = multiplayer.is_server()
	for alien: Alien in sector.aliens.values():
		alien.simulation_authority = multiplayer.is_server()
		alien.position = alien.home_position
		alien.patrol_time = 0.0
		alien.life = 0
		alien.respawn = 0.0
		alien.returning = false
		alien.engaged = false
		alien.contributors.clear()
		alien.snapshot_goal.clear()
		alien.reset_health()
		alien.set_meta("feedback_health_received", false)
		alien.visible = multiplayer.is_server()
		if not alien.damaged.is_connected(record_damage):
			alien.damaged.connect(record_damage)
	sector.notify("Scouts near the approach. Sentinels ahead. Heavy on the right flank.")


func add_player(id: int, location: Vector3) -> void:
	var ship := session.ships[id]
	ship.simulation_authority = multiplayer.is_server()
	ship.set_meta("life", 0)
	ship.set_meta("feedback_health_received", false)
	if multiplayer.is_server():
		records[id] = {"credits": 0, "kills": 0, "stage": 0, "respawn": 0.0, "life": 0, "spawn": location}
		records[id]["contract"] = {}
		if session.sector.dedicated_server:
			records[id]["credits"] = session.store.pilots[session.pilot_ids[id]]["credits"]
			records[id]["contract"] = session.store.pilots[session.pilot_ids[id]]["contract"].duplicate()
			Equipment.apply_stats(ship, Equipment.stats(session.store.pilots[session.pilot_ids[id]]["equipment"]))
			ship.reset_health() # Initial spawn, not a fitting change.


func remove_player(id: int) -> void:
	records.erase(id)
	for alien: Alien in session.sector.aliens.values():
		alien.contributors.erase(id)


func record_damage(ship: SpaceShip, attacker: SpaceShip) -> void:
	if not session.active or not multiplayer.is_server():
		return
	var id: Variant = session.ships.find_key(attacker)
	var alien := ship as Alien
	if id != null and id not in alien.contributors:
		alien.contributors.append(id)


func tick(delta: float) -> void:
	var sector := session.sector
	for alien: Alien in sector.aliens.values():
		alien.check_retreat(choose_target(alien))
		if sector.target == alien and not alien.available():
			sector.select_target(null)
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
		var enemy: Alien = sector.target as Alien if id == 1 else remote_target(id)
		var firing := sector.auto_fire and not sector.paused if id == 1 else remote_firing(id)
		if firing and is_instance_valid(enemy) and enemy.available():
			records[id]["stage"] = maxi(records[id]["stage"], 2)
			ship.try_fire(enemy)
	for alien: Alien in sector.aliens.values():
		alien.tick_combat(delta)
		if alien.alive:
			alien.fly(delta, choose_target(alien), Sector.STATION_POSITION)
		else:
			alien.respawn = maxf(0.0, alien.respawn - delta)
			if alien.respawn <= 0.0:
				alien.position = alien.home_position
				alien.returning = false
				alien.reset_encounter()
	if records.has(1):
		update_local(records[1])


func remote_target(id: int) -> Alien:
	return session.sector.aliens.get(session.commands.get(id, {}).get("target", -1))


func remote_firing(id: int) -> bool:
	var command: Dictionary = session.commands.get(id, {})
	var alien := remote_target(id)
	return is_instance_valid(alien) and alien.available() and command.get("fire", false) and command.get("encounter", -1) == alien.life and Time.get_ticks_msec() - command["time"] < FlightSession.COMMAND_TIMEOUT * 1000


func choose_target(alien: Alien) -> Pilot:
	var target: Pilot = null
	var nearest: float = alien.tuning()["detection"]
	for ship: Pilot in session.ships.values():
		if not ship.alive or ship.position.distance_to(Sector.STATION_POSITION) <= 75.0:
			continue
		var distance := ship.position.distance_to(alien.position)
		if distance < nearest:
			target = ship
			nearest = distance
	return target


func destroyed(ship: SpaceShip) -> void:
	if not multiplayer.is_server():
		return
	show_explosion.rpc(ship.position)
	if ship is Alien:
		var alien := ship as Alien
		var contributors := alien.contributors
		var pool: int = alien.tuning()["reward"]
		# Conserve each pool; distribute integer remainders in peer-ID order.
		contributors.sort()
		var balances: Dictionary[int, int] = {}
		var contracts: Dictionary[int, Dictionary] = {}
		for index in range(contributors.size()):
			var id := contributors[index]
			var reward := int(pool / contributors.size()) + (1 if index < pool % contributors.size() else 0)
			balances[id] = mini(PilotStore.MAX_CREDITS, records[id]["credits"] + reward)
			contracts[id] = HuntingContracts.after_kill(records[id]["contract"], alien.kind.to_lower())
		if not balances.is_empty() and not session.save_balances(balances, contracts):
			return
		for id: int in balances:
			var reward: int = balances[id] - records[id]["credits"]
			records[id]["credits"] = balances[id]
			records[id]["contract"] = contracts[id]
			records[id]["kills"] += 1
			records[id]["stage"] = maxi(records[id]["stage"], 3)
			message(id, "Alien destroyed. Your share: +%d credits. Return to repair." % reward)
		contributors.clear()
		alien.respawn = alien.tuning()["respawn"]
		if session.sector.target == alien:
			session.sector.select_target(null)
		for id: int in session.commands:
			if session.commands[id].get("target", -1) == alien.alien_id:
				session.commands[id]["fire"] = false
	else:
		var id: int = session.ships.find_key(ship)
		var fee := mini(records[id]["credits"], Sector.RESPAWN_FEE)
		if not session.save_balances({id: records[id]["credits"] - fee}):
			return
		records[id]["credits"] -= fee
		records[id]["respawn"] = 3.0
		session.commands.erase(id)
		if ship == session.sector.player:
			session.sector.select_target(null)
			ship.release_mouse()
		message(id, "Ship lost. Recovery cost: %d credits. Rescue in three seconds." % fee)


func request_repair() -> bool:
	if session.sector.dedicated_server:
		return false
	session.sector.auto_fire = false
	if multiplayer.is_server():
		return repair(1, records[1]["life"])
	repair_request.rpc_id(1, int(session.sector.player.get_meta("life", 0)))
	return false # Host confirms the result asynchronously.


func request_contract(action: String, offer: String = "") -> void:
	if not session.active or session.sector.dedicated_server:
		return
	var current := session.sector.active_contract
	var run: String = current.get("run", "")
	var life := int(session.sector.player.get_meta("life", 0))
	if multiplayer.is_server():
		contract_action(1, life, action, offer, run)
	else:
		contract_request.rpc_id(1, life, action, offer, run)


@rpc("any_peer", "call_remote", "reliable")
func contract_request(life: int, action: String, offer: String, run: String) -> void:
	if session.active and multiplayer.is_server():
		contract_action(multiplayer.get_remote_sender_id(), life, action, offer, run)


# A run ID prevents old claim/abandon requests from affecting a repeated trip.
func contract_action(id: int, life: int, action: String, offer: String, run: String) -> bool:
	if not multiplayer.is_server() or not records.has(id) or records[id]["life"] != life:
		return false
	var blocker := session.sector.repair_blocker(session.ships[id])
	if not blocker.is_empty():
		message(id, blocker)
		return false
	var current: Dictionary = records[id]["contract"]
	var next: Dictionary = {}
	var balance: int = records[id]["credits"]
	var notice: String
	match action:
		"accept":
			if not current.is_empty() or not run.is_empty() or not HuntingContracts.OFFERS.has(offer):
				return false
			next = HuntingContracts.accept(offer)
			notice = "Contract accepted. " + HuntingContracts.objective(next)
		"claim":
			if not HuntingContracts.ready(current) or current["run"] != run:
				return false
			if balance > PilotStore.MAX_CREDITS - current["reward"]:
				message(id, "Spend credits before claiming this reward. Your contract is still ready.")
				return false
			balance += current["reward"]
			notice = "Contract claimed: +%d credits. Choose another hunt at the station." % current["reward"]
		"abandon":
			if current.is_empty() or current["run"] != run:
				return false
			notice = "Contract abandoned. No credits charged."
		_:
			return false
	if not session.save_balances({id: balance}, {id: next}):
		return false
	records[id]["credits"] = balance
	records[id]["contract"] = next
	session.commands.erase(id)
	message(id, notice)
	if id == 1:
		update_local(records[id])
	return true


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
	if not session.save_balances({id: records[id]["credits"] - cost}):
		return false
	records[id]["credits"] -= cost
	ship.reset_health()
	ship.energy = 100.0
	session.commands.erase(id)
	if records[id]["stage"] >= 3:
		records[id]["stage"] = 4
	message(id, "Repairs complete. Cost: %d credits." % cost, "purchase")
	if id == 1:
		session.sector.auto_fire = false
	return true


func health(ship: SpaceShip) -> Dictionary:
	return {"hull": ship.hull, "shield": ship.shield, "alive": ship.alive, "since_hit": ship.time_since_hit}


func pack_player(id: int) -> Dictionary:
	var data := health(session.ships[id])
	data.merge(records[id])
	var ship := session.ships[id]
	# Fixed four-number wire format keeps two-player snapshot chunks below the MTU.
	data["stats"] = Vector4(ship.laser_damage, ship.max_shield, ship.cruise_speed, ship.boost_speed)
	return data


func pack_alien(alien: Alien) -> Dictionary:
	var data := health(alien)
	data.merge({"id": alien.alien_id, "kind": alien.kind, "position": alien.position, "rotation": alien.rotation, "respawn": alien.respawn, "encounter": alien.life, "returning": alien.returning, "engaged": alien.engaged})
	return data


func apply_health(ship: SpaceShip, data: Dictionary) -> void:
	# Only decreases in authoritative snapshots produce feedback; initial joins and rescue do not.
	if ship.alive and bool(ship.get_meta("feedback_health_received", false)):
		ship.present_impact(float(data["shield"]) < ship.shield, float(data["hull"]) < ship.hull)
	ship.set_meta("feedback_health_received", true)
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
	var stats: Vector4 = data["stats"]
	Equipment.apply_stats(ship, {"damage": stats.x, "shield": stats.y, "speed": stats.z, "boost": stats.w})
	apply_health(ship, data)
	if ship == session.sector.player:
		update_local(data)
		if reset:
			session.sector.select_target(null)
			ship.release_mouse()
	return reset


func update_local(data: Dictionary) -> void:
	session.sector.active_contract = data.get("contract", {}).duplicate()
	session.sector.credits = data["credits"]
	session.sector.kills = data["kills"]
	session.sector.objective_stage = maxi(session.sector.objective_stage, data["stage"])
	session.sector.player_respawn = data["respawn"]


func apply_alien(data: Dictionary) -> void:
	var alien: Alien = session.sector.aliens.get(data["id"])
	if alien == null or alien.kind != data["kind"]:
		return
	var reset: bool = alien.life != data["encounter"] or alien.alive != data["alive"]
	if session.sector.target == alien and (reset or data["returning"]):
		session.sector.select_target(null)
	if reset or alien.snapshot_goal.is_empty() or alien.returning != data["returning"]:
		alien.position = data["position"]
		alien.rotation = data["rotation"]
	alien.life = data["encounter"]
	alien.returning = data["returning"]
	alien.engaged = data["engaged"]
	alien.respawn = data["respawn"]
	apply_health(alien, data)
	alien.snapshot_goal = data


func interpolate(delta: float) -> void:
	for alien: Alien in session.sector.aliens.values():
		if alien.snapshot_goal.is_empty():
			continue
		alien.position = alien.position.lerp(alien.snapshot_goal["position"], minf(1.0, delta * 15.0))
		var angles: Vector3 = alien.snapshot_goal["rotation"]
		for axis in range(3):
			alien.rotation[axis] = lerp_angle(alien.rotation[axis], angles[axis], minf(1.0, delta * 15.0))


func message(id: int, text: String, sound_cue: String = "") -> void:
	if id == 1:
		receive_message(text, sound_cue)
	else:
		receive_message.rpc_id(id, text, sound_cue)


@rpc("authority", "call_remote", "reliable")
func receive_message(text: String, sound_cue: String = "") -> void:
	if session.active:
		session.sector.notify(text)
		if not sound_cue.is_empty() and not session.sector.dedicated_server:
			SectorVisuals.sound(session.sector, sound_cue, session.sector.player.position)


@rpc("authority", "call_local", "unreliable", 3)
func show_laser(start: Vector3, finish: Vector3, hostile: bool) -> void:
	if session.active and not session.sector.dedicated_server:
		SectorVisuals.laser(session.sector, start, finish, hostile)


@rpc("authority", "call_local", "reliable")
func show_explosion(location: Vector3) -> void:
	if session.active and not session.sector.dedicated_server:
		SectorVisuals.explosion(session.sector, location)


func finish() -> void:
	session.sector.active_contract = {}
	inventory.clear()
	station_pending = false
	station_message = ""
	if not solo.is_empty():
		session.sector.credits = solo["credits"]
		session.sector.kills = solo["kills"]
		session.sector.objective_stage = solo["stage"]
	solo.clear()
	records.clear()
	for alien: Alien in session.sector.aliens.values():
		alien.contributors.clear()
		alien.snapshot_goal.clear()
		alien.simulation_authority = true
	if not session.sector.dedicated_server:
		session.sector.player.simulation_authority = true
		Equipment.apply_stats(session.sector.player, Equipment.stats(Equipment.starter()))


func request_station(action: String, subject: String, ship: String = "", slot: String = "") -> void:
	if station_pending or inventory.is_empty() or not session.active:
		return
	station_pending = true
	station_message = "Waiting for server..."
	station_request.rpc_id(1, int(inventory["revision"]) + 1, action, subject, ship, slot, int(session.sector.player.get_meta("life", 0)))


@rpc("any_peer", "call_remote", "reliable")
func station_request(sequence: int, action: String, subject: String, ship: String, slot: String, life: int) -> void:
	if not session.active or not multiplayer.is_server() or not session.sector.dedicated_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not records.has(id) or not session.pilot_ids.has(id):
		return
	var blocker := session.sector.repair_blocker(session.ships[id])
	if records[id]["life"] != life:
		blocker = "Ship changed. Review your fitting after rescue."
	if not blocker.is_empty():
		publish_inventory(id, blocker)
		return
	var pilot_id := session.pilot_ids[id]
	var result := session.store.transact(pilot_id, sequence, action, subject, ship, slot)
	if session.store.failed:
		session.stop_for_save_failure()
		return
	var pilot: Dictionary = session.store.pilots[pilot_id]
	records[id]["credits"] = pilot["credits"]
	Equipment.apply_stats(session.ships[id], Equipment.stats(pilot["equipment"]))
	publish_inventory(id, result)


func publish_inventory(id: int, result: String = "") -> void:
	if session.sector.dedicated_server:
		station_result.rpc_id(id, session.store.pilots[session.pilot_ids[id]]["equipment"], result)


@rpc("authority", "call_remote", "reliable")
func station_result(data: Dictionary, result: String) -> void:
	if session.active:
		inventory = data
		station_pending = false
		station_message = result
