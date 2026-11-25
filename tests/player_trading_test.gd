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


func delay_invite_ack(server: Sector, left: Sector, right: Sector) -> void:
	var menu := left.equipment_menu.trade_menu
	var sender := left.session.combat
	var recipient := right.session.combat
	menu.open()
	var deadline := Time.get_ticks_msec() + 5000
	while sender.trade_pending and Time.get_ticks_msec() < deadline:
		await process_frame
	menu.refresh()
	menu.pilots.select(menu.pilots.get_item_index(right.multiplayer.get_unique_id()))
	# Let the server and recipient handle the invitation while withholding every
	# inbound RPC from the sender.
	multiplayer_poll = false
	await click(left, menu.invite_button)
	deadline = Time.get_ticks_msec() + 5000
	while recipient.trade_state.is_empty() and Time.get_ticks_msec() < deadline:
		left.multiplayer.multiplayer_peer.host.flush()
		server.multiplayer.poll()
		right.multiplayer.poll()
		await process_frame
	check(sender.trade_pending and sender.trade_state.is_empty() and not recipient.trade_state.is_empty(), "Recipient sees invitation before sender receives its token")


func close_before_invite_ack(server: Sector, left: Sector, right: Sector, expire: bool) -> void:
	await delay_invite_ack(server, left, right)
	var sender := left.session.combat
	var recipient := right.session.combat
	var menu := left.equipment_menu.trade_menu
	var sender_id := left.multiplayer.get_unique_id()
	var trades := server.session.combat.trading
	var deadline := Time.get_ticks_msec() + 5000
	if expire and trades.trades.has(sender_id):
		trades.trades[sender_id]["expires"] = 0
		trades.tick()
		while not recipient.trade_state.is_empty() and Time.get_ticks_msec() < deadline:
			server.multiplayer.poll()
			right.multiplayer.poll()
			await process_frame
		recipient.request_trade("invite", {"peer": sender_id})
		while recipient.trade_pending and Time.get_ticks_msec() < deadline:
			server.multiplayer.poll()
			right.multiplayer.poll()
			await process_frame
		check(recipient.trade_state.get("inviter", false), "Recipient sends a fresh invitation while the first acknowledgement is delayed")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	left.get_viewport().push_input(escape)
	check(not menu.visible and not menu.shade.visible, "Escape dismisses the unacknowledged invitation")
	menu.open()
	# Deliver the queued acknowledgement before the server handles withdrawal.
	server.multiplayer.multiplayer_peer.host.flush()
	left.multiplayer.poll()
	if not expire:
		menu.refresh()
		check(sender.trade_state.is_empty() and not menu.columns.visible, "Late acknowledgement cannot revive the closed trade in the reopened menu")
	multiplayer_poll = true
	deadline = Time.get_ticks_msec() + 5000
	if expire:
		while sender.trade_state.get("token", "") != recipient.trade_state.get("token") and Time.get_ticks_msec() < deadline:
			await process_frame
		menu.refresh()
		await click(left, menu.confirm_button)
		await settle()
		check(sender.trade_state.get("joined", false) and recipient.trade_state.get("joined", false), "Reopened menu can accept the replacement invitation after the old one expired")
	else:
		while (sender.trade_pending or not recipient.trade_state.is_empty() or not sender.trade_state.is_empty()) and Time.get_ticks_msec() < deadline:
			await process_frame
		check(trades.trades.is_empty() and sender.trade_state.is_empty() and recipient.trade_state.is_empty(), "Closing before acknowledgement releases both peers and the server after reopen")
	menu.close()
	await settle()


func press_mouse(client: Sector, control: Control, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.pressed = down
	client.get_viewport().push_input(event)
	await process_frame
	await process_frame


# Holding Confirm while the partner lowers their price and confirms must not
# let the release consent to the new terms. With `refreshing`, the refreshed
# menu cancels the press; without it, the click handler checks the version.
func stale_confirmation(server: Sector, left: Sector, right: Sector, refreshing: bool) -> void:
	var a := left.session.combat
	var b := right.session.combat
	var menu := left.equipment_menu.trade_menu
	var store := server.session.store
	await begin_trade(left, right)
	await command(left, "offer", {"items": [], "credits": 2})
	await command(right, "offer", {"items": [], "credits": 100})
	menu.open()
	await settle(.1)
	var before := [store.pilots["pilot0"]["credits"], store.pilots["pilot1"]["credits"]]
	var shown: int = a.trade_state["version"]
	await press_mouse(left, menu.confirm_button, true)
	check(menu.armed.get("version") == shown, "Confirmation press records the displayed offer version")
	if not refreshing: menu.set_process(false)
	await command(right, "offer", {"items": [], "credits": 1})
	await command(right, "confirm")
	check(b.trade_state["confirmed"] and a.trade_state["version"] != shown, "Partner changes the price and confirms during the press")
	await press_mouse(left, menu.confirm_button, false)
	await settle(.15)
	menu.set_process(true)
	var label := "while the menu refreshes" if refreshing else "without a menu refresh"
	check(not a.trade_state.get("confirmed", true) and not a.trade_pending and server.session.combat.trading.trades.has(left.multiplayer.get_unique_id()), "Releasing a press started on older terms never confirms " + label)
	check(store.pilots["pilot0"]["credits"] == before[0] and store.pilots["pilot1"]["credits"] == before[1], "Changed terms move no credits from a stale press " + label)
	await settle(.05)
	await click(left, menu.confirm_button)
	var deadline := Time.get_ticks_msec() + 5000
	while not (a.trade_state.is_empty() and b.trade_state.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(a.trade_message == PlayerTrading.COMPLETED and store.pilots["pilot0"]["credits"] == before[0] - 1 and store.pilots["pilot1"]["credits"] == before[1] + 1, "A fresh click after review accepts the displayed terms " + label)
	menu.close()
	await settle(.1)


# A combat wallet debit keeps the inventory revision but makes the offer
# unaffordable. The server must refuse completion and leave both ledgers alone.
func wallet_debit(server: Sector, left: Sector, right: Sector) -> void:
	var a := left.session.combat
	var b := right.session.combat
	var store := server.session.store
	var trading := server.session.combat.trading
	var aid := left.multiplayer.get_unique_id()
	var wallet: int = store.pilots["pilot0"]["credits"]
	await begin_trade(left, right)
	await command(left, "offer", {"items": [], "credits": wallet})
	await command(right, "offer", {"items": [], "credits": 1})
	await command(left, "confirm")
	var revisions := [store.pilots["pilot0"]["equipment"]["revision"], store.pilots["pilot1"]["equipment"]["revision"]]
	var offers: Array = trading.trades[aid]["offers"].duplicate(true)
	check(store.commit({"pilot0": wallet - 1}), "Combat debits the offering wallet")
	server.session.combat.records[aid]["credits"] = wallet - 1
	check(store.pilots["pilot0"]["equipment"]["revision"] == revisions[0], "Wallet debit leaves the inventory revision unchanged")
	var debited := store.pilots.duplicate(true)
	check(store.complete_trade("pilot0", "pilot1", offers, revisions) == "Not enough credits for this offer." and store.pilots == debited, "Ledger refuses an unaffordable offer at the unchanged revision")
	await command(right, "confirm")
	await settle(.1)
	check(trading.trades.is_empty() and a.trade_state.is_empty() and b.trade_state.is_empty(), "Final confirmation after the debit cancels the trade for both pilots")
	check(a.trade_message.contains("wallet changed"), "Offering pilot learns the wallet changed: " + a.trade_message)
	check(without_industry(store.pilots["pilot0"]) == without_industry(debited["pilot0"]) and without_industry(store.pilots["pilot1"]) == without_industry(debited["pilot1"]), "Both pilots keep their debited wallet and items")
	check(store.commit({"pilot0": wallet}), "Restore the offering wallet")
	server.session.combat.records[aid]["credits"] = wallet


# The snapshot replacement commits the trade. When journal compaction then
# fails, both pilots still learn it completed before the server stops.
func compaction_failure(server: Sector, left: Sector, right: Sector) -> PilotStore:
	var a := left.session.combat
	var b := right.session.combat
	var store := server.session.store
	var trading := server.session.combat.trading
	var stopped := [false]
	trading.stop_for_save_failure = func(): stopped[0] = true
	var credits := [store.pilots["pilot0"]["credits"], store.pilots["pilot1"]["credits"]]
	await begin_trade(left, right)
	await command(left, "offer", {"items": [], "credits": 3})
	await command(left, "confirm")
	var ammo: Dictionary = store.pilots["pilot0"]["ammo"].duplicate()
	check(store.commit_combat({"pilot0": ammo}) and store.journal_sequence > store.checkpoint_sequence, "Pending combat journal records need compaction at the next checkpoint")
	# Block only the journal compaction, after the snapshot replacement succeeded.
	store.replacement_trace = func(destination: String, _marks: PackedInt64Array, renamed: bool):
		if destination == store.path and renamed: DirAccess.make_dir_absolute(store.path + ".combat.tmp")
	await command(right, "confirm")
	var deadline := Time.get_ticks_msec() + 5000
	while not (a.trade_state.is_empty() and a.trade_message == PlayerTrading.COMPLETED) and Time.get_ticks_msec() < deadline:
		await process_frame
	await settle(.1)
	store.replacement_trace = Callable()
	check(store.failed and stopped[0], "Compaction failure still stops the server for recovery: " + store.error)
	check(a.trade_message == PlayerTrading.COMPLETED and b.trade_message == PlayerTrading.COMPLETED, "Both pilots learn the saved trade completed (left: %s, right: %s)" % [a.trade_message, b.trade_message])
	check(a.inventory.get("revision") == store.pilots["pilot0"]["equipment"]["revision"] and b.inventory.get("revision") == store.pilots["pilot1"]["equipment"]["revision"], "Both pilots receive their saved inventories")
	check(trading.trades.is_empty() and store.pilots["pilot0"]["credits"] == credits[0] - 3 and store.pilots["pilot1"]["credits"] == credits[1] + 3, "Committed trade is reflected in the server ledger")
	trading.stop_for_save_failure = Callable()
	var directory := store.path.get_base_dir()
	store.close()
	# Operator recovery: inspect and remove the interrupted compaction.
	DirAccess.remove_absolute(directory.path_join("pilots.json.combat.tmp"))
	var recovered := PilotStore.new()
	check(recovered.open(directory), "Recovered store reopens after the compaction failure")
	check(recovered.pilots["pilot0"]["credits"] == credits[0] - 3 and recovered.pilots["pilot1"]["credits"] == credits[1] + 3, "Recovered wallets reflect the reported trade")
	server.session.store = recovered
	return recovered


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
	b.request_trade("confirm")
	deadline = Time.get_ticks_msec() + 5000
	while not (a.trade_state.is_empty() and b.trade_state.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	var both_completed := (a.trade_state.is_empty() and a.trade_message == PlayerTrading.COMPLETED
		and b.trade_state.is_empty() and b.trade_message == PlayerTrading.COMPLETED)
	check(both_completed, "Final confirmation ends both trade sessions (left: %s, right: %s)" % [a.trade_message, b.trade_message])
	if not both_completed:
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
	await stale_confirmation(server, left, right, true)
	await stale_confirmation(server, left, right, false)
	await wallet_debit(server, left, right)
	store = await compaction_failure(server, left, right)
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
	await close_before_invite_ack(server, left, right, false)
	await close_before_invite_ack(server, left, right, true)
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
	# Disconnecting after the partner confirmed a nonempty offer moves nothing.
	var o := observer.session.combat
	await begin_trade(observer, right)
	await command(right, "offer", {"items": ["hidden"], "credits": 5})
	await command(right, "confirm")
	check(b.trade_state["confirmed"] and o.trade_state["other"]["credits"] == 5, "Partner confirmed a nonempty offer")
	var held := store.pilots.duplicate(true)
	var stale_token: String = b.trade_state["token"]
	var stale_version: int = b.trade_state["version"]
	observer.session.disconnect_session("Test trade disconnect after confirmation")
	deadline = Time.get_ticks_msec() + 5000
	while (not b.trade_state.is_empty() or server.session.combat.trading.trades.has(bid)) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(b.trade_state.is_empty() and b.trade_message == "Trade cancelled: a pilot disconnected." and server.session.combat.trading.trades.is_empty(), "Partner disconnect cancels a confirmed trade for the remaining pilot")
	b.trade_request.rpc_id(1, "confirm", stale_token, stale_version, {}, int(right.player.get_meta("life", 0)))
	await settle(.1)
	check(without_industry(store.pilots["pilot1"]) == without_industry(held["pilot1"]) and without_industry(store.pilots["pilot2"]) == without_industry(held["pilot2"]), "Disconnect leaves both wallets and items untouched, even after a late confirmation")
	await delay_invite_ack(server, left, right)
	left.session.disconnect_session("Test trade disconnect")
	multiplayer_poll = true
	await settle(.2)
	check(not a.trade_pending and a.trade_state.is_empty() and b.trade_state.is_empty() and server.session.combat.trading.trades.is_empty(), "Sender disconnect before acknowledgement releases both peers and the server")
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
