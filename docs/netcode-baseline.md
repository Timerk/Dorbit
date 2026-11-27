# Netcode baseline

Movement networking measured before the netcode rework (network schema 23),
with the network simulator from phase 1 of the
[real-time netcode rework](../GAME_PLAN.md#real-time-netcode-rework). Later
phases rerun the same benchmark and append their results below; phase 2
redefined three metrics, as its section explains. [NETCODE.md](NETCODE.md)
summarizes these tables with the architecture and tradeoffs.

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

## After phase 3: snapshot interpolation

Network schema 25. Remote pilots and aliens are no longer lerped toward the
newest snapshot (25% of the remaining distance per tick). Each one has a
`SnapshotBuffer` of transforms keyed by server tick. Once per client physics
tick, `FlightSession.render_remote()` draws them at a render time on the
server's timeline, which `ServerClock` keeps:

- **Clock.** Each snapshot gives an offset sample: its server tick / 60 minus
  its local arrival time. The clock uses the median of the last 2 s of
  samples, so single late or early packets barely move it. The render time
  trails that estimate by `ServerClock.INTERPOLATION_DELAY` (100 ms, two
  snapshot intervals; a playtesting setting). It advances by each physics
  tick, time-scaled by at most ±5% to close a low-pass-filtered error, and
  snaps only past 250 ms (connecting, or a stall). The largest sample (the
  fastest path) was tried first. Frame and tick timing outliers set it, and it
  left typical packets about 30 ms less buffer (4.8% against 1.2% of entity
  ticks extrapolated at 150 ± 30 ms).
- **Interpolation.** Positions follow a cubic Hermite curve between the two
  bracketing samples, with tangents taken across neighbouring samples. Angles
  take the shortest path. Linear interpolation changed the drawn velocity at
  every snapshot, which showed as acceleration spikes on about 10% of ticks.
- **Dry buffers.** Past the newest sample, the entity extrapolates its last
  motion for at most `SnapshotBuffer.MAX_EXTRAPOLATION_TICKS` (250 ms), then
  holds. Out-of-order packets of the same life still fill gaps; stale and
  duplicate ticks are ignored.
- **Discontinuities** clear the buffer and snap to the new state: spawn and
  launch (a new buffer), despawn and dock, a new life or alive state
  (respawn, death, jump), map changes and visits, alien encounter resets and
  the end of a return home, and session start or end. The per-entity
  sequence, visit and life checks are unchanged.
- **Immediate state.** Health, shields, alive, docked and energy apply on
  arrival. Death and respawn are not delayed to the render time: the server
  has already decided them, and targeting and the HUD must not show a
  destroyed ship as attackable. A ship can therefore vanish up to the delay
  plus jitter early, about 3 m at cruise speed. Its explosion is drawn at the
  authoritative position, well within its diameter.
- **Effects.** Laser and explosion points within 8 m of an entity's newest
  received position move by that entity's drawn offset
  (`FlightSession.drawn_point`). Beams join the drawn ships: remote ships in
  the past, the local ship ahead of the server.

Tradeoff: remote ships are drawn about 100 ms plus the one-way latency in the
past. The server still decides hits on its current positions with no lag
compensation, so a pilot aims at a target that is further along than it is
drawn. Lag compensation, rewinding targets to the shooter's render time, is
out of scope and a possible later step.

The F8 overlay adds one line: interpolation delay, buffer depth (how far the
newest snapshot is ahead of the render time, min / mean over 2 s), the share
of remote entity ticks extrapolated, and underruns ("dry"). The jitter line
now also shows clock drift.

### Remote smoothness, before and after

The benchmark now has the measured client, routed through the relay, watch
the first extra pilot, which flies the same pattern and turns. Once per
physics tick it compares the drawn ship with the server's path (definitions in
`tests/netcode_benchmark.gd`). *Before* is the phase 2 build
(`feat/netcode-ticks`, 8a63bb0) running the same benchmark file. The earlier
metrics keep their definitions.

These runs shared the desktop with an unrelated heavy workload. The benchmark
process ran at 13–38 frames per second with three extra clients, not the
92–118 of phase 2. ENet is serviced once per frame, so snapshots arrived in
bursts. That inflates underruns and the main table's RTT column, which is why
the earlier tables are not repeated here. Both builds ran under the same load.
The last pair used one extra client, at 52 and 78 fps.

| Added RTT | Loss | Build | Path error mean / p95 / max | Lag behind server | Drawn accel p95 / max | Spikes | Render-time error mean / p95 / max | Extrapolated | Buffer depth min / mean |
| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 ms | 0% | before | 0.03 / 0.10 / 0.33 m | 113 ms | 1994 / 6707 m/s² | 86.1% | - | - | - |
| 0 ms | 0% | after | 0.00 / 0.01 / 0.18 m | 104 ms | 83 / 1136 m/s² | 1.8% | 0.00 / 0.01 / 0.21 m | 3.2% | -62 / 57 ms |
| 100 ms | 0% | before | 0.03 / 0.09 / 1.23 m | 158 ms | 1592 / 4618 m/s² | 86.5% | - | - | - |
| 100 ms | 0% | after | 0.00 / 0.01 / 0.66 m | 164 ms | 111 / 1015 m/s² | 2.6% | 0.00 / 0.01 / 0.19 m | 4.9% | -57 / 54 ms |
| 200 ms | 0% | before | 0.03 / 0.09 / 1.46 m | 211 ms | 1568 / 4514 m/s² | 85.9% | - | - | - |
| 200 ms | 0% | after | 0.01 / 0.01 / 1.14 m | 235 ms | 99 / 889 m/s² | 2.6% | 0.00 / 0.01 / 0.19 m | 6.9% | -72 / 56 ms |
| 0 ms | 5% | before | 0.03 / 0.10 / 0.50 m | 124 ms | 1990 / 4843 m/s² | 85.6% | - | - | - |
| 0 ms | 5% | after | 0.00 / 0.01 / 0.70 m | 120 ms | 115 / 882 m/s² | 3.4% | 0.01 / 0.03 / 0.15 m | 5.7% | -65 / 59 ms |
| 100 ms | 5% | before | 0.03 / 0.09 / 0.46 m | 165 ms | 1800 / 4868 m/s² | 84.8% | - | - | - |
| 100 ms | 5% | after | 0.00 / 0.01 / 0.41 m | 163 ms | 111 / 2328 m/s² | 3.0% | 0.01 / 0.03 / 0.52 m | 6.4% | -123 / 55 ms |
| 200 ms | 5% | before | 0.03 / 0.10 / 0.92 m | 213 ms | 1649 / 6602 m/s² | 85.0% | - | - | - |
| 200 ms | 5% | after | 0.01 / 0.01 / 1.14 m | 235 ms | 131 / 927 m/s² | 3.6% | 0.01 / 0.03 / 0.18 m | 6.4% | -73 / 54 ms |
| 150 ± 30 ms | 5% | before | 0.04 / 0.12 / 2.44 m | 215 ms | 2999 / 11859 m/s² | 83.9% | - | - | - |
| 150 ± 30 ms | 5% | after | 0.01 / 0.03 / 1.95 m | 203 ms | 118 / 2522 m/s² | 3.6% | 0.01 / 0.04 / 0.54 m | 8.5% | -127 / 60 ms |
| 150 ± 30 ms, 1 extra client | 5% | before | 0.03 / 0.10 / 0.81 m | 166 ms | 1610 / 4454 m/s² | 86.7% | - | - | - |
| 150 ± 30 ms, 1 extra client | 5% | after | 0.00 / 0.01 / 0.75 m | 185 ms | 81 / 2139 m/s² | 0.4% | 0.00 / 0.02 / 0.41 m | 1.0% | -96 / 64 ms |

The server's own path measures 60 / 80 m/s² (p95 / max) in nearly every run.
A brush with the station's collision envelope can push its maximum toward
1000 m/s². Spikes are ticks whose drawn acceleration exceeds three times the
server's p95.

### Observations

- **The stutter is gone.** The old lerp chased a target that stepped at every
  snapshot, so its drawn velocity jumped on most ticks. Its p95 acceleration
  was 1.6–3.0 km/s², 25–50 times the real motion, even on a clean link.
  Buffered Hermite interpolation draws within 1.3–2.2 times the server's own
  p95, and the drawn path stays within centimetres of a path the ship really
  flew.
- **The delay is similar.** The drawn ship trails the server by about 100 ms
  plus the one-way latency (104–235 ms here). The old lerp trailed by a
  similar amount through its smoothing lag, but its drawn path cut corners
  and never sat on the real one.
- **Extrapolation is rare but sensitive to load.** At about 50 fps, 1% of
  entity ticks are drawn past the newest sample. At 13–38 fps, arrivals
  bunched into frames raise that to 3–9%. The peaks in the maximum columns
  are the corrections when fresh samples replace an extrapolation. If
  playtests on real links show underruns, raise the interpolation delay.
- `tests/interpolation_network_test.gd` checks the same measures through the
  relay at 150 ± 30 ms with 5% loss. It also replays the old lerp from the same
  packets and asserts that it stutters (80–86% spike ticks against 0–5%).

## After phase 4: snapshot quantization and deltas

Network schema 26. The server packs public pilots and aliens once per
snapshot tick, then encodes a separate view for each recipient. Server tick,
sequence, visits, lives, encounters and profile revisions remain exact.
Reliable profiles still carry fitting and other infrequently changing state.
The owner retains float32 position, rotation, velocity and energy for
reconciliation and float64 hull and shields for exact repair costs.

| Public field | Wire quantum | Maximum rounding error |
| --- | --- | --- |
| Position | Signed 24-bit per axis, 1/256 m relative to the map origin | 1/512 m per axis, 3.39 mm in 3D |
| Euler angles | Unsigned 16-bit per axis, one turn / 65,536 | 0.00275° per axis, modulo a turn |
| Hull and shields | Unsigned 24-bit each, ¼ point | ⅛ point over 0 to 4,194,303.75 |
| Pilot energy | Unsigned 16-bit, 1/256 point | 1/512 point over 0 to 100 |
| Time since hit | Unsigned 16-bit, 10 ms, capped at 6 s | 5 ms before the cap |

The 1,200 m sector radius fits inside the ±32,768 m local position range.
An entity outside the quantized range carries its original float32 position.
The position bounds are relative to the input float32 coordinates at current
map origins. The server and owner retain the full hit timer for repair and
shield regeneration. The cap lets idle public records stop changing.
Radiation and alien respawn timers keep their existing float32 encoding.

`FlightInput` carries a 32-bit snapshot acknowledgement. Flying clients
include it in their regular input packets, and idle clients send it on the
same channel without controls. The server accepts only acknowledgements for
that viewer's exact sent sequence in the current map visit. Both sides keep
a 32-snapshot history. Missing or expired acknowledgements and new visits
produce full snapshots. A client discards a delta if its named baseline
never arrived or has expired.

Each part starts with four unsigned 32-bit values for sequence, visit, tick
and baseline. A baseline of zero marks a full snapshot. The header ends
with an 8-bit part index, an 8-bit part count and a 16-bit record count.
Each record has a 16-bit tag followed by a 32-bit pilot ID or 16-bit alien
ID. The tag's top two bits identify the kind. Its lower bits mark changed
field groups, from least to most significant.

| Record | Field groups in mask order |
| --- | --- |
| Public pilot | Metadata, position, angles, hull, shields, energy, hit timer, radiation |
| Owner | Metadata, position, angles, hull, shields, energy, hit timer, radiation, velocity, input acknowledgement and buffer, input counters, progress and respawn, traffic metrics, ammunition, rockets and boosts |
| Alien | Metadata, position, angles, hull, shields, hit timer, respawn |

New entities and changes to flags, profile revision or lifecycle metadata
send all groups. A zero mask repeats the entity's state at the new server
tick, so stationary entities keep filling their interpolation buffers.
Each snapshot lists current entities. An entity that leaves visibility
is absent from the new baseline.

The encoder packs the owner first, then visible pilots and aliens in ID
order. It splits on record boundaries at 1,200 bytes per RPC payload. Godot
4.7.2's vendored ENet has a 1,392-byte default MTU and starts fragmenting
payloads above 1,364 bytes (1,360 with its optional checksum). The remaining
headroom covers the Godot RPC envelope, including the initial node path.
Parts can apply independently on arrival. The client acknowledges the
sequence only after every part arrives.
[ENet defaults](https://github.com/godotengine/godot/blob/4.7.2-stable/thirdparty/enet/enet/enet.h)
[Fragmentation](https://github.com/godotengine/godot/blob/4.7.2-stable/thirdparty/enet/peer.c#L98-L112)
[Godot RPC envelope](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/multiplayer/scene_rpc_interface.cpp#L326-L430)

F8 reports the viewer's server snapshot payload bytes per second, mean
bytes per snapshot tick, share of ticks using a baseline, and cumulative
full snapshots. Those counters cover world snapshot payloads before
transport overhead or loss. The existing Down rate and the relay
benchmarks measure ENet traffic, including reliable messages.

### Relay benchmark

Both builds used the same headless Godot 4.7.2 benchmark on Windows with
one relayed pilot and three directly connected pilots. Each condition
warmed up for 15 s and sampled for 20 s. Phase 3 is
`feat/snapshot-interpolation` at `7c9933a`. Server traffic is measured at
the relay before simulated loss and includes ENet overhead. The world-only
column uses the phase 4 server counter. Rates are decimal bytes per second.

| Added RTT | Loss | Phase 3 server B/s / B/tick | Phase 4 server B/s / B/tick | Phase 4 world B/s / B/tick | Server rate saved |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 ms | 0% | 14351 / 718.6 | 5792 / 289.0 | 4959 / 247.4 | 59.6% |
| 100 ms | 0% | 14352 / 718.4 | 5287 / 263.7 | 4999 / 249.4 | 63.2% |
| 200 ms | 0% | 14356 / 718.2 | 5864 / 292.8 | 5040 / 251.6 | 59.2% |
| 0 ms | 5% | 14978 / 749.4 | 5228 / 261.4 | 4936 / 246.8 | 65.1% |
| 100 ms | 5% | 14353 / 718.6 | 5272 / 263.8 | 4985 / 249.4 | 63.3% |
| 200 ms | 5% | 14978 / 749.0 | 5863 / 293.2 | 5037 / 251.9 | 60.9% |
| 150 ± 30 ms | 5% | 14352 / 718.3 | 5229 / 265.5 | 4950 / 251.4 | 63.6% |

Every measured phase 4 snapshot used a baseline after warm-up. Across all
seven conditions, both builds lost zero inputs and p95 reconciliation error
rounded to 0.00 m. The runs with the largest corrections also recorded
input-buffer catch-up drops or starvation. The owner packets use the same
state precision in both builds.

| Added RTT | Loss | FPS before → after | Max reconciliation error (m) | p95 remote render-time error (m) | Drawn acceleration spikes | Extrapolated ticks |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 ms | 0% | 32 → 49 | 0.60 → 0.63 | 0.01 → 0.01 | 0.9% → 0.1% | 2.0% → 0.2% |
| 100 ms | 0% | 42 → 47 | 0.00 → 1.10 | 0.04 → 0.01 | 5.2% → 0.0% | 0.0% → 0.2% |
| 200 ms | 0% | 56 → 40 | 0.58 → 0.74 | 0.00 → 0.01 | 0.0% → 0.0% | 0.0% → 0.1% |
| 0 ms | 5% | 50 → 42 | 0.00 → 1.46 | 0.01 → 0.01 | 0.6% → 0.5% | 0.7% → 0.7% |
| 100 ms | 5% | 47 → 41 | 0.96 → 0.34 | 0.02 → 0.01 | 0.9% → 1.0% | 1.5% → 1.2% |
| 200 ms | 5% | 38 → 37 | 1.10 → 0.00 | 0.03 → 0.03 | 1.9% → 1.2% | 2.8% → 1.9% |
| 150 ± 30 ms | 5% | 44 → 23 | 2.11 → 1.17 | 0.01 → 0.15 | 0.3% → 5.3% | 0.6% → 9.4% |

The four-pilot degraded run had a 357 ms maximum snapshot interval deviation
on phase 4. At 23 fps, its arrivals were less evenly paced than those in the
44 fps phase 3 run. Repeating just that condition with one extra pilot
produced comparable frame rates and the same p95 remote render error and
acceleration. Maximum render error and extrapolation still varied.

| Two-pilot degraded repeat | FPS | Server B/s / B/tick | Max reconciliation error (m) | Remote render error p95 / max (m) | p95 drawn acceleration (m/s²) | Spikes | Extrapolated |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Phase 3 | 103 | 12,186 / 609.5 | 0.59 | 0.02 / 0.06 | 83 | 0.8% | 1.3% |
| Phase 4 | 102 | 5,211 / 260.5 | 0.62 | 0.02 / 0.15 | 83 | 1.2% | 2.1% |

### Ten-pilot traffic

`tests/snapshot_traffic_benchmark.gd` moves ten pilots and the five M1 aliens
on each of 100 snapshot ticks. It divides the server's ENet host counters by
the viewer and tick counts, then scales to 20 ticks/s. The fixture drives
snapshot sends directly and returns acknowledgements on schema 26.

| Build | Server B/s per viewer at 20 Hz | Server B/tick per viewer | World B/tick per viewer |
| --- | ---: | ---: | ---: |
| Phase 3 | 22,529 | 1,126.4 | — |
| Phase 4 | 6,705 | 335.3 | 319.9 |

ENet traffic dropped 70.2%. The phase 4 run used a baseline on every
measured tick. The separate MTU test forces a full snapshot with ten pilots
and twenty aliens, including reordered and incomplete part delivery.

For phase 5, an initial steady-flight budget is 8,000 pre-loss ENet bytes/s
per viewer at 150 ± 30 ms and 5% loss, measured over 20 s with up to four
pilots. Both degraded runs were close to 5,200 B/s on phase 4. Joins, map
changes and prolonged gaps in acknowledgements send full snapshots.
Combat traffic adds reliable messages, so measure it separately before
setting a budget for the combined playthrough.

## Degraded-network CI

`tests/degraded_network_playthrough.gd` runs a dedicated-style server and
three authenticated clients in separate physics worlds. Each client uses its
own UDP relay at 150 ± 30 ms added RTT and 5% loss in each direction. The
pilots join in sequence and accept a Scout hunt at Outpost 01, then fly 1,200
physics ticks of thrust, boost, strafing and turns. Two pilots then select
and fire on a Scout while the third observes. The server awards each shooter
150 credits and one kill toward the hunt. The observer earns zero of each.
The test waits for the reliable reward notices and loot drop as well as
snapshots carrying the death, wallet, contract progress and hull/shields.
It compares each pilot's hull and shields with the server values from the
same snapshot sequence, including during shield regeneration.
Before flight, it submits a wrong-life contract request followed by a valid
request on the same reliable channel to verify that a mismatched life cannot
change the hunt.

The playthrough prints a single `DEGRADED_NETWORK` JSON record. Reconciliation
and interpolation limits cover steady flight. The observer compares the
drawn pilot against the server path at the observer's render tick and counts
both extrapolated and held samples. Input counters cover the whole flight
through the end of combat. Bandwidth rates use wall time and bytes sent by
the server to each relay before simulated loss. The combat window includes
the engagement and reliable outcome delivery. The reliable subtotal counts
ENet reliable data commands and retransmissions, excluding shared datagram
headers and acknowledgements.
[Godot's vendored ENet packet layout](https://github.com/godotengine/godot/blob/4.7.2-stable/thirdparty/enet/enet/protocol.h)

| Metric | Asserted limit | Windows desktop, three runs | Windows CI | Linux CI |
| --- | ---: | ---: | ---: | ---: |
| Per-pilot simulation error p95 / max | 0.25 / 3.0 m | <0.001 / 1.34 m | 0 / 0 m | 0 / 0.53 m |
| Per-pilot visual offset max | 4.0 m | 1.33 m | 0 m | 0.46 m |
| Input gaps skipped by the server | 0 per pilot | 0 | 0 | 0 |
| Observed path error p95 / max | 0.5 / 3.0 m | 0.041 / 0.52 m | 0.018 / 0.045 m | 0.018 / 0.092 m |
| Observed extrapolated or held ticks | 15% | 8.9% | 1.2% | 1.2% |
| Steady-flight ENet downstream per viewer | 8,000 B/s | 5,088–5,775 B/s | 5,082–5,088 B/s | 5,080–5,082 B/s |
| Combat ENet downstream per viewer, including reliable traffic | 9,000 B/s | 4,495–5,840 B/s | 4,742–5,723 B/s | 4,725–5,661 B/s |
| Reliable ENet downstream per viewer during combat | Measured | 45–150 B/s | 64–149 B/s | 98–156 B/s |
| Runtime including setup | Target under 60 s | 52–62 s | 41 s | 39 s |

The CI columns are from the first passing workflow, before startup changed
to establish each connection in sequence.
[Windows job](https://github.com/Timerk/Dorbit/actions/runs/45885239860/job/140134382286)
[Linux job](https://github.com/Timerk/Dorbit/actions/runs/45885239860/job/140134382578)

The simulator's seeds fix the random streams. Host scheduling still affects
packet arrival order and the shared process's frame timing. A frame stall
can starve a server input buffer and introduce a correction even when all
input sequences ultimately arrive. The JSON record includes frame rate and
per-pilot late, catch-up drop and starvation counts. The slowest desktop
replay ran alongside the full suite at 22 FPS and recorded as many as 28
starved ticks and 23 catch-up drops for a pilot, with zero late or lost
inputs. Reliable totals can also include periodic station inventory traffic
when a Skylab update falls inside the measurement window.
