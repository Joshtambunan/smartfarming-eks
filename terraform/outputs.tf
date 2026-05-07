# ============================================================
# terraform/outputs.tf
# Nilai penting yang tampil setelah terraform apply selesai.
# Catat nilai ini untuk dipakai di langkah selanjutnya.
# ============================================================

output "eks_cluster_name" {
  description = "Nama EKS cluster – dipakai untuk aws eks update-kubeconfig"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint API server EKS"
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_url" {
  description = "OIDC provider URL – dipakai di trust policy IAM untuk IRSA"
  value       = module.eks.oidc_provider_url
}

output "ecr_storage_url" {
  description = "ECR URL untuk storage-service"
  value       = module.ecr.repository_urls["storage"]
}

output "ecr_farmdata_url" {
  description = "ECR URL untuk farm-data-service"
  value       = module.ecr.repository_urls["farmdata"]
}

output "ecr_frontend_url" {
  description = "ECR URL untuk frontend-service"
  value       = module.ecr.repository_urls["frontend"]
}

output "s3_bucket_name" {
  description = "Nama S3 bucket untuk storage-service"
  value       = module.s3.bucket_name
}

output "rds_endpoint" {
  description = "Endpoint RDS PostgreSQL untuk farm-data-service"
  value       = module.rds.db_endpoint
  sensitive   = true   # Disembunyikan di log, tapi bisa diakses via: terraform output rds_endpoint
}

output "irsa_storage_role_arn" {
  description = "IAM Role ARN untuk storage-service (masukkan ke k8s serviceaccount annotation)"
  value       = module.irsa.storage_role_arn
}

output "irsa_farmdata_role_arn" {
  description = "IAM Role ARN untuk farm-data-service"
  value       = module.irsa.farmdata_role_arn
}

output "irsa_frontend_role_arn" {
  description = "IAM Role ARN untuk frontend-service"
  value       = module.irsa.frontend_role_arn
}

output "kubectl_config_command" {
  description = "Command untuk setup kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
