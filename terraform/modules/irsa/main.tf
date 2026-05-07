# ============================================================
# terraform/modules/irsa/main.tf
#
# IRSA = IAM Roles for Service Accounts
# Module ini membuat IAM role untuk setiap Kubernetes service account.
# Setiap role hanya bisa dipakai oleh namespace + SA yang benar (trust policy).
# ============================================================

# ── IAM Role: storage-service ────────────────────────────────
# Role ini hanya bisa dipakai oleh pod yang pakai SA storage-service-sa
# di namespace storage.

data "aws_iam_policy_document" "storage_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.storage_namespace}:${var.storage_sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "storage_service" {
  name               = "${var.project_name}-storage-service-role"
  assume_role_policy = data.aws_iam_policy_document.storage_trust.json

  tags = {
    Service = "storage-service"
  }
}

# Policy: hanya boleh akses bucket miliknya sendiri
resource "aws_iam_policy" "storage_s3" {
  name = "${var.project_name}-storage-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "storage_s3" {
  role       = aws_iam_role.storage_service.name
  policy_arn = aws_iam_policy.storage_s3.arn
}


# ── IAM Role: farm-data-service ──────────────────────────────
# Hanya bisa dipakai oleh SA farm-data-service-sa di namespace farm-data

data "aws_iam_policy_document" "farmdata_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.farmdata_namespace}:${var.farmdata_sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "farmdata_service" {
  name               = "${var.project_name}-farmdata-service-role"
  assume_role_policy = data.aws_iam_policy_document.farmdata_trust.json

  tags = {
    Service = "farm-data-service"
  }
}

# Policy: hanya akses RDS spesifik + baca secret dari SSM (opsional)
resource "aws_iam_policy" "farmdata_rds" {
  name = "${var.project_name}-farmdata-rds-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRDSConnect"
        Effect = "Allow"
        Action = ["rds-db:connect"]
        Resource = [
          "arn:aws:rds-db:*:*:dbuser:${var.rds_resource_id}/farmuser"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "farmdata_rds" {
  role       = aws_iam_role.farmdata_service.name
  policy_arn = aws_iam_policy.farmdata_rds.arn
}


# ── IAM Role: frontend-service ───────────────────────────────

data "aws_iam_policy_document" "frontend_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.frontend_namespace}:${var.frontend_sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "frontend_service" {
  name               = "${var.project_name}-frontend-service-role"
  assume_role_policy = data.aws_iam_policy_document.frontend_trust.json

  tags = {
    Service = "frontend-service"
  }
}

# Frontend hanya perlu baca S3 (readonly)
resource "aws_iam_policy" "frontend_s3_readonly" {
  name = "${var.project_name}-frontend-s3-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowS3ReadOnly"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "frontend_s3" {
  role       = aws_iam_role.frontend_service.name
  policy_arn = aws_iam_policy.frontend_s3_readonly.arn
}
