terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Пізніше переведемо state в S3
}

provider "aws" {
  region = "eu-north-1"
}

# Security Group
resource "aws_security_group" "k3s" {
  name        = "k3s-sg"
  description = "K3s node security group"

  ingress {
    description = "SSH from home"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k3s-sg", Project = "SysOps-to-DevOps" }
}

# EC2 t2.micro — Free Tier
resource "aws_instance" "k3s" {
  ami           = "ami-075449515af5df0d1"  # Ubuntu 22.04 eu-north-1
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.k3s.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = { Name = "k3s-node", Project = "SysOps-to-DevOps" }
}

# Elastic IP — щоб IP не змінювався
resource "aws_eip" "k3s" {
  instance = aws_instance.k3s.id
  domain   = "vpc"
  tags     = { Name = "k3s-eip" }
}

output "public_ip"  { value = aws_eip.k3s.public_ip }
output "instance_id" { value = aws_instance.k3s.id }
