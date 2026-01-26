# NYX Setup Guide

## Deployment Issues & Resolutions

### Issue 1: Terraform FIS Provider Limitation

**Problem**: Terraform AWS provider doesn't support Lambda FIS targets. The `Functions` key isn't in the allowed target list.

**Error**:
```
expected action.0.target.0.key to be one of ["AutoScalingGroups" "Buckets" ...], got Functions
```

**Resolution**: Comment out FIS experiment templates in `fis.tf` and create them via AWS CLI after deployment.

---

### Issue 2: S3 Bucket Name Propagation Delay

**Problem**: After deleting an S3 bucket in ap-northeast-1, AWS wouldn't allow creating a bucket with the same name in us-east-1 due to global namespace propagation delays.

**Error**:
```
AuthorizationHeaderMalformed: The authorization header is malformed; the region 'us-east-1' is wrong; expecting 'ap-northeast-1'
```

**Resolution**: Added `-use1` suffix to bucket name in `s3.tf`:
```hcl
bucket = "${local.name_prefix}-uploads-${local.account_id}-use1"
```

---

### Issue 3: Lambda SQS Permission Race Condition

**Problem**: Lambda creation failed because IAM policy wasn't propagated yet.

**Error**:
```
The provided execution role does not have permissions to call SendMessage on SQS
```

**Resolution**: Added `depends_on` in `lambda.tf`:
```hcl
depends_on = [
  aws_iam_role_policy.lambda_custom
]
```

---

### Issue 4: Orphaned AWS Resources

**Problem**: Failed Terraform applies left orphaned resources (IAM roles, DynamoDB tables, etc.) that blocked subsequent deployments.

**Resolution**: Manual cleanup commands:
```bash
# IAM Roles (global)
aws iam detach-role-policy --role-name nyx-dev-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name nyx-dev-lambda-role
aws iam delete-role --role-name nyx-dev-fis-role

# DynamoDB (regional)
aws dynamodb delete-table --table-name nyx-dev-records --region us-east-1

# S3 with versioning
aws s3api delete-objects --bucket BUCKET_NAME --delete "$(aws s3api list-object-versions --bucket BUCKET_NAME --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)"
aws s3api delete-objects --bucket BUCKET_NAME --delete "$(aws s3api list-object-versions --bucket BUCKET_NAME --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)"
aws s3 rb s3://BUCKET_NAME

# SQS
aws sqs delete-queue --queue-url QUEUE_URL --region us-east-1

# CloudWatch
aws cloudwatch delete-alarms --alarm-names nyx-dev-error-rate-high nyx-dev-dlq-depth-high nyx-dev-latency-high --region us-east-1
aws cloudwatch delete-dashboards --dashboard-names nyx-dev --region us-east-1
```

---

## Fresh Deployment Steps

1. **Initialize Terraform**:
   ```bash
   cd nyx/terraform
   rm -rf .terraform terraform.tfstate*
   terraform init
   ```

2. **Validate and Deploy**:
   ```bash
   terraform validate
   terraform apply
   ```

3. **Create FIS Experiment via CLI**:
   ```bash
   aws fis create-experiment-template \
     --cli-input-json file://fis-experiment.json \
     --region us-east-1
   ```

---

## Current Deployment (us-east-1)

| Resource | Value |
|----------|-------|
| S3 Bucket | `nyx-dev-uploads-<YOUR-ACCOUNT-ID>-use1` |
| Lambda | `nyx-dev-processor` |
| DynamoDB | `nyx-dev-records` |
| DLQ | `nyx-dev-dlq` |
| API Gateway | `https://<YOUR-API-ID>.execute-api.us-east-1.amazonaws.com` |
| Dashboard | `nyx-dev` |

---

## Key Learnings

1. **S3 bucket names are globally unique** - even after deletion, propagation delays can block reuse in different regions
2. **IAM is global** - roles created in one region exist everywhere
3. **Terraform provider limitations** - not all AWS features are supported; CLI is the fallback
4. **Always use `depends_on`** for IAM policies attached to Lambda
5. **Clean up failed deployments** - partial applies leave orphaned resources
