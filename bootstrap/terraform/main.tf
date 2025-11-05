# ============================================================================
# Main Terraform Configuration for Platform Services Infrastructure
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "portal-kombat-terraform-state"
  #   key            = "platform-services/terraform.tfstate"
  #   region         = "us-east-2"
  #   dynamodb_table = "portal-kombat-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}



data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}


data "aws_vpc" "cluster_vpc" {
  id = var.vpc_id != "" ? var.vpc_id : data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
}


data "aws_subnets" "cluster_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.cluster_vpc.id]
  }

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}


data "aws_security_group" "cluster_sg" {
  vpc_id = data.aws_vpc.cluster_vpc.id

  filter {
    name   = "tag:aws:eks:cluster-name"
    values = [var.cluster_name]
  }
}



module "external_dns_irsa" {
  source = "./modules/external-dns-irsa"

  cluster_name     = var.cluster_name
  aws_account_id   = var.aws_account_id
  oidc_provider_id = var.oidc_provider_id
  hosted_zone_ids  = var.external_dns_hosted_zone_ids
}

# terraform/irsa/vpc-cni.tf
locals {
  oidc_provider_url = "oidc.eks.${var.aws_region}.amazonaws.com/id/${var.oidc_provider_id}"
  oidc_provider_arn = "arn:aws:iam::${var.aws_account_id}:oidc-provider/${local.oidc_provider_url}"
}

data "aws_iam_policy_document" "vpc_cni_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_cni" {
  name               = "${var.cluster_name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role.json

  tags = {
    Name      = "${var.cluster_name}-vpc-cni"
    ManagedBy = "Terraform"
    Cluster   = var.cluster_name
    Purpose   = "VPC-CNI-IRSA"
  }
}

resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}



output "vpc_cni_role_arn" {
  description = "ARN of the VPC CNI IRSA role"
  value       = aws_iam_role.vpc_cni.arn
}

output "vpc_cni_role_name" {
  description = "Name of the VPC CNI IRSA role"
  value       = aws_iam_role.vpc_cni.name
}