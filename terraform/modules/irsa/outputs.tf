output "storage_role_arn"  { value = aws_iam_role.storage_service.arn }
output "farmdata_role_arn" { value = aws_iam_role.farmdata_service.arn }
output "frontend_role_arn" { value = aws_iam_role.frontend_service.arn }
