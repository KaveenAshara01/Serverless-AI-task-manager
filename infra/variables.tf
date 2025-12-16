terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy to"
  default     = "us-east-1"
}

variable "table_name" {
  description = "DynamoDB table name"
  default     = "tasks"
}

variable "hf_api_key" {
  description = "HuggingFace API key (set via -var or terraform.tfvars). Do NOT check into source control."
  type        = string
  sensitive   = true
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  default     = "nodejs18.x"
}
