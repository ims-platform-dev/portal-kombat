output "role_arn" {
  description = "ARN of the Karpenter node IAM role"
  value       = aws_iam_role.karpenter_node.arn
}

output "role_name" {
  description = "Name of the Karpenter node IAM role"
  value       = aws_iam_role.karpenter_node.name
}

output "instance_profile_arn" {
  description = "ARN of the Karpenter node instance profile"
  value       = aws_iam_instance_profile.karpenter_node.arn
}

output "instance_profile_name" {
  description = "Name of the Karpenter node instance profile"
  value       = aws_iam_instance_profile.karpenter_node.name
}
