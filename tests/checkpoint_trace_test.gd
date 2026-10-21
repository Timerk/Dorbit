extends SceneTree
## Exercise real replacement I/O with and without the optional observer.

var failures := 0


func _initialize() -> void:
	var directory := ProjectSettings.globalize_path("user://checkpoint-trace-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	for traced in [false, true]:
		var store = preload("res://tests/benchmark_store.gd").new()
		store.measuring = true
		if not traced: store.replacement_trace = Callable()
		var path := directory.path_join("traced" if traced else "plain")
		verify(store.replace_file(path, "old"), "Initial write succeeds")
		verify(store.replace_file(path, "new"), "Replacement succeeds")
		verify(FileAccess.get_file_as_string(path) == "new", "Replacement is readable")
		if traced:
			verify(store.events.size() == 2, "One substep event per replacement")
			var event: Dictionary = store.events[-1]
			verify(event["succeeded"] and event["stages_us"].keys() == ["open", "encode", "write", "flush", "readback", "close", "rename"], "All ordered substeps recorded")
			var total := 0.0
			for value: float in event["stages_us"].values():
				verify(value >= 0.0, "Substep duration is nonnegative")
				total += value
			verify(total == event["duration_us"], "Substeps cover measured replacement")
		else:
			verify(store.events.is_empty(), "Disabled observer records no substeps")
		# A directory at the destination forces rename failure after verified I/O.
		var blocked := path + "-directory"
		DirAccess.make_dir_absolute(blocked)
		verify(not store.replace_file(blocked, "evidence") and store.failed, "Rename failure fails closed")
		verify(FileAccess.get_file_as_string(blocked + ".tmp") == "evidence" and DirAccess.dir_exists_absolute(blocked), "Rename failure preserves original and temporary evidence")
		if traced: verify(not store.events[-1]["succeeded"], "Trace records failed rename")
		verify(not store.replace_file(blocked, "overwrite"), "Leftover temporary blocks retry")
		verify(FileAccess.get_file_as_string(blocked + ".tmp") == "evidence", "Retry preserves evidence")
		DirAccess.remove_absolute(blocked + ".tmp")
		DirAccess.remove_absolute(blocked)
		DirAccess.remove_absolute(path)
	# Exercise the adapter's full commit override, including the current research
	# argument, and compare its committed in-memory state with a reopened ledger.
	var ledger := directory.path_join("ledger")
	DirAccess.make_dir_absolute(ledger)
	var file := FileAccess.open(ledger.path_join("pilots.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "pilots": {"pilot0": {"credits": 0, "verifier": "token".sha256_text()}}}))
	file.close()
	var adapter = preload("res://tests/benchmark_store.gd").new()
	verify(adapter.open(ledger), "Adapter opens disposable ledger")
	adapter.measuring = true
	verify(adapter.commit({"pilot0": 123}, {}, {}, {}, {}, {"pilot0": 7}), "Adapter forwards complete commit signature")
	var committed: Dictionary = adapter.pilots.duplicate(true)
	verify(committed["pilot0"]["equipment"]["research"]["points"] == 7, "Research argument is applied")
	verify(adapter.counts.get("checkpoint_economy", 0) == 1, "Full commit is timed")
	verify(adapter.close(), "Adapter closes cleanly")
	var reopened := PilotStore.new()
	verify(reopened.open(ledger), "Reopened ledger opens")
	# Reopening catches the lab up to the wall clock; replay that on the expected state.
	Skylab.advance(committed["pilot0"], reopened.pilots["pilot0"]["skylab"]["lastSimulatedAt"])
	verify(reopened.pilots == committed, "Traced commit survives reopen without changing state")
	verify(reopened.close(), "Reopened ledger closes")
	for name in DirAccess.get_files_at(ledger): DirAccess.remove_absolute(ledger.path_join(name))
	DirAccess.remove_absolute(ledger)
	DirAccess.remove_absolute(directory)
	print("CHECKPOINT_TRACE_TEST failures=", failures)
	quit(int(failures > 0))


func verify(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
