# Platform Services Infrastructure - Terraform

This Terraform configuration creates AWS infrastructure required for the platform services:
- **External DNS**: IAM role with IRSA for Route53 DNS management
- **VPC CNI**: IAM role with IRSA for pod networking

**Note:** Cluster autoscaling is handled by cluster-autoscaler deployed in `eks-bootstrap/main.tf` (lines 172-272).

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.5.0
3. **EKS Cluster** already deployed with OIDC provider configured
4. **Kubectl** access to the cluster

## Architecture

The infrastructure is organized into modular components:

```
bootstrap/terraform/
├── main.tf                 # Root configuration
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── terraform.tfvars        # Your custom values (create from .example)
└── modules/
    └── external-dns-irsa/  # External DNS IAM role
```

## Quick Start

### 1. Configure Variables

Create `terraform.tfvars` from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
cluster_name     = "raiden-control-plane"
aws_region       = "us-east-2"
aws_account_id   = "654654563406"
oidc_provider_id = "31F74548D0C0D4910526F1FBE62C72B5"
```

**Get your OIDC Provider ID:**
```bash
aws eks describe-cluster --name raiden-control-plane \
  --query "cluster.identity.oidc.issuer" \
  --output text | cut -d'/' -f5
```

### 2. Initialize Terraform

```bash
cd bootstrap/terraform
terraform init
```

### 3. Review the Plan

```bash
terraform plan
```

Expected resources to be created:
- 2 IAM roles (External DNS, VPC CNI)
- Subnet and security group tags

### 4. Apply Configuration

```bash
terraform apply
```

Review the plan and type `yes` to confirm.

### 5. Verify Outputs

```bash
terraform output
```

You should see:
- IAM role ARNs for External DNS and VPC CNI
- Tagged subnet and security group IDs

## Outputs

The following outputs are provided for use in Kubernetes manifests:

| Output | Description | Used In |
|--------|-------------|---------|
| `external_dns_role_arn` | External DNS IAM role ARN | `environments/dev/cluster-addons/external-dns/values.yaml` |
| `vpc_cni_role_arn` | VPC CNI IAM role ARN | Used by VPC CNI for pod networking |

## Module Details

### External DNS IRSA

Creates an IAM role with IRSA (IAM Roles for Service Accounts) for External DNS to manage Route53 records.

**Permissions:**
- `route53:ChangeResourceRecordSets` on specified hosted zones
- `route53:ListHostedZones`, `ListResourceRecordSets`, `ListTagsForResource`

**Configuration:**
- Restrict hosted zones in production using `external_dns_hosted_zone_ids`
- Default `["*"]` allows all zones (dev/test only)

### VPC CNI IRSA

Creates an IAM role with IRSA for VPC CNI plugin to manage pod networking.

**Permissions:**
- AWS managed policy: `AmazonEKS_CNI_Policy`

## Integration with Kubernetes

After Terraform applies successfully, update your Kubernetes manifests:

### External DNS

Update `environments/dev/cluster-addons/external-dns/values.yaml`:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: <external_dns_role_arn>
```

## Remote State (Optional)

For production, configure remote state in S3:

1. Create S3 bucket and DynamoDB table:
```bash
aws s3api create-bucket \
  --bucket portal-kombat-terraform-state \
  --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2

aws dynamodb create-table \
  --table-name portal-kombat-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-2
```

2. Uncomment backend configuration in `main.tf`:
```hcl
backend "s3" {
  bucket         = "portal-kombat-terraform-state"
  key            = "platform-services/terraform.tfstate"
  region         = "us-east-2"
  dynamodb_table = "portal-kombat-terraform-locks"
  encrypt        = true
}
```

3. Migrate state:
```bash
terraform init -migrate-state
```

## Troubleshooting

### OIDC Provider Not Found

**Error:** "Error: no matching OIDC provider found"

**Fix:** Verify OIDC provider is configured:
```bash
aws iam list-open-id-connect-providers
```

If missing, create it:
```bash
eksctl utils associate-iam-oidc-provider \
  --cluster raiden-control-plane \
  --region us-east-2 \
  --approve
```

### No Subnets Found

**Error:** "Error: no subnets found for cluster"

**Fix:** Check subnet tagging:
```bash
aws ec2 describe-subnets \
  --filters "Name=tag:kubernetes.io/cluster/raiden-control-plane,Values=shared"
```

Subnets must have tag: `kubernetes.io/cluster/<cluster-name> = shared`

### Permission Denied

**Error:** "User is not authorized to perform: iam:CreateRole"

**Fix:** Ensure your AWS credentials have IAM permissions:
```json
{
  "Effect": "Allow",
  "Action": [
    "iam:CreateRole",
    "iam:AttachRolePolicy",
    "ec2:CreateTags"
  ],
  "Resource": "*"
}
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning:** This will delete:
- All IAM roles and policies
- Tags on subnets and security groups

## Cost Considerations

This infrastructure has minimal cost:
- **IAM Roles**: Free
- **EC2 Tags**: Free

**Total estimated cost:** $0/month

## Security Best Practices

1. **Restrict Route53 Zones**: In production, specify exact hosted zone IDs
2. **Use Remote State**: Store state in S3 with encryption and locking
3. **Limit OIDC Conditions**: Trust policy scoped to specific service account
4. **Regional Restrictions**: Permissions scoped to specific region

## Next Steps

After Terraform completes:

1. **Update Kubernetes manifests** with output values
2. **Deploy platform services** via ArgoCD:
   ```bash
   kubectl apply -f environments/dev/argocd/k8s-platform-services-apps.yaml
   ```
3. **Verify deployments**:
   ```bash
   kubectl get pods -n external-dns
   kubectl get nodes  # Verify cluster-autoscaler is managing nodes
   ```

## Cluster Autoscaler

The cluster-autoscaler is deployed via Terraform in `eks-bootstrap/main.tf` (lines 172-272) with:
- IAM role with IRSA for autoscaling permissions
- Helm chart version 9.43.0
- Auto-discovery of node groups using cluster tags
- Proper configuration for EKS integration

To verify cluster-autoscaler:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler
```

## Support

For issues:
1. Check AWS CloudTrail for permission errors
2. Review Terraform plan before applying
3. Verify EKS cluster configuration
4. Check OIDC provider configuration
