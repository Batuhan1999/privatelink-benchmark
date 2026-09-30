provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region

  default_tags {
    tags = {
      Project   = "privatelink-benchmark"
      ManagedBy = "terraform"
    }
  }
}

data "http" "operator_ip" {
  url = "https://checkip.amazonaws.com/"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  operator_cidr = "${chomp(data.http.operator_ip.response_body)}/32"
  common_tags = {
    Project = "privatelink-benchmark"
  }
}

resource "aws_vpc" "benchmark" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "privatelink-benchmark" })
}

resource "aws_subnet" "runner" {
  vpc_id                  = aws_vpc.benchmark.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "privatelink-benchmark-runner" })
}

resource "aws_internet_gateway" "benchmark" {
  vpc_id = aws_vpc.benchmark.id
  tags   = merge(local.common_tags, { Name = "privatelink-benchmark" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.benchmark.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.benchmark.id
  }

  tags = merge(local.common_tags, { Name = "privatelink-benchmark-public" })
}

resource "aws_route_table_association" "runner" {
  subnet_id      = aws_subnet.runner.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "runner" {
  name        = "privatelink-benchmark-runner"
  description = "SSH from the benchmark operator and outbound test traffic"
  vpc_id      = aws_vpc.benchmark.id

  ingress {
    description = "SSH from current operator IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.operator_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "privatelink-benchmark-runner" })
}

resource "aws_security_group" "endpoint" {
  name        = "privatelink-benchmark-endpoint"
  description = "PlanetScale Postgres PrivateLink endpoint"
  vpc_id      = aws_vpc.benchmark.id

  ingress {
    description     = "Postgres from benchmark runner"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.runner.id]
  }

  ingress {
    description     = "PgBouncer from benchmark runner"
    from_port       = 6432
    to_port         = 6432
    protocol        = "tcp"
    security_groups = [aws_security_group.runner.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "privatelink-benchmark-endpoint" })
}

resource "aws_vpc_endpoint" "planetscale" {
  vpc_id             = aws_vpc.benchmark.id
  service_name       = var.planetscale_private_service_name
  vpc_endpoint_type  = "Interface"
  subnet_ids         = [aws_subnet.runner.id]
  security_group_ids = [aws_security_group.endpoint.id]
  # Private DNS needs broader Route 53 access; deploy.sh pins the endpoint ENI instead.
  private_dns_enabled = false

  tags = merge(local.common_tags, { Name = "privatelink-benchmark-planetscale" })
}

resource "aws_key_pair" "runner" {
  key_name   = "privatelink-benchmark"
  public_key = file(var.ssh_public_key_path)

  tags = local.common_tags
}

resource "aws_instance" "runner" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  availability_zone           = var.availability_zone
  subnet_id                   = aws_subnet.runner.id
  vpc_security_group_ids      = [aws_security_group.runner.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.runner.key_name
  monitoring                  = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    dnf install -y bind-utils jq tcpdump
    install -d -o ec2-user -g ec2-user /home/ec2-user/benchmark/results
  EOF

  tags = merge(local.common_tags, { Name = "privatelink-benchmark-runner" })

  depends_on = [aws_route_table_association.runner]
}
