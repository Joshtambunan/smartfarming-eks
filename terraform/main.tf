# ============================================================
# terraform/main.tf – Root Module
#
# File ini memanggil semua module untuk membuat infrastruktur
# AWS secara lengkap: VPC, ECR, EKS, S3, RDS, IRSA.
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }

  # Remote state – simpan tfstate di S3 agar bisa diakses tim
  # GANTI bucket name sesuai yang kamu buat di FASE 2 Step 2.1
  backend "s3" {
    bucket         = "smartfarming-tfstate-GANTI_INI"
    key            = "eks/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "smartfarming-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  # Tag default untuk semua resource yang dibuat Terraform
  default_tags {
    tags = {
      Project     = "smartfarming"
      Environment = var.environment
      Owner       = var.owner_name
      CostCenter  = "CC-AGRI-01"
      ManagedBy   = "terraform"
    }
  }
}

# ── 1. VPC ──────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

# ── 2. ECR Repositories ─────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
  services     = ["storage", "farmdata", "frontend"]
}

# ── 3. EKS Cluster ──────────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  eks_version        = var.eks_version
  node_instance_type = var.node_instance_type
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size
}

# ── 4. S3 Bucket (storage-service) ──────────────────────────
module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
}

# ── 5. RDS PostgreSQL (farm-data-service) ───────────────────
module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  db_name            = var.db_name
  db_username        = var.db_username
  eks_sg_id          = module.eks.node_security_group_id
}

# ── 6. IRSA (IAM Roles for Service Accounts) ────────────────
module "irsa" {
  source = "./modules/irsa"

  project_name     = var.project_name
  eks_oidc_url     = module.eks.oidc_provider_url
  eks_oidc_arn     = module.eks.oidc_provider_arn
  s3_bucket_arn    = module.s3.bucket_arn
  rds_resource_id  = module.rds.db_resource_id

  # Namespace dan service account name harus cocok dengan manifest k8s/
  storage_namespace   = "storage"
  storage_sa_name     = "storage-service-sa"
  farmdata_namespace  = "farm-data"
  farmdata_sa_name    = "farm-data-service-sa"
  frontend_namespace  = "frontend"
  frontend_sa_name    = "frontend-service-sa"
}

# ── 7. AWS Budget & Alerts ───────────────────────────────────
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
