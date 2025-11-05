# ============================================================================
# Karpenter Node IAM Role
# ============================================================================

# Trust policy for EC2 service
data "aws_iam_policy_document" "karpenter_node_trust_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM Role for Karpenter nodes
resource "aws_iam_role" "karpenter_node" {
  name               = "karpenter_node_role-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_trust_policy.json

  tags = {
    Service = "karpenter"
    Role    = "node"
  }
}

# Attach AWS managed policies for EKS worker nodes
resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for Karpenter nodes
resource "aws_iam_instance_profile" "karpenter_node" {
  name = var.instance_profile_name
  role = aws_iam_role.karpenter_node.name

  tags = {
    Service = "karpenter"
    Role    = "node"
  }
}
