extends "res://tests/network_test.gd"
## Recovery boundaries, atomic ammo/boost debits and a real server failure.


func run() -> void:
	if "--journal-failure" in OS.get_cmdline_user_args() or "--journal-write-failure" in OS.get_cmdline_user_args():
		await failure_process()
		return
	var server := make_sector("Journal", true)
	var directory := server.session.store.path.get_base_dir().path_join("journal-cases")
	DirAccess.make_dir_absolute(directory)
	var path := directory.path_join("pilots.json")
	write_text(path, JSON.stringify({"version": 7, "pilots": server.session.store.pilots}))
	var store := PilotStore.new()
	check(store.open(directory), "Schema-7 ledger upgrades to a snapshot/journal pair")
	check(JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))["version"] == 7, "Migration retains the legacy snapshot backup")
	var snapshot := FileAccess.get_file_as_string(path)
	var ammo: Dictionary = store.pilots["pilot0"]["ammo"].duplicate()
	ammo["x1"] -= 4
	var boosts := {"starter": {"lasers": {"resource": "seprom", "remaining": 7}, "shields": {"resource": "duranium", "remaining": 12.25}}}
	check(store.commit_combat({"pilot0": ammo}, {"pilot0": boosts}), "One flushed transaction commits ammo and all boost reserves")
	check(FileAccess.get_file_as_string(path) == snapshot, "Combat leaves the complete snapshot untouched")
	var pending := FileAccess.get_file_as_string(path + ".combat")
	var recovered: Dictionary = JSON.parse_string(snapshot)
	check(CombatJournal.replay(pending, recovered["combat_journal"], recovered["pilots"]) == 1 and same_json(recovered["pilots"]["pilot0"]["ammo"], ammo) and same_json(recovered["pilots"]["pilot0"]["boosts"], boosts), "Disk alone recovers both fields before a snapshot checkpoint")
	check_provisioning_interop(directory, snapshot, pending, ammo, boosts)
	# Simulate a process death without close() checkpointing. The operator removes
	# the stale lock only; the next store must recover the committed journal.
	DirAccess.remove_absolute(path + ".lock")
	store.close_journal()
	store.locked = false
	store = PilotStore.new()
	check(store.open(directory) and same_json(store.pilots["pilot0"]["ammo"], ammo) and same_json(store.pilots["pilot0"]["boosts"], boosts), "Restart replays debits without refilling ammunition or boosts")
	ammo["r-310"] -= 1
	check(store.commit_combat({"pilot0": ammo}), "Rocket debit uses the same durable journal")
	var before := store.pilots.duplicate(true)
	var stale_journal := FileAccess.get_file_as_string(path + ".combat")
	check(store.commit({"pilot0": 2000, "pilot1": 1000}), "Reward shares checkpoint prior combat together")
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))
	check(same_json(backup["pilots"], before), "Backup includes pending combat rather than restoring spent rounds")
	check(FileAccess.get_file_as_string(path + ".combat").split("\n").size() == 2, "Checkpoint compacts the journal to its header")
	# Crash between primary replacement and journal compaction: old records must
	# not undo a subsequent ammo purchase recorded in the new snapshot.
	var purchased := ammo.duplicate()
	purchased["x1"] += 100
	check(store.commit({}, {}, {}, {"pilot0": purchased}), "Full economy save can follow a combat checkpoint")
	var checkpoint := FileAccess.get_file_as_string(path)
	store.close()
	write_text(path + ".combat", stale_journal)
	store = PilotStore.new()
	check(store.open(directory) and store.pilots["pilot0"]["ammo"] == purchased, "Already-checkpointed records cannot reverse a purchase after interrupted compaction")
	store.close()
	var metadata: Dictionary = JSON.parse_string(checkpoint)["combat_journal"]
	var clean := CombatJournal.header(metadata)
	var entry := CombatJournal.record(int(metadata["sequence"]) + 1, {"pilot0": ammo}, {})
	var corrupt: Array = JSON.parse_string(entry)
	corrupt[1] = "0".repeat(64)
	for damaged: String in ["", clean.trim_suffix("\n"), clean + "partial", CombatJournal.header({"id": "0".repeat(32), "sequence": metadata["sequence"]}), CombatJournal.header({"id": metadata["id"], "sequence": metadata["sequence"] + 1}), clean + CombatJournal.record(int(metadata["sequence"]) + 2, {"pilot0": ammo}, {}), clean + CombatJournal.record(int(metadata["sequence"]) + 1, {"unknown": ammo}, {}), clean + entry.trim_suffix("\n"), clean + JSON.stringify(corrupt) + "\n"]:
		write_text(path, checkpoint)
		write_text(path + ".combat", damaged)
		store = PilotStore.new()
		check(not store.open(directory) and store.failed and FileAccess.get_file_as_string(path) == checkpoint and FileAccess.get_file_as_string(path + ".combat") == damaged, "Missing, interrupted, mismatched or invalid journals fail closed without modifying evidence")
		store.close()
	write_text(path, checkpoint)
	write_text(path + ".combat", clean)
	store = PilotStore.new()
	check(store.open(directory), "Operator-restored pair opens")
	before = store.pilots.duplicate(true)
	write_text(path + ".combat", clean + "external edit")
	check(not store.commit_combat({"pilot0": ammo}) and store.failed and store.pilots == before, "Runtime journal edits cancel combat without consuming ammo")
	store.close()
	# A large but valid header exercises the size-bound checkpoint without
	# thousands of synthetic shots or timing assertions.
	var bounded_dir := directory.path_join("bounded")
	DirAccess.make_dir_absolute(bounded_dir)
	var bounded_path := bounded_dir.path_join("pilots.json")
	var future := server.session.store.pilots.duplicate(true)
	for pilot: Dictionary in future.values(): pilot["skylab"]["lastSimulatedAt"] = Skylab.now() + 600
	var bounded_metadata := {"id": "e".repeat(32), "sequence": 0}
	write_text(bounded_path, JSON.stringify({"version": 8, "combat_journal": bounded_metadata, "pilots": future}))
	write_text(bounded_path + ".combat", JSON.stringify(bounded_metadata) + " ".repeat(CombatJournal.MAX_BYTES) + "\n")
	var bounded := PilotStore.new()
	check(bounded.open(bounded_dir) and bounded.journal_bytes > CombatJournal.MAX_BYTES, "Open valid journal at the compaction size boundary")
	check(bounded.commit_combat({"pilot0": ammo}) and bounded.journal_bytes < 1024, "Size-bound checkpoint precedes the next durable debit and compacts replay work")
	check(bounded.close(), "Clean shutdown checkpoints the final debit")
	bounded = PilotStore.new()
	check(bounded.open(bounded_dir) and bounded.pilots["pilot0"]["ammo"] == ammo, "Size-bound and shutdown checkpoints preserve spent ammunition")
	bounded.close()
	# Operator tooling on Windows may produce CRLF. Keep the raw journal bytes
	# for live verification rather than normalizing its line endings at startup.
	write_text(path, checkpoint)
	write_text(path + ".combat", clean.replace("\n", "\r\n"))
	store = PilotStore.new()
	check(store.open(directory) and store.commit_combat({"pilot0": ammo}), "CRLF header remains valid for the next combat append")
	store.close()
	server.session.disconnect_session("Journal cases complete")
	for mode: String in ["--journal-failure", "--journal-write-failure"]:
		var output: Array = []
		var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/combat_journal_test.gd", "--", mode], output, true)
		check(code == 1 and str(output).contains("JOURNAL_FAILURE_VERIFIED"), "Real server stops and exits before damage on " + mode)
	finish()


func same_json(first: Variant, second: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(first)) == JSON.parse_string(JSON.stringify(second))


func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func check_provisioning_interop(directory: String, snapshot: String, journal: String, ammo: Dictionary, boosts: Dictionary) -> void:
	var fixture := directory.path_join("provisioning-interop")
	DirAccess.make_dir_absolute(fixture)
	write_text(fixture.path_join("pilots.json"), snapshot)
	write_text(fixture.path_join("pilots.json.combat"), journal)
	var python := "python" if OS.get_name() == "Windows" else "python3"
	var tool := ProjectSettings.globalize_path("res://tools/pilots.py")
	var output: Array = []
	var code := OS.execute(python, [tool, fixture, "pilot0", fixture.path_join("credential-1.json"), "--rotate"], output, true)
	check(code == 0, "Provisioning tool replays a real Godot journal before rotation")
	if code != 0: return
	var probe := PilotStore.new()
	check(probe.open(fixture) and same_json(probe.pilots["pilot0"]["ammo"], ammo) and same_json(probe.pilots["pilot0"]["boosts"], boosts), "Godot loads the Python checkpoint without restoring ammo or reserves")
	var next := ammo.duplicate()
	next["x1"] -= 1
	check(probe.commit_combat({"pilot0": next}), "Godot appends after Python journal compaction")
	probe.close_journal()
	DirAccess.remove_absolute(probe.path + ".lock")
	probe.locked = false # Leave the real journal pending for the operator reader.
	output.clear()
	code = OS.execute(python, [tool, fixture, "pilot0", fixture.path_join("credential-2.json"), "--rotate"], output, true)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(probe.path))
	check(code == 0 and same_json(saved["pilots"]["pilot0"]["ammo"], next) and same_json(saved["pilots"]["pilot0"]["boosts"], boosts), "Second rotation preserves newly appended Godot transactions")


func failure_process() -> void:
	var server := make_sector("FailedJournal", true)
	var client := make_sector("Pilot")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24683))
	await settle(0.5)
	if server.session.ships.size() != 1:
		quit(2)
		return
	client.session.launch()
	await settle()
	var ship := server.session.ships[client.multiplayer.get_unique_id()]
	ship.position = Vector3(0, 200, 0)
	ship.rotation = Vector3.ZERO
	ship.shot_cooldown = 0
	server.alien.position = Vector3(0, 200, -100)
	server.alien.home_position = server.alien.position
	server.alien.reset_health()
	await physics_frame
	var ammo := ship.ammo.duplicate()
	var health := server.alien.hull + server.alien.shield
	var store := server.session.store
	var boosts := {"starter": {"lasers": {"resource": "seprom", "remaining": 7}}}
	if not store.commit({}, {}, {}, {}, {"pilot0": boosts}):
		quit(2)
		return
	ship.resource_boosts = boosts["starter"].duplicate(true)
	var durable_before_damage := [false]
	server.alien.damaged.connect(func(_target: SpaceShip, _attacker: SpaceShip):
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
		var sequence := CombatJournal.replay(FileAccess.get_file_as_string(store.path + ".combat"), saved["combat_journal"], saved["pilots"])
		durable_before_damage[0] = sequence == store.journal_sequence and saved["pilots"]["pilot0"]["ammo"]["x1"] == ammo["x1"] - ship.laser_count and saved["pilots"]["pilot0"]["boosts"]["starter"]["lasers"]["remaining"] == 7 - ship.laser_count
	, CONNECT_ONE_SHOT)
	store.begin_combat_tick()
	var first_shot := ship.try_fire(server.alien)
	store.end_combat_tick()
	if not first_shot or not durable_before_damage[0]:
		print("Ordering failure: fired=", first_shot, " durable=", durable_before_damage[0], " blocker=", ship.firing_blocker(server.alien), " store=", store.error)
		quit(2)
		return
	ammo = ship.ammo.duplicate()
	health = server.alien.hull + server.alien.shield
	var reserve := ResourceBoosts.remaining(ship.resource_boosts, "lasers")
	ship.shot_cooldown = 0
	var journal := FileAccess.get_file_as_string(store.path + ".combat")
	if "--journal-write-failure" in OS.get_cmdline_user_args():
		# Use a real read-only FileAccess to force the actual append/verify path to
		# fail after validation, without modifying operator files or filling a disk.
		store.close_journal()
		store.journal_file = FileAccess.open(store.path + ".combat", FileAccess.READ)
		store.journal_modified_time = FileAccess.get_modified_time(store.path + ".combat")
	else:
		write_text(store.path + ".combat", journal + "interrupted write")
	server.set_physics_process(true)
	var fired := ship.try_fire(server.alien)
	if not fired and store.failed and not server.is_physics_processing() and ship.ammo == ammo and ResourceBoosts.remaining(ship.resource_boosts, "lasers") == reserve and ship.shot_cooldown == 0 and server.alien.hull + server.alien.shield == health:
		print("JOURNAL_FAILURE_VERIFIED")
	else:
		quit(2)
