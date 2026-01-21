# NYX

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat-square&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat-square&logo=amazonaws&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)

AWS chaos engineering platform using Terraform and FIS.

Named after the Greek goddess of night (mother of Eris).

## What it does

NYX is a serverless system designed to be broken. Upload a file to S3, Lambda processes it, stores metadata in DynamoDB. Simple enough - until you start injecting failures.

The chaos layer uses AWS Fault Injection Simulator to throttle Lambda, then watches what happens. Does S3 retry? Do messages end up in the dead letter queue? Does the system recover when you stop the chaos?

## Architecture

```
S3 Bucket ──trigger──▶ Lambda ──write──▶ DynamoDB
                          │
                          └── on failure ──▶ SQS (DLQ)

AWS FIS watches CloudWatch alarms and auto-stops if things get too broken.
```

## Setup

```bash
cd terraform
terraform init
terraform apply
```

## Running chaos

```bash
# Upload some test files
BUCKET=$(terraform output -raw s3_bucket_name)
for i in {1..10}; do
  echo "test $i" | aws s3 cp - s3://$BUCKET/test-$i.txt
done

# Break things
aws fis start-experiment \
  --experiment-template-id $(terraform output -raw fis_experiment_lambda_throttle_id)

# Watch the dashboard
terraform output cloudwatch_dashboard_url
```

## Experiments

**Lambda Throttle** - Sets concurrency to 0, blocking all invocations. S3 retries until it gives up and messages land in the DLQ.

**Concurrency Limit** - Allows only 1 concurrent execution. Good for seeing how the system handles queuing under load.

Both experiments auto-stop if error rates spike too high (CloudWatch alarms trigger FIS stop conditions).

## Cleanup

```bash
terraform destroy
```
