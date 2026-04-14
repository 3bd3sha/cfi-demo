# Terraform Backend Configuration
# Remote state storage with locking to prevent conflicts between team members

terraform {
  required_version = ">= 1.0"
  
  # S3 backend for state storage (AWS)
  backend "s3" {
    bucket         = "cfi-terraform-state"
    key            = "monitoring/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"  # State locking
    
    # Prevent accidental deletion
    # lifecycle {
    #   prevent_destroy = true
    # }
  }
  
  # Alternative: Azure backend (uncomment if using Azure)
  # backend "azurerm" {
  #   resource_group_name  = "cfi-terraform-state-rg"
  #   storage_account_name = "cfitfstate"
  #   container_name       = "tfstate"
  #   key                  = "monitoring.tfstate"
  # }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Provider configurations
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "CFI Trading Platform"
      ManagedBy   = "Terraform"
      Environment = var.environment
      CostCenter  = "Trading Operations"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
