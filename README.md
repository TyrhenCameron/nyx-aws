# NYX

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat-square&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat-square&logo=amazonaws&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![k6](https://img.shields.io/badge/k6-7D64FF?style=flat-square&logo=k6&logoColor=white)

AWS serverless chaos engineering platform.

Named after the Greek goddess of night (mother of Eris).

## What it does

NYX is a serverless system designed to be broken. Upload a file to S3, Lambda processes it, stores metadata in DynamoDB. Hit the API Gateway for load testing. Inject failures and watch what happens.

- Does S3 retry failed invocations?
- Do messages end up in the dead letter queue?
- Does the system recover when you stop the chaos?

## Architecture

```
                         ┌─────────────────┐
                         │  API Gateway    │
                         │  (load testing) │
                         └────────┬────────┘
                                  │
S3 Bucket ──trigger──▶ Lambda ◀───┘
                          │
                          ├──write──▶ DynamoDB
                          │
                          └──failure──▶ SQS (DLQ)

CloudWatch: Alarms, Dashboard, Metrics
```

## Chaos Approach

This project uses **application-level chaos** via feature flags rather than AWS FIS.

### Why not FIS?

AWS FIS Lambda actions (`invocation-error`, `invocation-add-delay`) require an extension layer that isn't publicly accessible. The Terraform provider also doesn't support Lambda FIS targets. After testing in both `ap-northeast-1` and `us-east-1`, I implemented feature flag chaos instead.

This is actually the right approach for serverless - FIS is better suited for infrastructure-level chaos (EC2, ECS, RDS). Application-level chaos gives you more control over failure modes.

## Setup

```bash
cd nyx/terraform
terraform init
terraform apply
```

## Running Chaos

### 1. Test normal flow

```bash
# Upload files
for i in {1..5}; do echo "test $i" | aws s3 cp - s3://$(terraform output -raw s3_bucket_name)/test-$i.txt --region us-east-1; done

# Watch logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow --region us-east-1
```

### 2. Enable chaos (50% failure rate)

```bash
aws lambda update-function-configuration --function-name nyx-dev-processor --environment 'Variables={DYNAMODB_TABLE=nyx-dev-records,ENVIRONMENT=dev,CHAOS_MODE=true,CHAOS_RATE=0.5}' --region us-east-1
```

### 3. Run load test during chaos

Terminal 1 - k6 load test:
```bash
k6 run nyx/tools/load-test.js
```

Terminal 2 - S3 uploads:
```bash
for i in {1..20}; do echo "chaos $i" | aws s3 cp - s3://$(terraform output -raw s3_bucket_name)/chaos-$i.txt --region us-east-1; sleep 1; done
```

### 4. Observe

- **CloudWatch Dashboard**: Lambda errors spike, DLQ depth increases
- **k6 output**: ~50% of API requests return 500
- **Logs**: "CHAOS: Injecting simulated failure" messages

### 5. Disable chaos

```bash
aws lambda update-function-configuration --function-name nyx-dev-processor --environment 'Variables={DYNAMODB_TABLE=nyx-dev-records,ENVIRONMENT=dev,CHAOS_MODE=false}' --region us-east-1
```

### 6. Verify recovery

```bash
for i in {1..3}; do echo "recovery $i" | aws s3 cp - s3://$(terraform output -raw s3_bucket_name)/recovery-$i.txt --region us-east-1; done
```

## What to expect

| Phase | Lambda Errors | DLQ Depth | API Response |
|-------|---------------|-----------|--------------|
| Normal | 0 | 0 | 200 |
| Chaos | ~50% | Increasing | ~50% 500s |
| Recovery | 0 | Stable | 200 |

## Key Learnings

1. **FIS has limitations** - Lambda actions require inaccessible extension layers
2. **Feature flags work** - Application-level chaos is often more practical for serverless
3. **Two failure paths** - S3 triggers raise exceptions (DLQ), API returns 500 (graceful)
4. **Observability matters** - Can't do chaos without metrics

## Cleanup

```bash
terraform destroy
```
