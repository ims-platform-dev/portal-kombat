output "s3_bucket_name" {
  description = "Name of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.id
}

output "s3_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB state lock table"
  value       = aws_dynamodb_table.terraform_locks.id
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB state lock table"
  value       = aws_dynamodb_table.terraform_locks.arn
}




output "backend_config" {
  description = "Terraform backend configuration to use in main infrastructure"
  value = {
    bucket         = aws_s3_bucket.terraform_state.id
    key            = "terraform.tfstate"
    region         = var.region
    encrypt        = true
    dynamodb_table = aws_dynamodb_table.terraform_locks.id
    kms_key_id     = aws_kms_key.terraform_state.id
  }
  sensitive = false
}

output "backend_config_hcl" {
  description = "HCL backend configuration block for main infrastructure"
  value       = <<-EOT
terraform {
  backend "s3" {
    bucket         = "${aws_s3_bucket.terraform_state.id}"
    key            = "terraform.tfstate"
    region         = "${var.region}"
    encrypt        = true
    dynamodb_table = "${aws_dynamodb_table.terraform_locks.id}"
    kms_key_id     = "${aws_kms_key.terraform_state.id}"
  }
}
EOT
  sensitive   = false
}
