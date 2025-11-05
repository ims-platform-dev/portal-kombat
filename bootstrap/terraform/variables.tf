# ============================================================================
# Variables for Platform Services Infrastructure
# ============================================================================

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "raiden-control-plane"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = "654654563406"
}

variable "oidc_provider_id" {
  description = "EKS OIDC provider ID (without https://)"
  type        = string
  default     = "31F74548D0C0D4910526F1FBE62C72B5"
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster (will be auto-discovered if not provided)"
  type        = string
  default     = "vpc-0d5098e85edf3c66a"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Project     = "portal-kombat"
    Cluster     = "raiden-control-plane"
  }
}

# External DNS Configuration
variable "external_dns_hosted_zone_ids" {
  description = "List of Route53 hosted zone IDs that External DNS can manage"
  type        = list(string)
  default     = ["Z05914812OPX7495S4MSP"]  # Allows all zones - restrict in production
}

# Karpenter Configuration
variable "karpenter_node_instance_profile_name" {
  description = "Name for the Karpenter node instance profile"
  type        = string
  default     = "karpenter_node_instance_profile"
}

variable "karpenter_interruption_queue_name" {
  description = "Name for the SQS queue for spot interruption handling"
  type        = string
  default     = "raiden-control-plane"
}
