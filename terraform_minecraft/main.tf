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

provider "aws" {
  profile = "default"
  region  = var.your_region
}


variable "your_ami" {
  type        = string
  description = "Ubuntu AMI String"
  default     = "ami-0e2c8caa4b6378d8c"
}

variable "your_ip" {
  type        = string
  description = "IP for admin access."
  default     = "0.0.0.0/0"
}

variable "your_public_key" {
  type        = string
  description = "Public SSH key."
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDP1/245AkQW3B4t/Ww6Vhvruuw9psYqoAr+Z722MDTUec6j+0SfxloeuuBcE+bsR+B/q3X36u02hhGJIjvgH2jGTLMFEo42WvA+N23fidzC1u9/FH+4DB+eNI0JZGCJGHinpRS6mm8oNy+4dwqtQ5i3Kpz+fsGa5vs7d+T0+8GkqV02lDXpAiGMvxAQN3paYW7OuXEThjkErhu+73/vsE1OSudNQwJKNHfU15tvtYCFnCtGhK7fjLhyH/39QG4ShxXr9FSIz3pB/omQ8wwkYiBghyfTra97qx8jX8aQ/NWqKypIASKLm6vMTqy6/ZOQEETk7gQrCHWBlocqcmId4PH rober@forsyth"
}

variable "mojang_server_url" {
  type        = string
  description = "Minecraft server JAR download URL."
  default     = "https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar"
}

variable "s3_backup_bucket" {
  type        = string
  description = "S3 bucket for backups."
  default     = "forsyth-minecraft-world-backup"
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
resource "aws_key_pair" "home" {
  key_name   = "Home"
  public_key = var.your_public_key
}

# Minecraft EC2 Instance
resource "aws_instance" "minecraft" {
  ami                         = var.your_ami
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.minecraft_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.minecraft_s3_profile.name
  key_name                    = aws_key_pair.home.key_name
  user_data                   = <<-EOF
    #!/bin/bash
    set -e

    # Update system and install dependencies
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt-get install -y curl wget openjdk-21-jdk awscli

    # Create necessary directories
    sudo mkdir -p /opt/minecraft/server
    sudo mkdir -p /opt/minecraft/backups
    sudo chown -R ubuntu:ubuntu /opt/minecraft

    # Fetch the latest backup from S3
    BACKUP_BUCKET="${var.s3_backup_bucket}"
    BACKUP_FILE=$(aws s3 ls s3://$BACKUP_BUCKET/ --recursive | sort | tail -n 1 | awk '{print $4}')
    if [ -n "$BACKUP_FILE" ]; then
        aws s3 cp s3://$BACKUP_BUCKET/$BACKUP_FILE /opt/minecraft/backups/latest-backup.tar.gz
        tar -xzf /opt/minecraft/backups/latest-backup.tar.gz -C /opt/minecraft/server
    else
        echo "No backup found. Starting with a fresh server."
    fi

    # Download and configure Minecraft server if no backup exists
    if [ ! -f "/opt/minecraft/server/server.jar" ]; then
        cd /opt/minecraft/server
        wget -O server.jar ${var.mojang_server_url}
        java -Xmx1024M -Xms1024M -jar server.jar nogui || true
        sed -i 's/eula=false/eula=true/' eula.txt
    fi

    # Start the server
    cd /opt/minecraft/server
    java -Xmx1024M -Xms1024M -jar server.jar nogui &

    # Download the backup script
    curl -o /opt/minecraft/backup.sh https://raw.githubusercontent.com/Forsyth-Creations/terraform-minecraft/main/backup.sh
    chmod +x /opt/minecraft/backup.sh

    # Set up cron job for regular backups every two minutes
    (crontab -l 2>/dev/null; echo "*/2 * * * * /opt/minecraft/backup.sh") | crontab -

  EOF

  tags = {
    Name = "Minecraft-Instance"
  }

  depends_on = [aws_iam_instance_profile.minecraft_s3_profile]
}




output "instance_ip_addr" {
  value = aws_instance.minecraft.public_ip
}

resource "aws_s3_bucket" "minecraft_backup" {
  bucket        = var.s3_backup_bucket

  tags = {
    Name = "Minecraft-World-Backup"
  }
}

resource "aws_iam_role" "minecraft_s3_role" {
  name = "forsyth_minecraft_backup_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "minecraft_s3_policy" {
  name = "minecraft-s3-backup-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = [
        aws_s3_bucket.minecraft_backup.arn,
        "${aws_s3_bucket.minecraft_backup.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "minecraft_s3_role_attachment" {
  role       = aws_iam_role.minecraft_s3_role.name
  policy_arn = aws_iam_policy.minecraft_s3_policy.arn
}

resource "aws_iam_instance_profile" "minecraft_s3_profile" {
  name = "minecraft-s3-backup-profile"
  role = aws_iam_role.minecraft_s3_role.name
}