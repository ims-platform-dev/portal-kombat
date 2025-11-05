output "role_arn" {
  description = "ARN of the External DNS IAM role"
  value       = aws_iam_role.external_dns.arn
}

output "role_name" {
  description = "Name of the External DNS IAM role"
  value       = aws_iam_role.external_dns.name
}
