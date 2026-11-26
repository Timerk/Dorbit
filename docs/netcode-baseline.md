# Netcode baseline

Movement networking measured before the netcode rework (network schema 23),
with the network simulator from phase 1 of the
[real-time netcode rework](../GAME_PLAN.md#real-time-netcode-rework). Later
phases rerun the same benchmark unchanged; phase 6 folds these tables into
`docs/NETCODE.md`.

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
