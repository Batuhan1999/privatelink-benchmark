#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key_path="${SSH_KEY_PATH:-$repo_dir/.secrets/benchmark_ed25519}"
runner_ip="$(terraform -chdir="$repo_dir/infra" output -raw runner_public_ip)"
ssh_opts=(-i "$key_path" -o StrictHostKeyChecking=accept-new)

remote_env=""
for name in ITERATIONS DURATION_PER_MODE INTERVAL WARMUP PAYLOAD_BYTES; do
  if [[ -n "${!name:-}" ]]; then
    printf -v quoted '%q' "${!name}"
    remote_env+="$name=$quoted "
  fi
done

ssh "${ssh_opts[@]}" "ec2-user@$runner_ip" "cd ~/benchmark && ${remote_env}./run-suite.sh"
