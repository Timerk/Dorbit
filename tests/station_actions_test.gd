extends SceneTree
## Station action rules on a copied pilot record, and the store's handling of their blockers.

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func make_pilot() -> Dictionary:
	var equipment := Equipment.starter()
	equipment["items"]["expander"] = {"model": "cargo-expander", "ship": "starter", "slot": "extra1"}
	return {"verifier": "0".repeat(64), "credits": 5_000_000, "contracts": {}, "equipment": equipment,
		"cargo": {"starter": {}}, "ammo": Ammunition.starter(), "boosts": ResourceBoosts.empty_holds(equipment),
		"skylab": Skylab.bootstrap(Skylab.now() + 3600), "premium": false}


func run_rules() -> void:
	var saved := make_pilot()
	var capacity := CargoResources.capacity(saved["equipment"])
	# A delivery may overfill a hold beyond the expanded capacity.
	saved["cargo"]["starter"] = {"prometium": capacity + 1}
	var untouched := saved.duplicate(true)
	var pilot := saved.duplicate(true)
	check(StationActions.apply(pilot, saved, 1, "fit", "starter-laser", "", "").is_empty(), "Fitting that keeps capacity ignores an overfilled hold")
	check(StationActions.result(pilot, "fit", "starter-laser", 5_000_000, 0) == "Fitting saved.", "Fit reports the saved fitting")
	check(saved == untouched, "Rules leave the saved record unchanged")
	pilot = saved.duplicate(true)
	check(StationActions.apply(pilot, saved, 1, "fit", "expander", "", "") == "Sell excess cargo before removing cargo capacity. No items were moved.", "Removing capacity from an overfilled hold is blocked")
	pilot = saved.duplicate(true)
	check(StationActions.apply(pilot, saved, 1, "buy", "laser:3", "", "").is_empty() and pilot["equipment"]["items"].has("purchase-1-3"), "Batch purchases use sequence-derived item IDs")
	check(StationActions.result(pilot, "buy", "laser:3", 5_000_000, 0) == "Purchased 3 items. Items are in storage.", "Batch purchase reports its quantity")
	pilot = saved.duplicate(true)
	pilot["equipment"]["items"]["purchase-1-2"] = {"model": "laser", "ship": "", "slot": ""}
	check(StationActions.apply(pilot, saved, 1, "buy", "laser:2", "", "") == StationActions.ITEM_ID_CONFLICT, "Item ID collisions are reported to the store")
	check(StationActions.apply(saved.duplicate(true), saved, 1, "launch", "", "", "") == "Unknown station action.", "Unknown actions are rejected")


func run_store(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("pilots.json")
	for suffix in ["", ".bak", ".combat"]:
		DirAccess.remove_absolute(path + suffix)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 7, "pilots": {"pilot0": make_pilot()}}))
	file.close()
	var store := PilotStore.new()
	if not store.open(directory):
		check(false, "Station action ledger opens: " + store.error)
		return
	check(store.transact("pilot0", 1, "sell", "all", "", "") == "No resources to sell." and store.pilots["pilot0"]["equipment"]["revision"] == 0, "A blocker keeps the request sequence")
	check(store.transact("pilot0", 1, "buy", "laser", "", "") == "Purchased. Item is in storage." and store.pilots["pilot0"]["credits"] == 5_000_000 - Equipment.MODELS["laser"]["price"], "An accepted action saves and confirms")
	var next := store.pilots.duplicate(true)
	next["pilot0"]["equipment"]["story"] = {"step": 7, "progress": 0}
	next["pilot0"]["cargo"]["starter"] = {"prometium": 5}
	next["pilot0"]["credits"] = PilotStore.MAX_CREDITS
	check(store.persist(next), "Seed a story delivery at the wallet cap")
	check(store.transact("pilot0", 2, "story_deliver", "", "", "") == "Reward exceeds the credit limit. Free wallet space first." and store.pilots == next, "Blocked delivery preserves cargo, story, wallet and sequence")
	next = store.pilots.duplicate(true)
	next["pilot0"]["credits"] = 1000
	check(store.persist(next), "Make wallet space for the delivery reward")
	var delivery := store.transact("pilot0", 2, "story_deliver", "", "", "")
	check(delivery == "Delivered Prometium x5. +2,000 CR." and store.pilots["pilot0"]["cargo"]["starter"].is_empty() and store.pilots["pilot0"]["credits"] == 3000 and Story.state(store.pilots["pilot0"]["equipment"])["step"] == 8, "Delivery saves cargo consumption, progress and reward with its confirmation")
	check(store.transact("pilot0", 2, "story_deliver", "", "", "") == "Request already processed. Inventory refreshed.", "Delivery replay uses the shared transaction sequence")
	var skipped := store.transact("pilot0", 3, "story_skip", "", "", "")
	check(skipped == "Prologue skipped. +7,000 CR and +3 research points." and Story.state(store.pilots["pilot0"]["equipment"]) == {"step": 10, "progress": 0} and store.pilots["pilot0"]["credits"] == 10000, "Skip confirms and saves only the remaining prologue rewards")
	store.pilots["pilot0"]["equipment"]["items"]["purchase-4"] = {"model": "laser", "ship": "", "slot": ""}
	check(store.transact("pilot0", 4, "buy", "laser", "", "") == "Persistence unavailable." and store.failed and store.error == StationActions.ITEM_ID_CONFLICT, "An item ID collision fails the store")
	store.close()


func run() -> void:
	run_rules()
	run_store(OS.get_user_data_dir().path_join("station-actions"))
	print("Station action checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
