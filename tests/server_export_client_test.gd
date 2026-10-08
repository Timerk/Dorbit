extends "res://tests/network_test.gd"
## Run a normal source client against a separate exported server process.


func run() -> void:
	var client := make_sector("ExportClient")
	client.session.credential_id = "export_test"
	client.session.credential_token = "disposable-export-check-token"
	var port := int(OS.get_cmdline_user_args()[0])
	check(client.session.join("127.0.0.1", port) == OK, "Client begins connecting to exported server")
	var deadline := Time.get_ticks_msec() + 8000
	while (not client.session.active or not client.session.received_snapshot or client.session.combat.inventory.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(client.session.active and client.session.received_snapshot, "Exported server authenticates a real client and replicates state")
	check(client.credits == 137 and client.cargo.get("seprom", 0) == 5, "Exported server loads the disposable pilot's progression")
	check(client.session.ships.size() == 1 and client.aliens.size() == 5, "Server replicates one pilot and the complete alien roster")
	client.session.launch()
	deadline = Time.get_ticks_msec() + 8000
	while client.preflight and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not client.preflight, "Exported server admits pilot to flight")
	var start := client.player.position
	client.session.command_flight.rpc_id(1, Vector3(0, 0, -1), Vector3.ZERO, true)
	deadline = Time.get_ticks_msec() + 3000
	while client.player.position.distance_to(start) < 1.0 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(client.player.position.distance_to(start) >= 1.0, "Exported server simulates movement and sends it back to the client")
	finish()
