extends "res://tests/dedicated_server_test.gd"
## A differing Combat RPC table must be rejected before any gameplay packets arrive.


func run() -> void:
	var server := make_sector("CompatibilityServer", true)
	var original: Script = server.session.combat.get_script()
	var original_source := original.source_code.replace("\r\n", "\n")
	# Reproduce an extra RPC from another gameplay branch while keeping flight compatible.
	var different := GDScript.new()
	different.source_code = 'extends SessionCombat\n\n@rpc("any_peer", "call_remote", "reliable")\nfunc fixture_request(life: int, action: String, offer: String, run: String) -> void:\n\tpass\n'
	check(different.reload() == OK, "Mismatched combat fixture compiles")
	server.session.combat.set_script(different)
	server.session.combat.session = server.session
	var client := make_sector("CompatibilityClient")
	if DisplayServer.get_name() != "headless":
		var viewport := client.get_parent() as SubViewport
		viewport.size = Vector2i(1280, 720)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var display := TextureRect.new()
		display.texture = viewport.get_texture()
		display.size = viewport.size
		root.add_child(display)
		root.content_scale_size = viewport.size
		root.size = viewport.size
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.client_only = true
	client.session.join("127.0.0.1", test_port(24683))
	await settle(0.5)
	check(not client.session.active and server.session.ships.is_empty(), "Different Combat RPC tables cannot enter the sector")
	check(client.session.status.contains("build"), "Build mismatch gives an actionable connection message")
	check(server.session.pilot_ids.is_empty() and server.session.challenges.is_empty(), "Incompatible peers reserve no pilot login or challenge")
	# A changed signature can keep the same names and still misinterpret packets.
	different = GDScript.new()
	different.source_code = original_source.replace("class_name SessionCombat\n", "").replace(
		'func show_laser(start: Vector3, finish: Vector3, hostile: bool, ammo_type: String = "x1")',
		'func show_laser(start: Vector3, finish: Vector3, hostile: bool, ammo_type: String = "x1", extra: bool = false)')
	check(different.reload() == OK, "Changed-argument fixture compiles")
	server.session.combat.set_script(different)
	server.session.combat.session = server.session
	client.session.join("127.0.0.1", test_port(24683))
	await settle(0.3)
	check(not client.session.active and server.session.ships.is_empty(), "Changed RPC arguments are rejected before gameplay")
	different = GDScript.new()
	different.source_code = 'extends SessionCombat\n\n@rpc("authority", "call_local", "unreliable", 4)\nfunc show_laser(start: Vector3, finish: Vector3, hostile: bool, ammo_type: String = "x1") -> void:\n\tpass\n'
	check(different.reload() == OK, "Changed-channel fixture compiles")
	server.session.combat.set_script(different)
	server.session.combat.session = server.session
	client.session.join("127.0.0.1", test_port(24683))
	await settle(0.3)
	check(not client.session.active and server.session.ships.is_empty(), "Changed RPC transport settings are rejected before gameplay")
	server.session.combat.set_script(original)
	server.session.combat.session = server.session
	server.multiplayer.peer_authenticating.disconnect(server.session.begin_authentication)
	var legacy := func(id: int): server.multiplayer.send_auth(id, Crypto.new().generate_random_bytes(32))
	server.multiplayer.peer_authenticating.connect(legacy)
	client.session.join("127.0.0.1", test_port(24683))
	await settle(0.3)
	check(not client.session.active and client.session.status.contains("build"), "Older servers without a compatibility handshake are rejected clearly")
	server.multiplayer.peer_authenticating.disconnect(legacy)
	server.multiplayer.peer_authenticating.connect(server.session.begin_authentication)
	# A peer cannot skip the server-side check by sending a valid pilot proof alone.
	client.multiplayer.auth_callback = func(id: int, data: PackedByteArray):
		var envelope: Dictionary = JSON.parse_string(data.get_string_from_utf8())
		var nonce: PackedByteArray = envelope["nonce"].hex_decode()
		var proof := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, client.session.credential_token.sha256_buffer(), nonce)
		client.multiplayer.send_auth(id, JSON.stringify({"id": "pilot0", "proof": proof.hex_encode(), "protocol": "wrong"}).to_utf8_buffer())
	client.session.join("127.0.0.1", test_port(24683))
	await settle(0.3)
	check(not client.session.active and server.session.pilot_ids.is_empty(), "Server rejects incompatible proofs without reserving a pilot")
	client.multiplayer.auth_callback = client.session.authenticate
	client.session.join("127.0.0.1", test_port(24683))
	await settle(0.4)
	await replicate(server)
	check(client.session.active and server.session.ships.size() == 1, "Matching builds connect after mismatch rejection")
	if client.session.active:
		client.session.launch()
		await settle()
		var pilot: Pilot = server.session.ships[client.multiplayer.get_unique_id()]
		pilot.position = Vector3(0, 100, 0)
		server.alien.position = Vector3(0, 100, -100)
		server.alien.home_position = server.alien.position
		await replicate(server)
		client.player.position = pilot.position
		client.alien.position = server.alien.position
		client.select_target(client.alien)
		client.auto_fire = true
		client.weapon_status = client.player.firing_blocker(client.target)
		await physics_frame
		await send_fire(client)
		var shield := server.alien.shield
		server.session.combat.tick(0.01)
		# ENet effects normally arrive in milliseconds, before the 180 ms beam expires.
		var deadline := Time.get_ticks_msec() + 1000
		var visible_beam := false
		while Time.get_ticks_msec() < deadline and not visible_beam:
			await process_frame
			for child in client.get_children():
				if child is CombatEffect and child.get_meta("laser", false) and child.is_in_group("transient_feedback"):
					visible_beam = true
		check(server.alien.shield < shield, "Matching builds retain authoritative pilot laser damage")
		check(visible_beam, "The server-confirmed pilot shot creates a visible client laser mesh")
		if visible_beam and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var directory := ProjectSettings.globalize_path("res://build/validation")
			DirAccess.make_dir_recursive_absolute(directory)
			root.get_texture().get_image().save_png(directory.path_join("network-pilot-laser.png"))
	await finish()
