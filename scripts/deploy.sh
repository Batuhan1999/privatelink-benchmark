#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key_path="${SSH_KEY_PATH:-$repo_dir/.secrets/benchmark_ed25519}"
env_path="${BENCHMARK_ENV_PATH:-$repo_dir/.env.benchmark}"

if [[ ! -f "$env_path" ]]; then
  echo "Missing $env_path. Copy .env.example and add the two PlanetScale DSNs." >&2
  exit 1
fi

runner_ip="$(terraform -chdir="$repo_dir/infra" output -raw runner_public_ip)"
endpoint_id="$(terraform -chdir="$repo_dir/infra" output -raw vpc_endpoint_id)"
endpoint_eni_id="$(
  terraform -chdir="$repo_dir/infra" output -json vpc_endpoint_network_interface_ids |
    jq -er 'if length == 1 then .[0] else error("expected one endpoint ENI") end'
)"

endpoint_ip="$(
  aws --profile privatelink-benchmark --region eu-central-1 ec2 describe-network-interfaces \
    --network-interface-ids "$endpoint_eni_id" \
    --query 'NetworkInterfaces[0].PrivateIpAddress' \
    --output text
)"

set -a
source "$env_path"
set +a
public_authority="${PUBLIC_DATABASE_URL##*@}"
public_host="${public_authority%%[:/?]*}"
private_authority="${PRIVATE_DATABASE_URL##*@}"
private_host="${private_authority%%[:/?]*}"

if [[ ! "$endpoint_id" =~ ^vpce-[a-f0-9]+$ ]]; then
  echo "Unexpected VPC endpoint ID: $endpoint_id" >&2
  exit 1
fi
if [[ ! "$endpoint_ip" =~ ^10\.42\.1\.[0-9]{1,3}$ ]]; then
  echo "Unexpected endpoint IP: $endpoint_ip" >&2
  exit 1
fi
if [[ ! "$private_host" =~ ^[a-z0-9.-]+\.private-pg\.psdb\.cloud$ ]]; then
  echo "Unexpected PlanetScale private hostname: $private_host" >&2
  exit 1
fi
if [[ ! "$public_host" =~ ^[a-z0-9.-]+\.pg\.psdb\.cloud$ ]]; then
  echo "Unexpected PlanetScale public hostname: $public_host" >&2
  exit 1
fi

mkdir -p "$repo_dir/bin"
(
  cd "$repo_dir"
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -o bin/benchmark-linux-arm64 ./cmd/benchmark
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -o bin/analyze-linux-arm64 ./cmd/analyze
)

ssh_opts=(-i "$key_path" -o StrictHostKeyChecking=accept-new)
public_ip="$(
  ssh "${ssh_opts[@]}" "ec2-user@$runner_ip" \
    "getent ahostsv4 '$public_host' | awk 'NR == 1 { print \$1 }'"
)"
if [[ ! "$public_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
  echo "Unexpected public endpoint IP: $public_ip" >&2
  exit 1
fi

ssh "${ssh_opts[@]}" "ec2-user@$runner_ip" \
  "sudo sed -i '/# privatelink-benchmark$/d' /etc/hosts"
printf '%s %s # privatelink-benchmark\n%s %s # privatelink-benchmark\n' \
  "$public_ip" "$public_host" "$endpoint_ip" "$private_host" | \
  ssh "${ssh_opts[@]}" "ec2-user@$runner_ip" 'sudo tee -a /etc/hosts >/dev/null'
resolved_private_ip="$(
  ssh "${ssh_opts[@]}" "ec2-user@$runner_ip" \
    "getent ahostsv4 '$private_host' | awk 'NR == 1 { print \$1 }'"
)"
if [[ "$resolved_private_ip" != "$endpoint_ip" ]]; then
  echo "Private hostname resolved to $resolved_private_ip, expected $endpoint_ip." >&2
  exit 1
fi

ssh "${ssh_opts[@]}" "ec2-user@$runner_ip" \
  'sudo mkdir -p ~/benchmark/results && sudo chown -R ec2-user:ec2-user ~/benchmark'
scp "${ssh_opts[@]}" \
  "$repo_dir/bin/benchmark-linux-arm64" \
  "$repo_dir/bin/analyze-linux-arm64" \
  "$repo_dir/scripts/run-suite.sh" \
  "$repo_dir/scripts/run-payload-matrix.sh" \
  "ec2-user@$runner_ip:~/benchmark/"
scp "${ssh_opts[@]}" "$env_path" "ec2-user@$runner_ip:~/benchmark/.env.benchmark"
ssh "${ssh_opts[@]}" "ec2-user@$runner_ip" \
  'chmod 700 ~/benchmark/benchmark-linux-arm64 ~/benchmark/analyze-linux-arm64 ~/benchmark/run-suite.sh ~/benchmark/run-payload-matrix.sh && chmod 600 ~/benchmark/.env.benchmark'

echo "Deployed benchmark to ec2-user@$runner_ip:~/benchmark"
echo "Pinned $public_host to its current public endpoint ($public_ip)"
echo "Pinned $private_host to PrivateLink endpoint $endpoint_id ($endpoint_ip)"
