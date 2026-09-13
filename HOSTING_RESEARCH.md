# Budget Linux hosting research

Checked 2026-09-13. Prices below use German consumer VAT (19%) unless stated otherwise. No account, cart, order, or infrastructure was created. Public listing availability does not guarantee capacity when ordering.

## Recommendation for Dorbit

Start with netcup VPS nano G11s in Nuremberg if paying about EUR 18.48 for six
months is acceptable. At EUR 3.08/month including German VAT and IPv4, it is the
cheapest practical candidate in this comparison. Select Ubuntu 24.04 x86-64.
This is a recommendation for an initial trial, not a proven ten-player capacity
claim. The operating system, game startup/import and future persistence need
memory beyond the running game process, so prefer 2 GB to the smallest 1 GB tier.

If avoiding a six-month commitment matters more, consider netcup VPS 500 G12
with the zero-month contract option, about EUR 6.81/month with its default
European location. Do not accidentally order its default annual contract.
Hetzner CX23 would also be suitable to try if available, but it is currently
listed unavailable and costs more. No purchase is authorized by this research.

## What the existing performance report tells us

[PR #11](https://github.com/Timerk/Dorbit/pull/11) measured ten independent
headless clients connected to one Linux server. Its
[report at the reviewed commit](https://github.com/Timerk/Dorbit/blob/d8e6408e220abd29717e782dc3c6b94b45d1f191/PERFORMANCE.md)
records mean server CPU of 3.49% of one logical CPU, p95 4.98%, and peak resident
memory of 111.50 MiB. The host was an Intel i7-13800H running Ubuntu under WSL2.

That supports trying a small shared-CPU VPS before spending more. It does not
mean the same CPU percentages will hold on a rented server. The measurement ran
for about two minutes, all clients used local loopback, the single alien was
alive for only 3.87% of ticks, and the report records a roughly 10% clock
discrepancy. It does not cover sustained multi-alien combat, newer persistence
work, long-term memory growth or internet bandwidth.

After renting, repeat the benchmark on the actual host, then play from separate
networks and verify the deployment service's restart, reboot and rollback
procedures. Benchmark clients consume resources too; running all ten on a tiny
VPS is a stress test of the whole machine, not an isolated server measurement.
Do not upgrade solely because a marketing page recommends dedicated CPUs for
games. Upgrade if observed CPU contention or memory pressure causes problems.

## Hetzner

The public price matrix was checked in the browser with EUR and VAT 0% selected.
Its matrix explicitly includes IPv4 and excludes VAT. The consumer estimates
below multiply that amount by 1.19; confirm the checkout total for the customer's
billing country. Do not add the IPv4 charge a second time to these totals.

| Plan | CPU / RAM / storage | Listed monthly price with IPv4, before VAT | With German VAT | Status and assessment |
| --- | --- | --- | --- | --- |
| CX23 | 2 Intel/AMD vCPU / 4 GB / 40 GB NVMe | EUR 5.99 | About EUR 7.13 | Explicitly marked unavailable on the public page; sensible small trial if stock returns |
| CPX12 | 1 AMD vCPU / 2 GB / 40 GB NVMe | EUR 11.99 | About EUR 14.27 | Higher price than the budget alternatives; no reason to start here from the current benchmark |

Both listed EU configurations include 20 TB traffic. Hetzner bills by the hour
up to a monthly cap. Turning the server off does not stop billing; the server
must be deleted when no longer needed. A retained Primary IPv4 address is billed
separately until deleted too. No paid extras are included in this comparison.

Choose an Intel/AMD x86-64 plan for the existing helper. Hetzner CAX plans use
ARM, which does not match the helper's pinned Linux x86-64 executable.

Sources: [CX specifications, pricing and availability](https://www.hetzner.com/cloud/cost-optimized/),
[CPX specifications and pricing](https://www.hetzner.com/cloud/regular-performance/),
[hourly billing and retained IP charges](https://docs.hetzner.com/cloud/billing/faq/),
[current server helper](https://github.com/Timerk/Dorbit/blob/236f52437426b38a363acf608d51d20401c65b1b/tools/server.sh).

## Budget alternatives

### netcup VPS nano G11s: cheapest practical candidate, with a commitment

- **€3.08/month including 19% VAT and IPv4 + IPv6.** IPv6-only saves €0.60/month, but keep IPv4 for straightforward game connections.
- **Six-month minimum contract and six-month billing period**, not a cancel-anytime monthly service. Budget approximately **€18.48 for the first six months**; confirm the exact invoice total at checkout because tax rounding can differ.
- **€0 setup fee.**
- **2 x86 vCores, 2 GB RAM, 60 GB SSD**, KVM, full server control. Nuremberg, Germany.
- 1 Gbit/s interface; if average network traffic over the previous 24 hours exceeds 100 Mbps, temporary throttling to 100 Mbps applies.
- Product page exposes an Add to shopping cart button and no unavailable notice in the fetched visible text. Checkout stock was not tested.
- Lite plans use shared CPU resources. Listed core counts alone cannot establish game tick performance. Run the existing benchmark on the actual rented instance before treating player capacity as proven.
- Moving from nano G11s to the newer Lite G12s family requires ordering another server and migrating; it is not an in-place plan upgrade. Local Block Storage cannot be added to nano.

Sources: [nano product and contract details](https://www.netcup.com/en/server/vps/vps-nano-g11s-iv-6m-nue), [Lite plan comparison, location and upgrade FAQ](https://www.netcup.com/en/server/vps-lite).

**Provisional recommendation:** nano is attractive when the workload fits 2 GB RAM and the user accepts paying for six months. Do not describe €3.08 as a monthly cancel-anytime option. For a short experiment, compare flexible pricing before choosing.

### netcup VPS 500 G12: flexible alternative with more memory

- 2 x86 vCores, 4 GB DDR5 ECC RAM, 128 GB NVMe.
- Product default is **€5.91/month including 19% VAT and IPv4 + IPv6**, with **12-month minimum term and 12-month billing**; €0 setup.
- The product configurator displays a **zero-month contract option for +€0.90/month**: approximately **€6.81/month including VAT**, with IPv4 and the default European location selection. The general VPS FAQ says hourly plans are paid monthly in advance, adjusted hourly when terminated, and have no minimum term or notice period.
- Default location is “No preference Europe.” Selecting Nuremberg costs another **€0.90/month** in the fetched configurator. Confirm the final selected total before ordering.
- The public page warns configuration choices may be constrained by availability; no checkout was performed.

Sources: [VPS 500 G12 product/configurator](https://www.netcup.com/en/server/vps/vps-500-g12-iv-12m), [billing and locations FAQ](https://www.netcup.com/en/server/vps).

### OVHcloud VPS-1: headline looks cheap, but needs a term check

- German official page advertises **from €4.53/month including VAT** for **2 vCores, 4 GB RAM, 40 GB NVMe**, 500 Mbps public bandwidth, unlimited European traffic, and included dedicated IPv4.
- The Configure link attached to that headline explicitly selects **`pricing=upfront12`**. Treat this as an annual upfront offer, not a verified flexible monthly price.
- **Flexible monthly price, exact commitment conditions, setup charges, and stock were not verified.** The public configurator's fetched HTML did not expose these values. The advertised price alone is insufficient for a final purchase comparison.
- Daily host-level backup is advertised as included. This research does not define or implement game persistence or backup behavior.

Sources: [German VPS listing](https://www.ovhcloud.com/de/vps/), [linked VPS-1 configurator](https://www.ovhcloud.com/de/vps/configurator/?planCode=vps-2027-model1&brick=VPS%2BModel%2B1&pricing=upfront12&processor=%20&vcore=2__vCore&storage=40__SSD__NVMe). The [Irish listing](https://www.ovhcloud.com/en-ie/vps/) gives the same headline as €3.81 excluding VAT and states VAT depends on residence.
