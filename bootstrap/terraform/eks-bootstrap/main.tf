# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# provider "aws" {
#   region = var.region
#   assume_role {
#     role_arn     = "arn:aws:iam::654654563406:role/cross_account_admin"
#     session_name = "sre-inf-terraform-admin"
#     external_id  = "sre-inf-terraform"
#   }
# }

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", local.name, "--region", local.region]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", local.name, "--region", local.region]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", local.name, "--region", local.region]
    command     = "aws"
  }
  load_config_file  = false
  apply_retry_count = 15
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

locals {
  name   = var.name
  region = var.region

  cluster_version = var.cluster_version
  cluster_name    = local.name

  vpc_name = local.name
  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  # VPC and Subnet IDs - conditional based on create_vpc
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  public_subnet_ids  = var.public_subnet_ids

  tags = merge(
    {
      Blueprint   = local.name
      Environment = var.environment
      CodeManaged = "true"
    },

    var.owner != "" ? { Owner = var.owner } : {},
    var.additional_tags
  )
}

#---------------------------------------------------------------
# EBS CSI Driver Role
#---------------------------------------------------------------

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name = "${local.name}-ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name                         = local.name
  cluster_version                      = local.cluster_version
  cluster_endpoint_public_access = true
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  kms_key_enable_default_policy        = true
  enable_cluster_creator_admin_permissions = true
  # Explicitly set to STANDARD support (SCP denies EXTENDED support)
  bootstrap_self_managed_addons = false
  cluster_upgrade_policy = {
    support_type = "STANDARD" # Prevent EXTENDED support (blocked by SCP)
  }

  # Enable CloudWatch logging (often required by SCPs)
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]


  vpc_id     = local.vpc_id
  subnet_ids = local.private_subnet_ids

  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      before_compute = true # Ensure the addon is configured before compute resources are created
      most_recent    = true
    }
  }
 
  eks_managed_node_group_defaults = {
    metadata_options = {
      http_tokens = "required"
    }
  }

  # for production cluster, add a node group for add-ons that should not be inerrupted such as coredns
  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.xlarge","m5.2xlarge"]
      capacity_type  = var.capacity_type 
      min_size       = 1
      max_size       = 5
      desired_size   = 3
      subnet_ids     = local.private_subnet_ids

      # CRITICAL: Disable public IP assignment to comply with SCP policies
      # This prevents the "RunInstances" error when SCPs block public IP assignment
      # Nodes will use NAT Gateway through private subnets for internet access
      associate_public_ip_address = false
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Cluster Autoscaler IAM and Deployment
#---------------------------------------------------------------

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid     = "ClusterAutoscalerRead"
    effect  = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeScheduledActions",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ClusterAutoscalerWrite"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${module.eks.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${module.eks.cluster_name}-cluster-autoscaler"
  description = "Permissions for the Kubernetes Cluster Autoscaler"
  policy      = data.aws_iam_policy_document.cluster_autoscaler.json
}

module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name_prefix = "${substr(module.eks.cluster_name, 0, 26)}-ca-"

  role_policy_arns = {
    autoscaler = aws_iam_policy.cluster_autoscaler.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = local.tags
}

resource "helm_release" "cluster_autoscaler" {
  name             = "cluster-autoscaler"
  namespace        = "kube-system"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = "9.43.0"
  create_namespace = false

  depends_on = [
    module.eks,
    module.cluster_autoscaler_irsa
  ]

  values = [
    yamlencode({
      cloudProvider = "aws"
      awsRegion     = local.region
      autoDiscovery = {
        clusterName = module.eks.cluster_name
      }
      rbac = {
        serviceAccount = {
          create = true
          name   = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = module.cluster_autoscaler_irsa.iam_role_arn
          }
        }
      }
      extraArgs = {
        "balance-similar-node-groups" = "true"
        "scale-down-unneeded-time"    = "5m"
      }
    })
  ]
}

#---------------------------------------------------------------
# EKS Addons
#---------------------------------------------------------------

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_argocd = true
  argocd = {
    namespace     = "argocd"
    chart_version = "9.0.5" # ArgoCD v2.11.2
    values        = [file("${path.module}/values/argocd.yaml")]
  }

  enable_metrics_server               = true
  enable_aws_load_balancer_controller = true

  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    timeout = "600"
    values  = [file("${path.module}/values/prometheus.yaml")]
  }

  depends_on = [module.eks.cluster_addons]
}

resource "time_sleep" "addons_wait_60_seconds" {
  create_duration = "60s"
  depends_on      = [module.eks_blueprints_addons]
}

module "gatekeeper" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "1.1.1"

  name             = "gatekeeper"
  description      = "A Helm chart to deploy gatekeeper project"
  namespace        = "gatekeeper-system"
  create_namespace = true
  chart            = "gatekeeper"
  chart_version    = "3.20.1"
  repository       = "https://open-policy-agent.github.io/gatekeeper/charts"

  depends_on = [time_sleep.addons_wait_60_seconds]
}

#---------------------------------------------------------------
# Crossplane
#---------------------------------------------------------------
module "crossplane" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "1.1.1"

  name             = "crossplane"
  description      = "A Helm chart to deploy crossplane project"
  namespace        = "crossplane-system"
  create_namespace = true
  chart            = "crossplane"
  chart_version    = "2.0.2"
  repository       = "https://charts.crossplane.io/stable/"
  timeout          = "600"
  values           = [file("${path.module}/values/crossplane.yaml")]

  depends_on = [time_sleep.addons_wait_60_seconds]
}

# Install function-patch-and-transform (required for EnvironmentConfig and Compositions)
resource "kubectl_manifest" "function_patch_and_transform" {
  yaml_body = <<-YAML
    apiVersion: pkg.crossplane.io/v1beta1
    kind: Function
    metadata:
      name: function-patch-and-transform
    spec:
      package: xpkg.upbound.io/crossplane-contrib/function-patch-and-transform:v0.9.0
  YAML

  depends_on = [module.crossplane]
}

# Wait for Crossplane CRDs to be installed
resource "time_sleep" "wait_for_crossplane_crds" {
  create_duration = "90s"
  depends_on      = [module.crossplane]
}

# Wait for function to be installed before creating EnvironmentConfig
resource "time_sleep" "wait_for_function" {
  create_duration = "60s"
  depends_on      = [kubectl_manifest.function_patch_and_transform]
}

resource "kubectl_manifest" "environmentconfig" {
  yaml_body = templatefile("${path.module}/config/environmentconfig.yaml", {
    awsAccountID = data.aws_caller_identity.current.account_id
    eksOIDC      = module.eks.oidc_provider
    vpcID        = local.vpc_id
  })

  depends_on = [
    time_sleep.wait_for_crossplane_crds,
    time_sleep.wait_for_function
  ]
}

#---------------------------------------------------------------
# Crossplane Providers IRSA Configuration
# Note: Providers are deployed via ArgoCD from infra-definitions/
# Terraform only creates the IRSA role for AWS authentication
#---------------------------------------------------------------
locals {
  crossplane_namespace = "crossplane-system"
}

#---------------------------------------------------------------
# Crossplane AWS Providers IRSA Role
# Creates IAM role for Crossplane providers to authenticate with AWS
# Providers themselves are deployed via ArgoCD from infra-definitions/
#---------------------------------------------------------------
module "crossplane_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name_prefix           = "${local.name}-crossplane-"
  assume_role_condition_test = "StringLike"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AdministratorAccess"
  }

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "${local.crossplane_namespace}:provider-aws-*",
        "${local.crossplane_namespace}:provider-upjet-aws-*"
      ]
    }
  }

  tags = local.tags

  depends_on = [module.crossplane]
}

#---------------------------------------------------------------
# Supporting Resources
#---------------------------------------------------------------

module "vpc" {
  count   = var.create_vpc ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  manage_default_vpc = true

  name = local.vpc_name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}
