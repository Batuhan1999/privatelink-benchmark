# Payload-matrix raw samples

These files contain the 120,000 observations summarized in
[`../../RESULTS.md`](../../RESULTS.md). Each gzip archive expands to JSON Lines
with the schema defined in [`../../internal/sample/sample.go`](../../internal/sample/sample.go).

| Payload bytes | Pairs | Archive |
|---:|---:|---|
| 1,024 | 10,000 | `payload-1024.jsonl.gz` |
| 16,384 | 10,000 | `payload-16384.jsonl.gz` |
| 65,536 | 10,000 | `payload-65536.jsonl.gz` |
| 262,144 | 10,000 | `payload-262144.jsonl.gz` |
| 1,048,576 | 10,000 | `payload-1048576.jsonl.gz` |
| 4,194,304 | 10,000 | `payload-4194304.jsonl.gz` |

Verify the archives from this directory:

```bash
shasum -a 256 -c SHA256SUMS
```

Analyze a file without modifying the checked-in archive:

```bash
gzip -dc payload-4194304.jsonl.gz > /tmp/payload-4194304.jsonl
go run ../../cmd/analyze \
  -input /tmp/payload-4194304.jsonl \
  -output /tmp/payload-4194304-summary.md
```

The samples contain timing metadata only—no DSNs, credentials, hostnames, IP
addresses, or query results.
