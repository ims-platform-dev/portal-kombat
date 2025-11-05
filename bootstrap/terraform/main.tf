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


module "karpenter_controller_irsa" {
  source = "./modules/karpenter-controller-irsa"

  cluster_name     = var.cluster_name
  aws_account_id   = var.aws_account_id
  aws_region       = var.aws_region
  oidc_provider_id = var.oidc_provider_id
  queue_name       = var.karpenter_interruption_queue_name
}


module "karpenter_node_role" {
  source = "./modules/karpenter-node-role"

  cluster_name            = var.cluster_name
  instance_profile_name   = var.karpenter_node_instance_profile_name
}


module "karpenter_interruption_queue" {
  source = "./modules/karpenter-interruption-queue"

  cluster_name            = var.cluster_name
  queue_name              = var.karpenter_interruption_queue_name
  karpenter_controller_role_arn = module.karpenter_controller_irsa.role_arn
}


module "karpenter_tags" {
  source = "./modules/karpenter-tags"

  cluster_name        = var.cluster_name
  subnet_ids          = data.aws_subnets.cluster_subnets.ids
  security_group_ids  = [data.aws_security_group.cluster_sg.id]
}
