# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "name" {
  description = "EKS Cluster Name and the VPC name"
  type        = string
  default     = "raiden-control-plane"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes Version"
  default     = "1.34"
}

variable "capacity_type" {
  type        = string
  description = "Capacity SPOT or ON_DEMAND"
  default     = "SPOT"
}

# VPC Configuration Variables
variable "create_vpc" {
  description = "Create a new VPC. Set to false to use an existing VPC."
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for VPC. Only used when create_vpc is true."
  type        = string
  default     = "10.140.56.0/21"
}

variable "vpc_id" {
  description = "ID of existing VPC. Required if create_vpc is false."
  type        = string
  default     = "vpc-0d5098e85edf3c66a"

  validation {
    condition     = var.create_vpc || var.vpc_id != null
    error_message = "vpc_id must be provided when create_vpc is false."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS cluster. Required if create_vpc is false. Must span at least 2 AZs."
  type        = list(string)
  default     = ["subnet-091c47ba29231928e", "subnet-051a61728a2e6b2f4", "subnet-0b38b67589017f7e3"]

  validation {
    condition     = var.create_vpc || length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnet IDs are required when using an existing VPC (EKS requirement)."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for load balancers. Optional when using existing VPC."
  type        = list(string)
  default     = ["subnet-0b4ba68dce446a70a", "subnet-0562936295b6fd63d", "subnet-0a21b8538f27cb78d"]
}

# Note: Crossplane providers are now deployed via ArgoCD from infra-definitions/
# Terraform only creates the IRSA role for AWS authentication

# EKS Cluster Endpoint Access Configuration
variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint. Set to false for fully private cluster."
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Tagging Variables (often required by SCPs)
variable "environment" {
  description = "Environment tag (e.g., production, development, staging)"
  type        = string
  default     = "dev"
}



variable "owner" {
  description = "Owner/team responsible for the cluster"
  type        = string
  default     = "platform"
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Bastion Host Configuration
variable "create_bastion" {
  description = "Create a bastion host for accessing the private EKS cluster"
  type        = bool
  default     = false
}

variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_ssh_key_name" {
  description = "SSH key name for bastion host access"
  type        = string
  default     = ""
}

variable "bastion_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
