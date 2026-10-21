class_name GateRun
extends RefCounted
## Server-owned Vashar Gate run. One run at a time: a pilot assembles the gate at
## Outpost 01, the gate opens nearby, and any pilot can fly through while it is
## open. Waves activate dormant arena aliens and end with the mothership.
## Run state is session state; a server restart ends an open run.

# The owning SessionCombat. Typed as Node because the RPC compatibility test
# recompiles SessionCombat's source without its class_name.
var combat: Node
var active := false
var builder := ""
# waiting: before the first wave; fighting; interval: between waves; victory.
var phase := "waiting"
var wave := -1
var clock := 0.0
var empty_clock := 0.0
var escort_clock := 0.0
# Remaining lives and participation, keyed by persistent pilot identity.
var lives: Dictionary[String, int] = {}
var wave_aliens: Array[Alien] = []
var rng := RandomNumberGenerator.new()


func _init(owner: Node) -> void:
	combat = owner
	rng.randomize()


static func dormant(alien: Alien) -> void:
	alien.alive = false
	alien.velocity = Vector3.ZERO
	alien.hide()
	alien.set_collision_layer_value(2, false)
	alien.contributors.clear()
	alien.engaged = false
	alien.returning = false
	alien.last_attacker = null
	alien.respawn = 0.0
	alien.life += 1


func sector() -> Sector:
	return combat.session.sector


func key(id: int) -> String:
	return combat.session.pilot_ids.get(id, "peer%d" % id)


func arena_aliens() -> Array[Alien]:
	var result: Array[Alien] = []
	result.assign(sector().map_rosters[GalaxyGates.MAP].values())
	return result


func inside() -> Array[int]:
	var result: Array[int] = []
	for id: int in combat.session.ships:
		var ship: Pilot = combat.session.ships[id]
		if ship.map_id == GalaxyGates.MAP and ship.alive and not ship.get_meta("docked", false):
			result.append(id)
	return result


## Clears every run without rewards; used when a session starts or ends.
func reset() -> void:
	active = false
	builder = ""
	phase = "waiting"
	wave = -1
	lives.clear()
	wave_aliens.clear()
	SectorMaps.rift_open = false
	for alien in arena_aliens():
		dormant(alien)
	if not sector().dedicated_server:
		sector().refresh_rift()


func open_blocker() -> String:
	return "A %s run is already open. Join it near Outpost 01." % GalaxyGates.NAME if active else ""


func start(label: String) -> void:
	reset()
	active = true
	builder = label
	clock = GalaxyGates.FIRST_WAVE_DELAY
	empty_clock = 0.0
	SectorMaps.rift_open = true
	publish()
	broadcast("%s opened near Outpost 01 by %s. Fly through it to join the run." % [GalaxyGates.NAME, label])


func entry_blocker(id: int) -> String:
	if not active or phase == "victory":
		return "The %s is closed." % GalaxyGates.NAME
	if lives.get(key(id), GalaxyGates.LIVES) <= 0:
		return "No lives left in this %s run." % GalaxyGates.NAME
	return ""


func entered(id: int) -> void:
	if not lives.has(key(id)):
		lives[key(id)] = GalaxyGates.LIVES
	empty_clock = 0.0
	publish()
	var notice := "Entered the Vashar Rift. %d lives. The gate behind you returns to M1." % lives[key(id)]
	if phase == "waiting":
		notice += " First wave in %d seconds." % ceili(clock)
	combat.message(id, notice)


func died(id: int) -> void:
	if not active or not lives.has(key(id)):
		return
	lives[key(id)] = maxi(0, lives[key(id)] - 1)
	combat.message(id, "Ship lost in the Vashar Rift. %d lives left in this run." % lives[key(id)] if lives[key(id)] > 0 else "Ship lost. No lives left in this Vashar Gate run.")
	publish()


func tick(delta: float) -> void:
	if not active:
		return
	var pilots := inside()
	if phase == "victory":
		clock -= delta
		if clock <= 0.0:
			close()
		return
	if pilots.is_empty():
		empty_clock += delta
		var exhausted: bool = not lives.is_empty() and lives.values().max() <= 0
		if exhausted or empty_clock >= GalaxyGates.ABANDON_TIME:
			fail("No pilots can continue." if exhausted else "Nobody held the rift.")
		return
	empty_clock = 0.0
	match phase:
		"waiting", "interval":
			clock -= delta
			if clock <= 0.0:
				start_wave(wave + 1, pilots.size())
		"fighting":
			tick_escorts(delta)
			for alien in wave_aliens:
				if alien.alive:
					return
			if wave >= GalaxyGates.WAVES.size() - 1:
				victory()
			else:
				phase = "interval"
				clock = GalaxyGates.WAVE_DELAY
				arena_message("Wave %d cleared. Next wave in %d seconds." % [wave + 1, int(GalaxyGates.WAVE_DELAY)])
				publish()


func start_wave(index: int, pilots: int) -> void:
	wave = index
	phase = "fighting"
	escort_clock = 0.0
	wave_aliens.clear()
	var counts := GalaxyGates.wave_counts(wave, pilots)
	var parts: PackedStringArray = []
	for kind: String in counts:
		var spawned := 0
		for alien in arena_aliens():
			if spawned >= counts[kind]:
				break
			if alien.kind == kind and not alien.alive:
				spawn(alien, wave_point(kind))
				spawned += 1
		parts.append("%d %s" % [spawned, kind + ("s" if spawned != 1 else "")])
	arena_message("Wave %d of %d: %s." % [wave + 1, GalaxyGates.WAVES.size(), ", ".join(parts)])
	publish()


func wave_point(kind: String) -> Vector3:
	var origin := SectorMaps.origin(GalaxyGates.MAP)
	if kind == "Mothership":
		return origin + Vector3(0, 60, -450)
	return origin + Vector3(rng.randf_range(-320, 320), rng.randf_range(-120, 120), rng.randf_range(-420, -80))


func spawn(alien: Alien, point: Vector3) -> void:
	alien.home_position = point
	alien.position = point
	alien.rotation = Vector3.ZERO
	alien.patrol_time = 0.0
	alien.returning = false
	alien.reset_encounter()
	wave_aliens.append(alien)


# The mothership launches Shardling escorts from its hangar while it survives.
func tick_escorts(delta: float) -> void:
	var boss: Alien = null
	for alien in wave_aliens:
		if alien.kind == "Mothership" and alien.alive:
			boss = alien
	if boss == null:
		return
	escort_clock += delta
	if escort_clock < GalaxyGates.ESCORT_INTERVAL:
		return
	escort_clock = 0.0
	var launched := 0
	for alien in arena_aliens():
		if launched < GalaxyGates.ESCORTS and alien.kind == "Shardling" and not alien.alive:
			wave_aliens.erase(alien)
			spawn(alien, boss.position + Vector3(rng.randf_range(-40, 40), -20, rng.randf_range(-40, 40)))
			launched += 1
	if launched > 0:
		arena_message("The mothership launches %d Shardlings." % launched)


func victory() -> void:
	phase = "victory"
	clock = GalaxyGates.VICTORY_TIME
	SectorMaps.rift_open = false
	var session: FlightSession = combat.session
	var winners: Array[int] = []
	var items: Dictionary[int, bool] = {}
	var rewards := {}
	for id: int in combat.records:
		if lives.has(key(id)):
			winners.append(id)
			items[id] = rng.randf() < float(GalaxyGates.REWARD["item_chance"])
			rewards[key(id)] = {"credits": GalaxyGates.REWARD["credits"], "research": GalaxyGates.REWARD["research"],
				"x4": GalaxyGates.REWARD["x4"], "item": GalaxyGates.REWARD["item"] if items[id] else ""}
	# One save for every winner before anyone sees a reward.
	if session.sector.dedicated_server and not rewards.is_empty() and not session.store.reward_gate(rewards):
		session.stop_for_save_failure()
		return
	for id: int in winners:
		var ship := session.ships[id]
		if session.sector.dedicated_server:
			var pilot: Dictionary = session.store.pilots[key(id)]
			combat.records[id]["credits"] = pilot["credits"]
			ship.ammo = pilot["ammo"].duplicate()
		else:
			combat.records[id]["credits"] = mini(PilotStore.MAX_CREDITS, int(combat.records[id]["credits"]) + int(GalaxyGates.REWARD["credits"]))
			ship.ammo["x4"] = mini(Ammunition.MAX_SHOTS, int(ship.ammo["x4"]) + int(GalaxyGates.REWARD["x4"]))
		combat.message(id, "Vashar mothership destroyed. Their invasion is set back. %s. The rift closes in %d seconds." % [GalaxyGates.reward_text(items[id]), int(GalaxyGates.VICTORY_TIME)])
		combat.publish_inventory(id)
	publish()


func fail(reason: String) -> void:
	broadcast("%s collapsed. %s The gate parts are lost." % [GalaxyGates.NAME, reason])
	close()


func close() -> void:
	for id in inside():
		combat.message(id, "The rift is closing. Returning to M1.")
		combat.session.transfer(id, 0)
	reset()
	publish()


func arena_message(text: String) -> void:
	for id in inside():
		combat.message(id, text)


func broadcast(text: String) -> void:
	for id: int in combat.records:
		combat.message(id, text)


## Run summary for one pilot's HUD and station page.
func state_for(id: int) -> Dictionary:
	if not active:
		return {"active": false}
	return {"active": true, "open": SectorMaps.rift_open, "phase": phase, "wave": wave + 1, "waves": GalaxyGates.WAVES.size(),
		"lives": lives.get(key(id), GalaxyGates.LIVES), "entered": lives.has(key(id)), "builder": builder, "pilots": inside().size()}


func publish() -> void:
	for id: int in combat.records:
		if id == 1:
			combat.gate_state(state_for(id))
		else:
			combat.gate_state.rpc_id(id, state_for(id))
