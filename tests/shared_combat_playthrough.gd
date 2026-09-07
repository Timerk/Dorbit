extends "res://tests/flight_playthrough.gd"
## Start two processes with -- host / -- client for a real co-op hunt and return.

var replay_active: bool = false
var firing: bool = false


func _process(delta: float) -> bool:
	super._process(delta)
	if replay_active and is_instance_valid(sector):
		# Only this automated replay ignores window focus, so both processes can fly.
		sector.set_paused(false)
		if firing and sector.alien.alive and sector.target != null:
			sector.auto_fire = true
	return false


func run() -> void:
	var is_host := "host" in OS.get_cmdline_user_args()
	var label := "host" if is_host else "client"
	sector = preload("res://scenes/sector.tscn").instantiate()
	root.add_child(sector)
	current_scene = sector
	await process_frame
	if is_host:
		check(sector.session.host(24682) == OK, "Replay host starts")
	else:
		check(sector.session.join("127.0.0.1", 24682) == OK, "Replay client starts")
	var deadline := Time.get_ticks_msec() + 10000
	while (sector.session.ships.size() < 2 or (not is_host and not sector.session.received_snapshot)) and Time.get_ticks_msec() < deadline:
		await physics_frame
	check(sector.session.ships.size() == 2, "Both players connect")
	if failures > 0:
		quit(1)
		return
	replay_active = true
	sector.set_paused(false)
	await press(KEY_TAB)
	await press(KEY_SPACE)
	firing = true
	Input.action_press("forward")
	await create_timer(3.4).timeout
	Input.action_release("forward")
	await create_timer(0.6).timeout
	await snapshot("shared-combat-" + label)
	deadline = Time.get_ticks_msec() + 25000
	while sector.kills == 0 and Time.get_ticks_msec() < deadline and sector.player.alive:
		await physics_frame
	firing = false
	check(sector.kills == 1, "Both contributors receive a kill")
	check(sector.credits in [37, 38], "Both contributors receive half the reward pool")
	check(sector.player.alive, "Co-op encounter is survivable")
	await snapshot("shared-reward-" + label)
	Input.action_press("backward")
	deadline = Time.get_ticks_msec() + 10000
	while sector.player.position.z < 30 and Time.get_ticks_msec() < deadline:
		await physics_frame
	Input.action_release("backward")
	await create_timer(1.0).timeout
	deadline = Time.get_ticks_msec() + 6000
	while sector.player.time_since_hit < 5 and Time.get_ticks_msec() < deadline:
		await physics_frame
	await press(KEY_R)
	await create_timer(0.5).timeout
	check(sector.objective_stage == 4 and sector.player.hull == sector.player.max_hull, "Both players return and repair through the host")
	await snapshot("shared-repaired-" + label)
	print("Shared combat replay (%s): %d failures; credits=%d; stage=%d" % [label, failures, sector.credits, sector.objective_stage])
	if is_host:
		await create_timer(3.0).timeout
	replay_active = false
	sector.session.disconnect_session("Replay finished")
	quit(0 if failures == 0 else 1)
