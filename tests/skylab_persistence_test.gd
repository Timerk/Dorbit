extends "res://tests/dedicated_server_test.gd"
## Actual authenticated RPCs, one ledger, duplicate request/restart/failure boundaries.


func run() -> void:
	var server := make_sector("SkylabServer", true, 24744)
	var client := make_sector("SkylabPilot")
	client.client_only = true
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24744))
	await settle(.6)
	check(client.session.active and not client.session.combat.lab_snapshot.is_empty(), "Authenticated pilot receives its own Skylab")
	if not client.session.active:
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	var store := server.session.store
	check(JSON.parse_string(FileAccess.get_file_as_string(store.path))["version"] == 8, "Legacy ledger migrates atomically to schema 8")
	check(not store.pilots["pilot0"].has("uridium") and not store.pilots["pilot0"]["premium"], "Migration does not grant premium currency or status")
	store.commit({"pilot0": 10000})
	server.session.combat.sync_lab_accounts()
	server.session.combat.publish_inventory(id)
	await settle()
	# Industry is available from flight; station proximity is not a Skylab prerequisite.
	server.session.ships[id].position = Vector3(300, 100, 200)
	client.session.combat.request_lab("upgrade", {"module": "basic"})
	await settle()
	check(store.pilots["pilot0"]["skylab"]["modules"]["basic"]["upgrade"] != null, "A remote authenticated pilot can start industry construction")
	var paid: int = store.pilots["pilot0"]["credits"]
	client.session.combat.skylab_request.rpc_id(1, 1, "upgrade", {"module": "basic"})
	await settle()
	check(store.pilots["pilot0"]["credits"] == paid and store.pilots["pilot0"]["equipment"]["revision"] == 1, "Retry cannot charge an upgrade twice")
	client.session.combat.request_lab("cancel", {"module": "basic"})
	await settle()
	check(store.pilots["pilot0"]["credits"] == paid and store.pilots["pilot0"]["skylab"]["modules"]["basic"]["level"] == 1, "Network cancellation forfeits costs and retains completed level")
	client.session.combat.request_lab("ship", {"manifest": {"prometium": 100}})
	await settle()
	check(store.pilots["pilot0"]["skylab"]["shipment"] != null and store.pilots["pilot0"]["equipment"]["revision"] == 3, "Dispatch saves manifest and request ID together")
	var shipment: Dictionary = store.pilots["pilot0"]["skylab"]["shipment"].duplicate(true)
	client.session.combat.skylab_request.rpc_id(1, 3, "ship", {"manifest": {"prometium": 100}})
	await settle()
	check(store.pilots["pilot0"]["skylab"]["shipment"] == shipment, "Shipment retry does not duplicate or replace its manifest")
	var next := store.pilots.duplicate(true)
	next["pilot0"]["cargo"]["starter"] = {"endurium": 400}
	next["pilot0"]["equipment"]["ships"]["second"] = "phoenix"
	next["pilot0"]["equipment"]["active_ship"] = "second"
	next["pilot0"]["cargo"]["second"] = {}
	next["pilot0"]["boosts"]["second"] = {}
	next["pilot0"]["skylab"]["shipment"]["arrivesAt"] = Skylab.now() - 1
	next["pilot0"]["skylab"]["shipment"]["dispatchedAt"] = Skylab.now() - 61
	check(store.persist(next), "Seed a filled hold and a different active ship during transit")
	check(store.advance_labs(Skylab.now()), "Server delivers a due shipment without an open browser")
	check(store.pilots["pilot0"]["cargo"]["starter"] == {"endurium": 400, "prometium": 100} and store.pilots["pilot0"]["cargo"]["second"].is_empty(), "Shipment goes to the dispatch ship, including overfull cargo, after switching")
	server.session.combat.sync_lab_accounts()
	server.session.disconnect_session("Restart delivery")
	await settle(.3)
	check(server.session.host(test_port(24744)) == OK, "Server restarts with a delivered shipment and overfull cargo")
	store = server.session.store
	check(store.pilots["pilot0"]["cargo"]["starter"]["prometium"] == 100 and store.pilots["pilot0"]["skylab"]["shipment"] == null, "Restart does not deliver the manifest twice")
	check(store.transact_lab("pilot0", 3, "ship", {"manifest": {"prometium": 100}}, Skylab.now()).contains("already"), "Persisted sequence rejects a retry after restart")
	var before := store.pilots.duplicate(true)
	store.advance_labs(Skylab.now())
	check(store.pilots["pilot0"]["cargo"] == before["pilot0"]["cargo"], "Repeated snapshot catch-up preserves delivery exactly once")
	var legacy_dir := store.path.get_base_dir().path_join("ammo-v4-migration")
	DirAccess.make_dir_recursive_absolute(legacy_dir)
	var legacy: Dictionary = store.pilots["pilot0"].duplicate(true)
	for field in ["skylab", "uridium", "premium"]: legacy.erase(field)
	legacy["ammo"] = {"x1": 321, "x2": 67, "x3": 89, "x4": 4}
	var legacy_text := JSON.stringify({"version": 4, "pilots": {"pilot0": legacy}})
	var legacy_file := FileAccess.open(legacy_dir.path_join("pilots.json"), FileAccess.WRITE)
	legacy_file.store_string(legacy_text)
	legacy_file.close()
	var migrated := PilotStore.new()
	check(migrated.open(legacy_dir), "Existing ammunition schema 4 migrates to combined schema 7")
	check(migrated.pilots["pilot0"]["ammo"] == Ammunition.starter().merged(legacy["ammo"], true) and migrated.pilots["pilot0"]["credits"] == legacy["credits"] and migrated.pilots["pilot0"]["equipment"] == legacy["equipment"], "Adding industry and rockets preserves spent/earned ammunition, wallet and equipment")
	check(migrated.pilots["pilot0"]["skylab"]["inventory"]["prometium"] == 1200 and FileAccess.get_file_as_string(migrated.path + ".bak") == legacy_text, "Ammo-era migration initializes industry once and keeps the exact old ledger backup")
	migrated.close()
	# The rocket and industry branches deployed different schema-6 layouts.
	for layout: String in ["rockets", "industry"]:
		var branch_dir := store.path.get_base_dir().path_join("v6-" + layout)
		DirAccess.make_dir_recursive_absolute(branch_dir)
		var record: Dictionary = store.pilots["pilot0"].duplicate(true)
		if layout == "rockets":
			for field in ["skylab", "premium"]: record.erase(field)
			record["ammo"]["r-310"] = 17
		else:
			record["ammo"] = {"x1": 321, "x2": 67, "x3": 89, "x4": 4}
		var branch_text := JSON.stringify({"version": 6, "pilots": {"pilot0": record}})
		var branch_file := FileAccess.open(branch_dir.path_join("pilots.json"), FileAccess.WRITE)
		branch_file.store_string(branch_text)
		branch_file.close()
		var combined := PilotStore.new()
		check(combined.open(branch_dir), "Schema-6 %s layout migrates" % layout)
		check(combined.pilots["pilot0"]["ammo"] == Ammunition.starter().merged(record["ammo"], true), "Migration preserves %s ammunition without repeating a grant" % layout)
		var saved_record: Dictionary = JSON.parse_string(branch_text)["pilots"]["pilot0"]
		check(not saved_record.has("skylab") or JSON.parse_string(JSON.stringify(combined.pilots["pilot0"]["skylab"])) == saved_record["skylab"], "Migration preserves existing industry jobs and robots")
		check(FileAccess.get_file_as_string(combined.path + ".bak") == branch_text, "Migration retains exact branch ledger backup")
		combined.close()
	var preview_dir := store.path.get_base_dir().path_join("preview-v5-migration")
	DirAccess.make_dir_recursive_absolute(preview_dir)
	var preview: Dictionary = store.pilots["pilot0"].duplicate(true)
	preview["credits"] = 2345
	preview["uridium"] = 70
	preview.erase("boosts") # The initial industry preview predates resource boosts.
	for robots: Dictionary in preview["skylab"]["robots"].values():
		robots["uridium"] = robots["advanced"]
		robots.erase("advanced")
	var activated := Skylab.now()
	preview["skylab"]["robots"]["prometiumCollector"]["active"] = [{"kind": "uridium", "startedAt": activated, "expiresAt": activated + 172800}]
	preview["skylab"]["robots"]["prometiumCollector"]["uridium"] = 7
	var preview_text := JSON.stringify({"version": 5, "pilots": {"pilot0": preview}})
	var preview_file := FileAccess.open(preview_dir.path_join("pilots.json"), FileAccess.WRITE)
	preview_file.store_string(preview_text)
	preview_file.close()
	var converted := PilotStore.new()
	check(converted.open(preview_dir), "Existing industry preview migrates to the credits-only ledger")
	check(converted.pilots["pilot0"]["credits"] == 9345 and not converted.pilots["pilot0"].has("uridium"), "Legacy wallet converts once at 100 credits per unit")
	var converted_robots: Dictionary = converted.pilots["pilot0"]["skylab"]["robots"]["prometiumCollector"]
	check(converted_robots["advanced"] == 7 and converted_robots["active"][0] == {"kind": "advanced", "startedAt": activated, "expiresAt": activated + 172800}, "Conversion preserves queued boost robots and their actual lifetime")
	check(FileAccess.get_file_as_string(converted.path + ".bak") == preview_text, "Credits-only migration preserves the exact old industry ledger backup")
	converted.close()
	check(converted.open(preview_dir) and converted.pilots["pilot0"]["credits"] == 9345, "Reload cannot repeat wallet conversion")
	converted.close()
	var failure_dir := store.path.get_base_dir().path_join("skylab-failure")
	DirAccess.make_dir_recursive_absolute(failure_dir)
	var file := FileAccess.open(failure_dir.path_join("pilots.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 6, "pilots": {"pilot0": store.pilots["pilot0"]}}))
	file.close()
	var probe := PilotStore.new()
	check(probe.open(failure_dir), "Open isolated Skylab failure ledger")
	before = probe.pilots.duplicate(true)
	var disk := FileAccess.get_file_as_string(probe.path)
	DirAccess.make_dir_absolute(probe.path + ".tmp")
	probe.transact_lab("pilot0", 4, "robots", {"module": "prometiumCollector", "kind": "credit", "amount": 1}, Skylab.now())
	check(probe.failed and probe.pilots == before and FileAccess.get_file_as_string(probe.path) == disk, "Write failure grants no robots and changes neither currency, revision nor ledger")
	probe.close()
	server.session.disconnect_session("Finished")
	finish()
