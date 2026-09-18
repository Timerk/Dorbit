extends "res://tests/flight_playthrough.gd"
## Render a real client accepting, hunting three Scouts and claiming from a disposable server.

var server: Sector
var flying := false
var hunt: Alien


func _process(delta: float) -> bool:
	super._process(delta)
	if flying and is_instance_valid(sector):
		# Automated replay alone ignores desktop focus changes.
		sector.set_paused(false)
		if is_instance_valid(hunt) and hunt.alive:
			sector.player.look_at(hunt.position, Vector3.UP)
			sector.select_target(hunt)
			sector.auto_fire = true
	return false


func run() -> void:
	OS.unset_environment("DORBIT_PILOT_FILE")
	var directory := ProjectSettings.globalize_path("user://contract-replay-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var token := "contract-replay".sha256_text()
	var file := FileAccess.open(directory.path_join("pilots.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "pilots": {"replay": {"verifier": token.sha256_text(), "credits": 0}}}))
	file.close()
	OS.set_environment("DORBIT_DATA_DIR", directory)
	var world := SubViewport.new()
	world.name = "ServerWorld"
	world.own_world_3d = true
	root.add_child(world)
	set_multiplayer(SceneMultiplayer.new(), world.get_path())
	server = preload("res://scenes/sector.tscn").instantiate()
	server.dedicated_server = true
	server.server_port = 24690
	world.add_child(server)
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	current_scene = sector
	sector.session.credential_id = "replay"
	sector.session.credential_token = token
	sector.session.join("127.0.0.1", 24690)
	await create_timer(1.0).timeout
	check(sector.session.received_snapshot, "Replay pilot authenticates and receives world")
	if failures:
		await finish_replay()
		return
	sector.set_paused(false)
	await press(KEY_C)
	check(sector.hud.contract_panel.visible, "C opens station contract board")
	check(not sector.hud.audio_controls.visible, "Station contracts hide pause-menu audio controls")
	await snapshot("contracts-01-offers")
	sector.hud.contract_offers[0].pressed.emit()
	await create_timer(0.4).timeout
	check(sector.active_contract.get("type") == "scout", "Scout button accepts through server RPC")
	await snapshot("contracts-02-accepted")
	await press(KEY_C)
	flying = true
	# Fly into the nearest Scout's territory with normal flight commands and target-lock fire.
	hunt = sector.aliens[1]
	Input.action_press("forward")
	var deadline := Time.get_ticks_msec() + 10000
	while (sector.player.position.distance_to(hunt.position) > 100 or sector.player.position.distance_to(Sector.STATION_POSITION) < 90) and Time.get_ticks_msec() < deadline:
		await physics_frame
	Input.action_release("forward")
	await create_timer(0.5).timeout
	await snapshot("contracts-03-hunting")
	deadline = Time.get_ticks_msec() + 80000
	while not HuntingContracts.ready(sector.active_contract) and Time.get_ticks_msec() < deadline:
		if not sector.player.alive:
			break
		await physics_frame
	flying = false
	hunt = null
	sector.auto_fire = false
	check(HuntingContracts.ready(sector.active_contract), "Three live Scout kills complete the contract")
	await snapshot("contracts-04-complete")
	if failures:
		await finish_replay()
		return
	# Return via the same movement simulation; aim at a point inside station interaction range.
	flying = true
	sector.player.look_at(Sector.SPAWN_POSITION, Vector3.UP)
	Input.action_press("forward")
	deadline = Time.get_ticks_msec() + 15000
	while sector.player.position.distance_to(Sector.SPAWN_POSITION) > 16 and Time.get_ticks_msec() < deadline:
		await physics_frame
	Input.action_release("forward")
	await create_timer(6.0).timeout
	flying = false
	await press(KEY_C)
	check(sector.hud.contract_panel.visible and not sector.hud.contract_claim.disabled, "Returning pilot can claim at the station")
	await snapshot("contracts-05-ready")
	var balance := sector.credits
	sector.hud.contract_claim.pressed.emit()
	await create_timer(0.4).timeout
	check(sector.active_contract.is_empty() and sector.credits == balance + 90, "Claim button pays once and restores the offer selection")
	await snapshot("contracts-06-claimed")
	if rendered:
		root.size = Vector2i(960, 600)
		await create_timer(0.4).timeout
		await snapshot("contracts-07-small-window")
	await finish_replay()


func finish_replay() -> void:
	flying = false
	Input.action_release("forward")
	print("Contract playthrough: %d failures; credits=%d; contract=%s" % [failures, sector.credits, sector.active_contract])
	sector.session.disconnect_session("Replay finished")
	server.session.disconnect_session("Replay finished")
	quit(0 if failures == 0 else 1)
