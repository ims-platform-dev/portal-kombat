#!/bin/bash
set -e

# Platform Services Setup Script
# This script sets up all required AWS infrastructure and deploys platform services via ArgoCD
#
# Order of operations:
# 1. Create External DNS IAM role
# 2. Create Karpenter IAM roles and infrastructure
# 3. Tag EKS subnets and security groups for Karpenter
# 4. Deploy ArgoCD application (which deploys all services in order)

CLUSTER_NAME=raiden-control-plane
AWS_REGION=us-east-2
AWS_ACCOUNT_ID=654654563406
OIDC_ID=31F74548D0C0D4910526F1FBE62C72B5

echo "=================================================="
echo "Platform Services Setup for ${CLUSTER_NAME}"
echo "=================================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Create External DNS IAM Role
echo -e "${YELLOW}Step 1: Creating External DNS IAM Role${NC}"
echo ""

if aws iam get-role --role-name external-dns-role 2>/dev/null; then
    echo -e "${GREEN}✓ External DNS IAM role already exists${NC}"
else
    echo "Creating External DNS IAM role..."
    aws iam create-role \
        --role-name external-dns-role \
        --assume-role-policy-document file://.templates/iam/external-dns-trust-policy.json

    aws iam put-role-policy \
        --role-name external-dns-role \
        --policy-name external-dns-policy \
        --policy-document file://.templates/iam/external-dns-iam-policy.json

    echo -e "${GREEN}✓ External DNS IAM role created${NC}"
fi
echo ""

# Step 2: Create Karpenter IAM Roles
echo -e "${YELLOW}Step 2: Creating Karpenter IAM Roles${NC}"
echo ""

# Karpenter Controller Role
if aws iam get-role --role-name karpenter_controller_role-${CLUSTER_NAME} 2>/dev/null; then
    echo -e "${GREEN}✓ Karpenter Controller IAM role already exists${NC}"
else
    echo "Creating Karpenter Controller IAM role..."

    cat > /tmp/karpenter-controller-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com",
          "oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:karpenter:karpenter"
        }
      }
    }
  ]
}
EOF

    aws iam create-role \
        --role-name karpenter_controller_role-${CLUSTER_NAME} \
        --assume-role-policy-document file:///tmp/karpenter-controller-trust-policy.json

    cat > /tmp/karpenter-controller-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet",
        "ec2:CreateLaunchTemplate",
        "ec2:CreateTags",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets",
        "ec2:DeleteLaunchTemplate",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "iam:PassRole",
        "iam:CreateServiceLinkedRole",
        "pricing:GetProducts",
        "ssm:GetParameter",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name karpenter_controller_role-${CLUSTER_NAME} \
        --policy-name KarpenterControllerPolicy \
        --policy-document file:///tmp/karpenter-controller-policy.json

    echo -e "${GREEN}✓ Karpenter Controller IAM role created${NC}"
fi
echo ""

# Karpenter Node Role
if aws iam get-role --role-name karpenter_node_role-${CLUSTER_NAME} 2>/dev/null; then
    echo -e "${GREEN}✓ Karpenter Node IAM role already exists${NC}"
else
    echo "Creating Karpenter Node IAM role..."

    cat > /tmp/karpenter-node-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws iam create-role \
        --role-name karpenter_node_role-${CLUSTER_NAME} \
        --assume-role-policy-document file:///tmp/karpenter-node-trust-policy.json

    # Attach AWS managed policies
    aws iam attach-role-policy \
        --role-name karpenter_node_role-${CLUSTER_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

    aws iam attach-role-policy \
        --role-name karpenter_node_role-${CLUSTER_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

    aws iam attach-role-policy \
        --role-name karpenter_node_role-${CLUSTER_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

    aws iam attach-role-policy \
        --role-name karpenter_node_role-${CLUSTER_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

    # Create instance profile
    aws iam create-instance-profile \
        --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} || true

    aws iam add-role-to-instance-profile \
        --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
        --role-name karpenter_node_role-${CLUSTER_NAME} || true

    echo -e "${GREEN}✓ Karpenter Node IAM role created${NC}"
fi
echo ""

# Step 3: Create SQS Queue for Spot Interruption
echo -e "${YELLOW}Step 3: Creating SQS Queue for Spot Interruption${NC}"
echo ""

if aws sqs get-queue-url --queue-name ${CLUSTER_NAME} 2>/dev/null; then
    echo -e "${GREEN}✓ SQS queue already exists${NC}"
else
    echo "Creating SQS queue..."
    QUEUE_URL=$(aws sqs create-queue \
        --queue-name ${CLUSTER_NAME} \
        --attributes MessageRetentionPeriod=300 \
        --query 'QueueUrl' \
        --output text)

    QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url ${QUEUE_URL} \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' \
        --output text)

    # Create EventBridge rules
    aws events put-rule \
        --name ${CLUSTER_NAME}-spot-interruption \
        --event-pattern '{"source":["aws.ec2"],"detail-type":["EC2 Spot Instance Interruption Warning"]}' || true

    aws events put-targets \
        --rule ${CLUSTER_NAME}-spot-interruption \
        --targets "Id=1,Arn=${QUEUE_ARN}" || true

    aws events put-rule \
        --name ${CLUSTER_NAME}-rebalance-recommendation \
        --event-pattern '{"source":["aws.ec2"],"detail-type":["EC2 Instance Rebalance Recommendation"]}' || true

    aws events put-targets \
        --rule ${CLUSTER_NAME}-rebalance-recommendation \
        --targets "Id=1,Arn=${QUEUE_ARN}" || true

    aws events put-rule \
        --name ${CLUSTER_NAME}-instance-state-change \
        --event-pattern '{"source":["aws.ec2"],"detail-type":["EC2 Instance State-change Notification"]}' || true

    aws events put-targets \
        --rule ${CLUSTER_NAME}-instance-state-change \
        --targets "Id=1,Arn=${QUEUE_ARN}" || true

    # Add SQS policy
    cat > /tmp/sqs-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "${QUEUE_ARN}"
    }
  ]
}
EOF

    aws sqs set-queue-attributes \
        --queue-url ${QUEUE_URL} \
        --attributes "Policy=$(cat /tmp/sqs-policy.json | jq -c .)"

    echo -e "${GREEN}✓ SQS queue and EventBridge rules created${NC}"
fi
echo ""

# Step 4: Tag EKS Subnets for Karpenter
echo -e "${YELLOW}Step 4: Tagging EKS Subnets for Karpenter${NC}"
echo ""

# Get VPC ID
VPC_ID=$(aws eks describe-cluster \
    --name ${CLUSTER_NAME} \
    --query 'cluster.resourcesVpcConfig.vpcId' \
    --output text)

# Get subnet IDs
SUBNET_IDS=$(aws eks describe-cluster \
    --name ${CLUSTER_NAME} \
    --query 'cluster.resourcesVpcConfig.subnetIds' \
    --output text)

for subnet_id in $SUBNET_IDS; do
    echo "Tagging subnet: ${subnet_id}"
    aws ec2 create-tags \
        --resources ${subnet_id} \
        --tags Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}
done

echo -e "${GREEN}✓ Subnets tagged${NC}"
echo ""

# Step 5: Tag EKS Security Groups for Karpenter
echo -e "${YELLOW}Step 5: Tagging EKS Security Groups for Karpenter${NC}"
echo ""

# Get cluster security group
CLUSTER_SG=$(aws eks describe-cluster \
    --name ${CLUSTER_NAME} \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
    --output text)

echo "Tagging security group: ${CLUSTER_SG}"
aws ec2 create-tags \
    --resources ${CLUSTER_SG} \
    --tags Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}

echo -e "${GREEN}✓ Security groups tagged${NC}"
echo ""

# Step 6: Deploy ArgoCD Application
echo -e "${YELLOW}Step 6: Deploying Platform Services via ArgoCD${NC}"
echo ""

kubectl apply -f environments/dev/argocd/platform-services-app.yaml

echo -e "${GREEN}✓ ArgoCD application created${NC}"
echo ""

# Summary
echo "=================================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=================================================="
echo ""
echo "ArgoCD will now deploy services in this order:"
echo "  1. Cert-Manager (sync-wave: 10)"
echo "  2. External DNS (sync-wave: 20)"
echo "  3. nginx-ingress (sync-wave: 30)"
echo "  4. Karpenter (sync-wave: 40)"
echo ""
echo "Monitor deployment:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get pods -n cert-manager"
echo "  kubectl get pods -n external-dns"
echo "  kubectl get pods -n ingress-nginx"
echo "  kubectl get pods -n karpenter"
echo ""
echo "After Karpenter is running, check NodePools:"
echo "  kubectl get nodepools"
echo "  kubectl get ec2nodeclasses"
echo ""
