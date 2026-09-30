#!/usr/bin/env bash
set -euo pipefail

run_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$run_dir"

set -a
source .env.benchmark
set +a

iterations="${ITERATIONS:-10000}"
interval="${INTERVAL:-50ms}"
warmup="${WARMUP:-50}"
timeout="${TIMEOUT:-15s}"
payload_sizes="${PAYLOAD_SIZES:-1024 16384 65536 262144 1048576 4194304}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
result_dir="results/${stamp}-payload-matrix"
mkdir -p "$result_dir"

read -r -a sizes <<<"$payload_sizes"

{
  echo "# Payload matrix benchmark"
  echo
  echo "- Started (UTC): $stamp"
  echo "- Iterations per path and payload size: $iterations"
  echo "- Interval: $interval"
  echo "- Warmup pairs: $warmup"
  echo "- Timeout: $timeout"
  echo "- Payload sizes (bytes): $payload_sizes"
} >"$result_dir/index.md"

printf 'payload_bytes\titerations_per_path\tinterval\tresult_file\n' >"$result_dir/manifest.tsv"

for payload_bytes in "${sizes[@]}"; do
  output="$result_dir/payload-${payload_bytes}.jsonl"
  summary="$result_dir/summary-${payload_bytes}.md"

  echo "Starting payload size ${payload_bytes} bytes at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ./benchmark-linux-arm64 \
    --mode payload \
    --payload-bytes "$payload_bytes" \
    --iterations "$iterations" \
    --interval "$interval" \
    --warmup "$warmup" \
    --timeout "$timeout" \
    --output "$output"

  ./analyze-linux-arm64 --input "$output" --output "$summary" >/dev/null
  printf '%s\t%s\t%s\t%s\n' "$payload_bytes" "$iterations" "$interval" "$output" >>"$result_dir/manifest.tsv"

  {
    echo
    echo "---"
    echo
    echo "## ${payload_bytes} bytes"
    echo
    cat "$summary"
  } >>"$result_dir/index.md"

  echo "Completed payload size ${payload_bytes} bytes at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
done

date -u +%Y-%m-%dT%H:%M:%SZ >"$result_dir/COMPLETE"
echo "$result_dir"
