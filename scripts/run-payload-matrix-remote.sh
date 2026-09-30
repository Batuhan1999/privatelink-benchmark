#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key_path="${SSH_KEY_PATH:-$repo_dir/.secrets/benchmark_ed25519}"
runner_ip="$(terraform -chdir="$repo_dir/infra" output -raw runner_public_ip)"
ssh_opts=(-i "$key_path" -o StrictHostKeyChecking=accept-new)

remote_env=()
for name in ITERATIONS INTERVAL WARMUP TIMEOUT PAYLOAD_SIZES; do
  if [[ -n "${!name:-}" ]]; then
    remote_env+=("$name=${!name}")
  fi
done

env_command=""
if ((${#remote_env[@]} > 0)); then
  printf -v env_command '%q ' "${remote_env[@]}"
fi
ssh "${ssh_opts[@]}" "ec2-user@$runner_ip" \
  "cd ~/benchmark && nohup env ${env_command}./run-payload-matrix.sh >payload-matrix.log 2>&1 </dev/null & echo \$!"

echo "Payload matrix started on $runner_ip. Fetch results after it completes with: make fetch"
