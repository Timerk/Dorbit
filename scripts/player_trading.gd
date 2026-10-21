class_name PlayerTrading
extends RefCounted
## Invitations and offers live only on the server. Only the two participants
## receive offers; the ledger commits both sides before success is published.

const MAX_ITEMS := 12
const TIMEOUT_MS := 120_000
const COMPLETED := "Trade completed. Items and credits saved."
var combat: Node
var trades: Dictionary[int, Dictionary] = {}


func _init(owner: Node) -> void:
	combat = owner


static func offer_blocker(pilot: Dictionary, offer: Variant) -> String:
	if not offer is Dictionary or offer.size() != 2 or not offer.get("items") is Array or not PilotStore.valid_credits(offer.get("credits")):
		return "Invalid trade offer."
	if offer["items"].size() > MAX_ITEMS:
		return "Offer at most %d items." % MAX_ITEMS
	if offer["credits"] > pilot["credits"]:
		return "Not enough credits for this offer."
	var seen := {}
	for id: Variant in offer["items"]:
		if not id is String or not PilotStore.valid_id(id) or seen.has(id):
			return "Invalid or duplicate trade item."
		seen[id] = true
		var item: Dictionary = pilot["equipment"]["items"].get(id, {})
		if item.is_empty(): return "You no longer own an offered item."
		if not item["ship"].is_empty() or not item["slot"].is_empty():
			return "Remove equipped items before trading them."
	return ""


func available(id: int) -> bool:
	var session: FlightSession = combat.session
	return (session.pilot_ids.has(id) and combat.records.has(id) and session.ships.has(id)
		and session.sector.repair_blocker(session.ships[id]).is_empty())


func candidates(id: int) -> Array:
	var result := []
	for peer: int in combat.records:
		if peer != id and available(peer) and not trades.has(peer):
			result.append({"peer": peer, "name": combat.session.pilot_ids[peer]})
	return result


func publish(id: int, message: String = "") -> void:
	var session: FlightSession = combat.session
	if not session.pilot_ids.has(id): return
	var state := {}
	if trades.has(id):
		var trade := trades[id]
		var index: int = trade["peers"].find(id)
		var other: int = trade["peers"][1 - index]
		var their_items := []
		for item_id: String in trade["offers"][1 - index]["items"]:
			var item: Dictionary = session.store.pilots[session.pilot_ids[other]]["equipment"]["items"].get(item_id, {})
			if not item.is_empty(): their_items.append(item.duplicate(true))
		state = {"token": trade["token"], "version": trade["version"], "partner": session.pilot_ids[other],
			"inviter": index == 0, "joined": trade["joined"], "own": trade["offers"][index].duplicate(true),
			"other": {"items": their_items, "credits": trade["offers"][1 - index]["credits"]},
			"confirmed": trade["confirmed"][index], "other_confirmed": trade["confirmed"][1 - index]}
	combat.trade_result.rpc_id(id, state, candidates(id), message)


func publish_both(trade: Dictionary) -> void:
	for id: int in trade["peers"]: publish(id)


func cancel(id: int, message: String = "Trade cancelled. No items or credits moved.") -> void:
	if not trades.has(id): return
	var peers: Array = trades[id]["peers"].duplicate()
	for peer: int in peers: trades.erase(peer)
	for peer: int in peers: publish(peer, message)


func tick() -> void:
	for id: int in trades.keys():
		if not trades.has(id): continue
		var trade := trades[id]
		if Time.get_ticks_msec() >= trade["expires"]:
			cancel(id, "Trade expired. No items or credits moved.")
			continue
		for index in range(2):
			var peer: int = trade["peers"][index]
			if not available(peer) or combat.records[peer]["life"] != trade["lives"][index]:
				cancel(id, "Trade cancelled: both pilots must remain at Outpost 01.")
				break
			var pilot: Dictionary = combat.session.store.pilots[combat.session.pilot_ids[peer]]
			if pilot["equipment"]["revision"] != trade["revisions"][index] or not offer_blocker(pilot, trade["offers"][index]).is_empty():
				cancel(id, "Trade cancelled: an inventory or wallet changed. Review it and start again.")
				break


func request(id: int, action: String, token: String, version: int, payload: Dictionary, life: int) -> void:
	var session: FlightSession = combat.session
	tick()
	if payload.size() > 2 or JSON.stringify(payload).length() > 2048 or token.length() > 32:
		publish(id, "Invalid trade request.")
		return
	if action == "snapshot":
		publish(id)
		return
	if action == "cancel":
		if trades.has(id) and trades[id]["token"] == token: cancel(id)
		else: publish(id, "Trade is no longer active.")
		return
	if not available(id) or combat.records[id]["life"] != life:
		publish(id, "Return to Outpost 01 and wait until station services are available.")
		return
	if action == "invite":
		var peer: Variant = payload.get("peer")
		if not peer is int or peer == id or not available(peer):
			publish(id, "Choose another pilot at Outpost 01.")
			return
		if trades.has(id) or trades.has(peer):
			publish(id, "A pilot is already in a trade. Refresh the pilot list.")
			return
		var trade := {"token": Crypto.new().generate_random_bytes(16).hex_encode(), "version": 0,
			"peers": [id, peer], "joined": false, "offers": [{"items": [], "credits": 0}, {"items": [], "credits": 0}],
			"confirmed": [false, false], "expires": Time.get_ticks_msec() + TIMEOUT_MS,
			"lives": [combat.records[id]["life"], combat.records[peer]["life"]],
			"revisions": [session.store.pilots[session.pilot_ids[id]]["equipment"]["revision"], session.store.pilots[session.pilot_ids[peer]]["equipment"]["revision"]]}
		trades[id] = trade
		trades[peer] = trade
		publish_both(trade)
		combat.message(peer, "%s invited you to trade. Open Hangar > Player trade." % session.pilot_ids[id])
		return
	if not trades.has(id) or trades[id]["token"] != token:
		publish(id, "Trade is no longer active.")
		return
	var trade := trades[id]
	if trade["version"] != version:
		publish(id, "Offer changed. Review both offers before confirming.")
		return
	var index: int = trade["peers"].find(id)
	if action == "join" and index == 1 and not trade["joined"]:
		trade["joined"] = true
		trade["version"] += 1
	elif not trade["joined"]:
		publish(id, "Wait for the other pilot to accept the invitation.")
		return
	elif action == "offer":
		var blocker := offer_blocker(session.store.pilots[session.pilot_ids[id]], payload)
		if not blocker.is_empty():
			publish(id, blocker)
			return
		if payload != trade["offers"][index]:
			trade["offers"][index] = payload.duplicate(true)
			trade["version"] += 1
			trade["confirmed"] = [false, false]
	elif action == "confirm":
		var offers: Array = trade["offers"]
		if offers[0]["items"].is_empty() and offers[1]["items"].is_empty() and offers[0]["credits"] == 0 and offers[1]["credits"] == 0:
			publish(id, "Add an item or credits before confirming.")
			return
		trade["confirmed"][index] = true
		if trade["confirmed"][0] and trade["confirmed"][1]:
			var peers: Array = trade["peers"]
			var result := session.store.complete_trade(session.pilot_ids[peers[0]], session.pilot_ids[peers[1]], offers, trade["revisions"])
			if session.store.failed:
				session.stop_for_save_failure()
				return
			if result == COMPLETED:
				for peer: int in peers:
					combat.records[peer]["credits"] = session.store.pilots[session.pilot_ids[peer]]["credits"]
					combat.publish_inventory(peer, result)
					combat.message(peer, result, "purchase")
			cancel(id, result)
			return
	else:
		publish(id, "Unknown trade action.")
		return
	trade["expires"] = Time.get_ticks_msec() + TIMEOUT_MS
	publish_both(trade)
