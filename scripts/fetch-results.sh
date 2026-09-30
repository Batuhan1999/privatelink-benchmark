#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key_path="${SSH_KEY_PATH:-$repo_dir/.secrets/benchmark_ed25519}"
runner_ip="$(terraform -chdir="$repo_dir/infra" output -raw runner_public_ip)"
mkdir -p "$repo_dir/results"
scp -r -i "$key_path" -o StrictHostKeyChecking=accept-new \
  "ec2-user@$runner_ip:~/benchmark/results/." "$repo_dir/results/"

echo "Results copied to $repo_dir/results"
