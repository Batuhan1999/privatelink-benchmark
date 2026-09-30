variable "aws_profile" {
  description = "Local AWS CLI profile used by Terraform."
  type        = string
  default     = "privatelink-benchmark"
}

variable "aws_region" {
  description = "AWS region for both the runner and PlanetScale database."
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = var.aws_region == "eu-central-1"
    error_message = "This benchmark is intentionally restricted to Frankfurt (eu-central-1)."
  }
}

variable "availability_zone" {
  description = "Frankfurt AZ used by the runner and the single-AZ benchmark endpoint."
  type        = string
  default     = "eu-central-1a"
}

variable "planetscale_private_service_name" {
  description = "Private Service Name copied from the PlanetScale Postgres role details."
  type        = string

  validation {
    condition     = startswith(var.planetscale_private_service_name, "com.amazonaws.vpce.eu-central-1.vpce-svc-")
    error_message = "Use the Frankfurt Private Service Name from PlanetScale role details."
  }
}

variable "ssh_public_key_path" {
  description = "Absolute path to the benchmark runner SSH public key."
  type        = string
  default     = "../.secrets/benchmark_ed25519.pub"
}

variable "instance_type" {
  description = "Non-burstable ARM instance used for stable latency measurements."
  type        = string
  default     = "c7g.large"
}
