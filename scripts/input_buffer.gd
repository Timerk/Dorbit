class_name InputBuffer
extends RefCounted
## Server-side flight inputs of one pilot, consumed one per server tick.
##
## Inputs arrive redundantly and possibly out of order. `receive()` keeps each
## sequence number once; `consume()`, called exactly once per server tick,
## applies the oldest buffered input in sequence order.
##
## Starvation: when no input is buffered, the tick reuses the last applied
## input without advancing the sequence, so a ship keeps its course through a
## late packet. Each starved tick delays the inputs behind it by one tick, so
## the buffer grows by itself to cover the jitter it sees. After
## TIMEOUT_TICKS starved ticks the pilot is treated as idle (no thrust, no
## boost, facing held), and its ship brakes.
##
## Catch-up: latency stays bounded. If the smallest depth seen after consuming
## over CATCH_UP_WINDOW ticks exceeds SPARE_DEPTH, the oldest surplus inputs
## are dropped. Depth beyond MAX_DEPTH is dropped at once. Dropped inputs are
## counted separately from inputs that never arrived.
##
## Counters (cumulative for the connection): applied, duplicates (already
## buffered or applied), late (arrived after their tick was skipped), lost
## (sequence gaps skipped: never applied), dropped (discarded by catch-up or
## overflow) and starved (ticks without a new input, until the timeout).

## Ticks without new input before the ship is treated as idle (0.5 s).
const TIMEOUT_TICKS := 30
## Ticks over which the minimum depth is observed before catching up (2 s).
const CATCH_UP_WINDOW := 120
## Spare buffered inputs kept for jitter; more for a whole window is surplus.
const SPARE_DEPTH := 2
## Hard bound on buffered inputs (200 ms of extra input latency).
const MAX_DEPTH := 12
## Remembered skipped sequences, for classifying late arrivals.
const MISSED_MEMORY := 256

var pending: Dictionary[int, Dictionary] = {}
## Last applied or skipped sequence, or -1 before the first input.
var last_seq: int = -1
## Last applied input, reused while starved.
var last_input: Dictionary = {}
## Consecutive ticks without a new input.
var starved_ticks: int = 0
var applied: int = 0
var duplicates: int = 0
var late: int = 0
var lost: int = 0
var dropped: int = 0
var starved: int = 0
var received: int = 0
var _resync: bool = true
var _missed: Dictionary[int, bool] = {}
var _window_min: int = 1 << 30
var _window_ticks: int = 0


func depth() -> int:
	return pending.size()


func receive(seq: int, input: Dictionary) -> void:
	received += 1
	if seq <= last_seq:
		if _missed.erase(seq):
			late += 1
		else:
			duplicates += 1
		return
	if pending.has(seq):
		duplicates += 1
		return
	pending[seq] = input
	if pending.size() > MAX_DEPTH * 2:
		# A flood cannot grow the buffer; the oldest inputs give way.
		drop_oldest(pending.size() - MAX_DEPTH * 2)


## Returns the input for this tick: the next buffered input, the last one
## while starved, or {} once idle (no input yet, or past the timeout).
func consume() -> Dictionary:
	if pending.is_empty():
		_window_min = 0
		_window_ticks += 1
		if last_input.is_empty() or starved_ticks >= TIMEOUT_TICKS:
			return {}
		starved_ticks += 1
		starved += 1
		return last_input
	var seq: int = pending.keys().min()
	advance_to(seq)
	last_input = pending[seq]
	pending.erase(seq)
	applied += 1
	starved_ticks = 0
	if pending.size() > MAX_DEPTH:
		drop_oldest(pending.size() - MAX_DEPTH)
	_window_min = mini(_window_min, pending.size())
	_window_ticks += 1
	if _window_ticks >= CATCH_UP_WINDOW:
		if _window_min > SPARE_DEPTH:
			drop_oldest(_window_min - SPARE_DEPTH)
		_window_ticks = 0
		_window_min = 1 << 30
	if _missed.size() > MISSED_MEMORY:
		for old: int in _missed.keys():
			if old < last_seq - MISSED_MEMORY:
				_missed.erase(old)
	return last_input


func drop_oldest(count: int) -> void:
	var order := pending.keys()
	order.sort()
	for index in mini(count, order.size()):
		advance_to(order[index])
		pending.erase(order[index])
		dropped += 1


## Moves past `seq`, counting any sequences skipped on the way as lost.
func advance_to(seq: int) -> void:
	if not _resync and seq > last_seq + 1:
		lost += seq - last_seq - 1
		for skipped in range(maxi(last_seq + 1, seq - MISSED_MEMORY), seq):
			_missed[skipped] = true
	_resync = false
	last_seq = maxi(last_seq, seq)


## Discards buffered inputs when a life ends (dock, jump, death or relaunch).
## Counters persist; the next accepted input starts a new run without
## counting the gap before it as lost.
func reset() -> void:
	pending.clear()
	last_input = {}
	starved_ticks = 0
	_resync = true
	_window_min = 1 << 30
	_window_ticks = 0


func counters() -> Dictionary:
	return {"applied": applied, "duplicates": duplicates, "late": late, "lost": lost,
		"dropped": dropped, "starved": starved, "received": received}
