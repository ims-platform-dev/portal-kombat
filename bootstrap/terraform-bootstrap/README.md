# Terraform Bootstrap - State Backend Setup

This is **Stage 1** of the two-stage Terraform bootstrap process for `portal-kombat`. This minimal infrastructure creates a secure, production-ready state backend that your main EKS/Crossplane infrastructure (Stage 2) will use.

## Overview

### What Gets Created

✅ **S3 Bucket** (`portal-kombat-terraform-state-dev`)
- Versioning enabled for state history
- Encryption at rest with KMS
- Access logging to separate bucket
- Public access blocked
- SSL/TLS enforcement via bucket policy

✅ **DynamoDB Table** (`portal-kombat-state-lock`)
- State locking to prevent concurrent applies
- Point-in-time recovery enabled
- KMS encryption

✅ **KMS Key** (`alias/portal-kombat-terraform-state-encryption`)
- Automatic key rotation enabled
- Fine-grained access control
- Supports encrypted state and audit logging

## Prerequisites

1. **AWS Account**: Active AWS account with admin credentials
2. **AWS CLI**: Configured with appropriate credentials
3. **Terraform**: Version >= 1.0
4. **Region**: Default is `us-east-1` (customize in `terraform.tfvars`)

## Quick Start

### Step 1: Deploy Bootstrap Backend

```bash
cd bootstrap/terraform-bootstrap
terraform init
terraform plan
terraform apply
```

### Step 2: Capture Output

Save the output values (you'll need them for Stage 2):

```bash
terraform output backend_config
terraform output backend_config_hcl > backend.tf
```

This creates a `backend.tf` file with the exact configuration needed for your main infrastructure.

## Configuration

Edit `terraform.tfvars` to customize:

```hcl
region       = "us-east-1"          # AWS region
environment  = "dev"                # dev/staging/prod
project_name = "portal-kombat"      # Your project name
```

## Key Features

### Security
- ✅ KMS encryption for S3 state and DynamoDB
- ✅ Bucket policies prevent unencrypted uploads
- ✅ Requires SSL/TLS for all access
- ✅ State file versioning for recovery
- ✅ Access logging

### Durability
- ✅ S3 versioning: Undo state mistakes
- ✅ DynamoDB point-in-time recovery
- ✅ KMS key rotation: Annual automatic rotation
- ✅ Lifecycle rules: Clean old versions after 90 days

### Cost Efficiency
- ✅ DynamoDB on-demand billing (pay per request)
- ✅ S3 lifecycle rules reduce storage costs
- ✅ No idle charges

## Stage 2: Connecting Main Infrastructure

After bootstrap completes, your main Terraform configuration uses this backend:

```hcl
terraform {
  backend "s3" {
    bucket         = "portal-kombat-terraform-state-dev"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "portal-kombat-state-lock"
    kms_key_id     = "arn:aws:kms:us-east-1:ACCOUNT:key/KEYID"
  }
}
```

See `../terraform/backend.tf` for the main infrastructure setup.

## Troubleshooting

### KMS Permission Denied
If you get KMS permission errors during main deployment:
1. Ensure the role/principal running Terraform is in the KMS key policy
2. Update `trusted_role_arn` in `terraform.tfvars`
3. Re-run bootstrap: `terraform apply`

### State Lock Issues
If locked during apply:
```bash
# View lock holders
aws dynamodb scan --table-name portal-kombat-state-lock \
  --region us-east-1 --profile your-profile

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Access Logging Issues
If S3 access logging fails:
```bash
# Ensure log bucket has ACL permissions
aws s3api put-bucket-acl \
  --bucket portal-kombat-terraform-state-dev-logs \
  --acl log-delivery-write
```

## Cleanup

To destroy bootstrap infrastructure:

```bash
terraform destroy
```

**Warning**: Destroying this deletes state history and locks. Only do this if you're demolishing the entire environment.

## Files

- `main.tf` - Core resources (S3, DynamoDB, KMS)
- `variables.tf` - Configuration variables
- `outputs.tf` - Output values for Stage 2
- `terraform.tfvars` - Your environment-specific settings
- `versions.tf` - Provider configuration

## Next Steps

1. ✅ Run this bootstrap
2. → Move to `../terraform/` for main infrastructure deployment
3. → Configure Crossplane providers via `../terraform/` module

## References

- [AWS S3 Backend Documentation](https://www.terraform.io/language/settings/backends/s3)
- [Terraform State Locking](https://www.terraform.io/language/state/locking)
- [KMS Key Policies](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html)
