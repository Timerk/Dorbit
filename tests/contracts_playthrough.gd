extends "res://tests/flight_playthrough.gd"
## Render concurrent hunts, automatic rewards, equipment fitting and restart recovery.

var server: Sector
var flying := false
var hunt: Alien
var checks := 0


class ReplayServer extends Sector:
	# Exercise repeated lives and real station trips without random long-distance travel.
	# Full-sector navigation and randomized respawns have their own integration checks.
	func relocate_alien(enemy: Alien) -> void:
		if enemy.alien_id == 1:
			enemy.home_position = Vector3(0, 8, 300)
			enemy.position = enemy.home_position
		else:
			super.relocate_alien(enemy)


func check(condition: bool, message: String) -> void:
	checks += 1
	super.check(condition, message)


func click_button(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame


func _process(delta: float) -> bool:
	super._process(delta)
	if flying and is_instance_valid(sector):
		# Automated replay alone ignores desktop focus changes.
		sector.set_paused(false)
		if is_instance_valid(hunt) and hunt.alive:
			sector.player.look_at(hunt.position, Vector3.UP)
			sector.select_target(hunt)
			sector.auto_fire = hunt.available()
			# Follow each respawn like the single-hunt replay instead of retaining
			# the firing position from the initial station approach.
			if sector.player.position.distance_to(hunt.position) > 85.0 or sector.player.position.distance_to(Sector.STATION_POSITION) < 85.0:
				Input.action_press("forward")
			else:
				Input.action_release("forward")
		elif is_instance_valid(hunt):
			Input.action_release("forward")
			sector.auto_fire = false
	return false


func run() -> void:
	# Inspect native pixel sizes, including the minimum supported window.
	root.content_scale_size = Vector2i.ZERO
	OS.unset_environment("DORBIT_PILOT_FILE")
	var directory := ProjectSettings.globalize_path("user://contract-replay-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var token := "contract-replay".sha256_text()
	var file := FileAccess.open(directory.path_join("pilots.json"), FileAccess.WRITE)
	# Seed an upgrade budget; the replay checks the loop, not time-to-first-purchase balance.
	file.store_string(JSON.stringify({"version": 1, "pilots": {"replay": {"verifier": token.sha256_text(), "credits": 10000}}}))
	file.close()
	OS.set_environment("DORBIT_DATA_DIR", directory)
	var world := SubViewport.new()
	world.name = "ServerWorld"
	world.own_world_3d = true
	root.add_child(world)
	set_multiplayer(SceneMultiplayer.new(), world.get_path())
	server = ReplayServer.new()
	server.name = "Sector"
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
	check(not sector.settings_menu.pause_panel.visible, "Station contracts hide flight-menu controls")
	sector.hud.contract_tabs[1].pressed.emit()
	check(sector.hud.contract_selected.is_empty() and sector.hud.contract_empty.visible and not sector.hud.contract_accept.visible, "Empty active tab has no actionable selection")
	sector.hud.contract_tabs[0].pressed.emit()
	await click_button(sector.hud.contract_choices["heavy"])
	check(sector.active_contracts.is_empty() and sector.hud.contract_selected == "heavy" and sector.hud.contract_reward.text == "Credits    30000", "Selecting a hunt only changes briefing and reward, without accepting")
	sector.hud.contract_choices["scout"].grab_focus()
	await press(KEY_ENTER)
	check(sector.hud.contract_selected == "scout", "Keyboard activation selects a hunt without accepting it")
	if rendered:
		root.size = Vector2i(960, 600)
		await create_timer(0.4).timeout
		var board := sector.hud.contract_panel.get_global_rect()
		check(board.position.x >= 0 and board.position.y >= 0 and board.end.x <= 960 and board.end.y <= 600, "Contracts fit the minimum native window")
		var last_choice := sector.hud.contract_choices["heavy"]
		var scroll := last_choice.get_parent().get_parent() as ScrollContainer
		check(last_choice.get_global_rect().end.y <= scroll.get_global_rect().end.y, "All three hunt rows are visible without scrolling at the minimum size")
	await snapshot("contracts-01-offers")
	await click_button(sector.hud.contract_accept)
	await create_timer(0.4).timeout
	check(not sector.hud.contract_accept.visible and sector.hud.contract_abandon.visible, "Active selection replaces acceptance with abandonment")
	sector.hud.contract_choices["sentinel"].pressed.emit()
	sector.hud.contract_accept.grab_focus()
	await create_timer(0.1).timeout
	check(sector.hud.contract_accept.has_focus(), "Live updates preserve keyboard focus on the action button")
	await press(KEY_ENTER)
	await create_timer(0.4).timeout
	sector.hud.contract_choices["heavy"].pressed.emit()
	sector.hud.contract_accept.pressed.emit()
	await create_timer(0.4).timeout
	check(sector.active_contracts.size() == 3, "All three hunts accept through server RPC")
	sector.hud.contract_tabs[1].pressed.emit()
	check(sector.hud.contract_slots.text == "3 / 3 active", "Board reports concurrent hunt capacity")
	# Saved runs can retain different terms from the current offer catalog.
	var original: Dictionary = sector.active_contracts["heavy"].duplicate()
	sector.active_contracts["heavy"]["required"] = 4
	sector.active_contracts["heavy"]["reward"] = 321
	sector.active_contracts["heavy"]["progress"] = 2
	sector.hud.update_contract_panel()
	check(sector.hud.contract_progress.value == 2 and sector.hud.contract_progress.max_value == 4 and sector.hud.contract_reward.text == "Credits    321", "Detail view uses accepted progress, objective and reward terms")
	sector.active_contracts["heavy"]["progress"] = 4
	sector.hud.update_contract_panel()
	check("Reward pending" in sector.hud.contract_choices["heavy"].text and "wallet full" in sector.hud.contract_reward.text, "Completed pending reward remains visible and cannot be reaccepted")
	sector.active_contracts["heavy"] = original
	sector.hud.update_contract_panel()
	var position := sector.player.position
	sector.player.position = Vector3(1000, 0, 0)
	sector.hud.update_contract_panel()
	check(sector.hud.contract_abandon.disabled and sector.hud.contract_status.visible, "Live station restrictions disable the action with an explanation")
	if rendered:
		await process_frame
		await process_frame
		check(sector.hud.contract_panel.get_global_rect().end.y <= 600, "Station restriction explanation fits the minimum window")
	sector.player.position = position
	sector.hud.update_contract_panel()
	await snapshot("contracts-02-accepted")
	if rendered:
		root.size = Vector2i(1440, 900)
		await create_timer(0.4).timeout
		await snapshot("contracts-large-window")
	sector.hud.contract_choices["scout"].pressed.emit()
	await click_button(sector.hud.contract_abandon)
	await create_timer(0.4).timeout
	check(sector.active_contracts.size() == 2 and not sector.hud.contract_choices["scout"].visible and sector.hud.contract_selected == "sentinel", "Abandoning only the selected hunt moves active selection to the next hunt")
	sector.hud.contract_tabs[0].pressed.emit()
	sector.hud.contract_choices["scout"].pressed.emit()
	sector.hud.contract_accept.pressed.emit()
	await create_timer(0.4).timeout
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
	deadline = Time.get_ticks_msec() + 150000
	var repaired_progress := 0
	var repair_spent := 0
	while sector.active_contracts.has("scout") and Time.get_ticks_msec() < deadline:
		if not sector.player.alive:
			break
		await physics_frame
		var progress: int = sector.active_contracts.get("scout", {}).get("progress", 3)
		if progress > repaired_progress and progress < 3:
			repaired_progress = progress
			var tracked := hunt
			hunt = null
			sector.auto_fire = false
			await return_to_station()
			var before_repair := sector.credits
			await press(KEY_R)
			await create_timer(0.4).timeout
			repair_spent += before_repair - sector.credits
			check(sector.player.alive and sector.player.hull == sector.player.max_hull and sector.active_contracts.get("scout", {}).get("progress") == progress,
				"Station repairs preserve partial Scout hunt progress (distance=%.1f speed=%.1f hull=%.0f/%.0f last_hit=%.1f)" % [sector.player.position.distance_to(Sector.STATION_POSITION), sector.player.velocity.length(), sector.player.hull, sector.player.max_hull, sector.player.time_since_hit])
			hunt = tracked
			if failures:
				break
	flying = false
	hunt = null
	sector.auto_fire = false
	Input.action_release("forward")
	check(not sector.active_contracts.has("scout") and sector.credits == 11800 - repair_spent, "Three live Scout kills pay automatically in flight, less confirmed repair charges")
	check(sector.active_contracts.has("sentinel") and sector.active_contracts.has("heavy"), "Other hunts remain active")
	await snapshot("contracts-04-complete")
	if failures:
		await finish_replay()
		return
	# Return within service range, rather than stopping short of the spawn point.
	flying = true
	await return_to_station()
	flying = false
	await press(KEY_C)
	sector.hud.contract_choices["scout"].pressed.emit()
	check(sector.hud.contract_panel.visible and sector.hud.contract_accept.visible and not sector.hud.contract_accept.disabled, "Returning pilot can repeat the paid hunt")
	# The live return can incur rescue fees; accepting a repeat must preserve this wallet.
	var station_credits := sector.credits
	sector.hud.contract_accept.pressed.emit()
	await create_timer(0.4).timeout
	check(sector.active_contracts.size() == 3 and sector.credits == station_credits, "Repeating a hunt leaves the wallet and other contracts intact")
	await snapshot("contracts-06-repeated")
	if rendered:
		root.size = Vector2i(960, 600)
		await create_timer(0.4).timeout
		await snapshot("contracts-07-small-window")
	await press(KEY_B)
	check(sector.shop.visible and not sector.hud.contract_panel.visible and not sector.settings_menu.pause_panel.visible, "B switches from the contract board to shop")
	if failures:
		await finish_replay()
		return
	sector.shop.select_model("laser")
	sector.shop.buys["laser"].pressed.emit()
	await create_timer(0.4).timeout
	check(sector.session.combat.inventory["items"].has("purchase-1") and sector.credits == station_credits - 10000, "Buying the laser deducts only its price from the returned wallet")
	if failures:
		await finish_replay()
		return
	await press(KEY_I)
	sector.equipment_menu.stored["purchase-1"].pressed.emit()
	await process_frame
	sector.equipment_menu.slots["laser2"].pressed.emit()
	await create_timer(0.4).timeout
	check(sector.player.laser_damage == 130, "Purchased laser fits through station controls")
	await snapshot("contracts-08-equipped")
	sector.session.disconnect_session("Progression restart")
	server.session.disconnect_session("Progression restart")
	await create_timer(0.3).timeout
	check(server.session.host(24690) == OK, "Server restarts with the combined progression ledger")
	sector.session.join("127.0.0.1", 24690)
	await create_timer(0.7).timeout
	check(sector.session.received_snapshot and sector.credits == station_credits - 10000 and sector.active_contracts.size() == 3 and sector.player.laser_damage == 130 and sector.session.combat.inventory.get("revision") == 2, "Restart preserves rewards, concurrent contracts and purchased fitting together")
	await finish_replay()


func finish_replay() -> void:
	flying = false
	Input.action_release("forward")
	print("Contract playthrough: %d checks, %d failures; credits=%d; contract=%s" % [checks, failures, sector.credits, sector.active_contracts])
	sector.session.disconnect_session("Replay finished")
	server.session.disconnect_session("Replay finished")
	quit(0 if failures == 0 else 1)
