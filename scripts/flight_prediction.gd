class_name FlightPrediction
extends RefCounted
## Client-side prediction and reconciliation of the local pilot.
##
## Each client physics tick samples one input, keeps it until the server
## acknowledges it, and simulates it at once with Pilot.simulate_input(), the
## same step the server runs per consumed input. Each new owner snapshot names
## the last input the server processed: the client drops acknowledged inputs,
## resets the ship's simulation state (position, velocity, energy, facing and
## turn budget) to the authoritative state and replays the rest in the same
## physics tick. The replay never touches the view facing, so mouse steering
## stays immediate.
##
## Corrections are hidden by drawing the model and camera at a world-space
## offset from the simulated ship, which decays exponentially. The simulation
## itself is never smoothed.

## Physics ticks between input packets (30 packets per second).
const SEND_INTERVAL_TICKS := 2
## Unacknowledged inputs kept for replay (two seconds); older ones are dropped.
const MAX_PENDING := 120
## Time constant of the decaying correction offset, in seconds: about 63% of
## a correction is hidden after this long and 95% after three times as long.
## A playtesting setting.
const SMOOTHING_TIME := 0.12
## Corrections larger than this, in metres, snap instead of smoothing.
const SNAP_DISTANCE := 10.0

## Sequence of the next sampled input. Sequences rise for the whole connection.
var next_seq: int = 1
var client_tick: int = 0
## Unacknowledged inputs, oldest first: {seq, tick, movement, boost, facing}.
var pending: Array[Dictionary] = []
## Newest owner state awaiting reconciliation, or {}.
var authoritative: Dictionary = {}
var last_ack: int = 0


## Forgets inputs and the correction offset at a discontinuity (connect,
## spawn, respawn, jump, dock or launch). The next snapshot re-anchors the
## simulation.
func reset(ship: Pilot) -> void:
	pending.clear()
	authoritative = {}
	ship.sim_rotation = ship.rotation
	ship.turn_budget = Pilot.MAX_TURN_RATE * (1.0 / Engine.physics_ticks_per_second + Pilot.TURN_LATENCY_ALLOWANCE)
	ship.set_visual_offset(Vector3.ZERO)


## Samples this tick's input and predicts it.
func predict(ship: Pilot, delta: float, movement: Vector3, boost: bool) -> void:
	ship.apply_look(delta)
	# Predict with exactly the facing the server will decode.
	var facing := FlightInput.quantize_facing(ship.rotation)
	ship.rotation = facing
	var input := {"seq": next_seq, "tick": client_tick, "movement": FlightInput.quantize_movement(movement), "boost": boost, "facing": facing}
	next_seq += 1
	pending.append(input)
	if pending.size() > MAX_PENDING:
		pending.pop_front()
	ship.simulate_input(delta, input["movement"], boost, facing)
	ship.present_motion(delta, input["movement"])


## The newest unacknowledged inputs, ready to send.
func packet(life: int, fire: bool, encounter: int, target: int) -> PackedByteArray:
	var inputs := pending.slice(maxi(0, pending.size() - FlightInput.REDUNDANCY))
	return FlightInput.encode(life, fire, encounter, target, client_tick, inputs)


## Rewinds to the newest authoritative state and replays unacknowledged
## inputs. Call from a physics tick: move_and_slide() uses the physics delta.
func reconcile(ship: Pilot, delta: float, stats: NetStats) -> void:
	if authoritative.is_empty():
		return
	var state := authoritative
	authoritative = {}
	var ack: int = state.get("ack", last_ack)
	var ack_lag := -1
	while not pending.is_empty() and pending[0]["seq"] <= ack:
		ack_lag = client_tick - int(pending[0]["tick"])
		pending.pop_front()
	last_ack = maxi(last_ack, ack)
	var predicted := ship.position
	ship.position = state["position"]
	ship.velocity = state["velocity"]
	ship.energy = state["energy"]
	ship.sim_rotation = state["rotation"]
	ship.turn_budget = state.get("turn_budget", ship.turn_budget)
	for input: Dictionary in pending:
		ship.simulate_input(delta, input["movement"], input["boost"], input["facing"])
	var error := predicted.distance_to(ship.position)
	var offset := ship.visual_offset + predicted - ship.position
	ship.set_visual_offset(Vector3.ZERO if offset.length() > SNAP_DISTANCE else offset)
	stats.record_reconciliation(error, pending.size(), ack_lag, int(state.get("input_depth", -1)))


## Decays the correction offset by one tick and re-applies it under the
## current view rotation.
func smooth(ship: Pilot, delta: float) -> void:
	var offset := ship.visual_offset * exp(-delta / SMOOTHING_TIME)
	ship.set_visual_offset(Vector3.ZERO if offset.length_squared() < 1e-8 else offset)
