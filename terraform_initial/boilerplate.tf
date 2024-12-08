# This will be used to make the following:
# - Two ECR repositories to store the frontend and backend docker images

# Create an AWS Provider to 
# facilitate the creation of AWS resources
terraform {
  backend "s3" {
    bucket         = "padua-terraform-state"   # Replace with your bucket name
    key            = "boilerplate-terraform.tfstate"       # Path to the state file in the bucket
    region         = "us-east-1"               # Specify the appropriate region
    encrypt        = true                      # Optional: Enable server-side encryption
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

}

provider "aws" {
  region = "us-east-1"
}