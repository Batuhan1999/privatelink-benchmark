output "runner_public_ip" {
  description = "Public IP used only for SSH administration."
  value       = aws_instance.runner.public_ip
}

output "runner_private_ip" {
  description = "Private IP of the benchmark runner."
  value       = aws_instance.runner.private_ip
}

output "vpc_endpoint_id" {
  description = "PlanetScale interface endpoint ID."
  value       = aws_vpc_endpoint.planetscale.id
}

output "vpc_endpoint_dns_entries" {
  description = "DNS entries assigned to the interface endpoint."
  value       = aws_vpc_endpoint.planetscale.dns_entry
}

output "vpc_endpoint_network_interface_ids" {
  description = "Network interfaces whose private IPs carry PlanetScale traffic."
  value       = aws_vpc_endpoint.planetscale.network_interface_ids
}

output "ssh_command" {
  description = "Command for reaching the runner."
  value       = "ssh -i ../.secrets/benchmark_ed25519 ec2-user@${aws_instance.runner.public_ip}"
}
