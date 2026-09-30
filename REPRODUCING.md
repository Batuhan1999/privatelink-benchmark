# Reproducing the benchmark

## Requirements

- A PlanetScale Postgres database and private endpoint service in Frankfurt
- An isolated AWS account or sandbox with access to `eu-central-1`
- Terraform 1.8+, Go 1.24+, AWS CLI v2, `jq`, and SSH
- An AWS CLI profile named `privatelink-benchmark` with permission to manage
  the EC2 resources in [`infra`](infra)

The topology creates one `c7g.large` runner and one single-AZ interface
endpoint. Both are billable. It is a benchmark setup, not a production
high-availability design.

## Configuration

```bash
mkdir -p .secrets
ssh-keygen -t ed25519 -N '' -f .secrets/benchmark_ed25519
cp infra/terraform.tfvars.example infra/terraform.tfvars
cp .env.example .env.benchmark
```

Set the PlanetScale Private Service Name in `infra/terraform.tfvars`.

Use the same role, branch, database, port, and TLS settings in both DSNs in
`.env.benchmark`. Only the public/private hostnames should differ. Database
credentials never enter Terraform state.

## Provision

```bash
make infra-init
make infra-plan
terraform -chdir=infra show benchmark.tfplan
make infra-apply
make deploy
```

`make run` runs the TCP, cold-connect, warm-query, and payload suite in the SSH
session. `make run-payloads` starts the published payload matrix as a detached
process on the runner, so it continues if the local SSH session ends.

```bash
make run-payloads
```

The defaults are 10,000 pairs per response size, a 50 ms target interval, and
payloads from 1 KiB to 4 MiB. They can be overridden without editing scripts:

```bash
ITERATIONS=20000 PAYLOAD_SIZES='1024 1048576 4194304' make run-payloads
```

Fetch completed results with:

```bash
make fetch
```

## Cleanup

```bash
make infra-destroy
```

Verify the AWS account after destruction and remove any dedicated IAM identity
that is no longer needed.

## Development

```bash
make check
```

DSNs, SSH keys, Terraform state and plans, binaries, and fetched results are
ignored by Git.
