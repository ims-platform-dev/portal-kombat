variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "oidc_provider_id" {
  description = "EKS OIDC provider ID"
  type        = string
}

variable "queue_name" {
  description = "Name of the SQS queue for spot interruption"
  type        = string
}
