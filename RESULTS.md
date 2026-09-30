# Benchmark results

The payload matrix ran on September 29, 2026 (UTC), with the EC2 runner, AWS
PrivateLink endpoint, and PlanetScale Postgres database in Frankfurt. It
completed 10,000 paired iterations at each of six payload sizes.

- 120,000 timed queries: 60,000 public and 60,000 private
- 111,759,360,000 returned payload bytes (104.08 GiB)
- 0 errors or timeouts
- Approximately 55 minutes of wall-clock runtime
- Persistent database connections, randomized public/private order per pair
- Query: `SELECT repeat('x', $1)::text`

Paired deltas are `private - public`; negative values favor PrivateLink.

| Payload | Public p50 | Private p50 | Paired p50 delta | Private wins | Public p95 | Private p95 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 KiB | 1.658 ms | 1.917 ms | +0.257 ms | 6.12% | 1.915 ms | 2.160 ms |
| 16 KiB | 1.915 ms | 1.881 ms | -0.032 ms | 59.67% | 2.163 ms | 2.131 ms |
| 64 KiB | 2.321 ms | 2.465 ms | +0.139 ms | 20.49% | 2.649 ms | 2.758 ms |
| 256 KiB | 4.053 ms | 3.761 ms | -0.292 ms | 92.48% | 4.491 ms | 4.143 ms |
| 1 MiB | 11.038 ms | 10.034 ms | -1.019 ms | 96.35% | 12.399 ms | 11.095 ms |
| 4 MiB | 41.127 ms | 37.248 ms | -3.827 ms | 97.82% | 45.590 ms | 39.323 ms |

## Interpretation

For responses of 64 KiB or less, differences were below 0.3 ms and changed
direction between payload sizes. They are measurable with 10,000 pairs but too
small and inconsistent to support a general latency claim.

For 256 KiB and larger responses, the advantage grew approximately linearly
with response size. A linear fit over 256 KiB, 1 MiB, and 4 MiB produced:

- Public: 9.927 ms/MiB, approximately 100.7 MiB/s
- PrivateLink: 8.970 ms/MiB, approximately 111.5 MiB/s
- PrivateLink advantage: approximately 0.96 ms/MiB and 10.7% modeled throughput

At 4 MiB, PrivateLink improved marginal p50 by 3.879 ms, p95 by 6.267 ms,
and p99 by 4.805 ms. Its p99.9 was 1.328 ms worse, showing that rare client,
database, or scheduling stalls dominate the extreme tail regardless of route.

Neither route failed in 60,000 queries. This run therefore provides no evidence
that either route is more reliable. Testing transient failures would require a
longer observation window, repeated runs at different times, or controlled
congestion.

## Conclusion

For small, ordinary database responses in the same Frankfurt region,
PrivateLink did not materially reduce query latency. For large results it
provided a repeatable throughput advantage that saved roughly 1 ms per MiB in
this setup. Its primary value remains private connectivity and predictable
routing; latency became meaningful mainly for responses of hundreds of KiB or
several MiB.

## Limitations

- This is one AWS availability zone, one PlanetScale database, and one run.
- Public traffic was pinned to one current public IP; provider-side routing can
  change over time.
- The test isolates client-observed latency, not server execution time. Both
  paths executed the same query against the same database.
- Serialization, driver scanning, and client scheduling are present on both
  paths. Randomized paired ordering reduces systematic bias but does not remove
  shared client noise.
- Database plan, cluster size, and background load were not recorded, so exact
  numbers should not be generalized to other deployments.

## Raw data

The six gzip-compressed JSONL files under
[`data/2026-09-29-payload-matrix`](data/2026-09-29-payload-matrix) contain every
timed observation. Validate them with the accompanying SHA-256 manifest, then
analyze one or more decompressed files with `go run ./cmd/analyze`.
