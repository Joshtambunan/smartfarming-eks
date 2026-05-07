# ============================================================
# terraform/variables.tf
# WAJIB diedit sebelum terraform apply!
# ============================================================

variable "aws_region" {
  description = "Region AWS tempat semua resource dibuat"
  type        = string
  default     = "ap-southeast-1"   # Singapore – paling dekat ke Indonesia
}

variable "project_name" {
  description = "Nama project, dipakai sebagai prefix semua resource"
  type        = string
  default     = "smartfarming"
}

variable "environment" {
  description = "Nama environment (dev / staging / prod)"
  type        = string
  default     = "dev"
}

variable "owner_name" {
  description = "Nama pemilik / NIM untuk tag resource"
  type        = string
  default     = "GANTI_DENGAN_NIM_KAMU"   # ← GANTI INI
}

variable "alert_email" {
  description = "Email untuk menerima notifikasi budget"
  type        = string
  default     = "GANTI@email.com"          # ← GANTI INI
}

# ── Network ─────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block untuk VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List AZ yang dipakai"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

# ── EKS ─────────────────────────────────────────────────────

variable "eks_version" {
  description = "Versi Kubernetes untuk EKS cluster"
  type        = string
  default     = "1.29"
}

variable "node_instance_type" {
  description = "Tipe EC2 untuk EKS worker nodes"
  type        = string
  default     = "t3.medium"   # Hemat credit: t3.medium cukup untuk project
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

# ── RDS ─────────────────────────────────────────────────────

variable "db_name" {
  type    = string
  default = "smartfarming"
}

variable "db_username" {
  type    = string
  default = "farmuser"
}

# ── Cost ─────────────────────────────────────────────────────

variable "monthly_budget_usd" {
  description = "Batas budget bulanan dalam USD"
  type        = string
  default     = "50"
}
