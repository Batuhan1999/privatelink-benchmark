#!/usr/bin/env bash
set -euo pipefail

run_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$run_dir"

set -a
source .env.benchmark
set +a

iterations="${ITERATIONS:-10000}"
duration_per_mode="${DURATION_PER_MODE:-}"
interval="${INTERVAL:-100ms}"
warmup="${WARMUP:-100}"
payload_bytes="${PAYLOAD_BYTES:-1024}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
result_dir="results/$stamp"
mkdir -p "$result_dir"

common=(--interval "$interval" --warmup "$warmup")
if [[ -n "$duration_per_mode" ]]; then
  common+=(--iterations 0 --duration "$duration_per_mode")
else
  common+=(--iterations "$iterations")
fi

./benchmark-linux-arm64 --mode tcp "${common[@]}" --output "$result_dir/tcp.jsonl"
./benchmark-linux-arm64 --mode warm "${common[@]}" --output "$result_dir/warm.jsonl"
./benchmark-linux-arm64 --mode cold "${common[@]}" --output "$result_dir/cold.jsonl"
./benchmark-linux-arm64 --mode payload --payload-bytes "$payload_bytes" "${common[@]}" --output "$result_dir/payload.jsonl"

./analyze-linux-arm64 \
  --input "$result_dir/tcp.jsonl" \
  --input "$result_dir/warm.jsonl" \
  --input "$result_dir/cold.jsonl" \
  --input "$result_dir/payload.jsonl" \
  --output "$result_dir/summary.md" | tee "$result_dir/summary.stdout.md"

echo "$result_dir"
