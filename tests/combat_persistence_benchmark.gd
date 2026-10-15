extends "res://tests/network_test.gd"
## Optional isolated timing workload. No timing thresholds in the correctness suite.


func timings(samples: Array[float]) -> Dictionary:
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	return {"mean_ms": total / samples.size(), "median_ms": samples[samples.size() / 2], "p95_ms": samples[ceili(samples.size() * 0.95) - 1], "max_ms": samples[-1]}


func run() -> void:
	var server := make_sector("CombatBenchmark", true)
	var store := server.session.store
	for count in [0, 999]:
		if count > 0:
			check(store.commit({"pilot0": 100_000_000}), "Fund isolated inventory fixture")
			check(store.transact("pilot0", 1, "buy", "laser:999", "", "").begins_with("Purchased"), "Add stored items to isolated fixture")
		for journaled in [false, true]:
			var samples: Array[float] = []
			var batch_samples: Array[float] = []
			for tick in range(30):
				var batch_started := Time.get_ticks_usec()
				if journaled: store.begin_combat_tick()
				for index in range(10):
					var id := "pilot%d" % index
					var ammo: Dictionary = store.pilots[id]["ammo"].duplicate()
					ammo["x1"] -= 1
					var boosts: Dictionary = store.pilots[id]["boosts"].duplicate(true)
					var started := Time.get_ticks_usec()
					var committed := store.commit_combat({id: ammo}, {id: boosts}) if journaled else store.commit({}, {}, {}, {id: ammo}, {id: boosts})
					check(committed, "Benchmark debit commits")
					samples.append((Time.get_ticks_usec() - started) / 1000.0)
				if journaled: store.end_combat_tick()
				batch_samples.append((Time.get_ticks_usec() - batch_started) / 1000.0)
			print("COMBAT_PERSISTENCE_BENCHMARK=", JSON.stringify({"mode": "journal" if journaled else "snapshot", "pilots": 10, "extra_items": count, "snapshot_bytes": store.saved_text.to_utf8_buffer().size(), "journal_bytes": store.journal_bytes, "debit": timings(samples), "ten_simultaneous_volleys": timings(batch_samples)}))
			check(store.persist(store.pilots), "Checkpoint isolated benchmark")
	# Journal growth: a debit should cost the same with a fresh or a ~500 KB journal.
	for target in [0, 500_000]:
		check(store.persist(store.pilots), "Compact journal before growth fixture")
		var ammo: Dictionary = store.pilots["pilot0"]["ammo"].duplicate()
		while store.journal_bytes < target:
			ammo["x1"] -= 1
			check(store.commit_combat({"pilot0": ammo}), "Grow journal fixture")
		var start_bytes := store.journal_bytes
		var checks: Array[float] = []
		for sample in range(300):
			var started := Time.get_ticks_usec()
			check(store.unchanged_files(), "Integrity check passes")
			checks.append((Time.get_ticks_usec() - started) / 1000.0)
		print("COMBAT_JOURNAL_GROWTH_BENCHMARK=", JSON.stringify({"journal_bytes_start": start_bytes, "integrity_check": timings(checks)}))
		for batched in [false, true]:
			var samples: Array[float] = []
			for tick in range(30):
				if batched: store.begin_combat_tick()
				for index in range(10):
					var id := "pilot%d" % index
					var next: Dictionary = store.pilots[id]["ammo"].duplicate()
					next["x1"] -= 1
					var started := Time.get_ticks_usec()
					check(store.commit_combat({id: next}, {id: store.pilots[id]["boosts"].duplicate(true)}), "Growth debit commits")
					samples.append((Time.get_ticks_usec() - started) / 1000.0)
				if batched: store.end_combat_tick()
			print("COMBAT_JOURNAL_GROWTH_BENCHMARK=", JSON.stringify({"journal_bytes_start": start_bytes, "journal_bytes_end": store.journal_bytes, "verify": "first call per tick" if batched else "every call", "debit": timings(samples)}))
	server.session.disconnect_session("Benchmark complete")
	for viewport in worlds: viewport.queue_free()
	await process_frame
	quit(int(failures > 0))
