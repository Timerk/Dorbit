# Netcode baseline

Movement networking measured before the netcode rework (network schema 23),
with the network simulator from phase 1 of the
[real-time netcode rework](../GAME_PLAN.md#real-time-netcode-rework). Later
phases rerun the same benchmark and append their results below; phase 2
redefined three metrics, as its section explains. Phase 6 folds these tables
into `docs/NETCODE.md`.

```
godot --headless --path . --script res://tests/netcode_benchmark.gd -- --scenario=baseline
```

Setup: one dedicated server, one measured client routed through the relay and
three clients connected directly, all in one headless process on a Windows 11
desktop (129–139 frames per second). Every pilot flies the same scripted input:
thrust, boost, strafe and turns in a mirrored 6-second cycle, about 30 m/s on
average. Each condition gets a 15-second warm-up and is then measured for
20 seconds. Added RTT is split evenly per direction (100 ms adds 50 ms each
way); loss applies independently in both directions. Metric definitions are in
the header of `tests/netcode_benchmark.gd`.

| Added RTT | Loss | ENet RTT | Client up | Client down | Server to client | Snapshot jitter mean / p95 / max | Prediction error mean / p95 / max | Correction mean / p95 / max | Gap to server now mean / p95 | Commands sent / applied / lost |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 ms | 0% | 28 ms | 1.1 KB/s | 13.6 KB/s | 13.6 KB/s | 5.7 / 16.0 / 30.5 ms | 0.24 / 0.55 / 0.87 m | 0.05 / 0.11 / 0.17 m | 0.20 / 0.47 m | 400 / 400 / 0 (0.0%) |
| 100 ms | 0% | 105 ms | 1.1 KB/s | 14.0 KB/s | 14.0 KB/s | 5.7 / 13.7 / 58.7 ms | 0.15 / 0.45 / 0.81 m | 0.03 / 0.09 / 0.16 m | 1.55 / 2.77 m | 401 / 400 / 1 (0.2%) |
| 200 ms | 0% | 206 ms | 0.7 KB/s | 6.3 KB/s | 6.3 KB/s | 61.3 / 156.8 / 175.0 ms | 0.82 / 1.81 / 2.78 m | 0.16 / 0.36 / 0.56 m | 3.26 / 6.11 m | 400 / 261 / 139 (34.8%) |
| 0 ms | 5% | 32 ms | 1.1 KB/s | 12.8 KB/s | 13.6 KB/s | 9.6 / 45.9 / 107.8 ms | 0.24 / 0.55 / 0.79 m | 0.05 / 0.11 / 0.16 m | 0.22 / 0.51 m | 400 / 385 / 15 (3.8%) |
| 100 ms | 5% | 105 ms | 1.1 KB/s | 13.5 KB/s | 14.4 KB/s | 7.3 / 30.6 / 98.8 ms | 0.15 / 0.39 / 1.57 m | 0.03 / 0.08 / 0.31 m | 1.55 / 2.74 m | 400 / 389 / 11 (2.8%) |
| 200 ms | 5% | 202 ms | 0.8 KB/s | 10.0 KB/s | 10.6 KB/s | 21.2 / 64.1 / 157.9 ms | 0.37 / 0.96 / 1.42 m | 0.07 / 0.19 / 0.28 m | 3.05 / 5.45 m | 400 / 299 / 101 (25.3%) |

## Observations

- **Prediction error looks small because reconciliation hides latency.** Each
  snapshot pulls the local ship 20% toward the authoritative position, which
  is about one round trip old. At steady speed this drags the predicted ship
  back onto the delayed server path instead of correcting real mispredictions.
  The gap to the server's current position grows with latency (0.2 m at 0 ms,
  1.6 m at 100 ms, 3.3 m at 200 ms), so the controls feel delayed even though
  the per-snapshot correction stays under 0.6 m.
- **ENet's packet throttle drops unreliable traffic at 200 ms.** Commands and
  snapshots are unreliable, and ENet discards unreliable packets at the sender
  when its round-trip variance suggests congestion. At 200 ms added RTT, 25–35%
  of flight commands never left the client and the server sent up to half its usual
  snapshot bytes, even with no simulated loss. Snapshot jitter rises
  accordingly. Phase 2's redundant inputs, and possibly ENet throttle settings,
  need to account for this.
- **Lost datagrams lose inputs.** At 5% loss, 3–4% of flight commands never
  reach the server. Commands are not resent, so each loss leaves the server on
  the previous input until the next command 50 ms later.
- **ENet RTT is a smoothed estimate.** ENet adjusts it by 1/8 per reliable
  acknowledgement, about two per second here, so it lags condition changes by
  several seconds; the benchmark's warm-up covers that.
- At 0 ms the 28 ms RTT and 16 ms jitter p95 mostly reflect frame timing in a
  single process hosting five sectors: ENet is serviced once per frame.

## After phase 2: ticks, input sequencing and reconciliation

Network schema 24. The same benchmark, scripted input and conditions, plus the
150 ± 30 ms, 5% loss condition used by phase 5 (`--scenario=degraded`).
Measured on the same Windows 11 desktop (92–118 frames per second).

```
godot --headless --path . --script res://tests/netcode_benchmark.gd -- --scenario=baseline
godot --headless --path . --script res://tests/netcode_benchmark.gd -- --scenario=degraded
```

Three metrics changed meaning, because the thing they measured changed (the
benchmark header has the full definitions):

- **Sim error** replaces *prediction error*. It is how far rewinding to the
  authoritative state and replaying the unacknowledged inputs moved the
  predicted ship at each reconciliation. Zero means the server simulated
  exactly what the client predicted. The old metric compared the predicted
  ship with a round-trip-old position, which mostly measured latency.
- **Visual offset** replaces *correction*. Corrections no longer move the drawn
  ship within a frame: the model and camera are drawn at a decaying offset
  from the simulated ship. This is that offset, sampled every client tick.
- **Inputs** replace *commands*. Clients now send one input per 60 Hz tick
  (30 packets per second, each repeating up to ten unacknowledged inputs).
  *Lost* counts inputs the server skipped because they never arrived; late,
  catch-up drops and starved ticks are the server's input buffer counters.

| Added RTT | Loss | ENet RTT | Client up | Client down | Server to client | Snapshot jitter mean / p95 / max | Sim error mean / p95 / max | Visual offset mean / p95 / max | Gap to server now mean / p95 | Replay mean / max | Server buffer | Inputs sent / applied / lost | Late / dropped / starved |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 ms | 0% | 32 ms | 2.7 KB/s | 14.4 KB/s | 14.4 KB/s | 5.8 / 16.3 / 24.9 ms | 0.00 / 0.00 / 0.00 m | 0.00 / 0.00 / 0.00 m | 2.00 / 3.44 m | 4.5 / 6 | 2.8 | 1201 / 1201 / 0 | 0 / 0 / 0 |
| 100 ms | 0% | 107 ms | 3.5 KB/s | 14.9 KB/s | 14.9 KB/s | 4.5 / 10.1 / 23.6 ms | 0.00 / 0.00 / 0.01 m | 0.00 / 0.00 / 0.01 m | 2.99 / 5.14 m | 9.0 / 10 | 2.3 | 1200 / 1200 / 0 | 0 / 0 / 0 |
| 200 ms | 0% | 205 ms | 3.5 KB/s | 14.4 KB/s | 14.4 KB/s | 5.0 / 12.1 / 19.5 ms | 0.00 / 0.00 / 0.00 m | 0.00 / 0.00 / 0.00 m | 4.59 / 7.92 m | 15.3 / 18 | 2.5 | 1200 / 1199 / 0 | 0 / 0 / 1 |
| 0 ms | 5% | 32 ms | 3.1 KB/s | 14.5 KB/s | 15.0 KB/s | 8.0 / 22.9 / 70.3 ms | 0.00 / 0.00 / 0.00 m | 0.00 / 0.00 / 0.00 m | 2.90 / 5.08 m | 6.6 / 8 | 4.6 | 1200 / 1200 / 0 | 0 / 0 / 0 |
| 100 ms | 5% | 109 ms | 3.5 KB/s | 13.9 KB/s | 14.4 KB/s | 7.5 / 18.8 / 61.8 ms | 0.00 / 0.00 / 1.21 m | 0.01 / 0.00 / 1.05 m | 4.45 / 7.65 m | 12.3 / 15 | 5.2 | 1200 / 1200 / 0 | 0 / 2 / 0 |
| 200 ms | 5% | 208 ms | 3.5 KB/s | 13.2 KB/s | 14.4 KB/s | 9.8 / 48.8 / 116.0 ms | 0.00 / 0.00 / 0.62 m | 0.01 / 0.01 / 0.54 m | 5.75 / 9.93 m | 17.8 / 20 | 4.8 | 1200 / 1199 / 0 | 0 / 1 / 1 |
| 150 ± 30 ms | 5% | 158 ms | 3.5 KB/s | 13.7 KB/s | 14.4 KB/s | 12.9 / 33.1 / 71.8 ms | 0.00 / 0.00 / 0.00 m | 0.00 / 0.00 / 0.00 m | 4.96 / 8.51 m | 14.5 / 16 | 4.7 | 1200 / 1200 / 0 | 0 / 0 / 0 |

### Observations

- **Replays match the server.** Straight flight replays bit for bit. Turning
  leaves float-rounding differences of a few millimetres, too small to show
  in the table's two decimals. Larger corrections come only from the server's
  input buffer policy: a catch-up drop or a starved tick shifts the server by
  one tick of motion (0.5–1.4 m), and the visual offset hides it over about
  0.3 s.
- **No input is lost**, at any condition: each input travels in up to five
  packets, so 5% loss and short bursts never leave a gap.
- **ENet's throttle no longer discards traffic at 200 ms.** The server now
  sends its full snapshot rate at every condition (14.4 KB/s, against 6.3 and
  10.6 KB/s before). The fix is the throttle configuration below, not the
  redundancy.
- **The gap to the server grew,** from 1.6/3.3 m to 3.0/4.6 m at 100/200 ms.
  That is the intended effect of prediction: the local ship now runs ahead of
  the server by the upstream delay plus the server's input buffer (2–5 ticks,
  33–83 ms) instead of being dragged back toward old snapshots. Controls
  respond in the same frame at every latency.
- **Upload doubled** (1.1 to 3.5 KB/s) for 30 redundant input packets per
  second; downstream is unchanged.

### ENet packet throttle

ENet throttles unreliable packets at the sender. Each peer keeps a packet
throttle (0–32) and drops that share of unreliable packets. Every throttle
interval (5 s) it compares the latest round trip with the previous interval's
mean: lower round trips accelerate the throttle, and a round trip above the
mean plus twice its variance decelerates it. With steady added delay the
variance is tiny, so ordinary frame-timing noise decelerates it repeatedly.
That produced the baseline's 25–35% loss of commands and snapshots at 200 ms.

Clients and the server now call `ENetPacketPeer.throttle_configure(5000, 2, 0)`
on every server/client peer (`FlightSession.ENET_THROTTLE`). Deceleration 0
keeps the throttle fully open. Dorbit's unreliable traffic is small and paced,
so it needs no congestion back-off. Reliable traffic keeps ENet's own
windowing, acknowledgements and resends, and the full suite of reliable
gameplay tests passes. Measured with the same phase 2 build, at 200 ms added
RTT:

| ENet deceleration | Loss | Server to client | Snapshot jitter p95 | Sim error max | Starved / dropped |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 2 (ENet default) | 0% | 14.9 KB/s | 19.7 ms | 0.71 m | 1 / 2 |
| 2 (ENet default) | 5% | 10.5 KB/s | 126.6 ms | 2.16 m | 11 / 11 |
| 0 (phase 2) | 0% | 14.4 KB/s | 12.1 ms | 0.00 m | 1 / 0 |
| 0 (phase 2) | 5% | 14.4 KB/s | 48.8 ms | 0.62 m | 1 / 1 |

With the default the throttle engaged at 5% loss in this run: the server
dropped 27% of its snapshot bytes, snapshot jitter rose 2.6 times, and
throttled input packets starved the input buffer.
