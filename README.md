# Does AWS PrivateLink make Postgres faster?

This started with [a tweet](https://x.com/mynameisyahia/status/2104322441942290595) from someone seeing an additional 300 ms of latency because their application and database were hosted separately. The solution was obviously putting them in the same region.

Then [one reply](https://x.com/WallisDev/status/2104592334398865634?s=20) even recommended always using AWS PrivateLink to avoid the extra hop over the public network. That caught my attention because PlanetScale mainly presents PrivateLink as a compliance feature rather than a performance optimization, reporting improvements only in the single-digit-millisecond range.
So I benchmarked its public and PrivateLink endpoints from the same AWS region to find out whether there is a measurable performance improvement.

## Short answer

PrivateLink produced a measurable performance improvement, but only for larger
responses. At 64 KiB and below, differences stayed under 0.3 ms and changed
direction—not a meaningful gain. From 256 KiB upward, PrivateLink pulled ahead;
at 4 MiB it was 3.8 ms faster at the median and delivered about 11% more
throughput.

The benchmark compared two connections to the same PlanetScale Postgres
database in Frankfurt. The role, branch, query, TLS settings, client, and EC2
runner stayed the same. Only the network path changed.

## Public endpoint vs. PrivateLink

```text
Public
EC2 → internet gateway → public endpoint → PlanetScale → Postgres

PrivateLink
EC2 → interface endpoint ENI → PrivateLink data plane → PlanetScale → Postgres
```


|                 | Public endpoint               | PrivateLink                    |
| --------------- | ----------------------------- | ------------------------------ |
| Address         | Public IP                     | Private VPC IP                 |
| VPC path        | Internet gateway              | Interface endpoint             |
| Service path    | Public routing semantics      | AWS PrivateLink                |
| Public exposure | Publicly addressable endpoint | Endpoint exists inside the VPC |


PrivateLink adds a logical forwarding layer through its interface endpoint and
data plane. That does not necessarily mean an extra physical hop: both paths
contain provider-side networking that traceroute cannot reveal. Likewise,
“public” describes addressing and routing semantics; it does not prove that a
packet physically left AWS's backbone.

## The experiment

- One `c7g.large` EC2 runner in `eu-central-1a`
- One PlanetScale Postgres database in Frankfurt
- Persistent connections for the payload test
- `SELECT repeat('x', $1)::text`
- Six response sizes from 1 KiB to 4 MiB
- 10,000 public/private pairs per size
- Randomized order inside every pair
- Public and private hostnames pinned before the run, keeping DNS out of the
timed comparison while preserving hostname-based TLS verification

The full run made 120,000 timed queries and returned 104.08 GiB in about 55
minutes. Neither path produced an error or timeout.

## Results

Each pair contains one public and one PrivateLink measurement for the same
payload, with their order randomized. The paired p50 delta is calculated as
`PrivateLink - public`, so a negative value means PrivateLink was faster.

“Pairs where PrivateLink was faster” is the share of the 10,000 pairs in which
the PrivateLink measurement had lower latency. It is not a speedup percentage.
For example, 97.82% at 4 MiB means PrivateLink was faster in 9,782 pairs; its
median latency was about 9.4% lower, not 97.82% lower.


| Response | Public p50 | PrivateLink p50 | Paired p50 delta | Pairs where PrivateLink was faster |
| -------- | ---------- | --------------- | ---------------- | ---------------------------------- |
| 1 KiB    | 1.658 ms   | 1.917 ms        | +0.257 ms        | 6.12%                              |
| 16 KiB   | 1.915 ms   | 1.881 ms        | -0.032 ms        | 59.67%                             |
| 64 KiB   | 2.321 ms   | 2.465 ms        | +0.139 ms        | 20.49%                             |
| 256 KiB  | 4.053 ms   | 3.761 ms        | -0.292 ms        | 92.48%                             |
| 1 MiB    | 11.038 ms  | 10.034 ms       | -1.019 ms        | 96.35%                             |
| 4 MiB    | 41.127 ms  | 37.248 ms       | -3.827 ms        | 97.82%                             |


At 64 KiB and below, differences stayed under 0.3 ms and changed direction.
There is no useful small-query latency win here.

At 256 KiB, PrivateLink began winning most pairs. At 1 MiB it saved about 1 ms;
at 4 MiB it saved about 3.8 ms at the median. A linear fit over the three
largest sizes estimated:

- Public: 100.7 MiB/s
- PrivateLink: 111.5 MiB/s
- PrivateLink advantage: 0.96 ms per MiB, or 10.7% modeled throughput

Four MiB is a large database response: roughly 2,000–8,000 ordinary rows if
each serialized row is 0.5–2 KiB. The 4 MiB case alone transferred 78.1 GiB
across both paths during its 10,000 pairs.

## Why the crossover makes sense

A useful model is:

```text
query time = shared database/client work + fixed path cost + payload transfer
```

Postgres execution, protocol framing, and client decoding are shared costs and
largely cancel in a randomized paired comparison. PrivateLink's logical
forwarding layer may add a small fixed cost.
That is why the latency improvement only appeared with larger payloads, where
transfer time had more leverage.

## What this benchmark did not show

Both paths completed all 60,000 queries. The run therefore gives no evidence that PrivateLink is more reliable. Testing transient failures would require a much longer observation window, repeated runs, or controlled congestion.

## Conclusion

Use PrivateLink for private connectivity and controlled routing. Do not expect
it to materially speed up ordinary small Postgres responses. Its performance
benefit became meaningful when results reached hundreds of KiB and grew to
roughly 1 ms per MiB in this Frankfurt test.

The detailed percentiles are in [RESULTS.md](RESULTS.md). Every raw observation
is available as compressed JSONL under
`[data/2026-09-29-payload-matrix](data/2026-09-29-payload-matrix)`.

To run the benchmark yourself, see [REPRODUCING.md](REPRODUCING.md).
