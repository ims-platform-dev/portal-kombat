variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs to tag for Karpenter discovery"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to tag for Karpenter discovery"
  type        = list(string)
}
