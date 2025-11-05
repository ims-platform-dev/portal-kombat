# ============================================================================
# Karpenter Tags - Subnet and Security Group Tagging
# ============================================================================

# Tag subnets for Karpenter discovery
resource "aws_ec2_tag" "subnet_karpenter_discovery" {
  for_each = toset(var.subnet_ids)

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# Tag security groups for Karpenter discovery
resource "aws_ec2_tag" "security_group_karpenter_discovery" {
  for_each = var.security_group_ids

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
