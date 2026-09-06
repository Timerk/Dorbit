extends SceneTree
## Run two processes with -- host / -- client to exercise real input and rendering.

var sector: Sector
var failures: int = 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var is_host := "host" in OS.get_cmdline_user_args()
	sector = preload("res://scenes/sector.tscn").instantiate()
	root.add_child(sector)
	await process_frame
	if is_host:
		sector.session.host(24680)
	else:
		sector.session.join("127.0.0.1", 24680)
	var deadline := Time.get_ticks_msec() + 10000
	while sector.session.ships.size() != 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	if sector.session.ships.size() != 2:
		push_error("Two-process connection failed")
		quit(1)
		return
	var start := sector.player.position
	if not is_host:
		Input.action_press("forward")
		Input.action_press("boost")
	for frame in range(180):
		# Automated replay must continue even when the other process has focus.
		sector.set_paused(false)
		await physics_frame
	Input.action_release("forward")
	Input.action_release("boost")
	if not is_host and (sector.player.position.z >= start.z - 20.0 or sector.player.energy >= 99.0):
		failures += 1
	if is_host:
		for id: int in sector.session.ships:
			if id != 1 and sector.session.ships[id].position.z >= start.z - 20.0:
				failures += 1
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build/validation")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/validation/network-%s.png" % ("host" if is_host else "client"))
		sector.session.open_menu()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/validation/network-menu-%s.png" % ("host" if is_host else "client"))
	print("Network playthrough (%s): %d failures" % ["host" if is_host else "client", failures])
	# Keep the host online long enough for the client's own screenshots.
	if is_host:
		await create_timer(2.0).timeout
	sector.session.disconnect_session("Replay finished")
	quit(0 if failures == 0 else 1)
