variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "queue_name" {
  description = "Name of the SQS queue"
  type        = string
}

variable "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role"
  type        = string
}
