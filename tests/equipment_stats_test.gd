extends SceneTree
## Base fitting cache isolation, invalidation and stable partial-volley ordering.

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func run() -> void:
	var data := Equipment.starter()
	data["ships"]["starter"] = "goliath"
	data["ships"]["other"] = "phoenix"
	# Insert out of slot order, with irrelevant storage and an inactive hull.
	data["items"]["late-laser"] = {"model": "lf-3", "ship": "starter", "slot": "laser10"}
	data["items"]["early-laser"] = {"model": "mp-1", "ship": "starter", "slot": "laser2"}
	data["items"]["other-laser"] = {"model": "lf-4", "ship": "other", "slot": "laser1"}
	var expected := Equipment.stats(data)
	for index in range(999):
		data["items"]["stored-%d" % index] = {"model": "lf-4", "ship": "", "slot": ""}
	check(Equipment.valid(data), "Large cache fixture is a valid owned inventory")
	check(Equipment.stats(data) == expected, "999 stored items and inactive fittings contribute no active stats")
	check(expected["lasers"] == [{"damage": 65.0, "npc_damage": 0.0}, {"damage": 70.0, "npc_damage": 0.0}, {"damage": 175.0, "npc_damage": 26.25}], "Filtering preserves natural laser1, laser2, laser10 order")
	var cache := Equipment.StatsCache.new()
	check(cache.get_stats(data) == expected, "Cached base stats preserve every fitting field")
	var base: Dictionary = cache.ships["starter"]
	for frame in range(60):
		cache.get_stats(data)
	check(is_same(base, cache.ships["starter"]), "Unchanged revision reuses the base calculation")
	var editable := cache.get_stats(data)
	editable["shield"] = -1
	editable["lasers"][0]["damage"] = -1
	check(cache.get_stats(data) == expected, "Returned stats and nested lasers cannot corrupt the cache")
	var boosts := {"shields": {"resource": "seprom", "remaining": 1.0}, "engines": {"resource": "duranium", "remaining": 1.0}, "lasers": {"resource": "seprom", "remaining": 2}}
	var boosted := ResourceBoosts.stats(cache.get_stats(data), boosts)
	check(is_equal_approx(boosted["shield"], expected["shield"] * 1.4) and is_equal_approx(boosted["speed"], expected["speed"] * 1.1), "Live shield and engine bonuses apply separately to cached base stats")
	check(is_equal_approx(ResourceBoosts.laser_damage(expected["lasers"], true, boosts), 417.25), "Last partial volley boosts the first two lasers in natural slot order")
	boosts["shields"]["remaining"] = 0
	boosts["engines"]["remaining"] = 0
	check(ResourceBoosts.stats(cache.get_stats(data), boosts) == expected and is_same(base, cache.ships["starter"]), "Boost expiry immediately restores base stats without an inventory revision or recalculation")
	data["items"]["early-laser"]["ship"] = ""
	data["items"]["early-laser"]["slot"] = ""
	data["revision"] += 1
	check(cache.get_stats(data) == Equipment.stats(data) and cache.get_stats(data)["damage"] == 240, "In-place revision change invalidates a removed laser")
	data["items"]["stored-0"]["ship"] = "starter"
	data["items"]["stored-0"]["slot"] = "laser2"
	data["revision"] += 1
	check(cache.get_stats(data)["damage"] == 440, "Newly installed purchased equipment invalidates cached damage")
	data["active_ship"] = "other"
	check(cache.get_stats(data) == Equipment.stats(data, "other") and cache.get_stats(data)["damage"] == 200, "Active ship selection cannot reuse another hull's fitting")
	check(cache.get_stats(data, "starter")["damage"] == 440, "Explicit ship queries retain the matching fitting")
	var replacement := Equipment.starter()
	replacement["revision"] = data["revision"]
	check(cache.get_stats(replacement) == Equipment.stats(replacement) and cache.ships.size() == 1, "Same-revision reconnect or pilot replacement invalidates old inventory stats")
	var proposal := replacement.duplicate(true)
	proposal["items"]["starter-laser"]["ship"] = ""
	proposal["items"]["starter-laser"]["slot"] = ""
	check(Equipment.stats(proposal)["damage"] == 0 and cache.get_stats(replacement)["damage"] == 65, "Same-revision uncommitted proposals remain uncached and leave committed stats intact")
	var started := Time.get_ticks_usec()
	for calculation in range(1000):
		Equipment.stats(data, "starter")
	var uncached := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for calculation in range(1000):
		cache.get_stats(data, "starter")
	print("Fitting timings with 999 stored items: uncached %.3f ms, cached %.3f ms per call" % [uncached / 1000000.0, (Time.get_ticks_usec() - started) / 1000000.0])
	print("Equipment stats checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
