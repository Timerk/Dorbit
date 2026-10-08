extends SceneTree

var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)


func pilot(at: int = 0) -> Dictionary:
	return {"equipment": Equipment.starter(), "cargo": {"starter": {}}, "credits": 1000000, "premium": false, "skylab": Skylab.bootstrap(at)}


func isolated() -> Dictionary:
	var value := pilot()
	for id: String in Skylab.MODULES:
		if id != "basic" and id != "solar": value["skylab"]["modules"][id]["enabled"] = false
	for resource: String in Skylab.RESOURCES: value["skylab"]["inventory"][resource] = 0
	return value


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	check(Skylab.valid(pilot()["skylab"], Equipment.starter()), "Bootstrap is valid and cannot softlock")
	for id: String in Skylab.MODULES:
		check(Skylab.data()["modules"][id].size() == (1 if id == "transport" else 20), "%s has explicit level data" % id)
	var value := isolated()
	value["skylab"]["modules"]["prometiumCollector"]["enabled"] = true
	Skylab.advance(value, 3600)
	check(value["skylab"]["inventory"]["prometium"] == 1800, "Collector earns the configured hourly output")
	Skylab.advance(value, 100000000)
	check(value["skylab"]["inventory"]["prometium"] == 10000, "Long absence stops at the separate capacity")
	var started := Time.get_ticks_msec()
	Skylab.advance(value, 1000000000)
	check(Time.get_ticks_msec() - started < 500, "Full idle storage fast-forwards decades without per-second loops")
	value["skylab"]["inventory"]["prometium"] -= 60
	Skylab.advance(value, 1000000120)
	check(value["skylab"]["inventory"]["prometium"] == 10000, "A full collector recovers when storage space is freed")
	for id: String in Skylab.RECIPES:
		value = isolated()
		value["skylab"]["modules"][id]["enabled"] = true
		value["skylab"]["carry"][id] = 1.0
		for resource: String in Skylab.RECIPES[id]: value["skylab"]["inventory"][resource] = Skylab.RECIPES[id][resource]
		if id == "promeriumRefinery": value["skylab"]["inventory"]["xenomit"] = 1
		Skylab.settle_tick(value["skylab"])
		check(value["skylab"]["inventory"][Skylab.OUTPUT[id]] == 1, "%s produces one exact recipe" % id)
		for resource: String in Skylab.RECIPES[id]: check(value["skylab"]["inventory"][resource] == 0, "%s conserves %s" % [id, resource])
		if id == "promeriumRefinery": check(value["skylab"]["inventory"]["xenomit"] == 0, "Real catalyst is consumed when virtual supply is absent")
		value["skylab"]["carry"][id] = 100.0
		Skylab.settle_tick(value["skylab"])
		check(value["skylab"]["inventory"][Skylab.OUTPUT[id]] == 1 and value["skylab"]["carry"][id] == 0, "%s discards blocked work without a catch-up burst" % id)
	value = isolated()
	value["skylab"]["inventory"]["prometid"] = 500
	value["skylab"]["inventory"]["prometium"] = 20
	value["skylab"]["inventory"]["endurium"] = 10
	value["skylab"]["carry"]["prometidRefinery"] = 1.0
	Skylab.settle_tick(value["skylab"])
	check(value["skylab"]["inventory"]["prometium"] == 20 and value["skylab"]["inventory"]["endurium"] == 10, "Full output does not destroy recipe ingredients")
	value = isolated()
	for turn in range(2):
		value["skylab"]["inventory"]["prometium"] = 100
		value["skylab"]["inventory"]["endurium"] = 10
		value["skylab"]["inventory"]["terbium"] = 100
		value["skylab"]["carry"]["prometidRefinery"] = 1.0
		value["skylab"]["carry"]["duraniumRefinery"] = 1.0
		Skylab.settle_tick(value["skylab"])
	check(value["skylab"]["inventory"]["prometid"] == 1 and value["skylab"]["inventory"]["duranium"] == 1, "Shared Endurium proportional ties alternate rather than starve one refinery")
	value = isolated()
	value["skylab"]["inventory"]["prometium"] = 2000
	value["skylab"]["inventory"]["terbium"] = 2000
	value["skylab"]["modules"]["prometidRefinery"]["enabled"] = true
	value["skylab"]["modules"]["duraniumRefinery"]["enabled"] = true
	var saved_rate: float = Skylab.table("duraniumRefinery", 1)["rate_per_hour"]
	Skylab.table("duraniumRefinery", 1)["rate_per_hour"] = 30.0
	for minute in range(1, 61):
		value["skylab"]["inventory"]["endurium"] += 10
		Skylab.advance(value, minute * 60)
	Skylab.table("duraniumRefinery", 1)["rate_per_hour"] = saved_rate
	check(value["skylab"]["inventory"]["duranium"] > 0 and value["skylab"]["inventory"]["prometid"] > 0, "Faster shared-input consumers cannot erase slower fractional progress and starve them")
	value = isolated()
	value["skylab"]["inventory"]["prometid"] = 10
	value["skylab"]["inventory"]["duranium"] = 10
	value["skylab"]["inventory"]["xenomit"] = 5
	value["skylab"]["carry"]["promeriumRefinery"] = 1.0
	value["skylab"]["carry"]["xeno"] = 1.0
	Skylab.settle_tick(value["skylab"])
	check(value["skylab"]["inventory"]["xenomit"] == 5 and value["skylab"]["inventory"]["promerium"] == 1, "Virtual catalyst takes priority without creating Xenomit")
	for low_xeno: bool in [true, false]:
		value = isolated()
		value["skylab"]["modules"]["promeriumRefinery"]["enabled"] = true
		value["skylab"]["modules"]["xeno"]["enabled"] = true
		value["skylab"]["modules"]["promeriumRefinery"]["level"] = 2 if low_xeno else 1
		value["skylab"]["modules"]["xeno"]["level"] = 1 if low_xeno else 2
		value["skylab"]["inventory"]["prometid"] = 200
		value["skylab"]["inventory"]["duranium"] = 200
		Skylab.advance(value, 3600)
		check(value["skylab"]["inventory"]["promerium"] == 6 and value["skylab"]["inventory"]["xenomit"] == 0, "Unequal Xeno/Promerium levels use all slower throughput without inventing stored ore (low=%s, count=%s, carry=%s)" % [low_xeno, value["skylab"]["inventory"]["promerium"], value["skylab"]["carry"]])
	value = pilot()
	check(Skylab.command(value, 1, "enable", {"module": "basic", "enabled": false}, 0).contains("cannot"), "Basic off is rejected")
	check(Skylab.command(value, 1, "upgrade", {"module": "transport"}, 0).contains("level 1"), "Transport upgrade is rejected")
	check(Skylab.command(value, 1, "upgrade", {"module": "solar"}, 0).contains("Basic"), "Upgrade cannot exceed completed Basic")
	check(Skylab.command(value, 1, "upgrade", {"module": "basic"}, 0) == "Upgrade started.", "Basic may upgrade itself")
	var credits: int = value["credits"]
	var ore: Dictionary = value["skylab"]["inventory"].duplicate()
	check(Skylab.command(value, 2, "cancel", {"module": "basic"}, 0).contains("forfeited"), "Cancel explains the cost consequence")
	check(value["credits"] == credits and value["skylab"]["inventory"] == ore and value["skylab"]["modules"]["basic"]["level"] == 1, "Cancellation retains the old level and refunds nothing")
	var missing := pilot()
	missing["skylab"]["inventory"]["prometium"] = 0
	var unpaid := missing.duplicate(true)
	Skylab.command(missing, 1, "build_instant", {"module": "basic"}, 0)
	check(missing == unpaid, "Instant currency cannot replace missing ordinary build ingredients")
	missing = pilot()
	Skylab.command(missing, 1, "upgrade", {"module": "basic"}, 0)
	Skylab.advance(missing, 60)
	var instant_before: int = missing["credits"]
	Skylab.command(missing, 2, "finish_upgrade", {"module": "basic"}, 60)
	check(missing["skylab"]["modules"]["basic"]["level"] == 2 and missing["credits"] == instant_before - 250, "Half-finished construction charges half the normal build price once")
	Skylab.command(value, 3, "build_instant", {"module": "basic"}, 0)
	Skylab.command(value, 4, "upgrade", {"module": "prometiumCollector"}, 0)
	Skylab.command(value, 5, "upgrade", {"module": "solar"}, 0)
	check(value["skylab"]["modules"]["solar"]["upgrade"] != null and value["skylab"]["modules"]["prometiumCollector"]["upgrade"] != null, "Independent module upgrades run concurrently")
	check(Skylab.rates(value["skylab"])["prometiumCollector"] == 0 and Skylab.power(value["skylab"])["capacity"] == 160, "Collector pauses; upgrading Solar retains completed service")
	Skylab.command(value, 6, "enable", {"module": "prometiumCollector", "enabled": false}, 0)
	Skylab.advance(value, 120)
	check(value["skylab"]["modules"]["prometiumCollector"]["level"] == 2 and not value["skylab"]["modules"]["prometiumCollector"]["enabled"], "Disabling does not stop construction or reset player preference")
	value = isolated()
	value["skylab"]["modules"]["solar"]["enabled"] = false
	check(not Skylab.power(value["skylab"])["admitted"]["basic"], "Power shortages use deterministic admission and recoverable flags")
	value = pilot()
	Skylab.command(value, 1, "robots", {"module": "prometiumCollector", "kind": "credit", "amount": 24}, 0)
	Skylab.command(value, 2, "robots", {"module": "prometiumCollector", "kind": "advanced", "amount": 12}, 0)
	check(is_equal_approx(Skylab.robot_bonus(value["skylab"], "prometiumCollector"), 1.12), "Credit robots stack additively to 12 percent")
	Skylab.command(value, 3, "enable", {"module": "prometiumCollector", "enabled": false}, 0)
	Skylab.advance(value, 172800)
	check(is_equal_approx(Skylab.robot_bonus(value["skylab"], "prometiumCollector"), 1.48), "Robots expire while disabled and refill advanced-first")
	check(value["skylab"]["robots"]["prometiumCollector"]["credit"] == 12 and value["skylab"]["robots"]["prometiumCollector"]["active"][0]["startedAt"] == 172800, "Queued robots do not age before actual activation")
	var whole := pilot(17)
	Skylab.command(whole, 1, "robots", {"module": "enduriumCollector", "kind": "credit", "amount": 36}, 17)
	Skylab.command(whole, 2, "upgrade", {"module": "basic"}, 17)
	Skylab.command(whole, 3, "ship", {"manifest": {"prometium": 100}}, 17)
	var split := whole.duplicate(true)
	Skylab.advance(whole, 400000)
	for at in range(23, 400000, 137): Skylab.advance(split, at)
	Skylab.advance(split, 400000)
	check(whole["skylab"]["inventory"] == split["skylab"]["inventory"] and whole["cargo"] == split["cargo"], "Multi-day offline advancement matches many snapshots across all events")
	check(whole["skylab"]["robots"] == split["skylab"]["robots"] and whole["skylab"]["modules"] == split["skylab"]["modules"], "Robot activation times and upgrade completion are offline-equivalent")
	for id: String in Skylab.MODULES: check(absf(whole["skylab"]["carry"][id] - split["skylab"]["carry"][id]) < .00001, "Persisted fractional %s work is stable across reads" % id)
	var saved := whole.duplicate(true)
	Skylab.advance(whole, 400000)
	Skylab.advance(whole, 399000)
	check(whole == saved, "Repeated reads and backwards clocks cannot duplicate work or delivery")
	value = pilot()
	var stock: int = value["skylab"]["inventory"]["prometium"]
	for manifest: Dictionary in [{"unknown": 1}, {"prometium": -1}, {"prometium": 1.5}, {"prometium": INF}, {"prometium": 2000000001}, {"prometium": 401}]:
		var before := value.duplicate(true)
		Skylab.command(value, 1, "ship", {"manifest": manifest}, 0)
		check(value == before, "Reject malformed or over-capacity shipment %s" % str(manifest))
	Skylab.command(value, 1, "ship", {"manifest": {"prometium": 100}}, 0)
	check(value["skylab"]["inventory"]["prometium"] == stock - 100, "Dispatch removes its manifest immediately")
	check(Skylab.command(value, 2, "ship", {"manifest": {"prometium": 1}}, 0).contains("already"), "Only one shipment is admitted")
	value["cargo"]["starter"] = {"endurium": 400}
	Skylab.advance(value, 200)
	check(value["cargo"]["starter"] == {"endurium": 400, "prometium": 100} and CargoResources.valid(value["cargo"], value["equipment"]), "Delivery preserves ore in an overfull persistent hold")
	var contents := {"xenomit": 1}
	check(CargoResources.collect(value["cargo"]["starter"], contents, 400).is_empty() and contents == {"xenomit": 1}, "Overfull cargo blocks collection without destroying loot")
	var normal := pilot()
	var premium := pilot()
	premium["premium"] = true
	Skylab.command(normal, 1, "ship", {"manifest": {"prometium": 100}}, 0)
	Skylab.command(premium, 1, "ship", {"manifest": {"prometium": 100}}, 0)
	check(premium["skylab"]["shipment"]["arrivesAt"] * 2 == normal["skylab"]["shipment"]["arrivesAt"], "Premium halves transport duration")
	instant_before = normal["credits"]
	Skylab.command(normal, 2, "finish_shipment", {}, 0)
	Skylab.command(normal, 3, "finish_shipment", {}, 0)
	check(normal["cargo"]["starter"] == {"prometium": 100} and normal["credits"] == instant_before - 125000 and normal["skylab"]["shipment"] == null, "Instant shipment delivers its existing manifest once and charges no empty retry")
	for amount: int in [1, 400]:
		var immediate := pilot()
		var before_credits: int = immediate["credits"]
		var before_stock: int = immediate["skylab"]["inventory"]["prometium"]
		check(Skylab.command(immediate, 1, "ship_instant", {"manifest": {"prometium": amount}}, 0) == "Shipment delivered instantly.", "Direct instant dispatch succeeds at %d cargo units" % amount)
		check(immediate["credits"] == before_credits - 125000 and immediate["cargo"]["starter"]["prometium"] == amount and immediate["skylab"]["inventory"]["prometium"] == before_stock - amount and immediate["skylab"]["shipment"] == null, "Instant dispatch charges the same flat fee, conserving its manifest")
	var unaffordable := pilot()
	unaffordable["credits"] = 124999
	var unchanged := unaffordable.duplicate(true)
	Skylab.command(unaffordable, 1, "ship_instant", {"manifest": {"prometium": 10}}, 0)
	check(unaffordable == unchanged, "Unaffordable instant dispatch removes neither credits nor ore")
	for manifest: Dictionary in [{}, {"prometium": 401}, {"prometium": 1.5}, {"unknown": 1}]:
		var immediate := pilot()
		unchanged = immediate.duplicate(true)
		Skylab.command(immediate, 1, "ship_instant", {"manifest": manifest}, 0)
		check(immediate == unchanged, "Instant send uses ordinary manifest and cargo validation")
	var robot_purchase := pilot()
	robot_purchase["credits"] = 5000
	Skylab.command(robot_purchase, 1, "robots", {"module": "prometiumCollector", "kind": "advanced", "amount": 1}, 0)
	check(robot_purchase["credits"] == 0 and is_equal_approx(Skylab.robot_bonus(robot_purchase["skylab"], "prometiumCollector"), 1.04), "Advanced robot costs 5000 credits and supplies four percent")
	var total_cost := pilot()
	total_cost["credits"] = 999
	unchanged = total_cost.duplicate(true)
	Skylab.command(total_cost, 1, "build_instant", {"module": "basic"}, 0)
	check(total_cost == unchanged, "Instant build validates combined ordinary and acceleration credits atomically")
	total_cost["credits"] = 1000
	Skylab.command(total_cost, 1, "build_instant", {"module": "basic"}, 0)
	check(total_cost["credits"] == 0 and total_cost["skylab"]["modules"]["basic"]["level"] == 2, "Instant build charges exactly twice the normal credit price")
	value = pilot()
	value["skylab"] = Skylab.screenshot_fixture(0)
	var fixture := Skylab.snapshot(value, 0)
	check(fixture["power"]["demand"] == 454 and fixture["power"]["capacity"] == 870, "Screenshot fixture reproduces the documented energy arithmetic")
	for id: String in Skylab.RECIPES: check(fixture["modules"][id]["productivity"] == 0, "Screenshot %s shows a separate zero-percent productivity indicator" % id)
	check(Skylab.screenshot_snapshot(0)["capacities"]["prometium"] == 4018569 and Skylab.screenshot_snapshot(0)["capacities"]["seprom"] == 1827, "Screenshot capacities remain a separate reference fixture")
	var invalid := pilot()["skylab"] as Dictionary
	invalid["carry"]["basic"] = NAN
	check(not Skylab.valid(invalid, Equipment.starter()), "Corrupt nonfinite progress fails closed")
	print("Skylab: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
