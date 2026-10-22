class_name GateRun
extends RefCounted
## Server-owned galaxy gate run. One run at a time across every gate: a pilot
## assembles a gate at Outpost 01, its portal opens nearby, and any pilot can fly
## through while it is open. Waves activate the gate's dormant arena aliens and
## end with its boss. Run state is session state; a server restart ends an open run.

# The owning SessionCombat. Typed as Node because the RPC compatibility test
# recompiles SessionCombat's source without its class_name.
var combat: Node
var active := false
# The open gate's ID in GalaxyGates.GATES, or empty without a run.
var gate := ""
var builder := ""
# waiting: before the first wave; fighting; interval: between waves; victory.
var phase := "waiting"
var wave := -1
var clock := 0.0
var empty_clock := 0.0
var escort_clock := 0.0
# Pilots inside at the last tick; the countdown pauses while the arena is empty.
var last_inside := 0
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


func definition() -> Dictionary:
	return GalaxyGates.info(gate)


func map() -> int:
	return int(definition()["map"]) if not gate.is_empty() else -1


func gate_name() -> String:
	return definition()["name"]


func arena_aliens() -> Array[Alien]:
	var result: Array[Alien] = []
	if not gate.is_empty():
		result.assign(sector().map_rosters[map()].values())
	return result


func inside() -> Array[int]:
	var result: Array[int] = []
	if gate.is_empty():
		return result
	for id: int in combat.session.ships:
		var ship: Pilot = combat.session.ships[id]
		if ship.map_id == map() and ship.alive and not ship.get_meta("docked", false):
			result.append(id)
	return result


## Clears every run without rewards; used when a session starts or ends.
func reset() -> void:
	active = false
	gate = ""
	builder = ""
	phase = "waiting"
	wave = -1
	lives.clear()
	wave_aliens.clear()
	SectorMaps.open_rift = -1
	for gate_id: String in GalaxyGates.ORDER:
		for alien: Alien in sector().map_rosters[int(GalaxyGates.info(gate_id)["map"])].values():
			dormant(alien)
	if not sector().dedicated_server:
		sector().refresh_rift()


func open_blocker() -> String:
	return "A %s run is already open. Join it near Outpost 01." % gate_name() if active else ""


func start(gate_id: String, label: String) -> void:
	reset()
	active = true
	gate = gate_id
	builder = label
	clock = GalaxyGates.FIRST_WAVE_DELAY
	empty_clock = 0.0
	SectorMaps.open_rift = map()
	publish()
	broadcast("%s opened near Outpost 01 by %s. Fly through it to join the run." % [gate_name(), label])


func entry_blocker(id: int, destination: int) -> String:
	if not active or phase == "victory" or destination != map():
		return "That galaxy gate is closed."
	if lives.get(key(id), int(definition()["lives"])) <= 0:
		return "No lives left in this %s run." % gate_name()
	return ""


## Pilots cannot slip out mid-wave to repair; the exit opens between waves.
func exit_blocker() -> String:
	return "The arena exit is sealed until this wave is cleared." if active and phase == "fighting" else ""


## Quitting to the station during a wave counts as a lost life.
func retreated(id: int) -> void:
	if active and phase == "fighting" and lives.has(key(id)):
		lives[key(id)] = maxi(0, lives[key(id)] - 1)
		combat.message(id, "You abandoned the wave. %d lives left in this %s run." % [lives[key(id)], gate_name()])
		publish()


func entered(id: int) -> void:
	if not lives.has(key(id)):
		lives[key(id)] = int(definition()["lives"])
	empty_clock = 0.0
	publish()
	var notice := "Entered the %s. %d lives. The gate behind you returns to M1 between waves." % [definition()["arena"], lives[key(id)]]
	if phase == "waiting":
		notice += " First wave in %d seconds." % ceili(clock)
	combat.message(id, notice)


func died(id: int) -> void:
	if not active or not lives.has(key(id)):
		return
	lives[key(id)] = maxi(0, lives[key(id)] - 1)
	combat.message(id, "Ship lost in the %s. %d lives left in this run." % [definition()["arena"], lives[key(id)]] if lives[key(id)] > 0 else "Ship lost. No lives left in this %s run." % gate_name())
	publish()


func tick(delta: float) -> void:
	if not active:
		return
	var pilots := inside()
	if pilots.size() != last_inside:
		last_inside = pilots.size()
		publish()
	if phase == "victory":
		clock -= delta
		if clock <= 0.0:
			close()
		return
	if pilots.is_empty():
		empty_clock += delta
		var exhausted: bool = not lives.is_empty() and lives.values().max() <= 0
		if exhausted or empty_clock >= GalaxyGates.ABANDON_TIME:
			fail("No pilots can continue." if exhausted else "Nobody held the arena.")
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
			if wave >= definition()["waves"].size() - 1:
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
	var counts := GalaxyGates.wave_counts(gate, wave, pilots)
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
	arena_message("Wave %d of %d: %s." % [wave + 1, definition()["waves"].size(), ", ".join(parts)])
	publish()


func wave_point(kind: String) -> Vector3:
	var origin := SectorMaps.origin(map())
	if kind == definition()["boss"]:
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


# The boss launches escorts from its hangar while it survives.
func tick_escorts(delta: float) -> void:
	var boss: Alien = null
	for alien in wave_aliens:
		if alien.kind == definition()["boss"] and alien.alive:
			boss = alien
	if boss == null:
		return
	escort_clock += delta
	if escort_clock < GalaxyGates.ESCORT_INTERVAL:
		return
	escort_clock = 0.0
	var launched := 0
	for alien in arena_aliens():
		if launched < GalaxyGates.ESCORTS and alien.kind == definition()["escort"] and not alien.alive:
			wave_aliens.erase(alien)
			spawn(alien, boss.position + Vector3(rng.randf_range(-40, 40), -20, rng.randf_range(-40, 40)))
			launched += 1
	if launched > 0:
		arena_message("The %s launches %d %ss." % [definition()["boss"], launched, definition()["escort"]])


func victory() -> void:
	phase = "victory"
	clock = GalaxyGates.VICTORY_TIME
	SectorMaps.open_rift = -1
	var reward: Dictionary = definition()["reward"]
	var session: FlightSession = combat.session
	var winners: Array[int] = []
	var items: Dictionary[int, bool] = {}
	var rewards := {}
	for id: int in combat.records:
		if lives.has(key(id)):
			winners.append(id)
			items[id] = rng.randf() < float(reward["item_chance"])
			rewards[key(id)] = {"credits": reward["credits"], "research": reward["research"],
				"x4": reward["x4"], "item": reward["item"] if items[id] else ""}
	# Rewards are persistent; runs only start on a dedicated server. One save
	# covers every winner before anyone sees a reward.
	if not session.sector.dedicated_server:
		publish()
		return
	if not rewards.is_empty() and not session.store.reward_gate(rewards):
		session.stop_for_save_failure()
		return
	for id: int in winners:
		var ship := session.ships[id]
		var pilot: Dictionary = session.store.pilots[key(id)]
		combat.records[id]["credits"] = pilot["credits"]
		ship.ammo = pilot["ammo"].duplicate()
		combat.message(id, "%s %s. The arena closes in %d seconds." % [definition()["victory"], GalaxyGates.reward_text(gate, items[id]), int(GalaxyGates.VICTORY_TIME)])
		combat.publish_inventory(id)
	publish()


func fail(reason: String) -> void:
	broadcast("%s collapsed. %s The gate parts are lost." % [gate_name(), reason])
	close()


func close() -> void:
	for id in inside():
		combat.message(id, "The arena is closing. Returning to M1.")
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
func state_for(id: int, pilots: int = -1) -> Dictionary:
	if not active:
		return {"active": false}
	if pilots < 0:
		pilots = inside().size()
	# Seconds until the next wave; clients count down locally from receipt and
	# stop while the arena is empty, matching the paused server clock.
	var countdown := clock if phase in ["waiting", "interval"] else -1.0
	return {"active": true, "gate": gate, "map": map(), "open": SectorMaps.open_rift == map(), "phase": phase,
		"wave": wave + 1, "waves": definition()["waves"].size(), "lives": lives.get(key(id), int(definition()["lives"])),
		"entered": lives.has(key(id)), "builder": builder, "pilots": pilots,
		"countdown": countdown, "paused": pilots == 0}


func publish() -> void:
	var pilots := inside().size()
	for id: int in combat.records:
		if id == 1:
			combat.gate_state(state_for(id, pilots))
		else:
			combat.gate_state.rpc_id(id, state_for(id, pilots))
