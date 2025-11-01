variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming (e.g., portal-kombat)"
  type        = string
  default     = "portal-kombat"
}

variable "trusted_role_arn" {
  description = "ARN of IAM role trusted to access the KMS key and S3 bucket (optional)"
  type        = string
  default     = null
}
variable "state_bucket_name" {
  description = "Name of the S3 bucket to store the Terraform state"
  type        = string
  default     = null
}