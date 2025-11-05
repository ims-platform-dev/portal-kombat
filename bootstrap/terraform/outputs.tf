# ============================================================================
# Outputs
# ============================================================================

# External DNS
output "external_dns_role_arn" {
  description = "ARN of the External DNS IAM role"
  value       = module.external_dns_irsa.role_arn
}

output "external_dns_role_name" {
  description = "Name of the External DNS IAM role"
  value       = module.external_dns_irsa.role_name
}

# Cluster Information
output "cluster_name" {
  description = "EKS cluster name"
  value       = var.cluster_name
}

output "cluster_vpc_id" {
  description = "VPC ID of the EKS cluster"
  value       = data.aws_vpc.cluster_vpc.id
}

output "cluster_subnet_ids" {
  description = "Subnet IDs tagged for the EKS cluster"
  value       = data.aws_subnets.cluster_subnets.ids
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = data.aws_security_group.cluster_sg.id
}
