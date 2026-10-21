extends "res://tests/shop_test.gd"
## Real authenticated ENet clients, checkpoint/restart safety and modal input.


func command(client: Sector, action: String, payload: Dictionary = {}) -> void:
	client.session.combat.request_trade(action, payload)
	var deadline := Time.get_ticks_msec() + 5000
	while client.session.combat.trade_pending and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not client.session.combat.trade_pending, "Trade request receives an authoritative reply: " + action)
	await settle(.04)


func begin_trade(left: Sector, right: Sector) -> void:
	await command(left, "invite", {"peer": right.multiplayer.get_unique_id()})
	await command(right, "join")
	check(left.session.combat.trade_state.get("joined", false) and right.session.combat.trade_state.get("joined", false), "Both pilots explicitly join the trade")


func run_rules(store: PilotStore) -> void:
	var pilot: Dictionary = store.pilots["pilot0"]
	for offer: Variant in [null, {}, {"items": [], "credits": -1}, {"items": [], "credits": 1.5},
			{"items": ["purchase-1", "purchase-1"], "credits": 0}, {"items": ["missing"], "credits": 0},
			{"items": ["starter-laser"], "credits": 0}, {"items": [], "credits": 1001},
			{"items": ["purchase-1"], "credits": 0, "recipient": "pilot9"}]:
		check(not PlayerTrading.offer_blocker(pilot, offer).is_empty(), "Malformed, duplicate, missing, fitted or unaffordable offers are blocked: " + str(offer))
	check(PlayerTrading.offer_blocker(pilot, {"items": ["purchase-1"], "credits": 1000}).is_empty(), "Stored equipment and the entire wallet can be offered")
	var many := pilot.duplicate(true)
	var items := []
	for index in range(PlayerTrading.MAX_ITEMS + 1):
		var id := "spare-%d" % index
		many["equipment"]["items"][id] = {"model": "engine", "ship": "", "slot": ""}
		items.append(id)
	check(not PlayerTrading.offer_blocker(many, {"items": items, "credits": 0}).is_empty(), "Offer item limit is enforced on the server")
	var before := store.pilots.duplicate(true)
	check(store.complete_trade("pilot0", "pilot0", [{"items": [], "credits": 1}, {"items": [], "credits": 0}], [0, 0]) == "Invalid trade.", "Self trading is rejected at the ledger boundary")
	check(store.complete_trade("pilot0", "pilot1", [{"items": [], "credits": 0}, {"items": [], "credits": 0}], [0, 0]) == "Add an item or credits before confirming.", "Empty trades cannot consume inventory revisions")
	check(store.pilots == before, "Rejected trades leave the entire ledger untouched")
	check(store.complete_trade("pilot0", "pilot1", [{"items": ["purchase-1"], "credits": 0}, {"items": [], "credits": 0}], [1, 0]) == "Inventory changed. Start a new trade.", "Ledger rejects stale reviewed inventory revisions")
	var capped := before.duplicate(true)
	capped["pilot1"]["credits"] = PilotStore.MAX_CREDITS
	check(store.persist(capped), "Seed a recipient at the wallet limit")
	check(store.complete_trade("pilot0", "pilot1", [{"items": ["purchase-1"], "credits": 1}, {"items": [], "credits": 0}], [0, 0]) == "Trade exceeds a pilot's credit limit." and store.pilots == capped, "Credit overflow preserves every offered item and both wallets")
	check(store.persist(before), "Restore uncapped trade fixtures")


func run() -> void:
	var server := make_sector("TradeServer", true)
	var clients: Array[Sector] = []
	for index in range(3):
		var client := make_sector("TradePilot%d" % index)
		client.session.credential_id = "pilot%d" % index
		client.session.credential_token = test_token(index)
		clients.append(client)
	for client in clients: client.session.join("127.0.0.1", test_port(24683))
	var deadline := Time.get_ticks_msec() + 10000
	while (server.session.ships.size() != 3 or clients.any(func(client: Sector): return not client.session.received_snapshot)) and Time.get_ticks_msec() < deadline:
		server.session.send_snapshot()
		await process_frame
	check(server.session.ships.size() == 3 and clients.all(func(client: Sector): return client.session.received_snapshot), "Three pilots authenticate and receive inventories")
	if server.session.ships.size() != 3:
		await finish()
		return
	var left := clients[0]
	var right := clients[1]
	var observer := clients[2]
	var a := left.session.combat
	var b := right.session.combat
	var aid := left.multiplayer.get_unique_id()
	var bid := right.multiplayer.get_unique_id()
	var store := server.session.store
	var next := store.pilots.duplicate(true)
	for index in range(2):
		next["pilot%d" % index]["credits"] = 1000
		next["pilot%d" % index]["equipment"]["items"]["purchase-1"] = {"model": "ammo-cpu" if index == 0 else "engine", "ship": "", "slot": ""}
		next["pilot%d" % index]["equipment"]["items"]["hidden"] = {"model": "shield", "ship": "", "slot": ""}
	next["pilot0"]["equipment"]["items"]["purchase-1"].merge({"enabled": false, "ammo_type": "x3"})
	check(store.persist(next), "Seed equipment with colliding pilot-local item IDs")
	for id: int in server.session.ships:
		server.session.combat.records[id]["credits"] = store.pilots[server.session.pilot_ids[id]]["credits"]
		server.session.combat.publish_inventory(id)
	await settle(.15)
	run_rules(store)
	await command(left, "snapshot")
	check(a.trade_candidates.size() == 2, "Station roster includes the two other available pilots")
	await command(left, "invite", {"peer": aid})
	check(a.trade_state.is_empty(), "Self invitation is rejected")
	await begin_trade(left, right)
	await command(observer, "invite", {"peer": aid})
	check(observer.session.combat.trade_state.is_empty(), "A participant cannot be drawn into a second trade")
	await command(left, "offer", {"items": ["purchase-1"], "credits": 100})
	await command(right, "offer", {"items": ["purchase-1"], "credits": 30})
	check(b.trade_state["other"]["items"].size() == 1 and b.trade_state["other"]["items"][0]["model"] == "ammo-cpu", "Counterparty receives only offered equipment, including its settings")
	check(observer.session.combat.trade_state.is_empty() and observer.session.combat.trade_candidates.is_empty(), "Bystander receives neither private offers nor unsolicited trade state")
	var token: String = a.trade_state["token"]
	var reviewed: int = a.trade_state["version"]
	observer.session.combat.trade_request.rpc_id(1, "confirm", token, reviewed, {}, 0)
	await settle(.1)
	check(store.pilots["pilot0"]["credits"] == 1000 and not a.trade_state["confirmed"], "A third peer cannot confirm someone else's trade")
	await command(left, "confirm")
	check(a.trade_state["confirmed"] and not b.trade_state["confirmed"], "First confirmation waits without transferring anything")
	await command(right, "offer", {"items": ["purchase-1"], "credits": 31})
	check(not a.trade_state["confirmed"] and not b.trade_state["confirmed"], "Changing an offer clears both confirmations")
	a.trade_request.rpc_id(1, "confirm", token, reviewed, {}, int(left.player.get_meta("life", 0)))
	await settle(.1)
	check(not a.trade_state["confirmed"] and store.pilots["pilot0"]["credits"] == 1000, "A delayed confirmation for the previous offer cannot consent to a new price")
	# Review the actual modal and send an offer through mouse input.
	var viewport := left.get_viewport() as SubViewport
	viewport.size = Vector2i(960, 600)
	if DisplayServer.get_name() != "headless":
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.size = viewport.size
		var screen := TextureRect.new()
		screen.texture = viewport.get_texture()
		root.add_child(screen)
	left.main_menu.select_page("hangar")
	await settle(.1)
	await click(left, left.equipment_menu.trade_button)
	var menu := left.equipment_menu.trade_menu
	await settle(.1)
	check(menu.visible and menu.shade.visible, "Hangar opens a modal trade window through real mouse input")
	for index in range(12):
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.pressed = true
		viewport.push_input(tab)
		await process_frame
		check(menu.is_ancestor_of(viewport.gui_get_focus_owner()), "Tab focus stays inside the trade modal")
	for dimensions: Vector2i in [Vector2i(960, 600), Vector2i(1440, 900)]:
		viewport.size = dimensions
		root.size = dimensions
		await settle(.1)
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(menu.get_global_rect()), "Trade window fits at %s" % dimensions)
		check(menu.get_global_rect().encloses(menu.confirm_button.get_global_rect()), "Confirmation stays inside the modal")
		await capture(left, "player-trade-%d" % dimensions.x)
	var toggle := menu.own_items.get_child(1) as CheckButton
	await click(left, toggle)
	check(menu.dirty and menu.confirm_button.disabled, "Unsent item edits block confirmation")
	await click(left, toggle)
	await click(left, menu.update_button)
	await settle(.1)
	check(not menu.dirty and not menu.confirm_button.disabled, "Updating the offer returns to the reviewed server state")
	await click(left, menu.confirm_button)
	await settle(.1)
	check(a.trade_state["confirmed"] and not menu.credits.editable and menu.own_items.get_child(0).disabled, "Confirmed offers lock their local editors until cancelled or changed by the partner")
	await command(right, "confirm")
	check(a.trade_state.is_empty() and b.trade_state.is_empty(), "Final confirmation ends both trade sessions")
	if not a.trade_state.is_empty():
		await finish()
		return
	check(store.pilots["pilot0"]["credits"] == 931 and store.pilots["pilot1"]["credits"] == 1069, "Both credit offers exchange in one balanced checkpoint")
	check(not a.inventory["items"].has("purchase-1") and a.inventory["items"]["trade-1-1"]["model"] == "engine", "Recipient inventory is synchronized with a collision-free incoming ID")
	check(b.inventory["items"]["trade-1-1"]["enabled"] == false and b.inventory["items"]["trade-1-1"]["ammo_type"] == "x3", "Transferred extra retains its per-instance settings")
	check(a.inventory["items"].has("hidden") and b.inventory["items"].has("hidden"), "Unrelated stored equipment remains intact")
	var completed := store.pilots.duplicate(true)
	a.trade_request.rpc_id(1, "confirm", token, reviewed + 1, {}, 0)
	await settle(.1)
	check(store.pilots == completed, "Duplicate final confirmations cannot repeat a transfer")
	menu.close()
	var directory := store.path.get_base_dir()
	store.close()
	var reopened := PilotStore.new()
	check(reopened.open(directory), "Completed exchange reloads from snapshot and journal")
	check(without_industry(reopened.pilots["pilot0"]) == without_industry(completed["pilot0"]) and without_industry(reopened.pilots["pilot1"]) == without_industry(completed["pilot1"]), "Both sides survive a server store restart")
	server.session.store = reopened
	store = reopened
	await begin_trade(left, right)
	await command(left, "offer", {"items": [], "credits": 1})
	await command(left, "confirm")
	await command(right, "confirm")
	check(store.pilots["pilot0"]["credits"] == 930 and store.pilots["pilot1"]["credits"] == 1070, "One-sided credit gifts are supported")
	await begin_trade(left, right)
	await command(left, "cancel")
	check(a.trade_state.is_empty() and b.trade_state.is_empty(), "Either pilot can cancel without transferring anything")
	await begin_trade(left, right)
	menu.open()
	await settle(.1)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	viewport.push_input(escape)
	await settle(.1)
	check(not menu.visible and not menu.shade.visible and left.equipment_menu.visible, "Escape closes only the trade modal and its input blocker")
	check(a.trade_state.is_empty() and b.trade_state.is_empty(), "Closing the modal cancels both pilots' offers")
	await begin_trade(left, right)
	server.session.ships[bid].position += Vector3(1000, 0, 0)
	server.session.combat.trading.tick()
	await settle(.1)
	check(a.trade_state.is_empty() and b.trade_state.is_empty(), "Leaving station range cancels the trade for both pilots")
	server.session.ships[bid].position = Sector.SPAWN_POSITION
	await begin_trade(left, right)
	server.session.combat.records[bid]["life"] += 1
	server.session.combat.trading.tick()
	await settle(.1)
	check(a.trade_state.is_empty(), "A changed ship life cancels an old trade even after rescue")
	server.session.combat.records[bid]["life"] -= 1
	await begin_trade(left, right)
	a.request_station("fit", "hidden", "starter", "generator3")
	await settle(.15)
	check(a.trade_state.is_empty() and b.trade_state.is_empty(), "Fitting an item cancels reviewed offers immediately")
	await begin_trade(left, right)
	server.session.combat.trading.trades[aid]["expires"] = 0
	server.session.combat.trading.tick()
	await settle(.1)
	check(a.trade_state.is_empty(), "Abandoned invitations and offers expire")
	await begin_trade(left, right)
	right.session.disconnect_session("Test trade disconnect")
	await settle(.2)
	check(a.trade_state.is_empty(), "Disconnect cancels the surviving pilot's trade")
	# Test a real write blocker after all network checks. No production data or
	# credentials are read: this store was provisioned by the inherited fixture.
	var before := store.pilots.duplicate(true)
	var snapshot := FileAccess.get_file_as_string(store.path)
	var revisions := [before["pilot0"]["equipment"]["revision"], before["pilot1"]["equipment"]["revision"]]
	DirAccess.make_dir_absolute(store.path + ".tmp")
	check(store.complete_trade("pilot0", "pilot1", [{"items": [], "credits": 1}, {"items": [], "credits": 0}], revisions) == "Persistence unavailable.", "Failed persistence never confirms a trade")
	check(store.pilots == before and FileAccess.get_file_as_string(store.path) == snapshot, "Failed save preserves both inventories and wallets in memory and on disk")
	DirAccess.remove_absolute(store.path + ".tmp")
	store.close()
	server.session.disconnect_session("Trade test complete")
	await settle(.1)
	print("Player trading checks complete")
	await finish()
