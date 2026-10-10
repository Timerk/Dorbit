class_name SessionCombat
extends Node
## Host-owned encounter state. Clients send intent and receive snapshots, never damage or money.

var session: FlightSession
var records: Dictionary[int, Dictionary] = {}
var solo: Dictionary = {}
var inventory: Dictionary = {}
var cargo_holds: Dictionary[int, Dictionary] = {}
var station_pending: bool = false
var station_message: String = ""
var preview_tools_available: bool = false
var ammo_sequence: int = -1
var boost_save_clock: float = 0.0
var boost_sequence: int = -1
var lab_snapshot: Dictionary = {}
var rocket_request_sequence: int = 0
var rocket_sequences: Dictionary[int, int] = {}


func connect_rockets(ship: Pilot) -> void:
	if not ship.rockets.launched.is_connected(on_rocket_launch):
		ship.rockets.launched.connect(on_rocket_launch)
		ship.rockets.resolved.connect(on_rocket_resolved)


func debit_rockets(kind: String, count: int, id: int) -> bool:
	var ship := session.ships[id]
	var pilot_id: String = session.pilot_ids[id]
	var pilot: Dictionary = session.store.pilots[pilot_id]
	var next := ship.ammo.duplicate()
	next[kind] -= count
	var boost := ship.resource_boosts.duplicate(true)
	ResourceBoosts.consume_rockets(boost, count)
	var holds: Dictionary = pilot["boosts"].duplicate(true)
	holds[pilot["equipment"]["active_ship"]] = boost
	if session.store.commit_combat({pilot_id: next}, {pilot_id: holds}):
		ship.resource_boosts = boost
		return true
	session.stop_for_save_failure()
	return false


func request_rocket(action: String, kind: String = "") -> void:
	var sector := session.sector
	if sector.paused or sector.preflight or not sector.player.alive or (sector.client_only and not session.active):
		return
	var enemy := sector.target as Alien
	if not session.active or multiplayer.is_server():
		var result := rocket_action(sector.player, action, kind, enemy)
		if not result.is_empty():
			sector.notify(result)
	else:
		rocket_request_sequence += 1
		rocket_request.rpc_id(1, rocket_request_sequence, int(sector.player.get_meta("life", 0)), action, kind, enemy.alien_id if is_instance_valid(enemy) else -1, enemy.life if is_instance_valid(enemy) else -1)


@rpc("any_peer", "call_remote", "reliable")
func rocket_request(sequence: int, life: int, action: String, kind: String, target_id: int, encounter: int) -> void:
	if not session.active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not records.has(id) or sequence <= rocket_sequences.get(id, 0):
		return
	rocket_sequences[id] = sequence # Reject replays, including previously rejected shots.
	var ship := session.ships[id]
	if records[id]["life"] != life or not ship.alive or ship.get_meta("docked", false):
		return
	var enemy: Alien = session.sector.aliens.get(target_id)
	if is_instance_valid(enemy) and enemy.life != encounter:
		enemy = null
	var result := rocket_action(ship, action, kind, enemy)
	if not result.is_empty():
		message(id, result)


func rocket_action(ship: Pilot, action: String, kind: String, target: Alien) -> String:
	match action:
		"select":
			return "" if ship.rockets.select(kind) else "UNKNOWN ROCKET AMMUNITION"
		"single":
			return ship.rockets.fire_single(target)
		"launcher":
			return ship.rockets.activate(target)
		"unload":
			ship.rockets.unload()
			return "LAUNCHER UNLOADED"
	return "UNKNOWN ROCKET ACTION"


func on_rocket_launch(event: Dictionary) -> void:
	if session.active and multiplayer.is_server():
		show_rocket.rpc(event)
	elif not session.active:
		show_rocket(event)


func on_rocket_resolved(id: String, location: Vector3, hit: bool) -> void:
	if session.active and multiplayer.is_server():
		resolve_rocket.rpc(id, location, hit)
	elif not session.active:
		resolve_rocket(id, location, hit)


@rpc("authority", "call_local", "reliable")
func show_rocket(event: Dictionary) -> void:
	if not session.sector.dedicated_server:
		RocketEffect.spawn(session.sector, event)


@rpc("authority", "call_local", "reliable")
func resolve_rocket(id: String, location: Vector3, hit: bool) -> void:
	if not session.sector.dedicated_server:
		RocketEffect.resolve(session.sector, id, location, hit)


func begin() -> void:
	var sector := session.sector
	sector.active_contracts = {}
	solo = {"credits": sector.credits, "kills": sector.kills, "stage": sector.objective_stage, "cargo": sector.cargo.duplicate(true)}
	if not sector.dedicated_server:
		solo["ammo"] = sector.player.ammo.duplicate()
		solo["ammo_type"] = sector.player.ammo_type
	sector.cargo = {}
	sector.loot.clear()
	cargo_holds.clear()
	records.clear()
	boost_save_clock = 0.0
	boost_sequence = -1
	sector.credits = 0
	sector.kills = 0
	sector.objective_stage = 0
	sector.player_respawn = 0.0
	if not sector.dedicated_server:
		sector.player.simulation_authority = multiplayer.is_server()
	for alien: Alien in sector.aliens.values():
		alien.simulation_authority = multiplayer.is_server()
		if multiplayer.is_server():
			sector.relocate_alien(alien)
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
	sector.notify("Alien contacts scattered across the sector. Press M to choose a destination.")


func add_player(id: int, location: Vector3) -> void:
	var ship := session.ships[id]
	connect_rockets(ship)
	ship.simulation_authority = multiplayer.is_server()
	ship.set_meta("life", 0)
	ship.set_meta("feedback_health_received", false)
	if multiplayer.is_server():
		records[id] = {"credits": 0, "kills": 0, "stage": 0, "respawn": 0.0, "life": 0, "spawn": location}
		records[id]["contracts"] = {}
		cargo_holds[id] = CargoResources.empty_holds(Equipment.starter())
		if session.sector.dedicated_server:
			ship.ammo = session.store.pilots[session.pilot_ids[id]]["ammo"].duplicate()
			ship.ammo_debit = debit_ammo.bind(id)
			ship.rockets.debit = debit_rockets.bind(id)
			cargo_holds[id] = session.store.pilots[session.pilot_ids[id]]["cargo"].duplicate(true)
			records[id]["credits"] = session.store.pilots[session.pilot_ids[id]]["credits"]
			records[id]["contracts"] = session.store.pilots[session.pilot_ids[id]]["contracts"].duplicate(true)
			apply_equipment(id)
			ship.reset_health() # Initial spawn, not a fitting change.


func apply_equipment(id: int) -> void:
	var pilot: Dictionary = session.store.pilots[session.pilot_ids[id]]
	var ship := session.ships[id]
	ship.resource_boosts = pilot["boosts"][pilot["equipment"]["active_ship"]].duplicate(true)
	Equipment.apply_stats(ship, ResourceBoosts.stats(Equipment.stats(pilot["equipment"]), ship.resource_boosts))


func flush_boosts(ids: Array = []) -> bool:
	if not session.active or not session.sector.dedicated_server or session.store == null or session.store.failed:
		return true
	var saved := {}
	for id: int in (records.keys() if ids.is_empty() else ids):
		if not session.pilot_ids.has(id) or not session.ships.has(id):
			continue
		var pilot_id: String = session.pilot_ids[id]
		var pilot: Dictionary = session.store.pilots[pilot_id]
		var next: Dictionary = pilot["boosts"].duplicate(true)
		var ship: String = pilot["equipment"]["active_ship"]
		if next[ship] != session.ships[id].resource_boosts:
			next[ship] = session.ships[id].resource_boosts.duplicate(true)
			saved[pilot_id] = next
	return saved.is_empty() or session.store.commit_combat({}, saved)


func remove_player(id: int) -> void:
	rocket_sequences.erase(id)
	records.erase(id)
	cargo_holds.erase(id)
	for alien: Alien in session.sector.aliens.values():
		alien.contributors.erase(id)


func debit_ammo(id: int) -> bool:
	var ship := session.ships[id]
	var pilot_id: String = session.pilot_ids[id]
	var pilot: Dictionary = session.store.pilots[pilot_id]
	var next_ammo := ship.ammo.duplicate()
	next_ammo[ship.ammo_type] -= ship.laser_count
	var next_boosts: Dictionary = pilot["boosts"].duplicate(true)
	var boost: Dictionary = ship.resource_boosts.duplicate(true)
	next_boosts[pilot["equipment"]["active_ship"]] = boost
	if boost.has("lasers"):
		boost["lasers"]["remaining"] = maxi(0, int(boost["lasers"]["remaining"]) - ship.laser_count)
		if boost["lasers"]["remaining"] == 0:
			boost.erase("lasers")
	# One write commits ammunition, laser reserve and live timed reserves together.
	if session.store.commit_combat({pilot_id: next_ammo}, {pilot_id: next_boosts}):
		ship.resource_boosts = boost.duplicate(true)
		return true
	session.stop_for_save_failure()
	return false


func request_ammo(kind: String) -> void:
	if Ammunition.ROCKETS.has(kind):
		request_rocket("select", kind)
		return
	if not Ammunition.TYPES.has(kind) or session.sector.paused or session.sector.preflight or not session.sector.player.alive:
		return
	if not session.active or multiplayer.is_server():
		session.sector.player.ammo_type = kind
	else:
		select_ammo.rpc_id(1, int(session.sector.player.get_meta("life", 0)), kind)


@rpc("any_peer", "call_remote", "reliable")
func select_ammo(life: int, kind: String) -> void:
	if not session.active or not multiplayer.is_server() or not Ammunition.TYPES.has(kind):
		return
	var id := multiplayer.get_remote_sender_id()
	if not records.has(id) or records[id]["life"] != life or not session.ships[id].alive or session.ships[id].get_meta("docked", false):
		return
	session.ships[id].ammo_type = kind


func record_damage(ship: SpaceShip, attacker: SpaceShip) -> void:
	if not session.active or not multiplayer.is_server():
		return
	var id: Variant = session.ships.find_key(attacker)
	var alien := ship as Alien
	if id != null and id not in alien.contributors:
		alien.contributors.append(id)


func tick(delta: float) -> void:
	var sector := session.sector
	boost_save_clock += delta
	for alien: Alien in sector.aliens.values():
		alien.check_retreat(choose_target(alien))
		if sector.target == alien and not alien.available():
			if not alien.alive:
				sector.select_target(null)
			else:
				sector.auto_fire = false
	if sector.dedicated_server: session.store.begin_combat_tick()
	for id: int in records:
		pay_pending_contracts(id)
		var ship := session.ships[id]
		if sector.dedicated_server:
			var expired := false
			for group: String in ["shields", "engines"]:
				if not ship.resource_boosts.has(group):
					continue
				ship.resource_boosts[group]["remaining"] = maxf(0, ResourceBoosts.remaining(ship.resource_boosts, group) - delta)
				if ResourceBoosts.remaining(ship.resource_boosts, group) <= 0:
					ship.resource_boosts.erase(group)
					expired = true
			if expired:
				var pilot: Dictionary = session.store.pilots[session.pilot_ids[id]]
				Equipment.apply_stats(ship, ResourceBoosts.stats(Equipment.stats(pilot["equipment"]), ship.resource_boosts))
		ship.tick_combat(delta)
		if not ship.alive:
			records[id]["respawn"] = maxf(0.0, records[id]["respawn"] - delta)
			if records[id]["respawn"] <= 0.0:
				ship.reset_health()
				if ship.get_meta("docked", false):
					ship.hide()
					ship.collision_layer = 0
				ship.energy = 100.0
				ship.position = records[id]["spawn"]
				ship.rotation = Vector3.ZERO
				records[id]["life"] += 1
				ship.set_meta("life", records[id]["life"])
				session.commands.erase(id)
			continue
		if ship.get_meta("docked", false):
			continue
		if ship.position.distance_to(Sector.STATION_POSITION) > Sector.PROTECTION_RADIUS:
			records[id]["stage"] = maxi(records[id]["stage"], 1)
		var enemy: Alien = sector.target as Alien if id == 1 else remote_target(id)
		var firing := sector.auto_fire and not sector.paused if id == 1 else remote_firing(id)
		if firing and is_instance_valid(enemy) and enemy.available():
			records[id]["stage"] = maxi(records[id]["stage"], 2)
			ship.try_fire(enemy)
	if sector.dedicated_server: session.store.end_combat_tick()
	if sector.dedicated_server and session.store.failed: return
	for alien: Alien in sector.aliens.values():
		alien.tick_combat(delta)
		if alien.alive:
			alien.fly(delta, choose_target(alien), Sector.STATION_POSITION)
		else:
			alien.respawn = maxf(0.0, alien.respawn - delta)
			if alien.respawn <= 0.0:
				sector.relocate_alien(alien)
				alien.returning = false
				alien.reset_encounter()
	if records.has(1):
		update_local(records[1])
	if sector.dedicated_server and boost_save_clock >= 5.0:
		boost_save_clock = 0.0
		if not flush_boosts():
			session.stop_for_save_failure()
			return
	sector.loot.tick(delta)


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
		if ship.get_meta("docked", false) or not ship.alive or ship.position.distance_to(Sector.STATION_POSITION) <= Sector.PROTECTION_RADIUS:
			continue
		var distance := ship.position.distance_to(alien.position)
		if distance < nearest:
			target = ship
			nearest = distance
	return target


func destroyed(ship: SpaceShip) -> void:
	if not multiplayer.is_server():
		return
	show_explosion.rpc(ship.position, SectorVisuals.destruction_size(ship))
	if ship is Alien:
		var alien := ship as Alien
		var contributors := alien.contributors
		var pool: int = alien.tuning()["reward"]
		# Conserve each pool; distribute integer remainders in peer-ID order.
		contributors.sort()
		var balances: Dictionary[int, int] = {}
		var contracts: Dictionary[int, Dictionary] = {}
		var payouts: Dictionary[int, Dictionary] = {}
		for index in range(contributors.size()):
			var id := contributors[index]
			var reward := int(pool / contributors.size()) + (1 if index < pool % contributors.size() else 0)
			balances[id] = mini(PilotStore.MAX_CREDITS, records[id]["credits"] + reward)
			var next: Dictionary = records[id]["contracts"].duplicate(true)
			var kind := alien.kind.to_lower()
			if next.has(kind):
				next[kind] = HuntingContracts.after_kill(next[kind], kind)
			payouts[id] = HuntingContracts.settle(next, balances[id])
			balances[id] = payouts[id]["credits"]
			contracts[id] = payouts[id]["contracts"]
		if not balances.is_empty() and not session.save_balances(balances, contracts):
			return
		session.sector.loot.spawn_drop(alien)
		for id: int in balances:
			var reward: int = balances[id] - records[id]["credits"] - payouts[id]["reward"]
			records[id]["credits"] = balances[id]
			records[id]["contracts"] = contracts[id]
			records[id]["kills"] += 1
			records[id]["stage"] = maxi(records[id]["stage"], 3)
			var notice := "Alien destroyed. Your share: +%d credits." % reward
			if payouts[id]["reward"] > 0:
				notice += " %s hunt completed: +%d credits paid automatically." % [", ".join(payouts[id]["paid"]), payouts[id]["reward"]]
			message(id, notice)
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
			session.sector.autopilot.cancel()
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


func pay_pending_contracts(id: int) -> void:
	var payout := HuntingContracts.settle(records[id]["contracts"], records[id]["credits"])
	if payout["reward"] == 0:
		return
	if not session.save_balances({id: payout["credits"]}, {id: payout["contracts"]}):
		return
	records[id]["credits"] = payout["credits"]
	records[id]["contracts"] = payout["contracts"]
	message(id, "%s hunt completed: +%d credits paid automatically." % [", ".join(payout["paid"]), payout["reward"]])


func request_contract(action: String, offer: String = "") -> void:
	if not session.active or session.sector.dedicated_server:
		return
	var current: Dictionary = session.sector.active_contracts.get(offer, {})
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


# A run ID prevents old abandon requests from affecting a repeated hunt.
func contract_action(id: int, life: int, action: String, offer: String, run: String) -> bool:
	if not multiplayer.is_server() or not records.has(id) or records[id]["life"] != life:
		return false
	var blocker := session.sector.repair_blocker(session.ships[id])
	if not blocker.is_empty():
		message(id, blocker)
		return false
	var current: Dictionary = records[id]["contracts"]
	var next := current.duplicate(true)
	var balance: int = records[id]["credits"]
	var notice: String
	match action:
		"accept":
			if current.has(offer) or not run.is_empty() or not HuntingContracts.OFFERS.has(offer):
				return false
			next[offer] = HuntingContracts.accept(offer)
			notice = "Contract accepted. " + HuntingContracts.objective(next[offer])
		"abandon":
			if not current.has(offer) or current[offer]["run"] != run:
				return false
			next.erase(offer)
			notice = "Contract abandoned. No credits charged."
		_:
			return false
	if not session.save_balances({id: balance}, {id: next}):
		return false
	records[id]["credits"] = balance
	records[id]["contracts"] = next
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
	if ship.get_meta("docked", false):
		message(id, "Launch before requesting repairs.")
		return false
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
	# The rescue/dock origin stays on the authority; clients receive current position.
	data.erase("spawn")
	var ship := session.ships[id]
	# Replicate combat and movement stats without exposing the owner's full inventory.
	data["stats"] = Vector4(ship.laser_damage, ship.max_shield, ship.cruise_speed, ship.boost_speed)
	data["absorption"] = ship.shield_absorption
	data["model"] = ship.ship_model
	data["max_hull"] = ship.max_hull
	data["npc_damage"] = ship.npc_laser_damage
	data["regen_bonus"] = ship.shield_regen_bonus
	data["radiation"] = ship.radiation_exposure
	data["docked"] = ship.get_meta("docked", false)
	return data


func publish_ammo(id: int, sequence: int) -> void:
	if id == 1:
		return # Listen-host pilot already owns its authoritative inventory.
	var ship := session.ships[id]
	var rounds := PackedInt32Array()
	for kind: String in Ammunition.types():
		rounds.append(ship.ammo[kind])
	rounds.append(Ammunition.TYPES.keys().find(ship.ammo_type))
	ammo_snapshot.rpc_id(id, rounds, sequence, ship.rockets.state())


@rpc("authority", "call_remote", "unreliable_ordered", 4)
func ammo_snapshot(rounds: PackedInt32Array, sequence: int, rocket_data: Dictionary = {}) -> void:
	if not session.active or sequence <= ammo_sequence:
		return
	ammo_sequence = sequence
	var ship := session.sector.player
	for index in range(Ammunition.types().size()):
		ship.ammo[Ammunition.types().keys()[index]] = int(rounds[index])
	ship.ammo_type = Ammunition.TYPES.keys()[rounds[Ammunition.types().size()]]
	if not rocket_data.is_empty():
		ship.rockets.apply_state(rocket_data)


func pack_alien(alien: Alien) -> Dictionary:
	var data := health(alien)
	data.merge({"id": alien.alien_id, "kind": alien.kind, "home": alien.home_position, "position": alien.position, "rotation": alien.rotation, "respawn": alien.respawn, "encounter": alien.life, "returning": alien.returning, "engaged": alien.engaged})
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
	if data.get("docked", false):
		ship.hide()
		ship.collision_layer = 0
	if not ship.alive:
		ship.velocity = Vector3.ZERO


func apply_player(id: int, data: Dictionary) -> bool:
	var ship := session.ships[id]
	var reset: bool = int(ship.get_meta("life", 0)) != data["life"] or ship.alive != data["alive"]
	ship.set_meta("life", data["life"])
	if reset:
		ship.set_meta("feedback_health_received", false)
	var stats: Vector4 = data["stats"]
	Equipment.apply_stats(ship, {"model": data["model"], "hull": data["max_hull"], "npc_damage": data["npc_damage"], "regen_bonus": data["regen_bonus"], "damage": stats.x, "shield": stats.y, "absorption": data["absorption"], "speed": stats.z, "boost": stats.w})
	apply_health(ship, data)
	ship.radiation_exposure = data.get("radiation", 0.0)
	if ship == session.sector.player:
		update_local(data)
		if reset:
			session.sector.select_target(null)
			session.sector.autopilot.cancel()
			ship.release_mouse()
	return reset


func update_local(data: Dictionary) -> void:
	session.sector.active_contracts = data.get("contracts", {}).duplicate(true)
	session.sector.credits = data["credits"]
	session.sector.kills = data["kills"]
	session.sector.objective_stage = maxi(session.sector.objective_stage, data["stage"])
	session.sector.player_respawn = data["respawn"]


func apply_alien(data: Dictionary) -> void:
	var alien: Alien = session.sector.aliens.get(data["id"])
	if alien == null or alien.kind != data["kind"]:
		return
	var reset: bool = alien.life != data["encounter"] or alien.alive != data["alive"]
	if session.sector.target == alien:
		if not data["alive"]:
			session.sector.select_target(null)
		elif reset or data["returning"]:
			# Keep tracking the living alien, but never carry fire into a reset encounter.
			session.sector.auto_fire = false
	if reset or alien.snapshot_goal.is_empty() or alien.returning != data["returning"]:
		alien.position = data["position"]
		alien.rotation = data["rotation"]
	alien.life = data["encounter"]
	alien.home_position = data["home"]
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
func show_laser(start: Vector3, finish: Vector3, hostile: bool, ammo_type: String = "x1") -> void:
	if session.active and not session.sector.dedicated_server:
		SectorVisuals.laser(session.sector, start, finish, hostile, ammo_type)


@rpc("authority", "call_local", "reliable")
func show_explosion(location: Vector3, diameter: float) -> void:
	if session.active and not session.sector.dedicated_server:
		SectorVisuals.explosion(session.sector, location, diameter)


func finish() -> void:
	rocket_request_sequence = 0
	rocket_sequences.clear()
	if is_instance_valid(session.sector.player):
		session.sector.player.rockets.pending.clear()
		session.sector.player.rockets.debit = Callable()
		session.sector.player.rockets.unload()
	session.sector.active_contracts = {}
	session.sector.loot.clear()
	cargo_holds.clear()
	session.sector.cargo = {}
	inventory.clear()
	lab_snapshot.clear()
	preview_tools_available = false
	station_pending = false
	station_message = ""
	ammo_sequence = -1
	boost_sequence = -1
	if not solo.is_empty():
		session.sector.credits = solo["credits"]
		session.sector.kills = solo["kills"]
		session.sector.objective_stage = solo["stage"]
		session.sector.cargo = solo["cargo"]
		if not session.sector.dedicated_server:
			session.sector.player.ammo = solo["ammo"]
			session.sector.player.ammo_type = solo["ammo_type"]
			session.sector.player.ammo_debit = Callable()
	solo.clear()
	records.clear()
	for alien: Alien in session.sector.aliens.values():
		alien.contributors.clear()
		alien.snapshot_goal.clear()
		alien.simulation_authority = true
	if not session.sector.dedicated_server:
		session.sector.player.simulation_authority = true
		session.sector.player.resource_boosts.clear()
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
	var previous_revision: int = session.store.pilots[pilot_id]["equipment"]["revision"]
	var previous_ship: String = session.store.pilots[pilot_id]["equipment"]["active_ship"]
	var result := session.store.transact(pilot_id, sequence, action, subject, ship, slot, session.can_grant_test_credits(id), session.ships[id].resource_boosts)
	if session.store.failed:
		session.stop_for_save_failure()
		return
	var pilot: Dictionary = session.store.pilots[pilot_id]
	records[id]["credits"] = pilot["credits"]
	session.ships[id].ammo = pilot["ammo"].duplicate()
	cargo_holds[id] = pilot["cargo"].duplicate(true)
	if pilot["equipment"]["revision"] > previous_revision:
		apply_equipment(id)
	if previous_ship != pilot["equipment"]["active_ship"]:
		session.ships[id].rockets.unload()
		# Switching is not a repair. Keep absolute hull/shield charge (clamped by
		# the new fitting), boost energy, cooldowns and damage timer.
		records[id]["life"] += 1
		session.ships[id].set_meta("life", records[id]["life"])
		session.commands.erase(id)
		session.ships[id].velocity = Vector3.ZERO
	publish_inventory(id, result)
	if action in ["buy", "buy_ship", "buy_ammo", "sell", "refine", "boost", "replace_boost"] and pilot["equipment"]["revision"] > previous_revision:
		message(id, result, "purchase")


func publish_inventory(id: int, result: String = "") -> void:
	if session.sector.dedicated_server:
		var pilot: Dictionary = session.store.pilots[session.pilot_ids[id]]
		station_result.rpc_id(id, pilot["equipment"], result, session.can_grant_test_credits(id), pilot["cargo"], pilot["credits"], pilot["ammo"], session.snapshot_sequence, session.ships[id].resource_boosts, Skylab.snapshot(pilot, int(pilot["skylab"]["lastSimulatedAt"])))


@rpc("authority", "call_remote", "reliable")
func station_result(data: Dictionary, result: String, test_credits_allowed: bool = false, holds: Dictionary = {}, credits: int = -1, ammo: Dictionary = {}, sequence: int = -1, boosts: Dictionary = {}, lab: Dictionary = {}) -> void:
	if session.active:
		var new_revision := int(data["revision"]) > int(inventory.get("revision", -1))
		inventory = data
		if new_revision or sequence >= boost_sequence:
			session.sector.player.resource_boosts = boosts.duplicate(true)
			boost_sequence = maxi(boost_sequence, sequence)
		session.sector.player.laser_count = Equipment.stats(data)["laser_count"]
		if not ammo.is_empty():
			# A delayed purchase reply must not restore ammunition spent afterward.
			if sequence >= ammo_sequence:
				session.sector.player.ammo = ammo.duplicate()
				ammo_sequence = sequence
		if not holds.is_empty():
			session.sector.cargo = holds[data["active_ship"]].duplicate()
			session.sector.cargo_capacity = CargoResources.capacity(data)
		if credits >= 0:
			session.sector.credits = credits
		preview_tools_available = test_credits_allowed
		station_pending = false
		station_message = result
		if not lab.is_empty():
			lab_snapshot = lab
			if is_instance_valid(session.sector.skylab_menu):
				session.sector.skylab_menu.received()


func request_lab(action: String = "snapshot", payload: Dictionary = {}) -> void:
	if not session.active or session.sector.dedicated_server or multiplayer.is_server() or inventory.is_empty() or station_pending:
		return
	station_pending = true
	station_message = "Waiting for server..."
	skylab_request.rpc_id(1, int(inventory["revision"]) + 1, action, payload)


@rpc("any_peer", "call_remote", "reliable")
func skylab_request(sequence: int, action: String, payload: Dictionary) -> void:
	if not session.active or not multiplayer.is_server() or not session.sector.dedicated_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not records.has(id) or not session.pilot_ids.has(id):
		return
	# Bound the RPC without trusting a client-selected account, recipient, clock or currency.
	if payload.size() > 4 or JSON.stringify(payload).length() > 4096:
		publish_inventory(id, "Invalid Skylab request.")
		return
	var result := session.store.transact_lab(session.pilot_ids[id], sequence, action, payload, Skylab.now())
	if session.store.failed:
		session.stop_for_save_failure()
		return
	sync_lab_accounts()
	publish_inventory(id, result)


func sync_lab_accounts() -> void:
	for id: int in records:
		var pilot: Dictionary = session.store.pilots[session.pilot_ids[id]]
		records[id]["credits"] = pilot["credits"]
		cargo_holds[id] = pilot["cargo"].duplicate(true)


func advance_labs() -> void:
	var at := Skylab.now()
	if at < session.store.next_lab_due:
		return
	if not session.store.advance_labs(at):
		session.stop_for_save_failure()
		return
	sync_lab_accounts()
	for id: int in records:
		publish_inventory(id)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func boost_state(data: Dictionary, sequence: int, revision: int) -> void:
	# Separate owner packets preserve the world-snapshot size budget. Reliable
	# station replies supersede older packets, including those from another hull.
	if session.active and sequence > boost_sequence and revision == int(inventory.get("revision", -1)):
		boost_sequence = sequence
		session.sector.player.resource_boosts = data.duplicate(true)

func collect_loot() -> void:
	if not multiplayer.is_server():
		return
	var next := cargo_holds.duplicate(true)
	var changed: Dictionary[int, Dictionary] = {}
	var notices: Dictionary[int, Dictionary] = {}
	var saved: Dictionary = {}
	for drop_id: int in session.sector.loot.drops:
		var drop: Dictionary = session.sector.loot.drops[drop_id].duplicate(true)
		var candidates: Array[int] = []
		for id: int in records:
			var ship := session.ships[id]
			var equipment := session.store.pilots[session.pilot_ids[id]]["equipment"] as Dictionary if session.sector.dedicated_server else Equipment.starter()
			if not ship.get_meta("docked", false) and ship.alive and ship.position.distance_to(drop["position"]) <= ResourceLoot.PICKUP_RADIUS and CargoResources.units(next[id][equipment["active_ship"]]) < CargoResources.capacity(equipment):
				candidates.append(id)
		candidates.sort_custom(func(a: int, b: int) -> bool:
			var da := session.ships[a].position.distance_squared_to(drop["position"])
			var db := session.ships[b].position.distance_squared_to(drop["position"])
			return a < b if is_equal_approx(da, db) else da < db)
		for id: int in candidates:
			var equipment := session.store.pilots[session.pilot_ids[id]]["equipment"] as Dictionary if session.sector.dedicated_server else Equipment.starter()
			var taken := CargoResources.collect(next[id][equipment["active_ship"]], drop["resources"], CargoResources.capacity(equipment))
			if taken.is_empty():
				continue
			changed[drop_id] = {} if drop["resources"].is_empty() else drop
			if not notices.has(id):
				notices[id] = {}
			for resource: String in taken:
				notices[id][resource] = int(notices[id].get(resource, 0)) + taken[resource]
			if session.sector.dedicated_server:
				saved[session.pilot_ids[id]] = next[id]
	if notices.is_empty():
		return
	# All nearby pickups commit once, before removing a single unit from space.
	if session.sector.dedicated_server and not session.store.commit({}, {}, saved):
		session.stop_for_save_failure()
		return
	cargo_holds = next
	for drop_id: int in changed:
		session.sector.loot.change(drop_id, changed[drop_id])
	for id: int in notices:
		message(id, "Collected " + CargoResources.describe(notices[id]))
		if session.sector.dedicated_server:
			var equipment: Dictionary = session.store.pilots[session.pilot_ids[id]]["equipment"]
			cargo_result.rpc_id(id, next[id][equipment["active_ship"]], CargoResources.capacity(equipment))
		elif id == 1:
			session.sector.cargo = next[id]["starter"].duplicate()
		else:
			cargo_result.rpc_id(id, next[id]["starter"])

@rpc("authority", "call_remote", "reliable")
func cargo_result(hold: Dictionary, capacity: int = 400) -> void:
	if session.active:
		session.sector.cargo = hold
		session.sector.cargo_capacity = capacity

@rpc("authority", "call_remote", "reliable")
func loot_changed(id: int, data: Dictionary) -> void:
	if session.active:
		session.sector.loot.apply_drop(id, data)

@rpc("authority", "call_remote", "reliable")
func loot_state(drops: Dictionary) -> void:
	if session.active:
		session.sector.loot.clear()
		for id: int in drops:
			session.sector.loot.apply_drop(id, drops[id])
