# S3 bucket for our file uploads to trigger Lambda functions
resource "aws_s3_bucket" "uploads" {
  bucket = "${local.name_prefix}-uploads-${local.account_id}"

  tags = {
    Name = "${local.name_prefix}-uploads"
  }
}

# block public access
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for recovery
resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 event notifications to Lambda go in the S3 file
resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.aws_region
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ""
  }

  depends_on = [aws_lamba_permission.s3_invoke]
}
