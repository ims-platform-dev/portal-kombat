# ============================================================================
# External DNS IRSA (IAM Role for Service Account)
# ============================================================================

# IAM policy for External DNS
data "aws_iam_policy_document" "external_dns_policy" {
  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = [
      for zone_id in var.hosted_zone_ids :
      zone_id == "*" ? "arn:aws:route53:::hostedzone/*" : "arn:aws:route53:::hostedzone/${zone_id}"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource"
    ]
    resources = ["*"]
  }
}

# Trust policy for IRSA
data "aws_iam_policy_document" "external_dns_trust_policy" {
  statement {
    effect = "Allow"

    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${var.aws_account_id}:oidc-provider/oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${var.oidc_provider_id}"
      ]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${var.oidc_provider_id}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${var.oidc_provider_id}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }
  }
}

# IAM Role
resource "aws_iam_role" "external_dns" {
  name               = "external-dns-role"
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust_policy.json

  tags = {
    Service = "external-dns"
  }
}

# Attach policy to role
resource "aws_iam_role_policy" "external_dns" {
  name   = "external-dns-policy"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns_policy.json
}

# Data source for current region
data "aws_region" "current" {}
