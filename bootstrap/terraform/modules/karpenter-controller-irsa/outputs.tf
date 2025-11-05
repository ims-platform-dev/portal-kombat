output "role_arn" {
  description = "ARN of the Karpenter controller IAM role"
  value       = aws_iam_role.karpenter_controller.arn
}

output "role_name" {
  description = "Name of the Karpenter controller IAM role"
  value       = aws_iam_role.karpenter_controller.name
}
