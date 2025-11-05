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

# Karpenter Controller
output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role"
  value       = module.karpenter_controller_irsa.role_arn
}

output "karpenter_controller_role_name" {
  description = "Name of the Karpenter controller IAM role"
  value       = module.karpenter_controller_irsa.role_name
}

# Karpenter Node
output "karpenter_node_role_arn" {
  description = "ARN of the Karpenter node IAM role"
  value       = module.karpenter_node_role.role_arn
}

output "karpenter_node_role_name" {
  description = "Name of the Karpenter node IAM role"
  value       = module.karpenter_node_role.role_name
}

output "karpenter_node_instance_profile_arn" {
  description = "ARN of the Karpenter node instance profile"
  value       = module.karpenter_node_role.instance_profile_arn
}

output "karpenter_node_instance_profile_name" {
  description = "Name of the Karpenter node instance profile"
  value       = module.karpenter_node_role.instance_profile_name
}

# Karpenter Interruption Queue
output "karpenter_interruption_queue_url" {
  description = "URL of the Karpenter interruption queue"
  value       = module.karpenter_interruption_queue.queue_url
}

output "karpenter_interruption_queue_arn" {
  description = "ARN of the Karpenter interruption queue"
  value       = module.karpenter_interruption_queue.queue_arn
}

output "karpenter_interruption_queue_name" {
  description = "Name of the Karpenter interruption queue"
  value       = module.karpenter_interruption_queue.queue_name
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
