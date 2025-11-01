terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.59.0"
    }
  }
}


provider "aws" {
  region     = "us-east-2"
  access_key = var.my-access_key
  secret_key = var.my-secret_key
}

