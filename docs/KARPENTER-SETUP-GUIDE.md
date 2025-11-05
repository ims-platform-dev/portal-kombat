# Karpenter Setup Guide

## Prerequisites

Before deploying Karpenter via ArgoCD, you need to create AWS infrastructure (IAM roles, instance profiles, SQS queue).

## Step 1: Create AWS Infrastructure

### Option A: Using AWS CLI (Quick)

```bash
# Set variables
export CLUSTER_NAME=raiden-control-plane
export AWS_REGION=us-east-2
export AWS_ACCOUNT_ID=654654563406
export KARPENTER_VERSION=v0.34.0

# 1. Create Karpenter Controller IAM Role
cat > karpenter-controller-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION}.amazonaws.com/id/31F74548D0C0D4910526F1FBE62C72B5"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${AWS_REGION}.amazonaws.com/id/31F74548D0C0D4910526F1FBE62C72B5:aud": "sts.amazonaws.com",
          "oidc.eks.${AWS_REGION}.amazonaws.com/id/31F74548D0C0D4910526F1FBE62C72B5:sub": "system:serviceaccount:karpenter:karpenter"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name karpenter_controller_role-${CLUSTER_NAME} \
  --assume-role-policy-document file://karpenter-controller-trust-policy.json

# 2. Attach Karpenter Controller Policy
cat > karpenter-controller-policy.json <<EOF
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
  --policy-document file://karpenter-controller-policy.json

# 3. Create Karpenter Node IAM Role
cat > karpenter-node-trust-policy.json <<EOF
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
  --assume-role-policy-document file://karpenter-node-trust-policy.json

# 4. Attach required AWS managed policies to node role
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

# 5. Create Instance Profile
aws iam create-instance-profile \
  --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME}

aws iam add-role-to-instance-profile \
  --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
  --role-name karpenter_node_role-${CLUSTER_NAME}

# 6. Create SQS Queue for Spot Interruption Handling
aws sqs create-queue \
  --queue-name ${CLUSTER_NAME} \
  --attributes MessageRetentionPeriod=300

# 7. Create EventBridge rules for Spot Interruptions
QUEUE_ARN=$(aws sqs get-queue-attributes \
  --queue-url $(aws sqs get-queue-url --queue-name ${CLUSTER_NAME} --query 'QueueUrl' --output text) \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

cat > event-rule-target.json <<EOF
[
  {
    "Id": "1",
    "Arn": "${QUEUE_ARN}"
  }
]
EOF

# EC2 Spot Instance Interruption Warning
aws events put-rule \
  --name ${CLUSTER_NAME}-spot-interruption \
  --event-pattern '{"source":["aws.ec2"],"detail-type":["EC2 Spot Instance Interruption Warning"]}'

aws events put-targets \
  --rule ${CLUSTER_NAME}-spot-interruption \
  --targets file://event-rule-target.json

# Instance Rebalance Recommendation
aws events put-rule \
  --name ${CLUSTER_NAME}-rebalance-recommendation \
  --event-pattern '{"source":["aws.ec2"],"detail-type":["EC2 Instance Rebalance Recommendation"]}'

aws events put-targets \
  --rule ${CLUSTER_NAME}-rebalance-recommendation \
  --targets file://event-rule-target.json

# Instance State Change
aws events put-rule \
  --name ${CLUSTER_NAME}-instance-state-change \
  --event-pattern '{"source":["aws.ec2"],"detail-type":["EC2 Instance State-change Notification"]}'

aws events put-targets \
  --rule ${CLUSTER_NAME}-instance-state-change \
  --targets file://event-rule-target.json

# 8. Add SQS policy to allow EventBridge
cat > sqs-policy.json <<EOF
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
  --queue-url $(aws sqs get-queue-url --queue-name ${CLUSTER_NAME} --query 'QueueUrl' --output text) \
  --attributes Policy="$(cat sqs-policy.json | jq -c .)"

echo "✅ AWS Infrastructure created successfully!"
echo ""
echo "ARNs to use in Karpenter configuration:"
echo "Controller Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/karpenter_controller_role-${CLUSTER_NAME}"
echo "Node Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/karpenter_node_role-${CLUSTER_NAME}"
echo "Instance Profile ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:instance-profile/KarpenterNodeInstanceProfile-${CLUSTER_NAME}"
echo "Queue Name: ${CLUSTER_NAME}"
```

### Option B: Using Terraform (Recommended for Production)

See `infrastructure/terraform/karpenter/` directory for Terraform modules.

## Step 2: Deploy via ArgoCD

After creating AWS infrastructure:

```bash
# Commit the ArgoCD applications
git add environments/dev/argocd/k8s-platform-services-apps.yaml
git add environments/dev/platform/karpenter/
git commit -m "Add Karpenter via ArgoCD"
git push

# ArgoCD will automatically deploy in order:
# 1. cert-manager
# 2. external-dns
# 3. nginx-ingress
# 4. karpenter
```

## Step 3: Verify Deployment

```bash
# Check Karpenter pods
kubectl get pods -n karpenter

# Check NodePools
kubectl get nodepools

# Check NodeClasses
kubectl get ec2nodeclasses

# Test scaling - create a deployment
kubectl create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause:3.7 --replicas=0
kubectl scale deployment inflate --replicas=10

# Watch Karpenter provision nodes
kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter -c controller

# Watch nodes being created
kubectl get nodes -w
```

## Troubleshooting

### Karpenter not creating nodes

1. Check controller logs:
   ```bash
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
   ```

2. Verify IAM role trust policy allows IRSA

3. Check NodePool configuration:
   ```bash
   kubectl describe nodepool default
   ```

4. Verify SQS queue exists:
   ```bash
   aws sqs get-queue-url --queue-name raiden-control-plane
   ```

### Nodes created but not joining cluster

1. Check node IAM role has required policies
2. Verify security groups allow node-to-control-plane communication
3. Check EKS cluster security group settings

## Next Steps

After Karpenter is working:
1. Create NodePools for different workload types (Crossplane, Port.io)
2. Configure pod affinities/taints for workload isolation
3. Set up cost monitoring with Kubecost
4. Enable Karpenter metrics in Prometheus
