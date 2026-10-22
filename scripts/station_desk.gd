class_name StationDesk
extends RefCounted
## Server-side station and Skylab requests for one SessionCombat. The RPC entry
## points stay on SessionCombat: their signatures are part of the protocol fingerprint.

# The owning SessionCombat. Typed as Node because the RPC compatibility test
# recompiles SessionCombat's source without its class_name.
var combat: Node


func _init(owner: Node) -> void:
	combat = owner


# The caller has checked that `id` is an authenticated pilot with a combat record.
func station_request(id: int, sequence: int, action: String, subject: String, ship: String, slot: String, life: int) -> void:
	var session: FlightSession = combat.session
	var records: Dictionary[int, Dictionary] = combat.records
	var active_ship: Pilot = session.ships[id]
	var blocker := ("" if active_ship.alive else "Wait for rescue.") if action == "refine" else session.sector.repair_blocker(active_ship)
	var pilot_id := session.pilot_ids[id]
	var fitting: Dictionary = session.store.pilots[pilot_id]["equipment"]
	var item: Dictionary = fitting["items"].get(subject, {})
	# Fitted automation settings are available in flight; fitting and purchases
	# still use station rules. Ownership, life and settings remain authoritative.
	if (action == "configure_extra" and session.ships[id].alive and not item.is_empty()
			and item.get("ship", "") == fitting["active_ship"]
			and Equipment.MODELS[item["model"]].get("family", "") in ["repair-auto", "ammo", "generators"]):
		blocker = ""
	if records[id]["life"] != life:
		blocker = "Ship changed. Review your fitting after rescue."
	if blocker.is_empty() and action in ["gate_assemble", "gate_preview"]:
		blocker = combat.gate.open_blocker()
	if blocker.is_empty() and action == "gate_preview" and not session.can_grant_test_credits(id):
		blocker = "Preview gates are unavailable for this pilot on this server."
	if not blocker.is_empty():
		publish_inventory(id, blocker)
		return
	# Preview gates open without parts or a saved transaction.
	if action == "gate_preview":
		combat.gate.start("a preview pilot")
		publish_inventory(id, "Preview: %s opened near Outpost 01." % GalaxyGates.NAME)
		return
	var previous_revision: int = session.store.pilots[pilot_id]["equipment"]["revision"]
	var previous_ship: String = session.store.pilots[pilot_id]["equipment"]["active_ship"]
	var result := session.store.transact(pilot_id, sequence, action, subject, ship, slot,
		session.can_grant_test_credits(id), session.ships[id].resource_boosts)
	if session.store.failed:
		session.stop_for_save_failure()
		return
	var pilot: Dictionary = session.store.pilots[pilot_id]
	records[id]["credits"] = pilot["credits"]
	session.ships[id].ammo = pilot["ammo"].duplicate()
	combat.cargo_holds[id] = pilot["cargo"].duplicate(true)
	if pilot["equipment"]["revision"] > previous_revision:
		if action == "configure_extra":
			var remote: Pilot = session.ships[id]
			remote.repair_auto = Extras.enabled(Equipment.extra(pilot["equipment"], "repair-auto"))
			if not remote.repair_auto and not remote.repair_requested:
				remote.robot_repairing = false
		else:
			combat.apply_equipment(id)
	if previous_ship != pilot["equipment"]["active_ship"]:
		session.ships[id].rockets.unload()
		# Switching is not a repair. Keep absolute hull/shield charge (clamped by
		# the new fitting), boost energy, cooldowns and damage timer.
		records[id]["life"] += 1
		session.ships[id].set_meta("life", records[id]["life"])
		session.commands.erase(id)
		session.ships[id].velocity = Vector3.ZERO
	publish_inventory(id, result)
	if action == "gate_assemble" and pilot["equipment"]["revision"] > previous_revision:
		combat.gate.start("Pilot %d" % id)
	if action in ["buy", "buy_ship", "buy_ammo", "sell", "refine", "boost", "replace_boost", "research", "research_reset"] and pilot["equipment"]["revision"] > previous_revision:
		combat.message(id, result, "purchase")


func publish_inventory(id: int, result: String = "") -> void:
	var session: FlightSession = combat.session
	if session.sector.dedicated_server:
		var pilot: Dictionary = session.store.pilots[session.pilot_ids[id]]
		var lab := Skylab.snapshot(pilot, int(pilot["skylab"]["lastSimulatedAt"]))
		combat.station_result.rpc_id(id, pilot["equipment"], result, session.can_grant_test_credits(id), pilot["cargo"],
			pilot["credits"], pilot["ammo"], session.snapshot_sequence, session.ships[id].resource_boosts, lab)


# The caller has checked that `id` is an authenticated pilot with a combat record.
func skylab_request(id: int, sequence: int, action: String, payload: Dictionary) -> void:
	var session: FlightSession = combat.session
	# Bound the RPC without trusting a client-selected account, recipient, clock or currency.
	if payload.size() > 4 or JSON.stringify(payload).length() > 4096:
		publish_inventory(id, "Invalid Skylab request.")
		return
	var result := session.store.transact_lab(session.pilot_ids[id], sequence, action, payload, Skylab.now(), session.can_grant_test_credits(id))
	if session.store.failed:
		session.stop_for_save_failure()
		return
	sync_lab_accounts()
	publish_inventory(id, result)


func sync_lab_accounts() -> void:
	var session: FlightSession = combat.session
	for id: int in combat.records:
		var pilot: Dictionary = session.store.pilots[session.pilot_ids[id]]
		combat.records[id]["credits"] = pilot["credits"]
		combat.cargo_holds[id] = pilot["cargo"].duplicate(true)


func advance_labs() -> void:
	var session: FlightSession = combat.session
	var at := Skylab.now()
	if at < session.store.next_lab_due:
		return
	if not session.store.advance_labs(at):
		session.stop_for_save_failure()
		return
	sync_lab_accounts()
	for id: int in combat.records:
		publish_inventory(id)
