terraform {
  backend "s3" {
    bucket         = "forsyth-minecraft-terraform-state"
    key            = "minecraft-terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

variable "your_region" {
  type        = string
  description = "AWS region for the server."
  default     = "us-east-1"
}

variable "your_ami" {
  type        = string
  description = "AMI ID for the instance."
  default     = "ami-0c3fd0f5d33134a76"
}

variable "your_ip" {
  type        = string
  description = "IP for admin access."
  default     = "0.0.0.0/0"
}

variable "your_public_key" {
  type        = string
  description = "Public SSH key."
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD"
}

variable "mojang_server_url" {
  type        = string
  description = "Minecraft server JAR download URL."
  default     = "https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar"
}

provider "aws" {
  profile = "default"
  region  = var.your_region
}

# Create VPC
resource "aws_vpc" "minecraft_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Minecraft-VPC"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "minecraft_igw" {
  vpc_id = aws_vpc.minecraft_vpc.id

  tags = {
    Name = "Minecraft-IGW"
  }
}

# Create a Public Subnet
resource "aws_subnet" "minecraft_public_subnet" {
  vpc_id                  = aws_vpc.minecraft_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "Minecraft-Public-Subnet"
  }
}

# Create Route Table
resource "aws_route_table" "minecraft_route_table" {
  vpc_id = aws_vpc.minecraft_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.minecraft_igw.id
  }

  tags = {
    Name = "Minecraft-Route-Table"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "minecraft_rta" {
  subnet_id      = aws_subnet.minecraft_public_subnet.id
  route_table_id = aws_route_table.minecraft_route_table.id
}

# Security Group for Minecraft
resource "aws_security_group" "minecraft" {
  vpc_id = aws_vpc.minecraft_vpc.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  ingress {
    description = "Allow Minecraft"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Minecraft-SG"
  }
}

# Key Pair
# resource "aws_key_pair" "home" {
#   key_name   = "Home"
#   public_key = var.your_public_key
# }

# Minecraft EC2 Instance
resource "aws_instance" "minecraft" {
  ami                         = var.your_ami
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.minecraft_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  associate_public_ip_address = true
  # key_name                    = aws_key_pair.home.key_name
  user_data                   = <<-EOF
    #!/bin/bash
    sudo yum -y update
    sudo rpm --import https://yum.corretto.aws/corretto.key
    sudo curl -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
    sudo yum install -y java-21-amazon-corretto-devel.x86_64
    wget -O server.jar ${var.mojang_server_url}
    java -Xmx1024M -Xms1024M -jar server.jar nogui
    sed -i 's/eula=false/eula=true/' eula.txt
    java -Xmx1024M -Xms1024M -jar server.jar nogui
  EOF

  tags = {
    Name = "Minecraft-Instance"
  }
}

output "instance_ip_addr" {
  value = aws_instance.minecraft.public_ip
}
