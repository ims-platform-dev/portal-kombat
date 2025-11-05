locals {
  default_state_bucket_name = "${var.project_name}-terraform-state-${var.environment}"
  state_bucket_name         = var.state_bucket_name != null && trimspace(var.state_bucket_name) != "" ? var.state_bucket_name : local.default_state_bucket_name
  lock_table_name           = "${var.project_name}-state-lock"
  kms_key_alias             = "alias/${var.project_name}-terraform-state-encryption"
  log_bucket_name           = "${local.state_bucket_name}-logs"
  trusted_role_arn          = trimspace(var.trusted_role_arn != null ? var.trusted_role_arn : "")
}



data "aws_iam_policy_document" "terraform_state_kms" {
  statement {
    sid = "EnableRootAccount"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = local.trusted_role_arn != "" ? [local.trusted_role_arn] : []
    content {
      sid = "AllowTrustedRole"

      principals {
        type        = "AWS"
        identifiers = [statement.value]
      }

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:List*",
        "kms:ReEncrypt*"
      ]

      resources = ["*"]
    }
  }
}

resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.terraform_state_kms.json
  tags = {
    Name = "terraform-state"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = local.kms_key_alias
  target_key_id = aws_kms_key.terraform_state.arn
}

resource "aws_s3_bucket" "terraform_state_logs" {
  bucket = local.log_bucket_name

  tags = {
    Name = "terraform-state-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "terraform_state_logs" {
  statement {
    sid = "AWSLogDeliveryWrite"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com", "delivery.logs.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.terraform_state_logs.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid = "AWSLogDeliveryCheck"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com", "delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.terraform_state_logs.arn]
  }
}

resource "aws_s3_bucket_policy" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id
  policy = data.aws_iam_policy_document.terraform_state_logs.json
}


resource "aws_s3_bucket" "terraform_state" {
  bucket = local.state_bucket_name

  tags = {
    Name = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  target_bucket = aws_s3_bucket.terraform_state_logs.id
  target_prefix = "state-logs/"
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "DeleteOldVersions"
    status = "Enabled"

    filter {
      and {
        prefix = ""
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "terraform-state-lock"
  }
}

data "aws_caller_identity" "current" {}
