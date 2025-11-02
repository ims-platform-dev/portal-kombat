#---------------------------------------------------------------
# Crossplane IRSA (IAM Roles for Service Accounts)
# Creates IAM roles for Crossplane providers to access AWS
#---------------------------------------------------------------

# IAM Policy for Crossplane Providers
resource "aws_iam_policy" "crossplane_provider" {
  name        = "${local.name}-crossplane-provider-policy"
  description = "IAM policy for Crossplane providers to manage AWS resources"
  policy      = file("${path.module}/../../shared/managed-resources/iam-roles/iam-policies/crossplane-provider-policy.json")

  tags = local.tags
}

# IRSA Role for Upbound AWS Provider (family-specific providers)
module "crossplane_upbound_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name_prefix           = "${local.name}-crossplane"
  assume_role_condition_test = "StringLike"

  role_policy_arns = {
    crossplane_policy = aws_iam_policy.crossplane_provider.arn
  }

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "${local.crossplane_namespace}:provider-aws-s3-*",
        "${local.crossplane_namespace}:provider-aws-ec2-*",
        "${local.crossplane_namespace}:provider-aws-eks-*",
        "${local.crossplane_namespace}:provider-aws-iam-*",
        "${local.crossplane_namespace}:provider-aws-rds-*"
      ]
    }
  }

  tags = local.tags
}

# Output the IRSA role ARN for use in ProviderConfigs
output "crossplane_upbound_irsa_role_arn" {
  description = "IAM Role ARN for Crossplane Upbound AWS Providers"
  value       = module.crossplane_upbound_irsa.iam_role_arn
}

output "crossplane_upbound_irsa_role_name" {
  description = "IAM Role Name for Crossplane Upbound AWS Providers"
  value       = module.crossplane_upbound_irsa.iam_role_name
}
