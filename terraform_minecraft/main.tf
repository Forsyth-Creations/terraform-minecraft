terraform {
  backend "s3" {
    bucket         = "forsyth-minecraft-terraform-state"   # Replace with your bucket name
    key            = "minecraft-terraform.tfstate"       # Path to the state file in the bucket
    region         = "us-east-1"               # Specify the appropriate region
    encrypt        = true                      # Optional: Enable server-side encryption
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
  description = "Where you want your server to be. The options are here https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html."
  default    = "us-east-1"
}

variable "your_ami" {
  type        = string
  description = "Insert AMI for your instance. Please refer to default Amazon Linux AMIs for every region. Find your AMI here https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami.html"
  default    = "ami-0c3fd0f5d33134a76"
}

variable "your_ip" {
  type        = string
  description = "Only this IP will be able to administer the server. Find it here https://www.whatsmyip.org/."
  default    = "0.0.0.0/0"
}

variable "your_public_key" {
  type        = string
  description = "This will be in ~/.ssh/id_rsa.pub by default."
  default    = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD"
}

variable "mojang_server_url" {
  type        = string
  description = "Copy the server download link from here https://www.minecraft.net/en-us/download/server/."
  default = "https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar"
}

provider "aws" {
  profile = "default"
  region  = var.your_region
}

resource "aws_security_group" "minecraft" {
  ingress {
    description = "Receive SSH from home."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.your_ip}"]
  }
  ingress {
    description = "Receive Minecraft from everywhere."
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Send everywhere."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Minecraft"
  }
}

resource "aws_key_pair" "home" {
  key_name   = "Home"
  public_key = var.your_public_key
}

resource "aws_instance" "minecraft" {
  ami                         = var.your_ami
  instance_type               = "t3.small"
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.home.key_name
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
    Name = "Minecraft"
  }
}

output "instance_ip_addr" {
  value = aws_instance.minecraft.public_ip
}
