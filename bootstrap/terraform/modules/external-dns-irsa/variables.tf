variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "oidc_provider_id" {
  description = "EKS OIDC provider ID"
  type        = string
}

variable "hosted_zone_ids" {
  description = "List of Route53 hosted zone IDs that External DNS can manage"
  type        = list(string)
  default     = ["*"]
}
