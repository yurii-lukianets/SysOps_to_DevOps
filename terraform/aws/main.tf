terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket       = "sysops-devops-tfstate-056885487909"
    key          = "aws/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-north-1"
}

data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

locals {
  my_ip       = "176.36.254.118/32"
  cf_ipv4     = ["173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
    "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
    "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
    "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22"]
}

resource "aws_security_group" "k3s" {
  name        = "k3s-sg"
  description = "K3s node security group"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  ingress {
    description = "HTTP - Cloudflare only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.cf_ipv4
  }

  ingress {
    description = "HTTPS - Cloudflare only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.cf_ipv4
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "k3s-sg"
    Project = "SysOps-to-DevOps"
  }
}

resource "aws_key_pair" "k3s" {
  key_name   = "k3s-key"
  public_key = file("${path.module}/id_ed25519.pub")

  tags = {
    Name    = "k3s-key"
    Project = "SysOps-to-DevOps"
  }
}

resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.k3s.id]
  key_name               = aws_key_pair.k3s.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name    = "k3s-node"
    Project = "SysOps-to-DevOps"
  }
}

resource "aws_eip" "k3s" {
  instance = aws_instance.k3s.id
  domain   = "vpc"
  tags = {
    Name = "k3s-eip"
  }
}

output "public_ip" {
  value = aws_eip.k3s.public_ip
}

output "instance_id" {
  value = aws_instance.k3s.id
}
