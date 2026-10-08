extends "res://tests/network_test.gd"
## Optional isolated timing workload. No timing thresholds in the correctness suite.


func timings(samples: Array[float]) -> Dictionary:
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	return {"mean_ms": total / samples.size(), "p95_ms": samples[ceili(samples.size() * 0.95) - 1], "max_ms": samples[-1]}


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
			print("COMBAT_PERSISTENCE_BENCHMARK=", JSON.stringify({"mode": "journal" if journaled else "snapshot", "pilots": 10, "extra_items": count, "snapshot_bytes": store.saved_text.to_utf8_buffer().size(), "journal_bytes": store.journal_text.to_utf8_buffer().size(), "debit": timings(samples), "ten_simultaneous_volleys": timings(batch_samples)}))
			check(store.persist(store.pilots), "Checkpoint isolated benchmark")
	server.session.disconnect_session("Benchmark complete")
	for viewport in worlds: viewport.queue_free()
	await process_frame
	quit(int(failures > 0))
