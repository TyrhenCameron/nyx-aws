# export values
# outputs are used for values needed to reference
# resource names/arns for scripts / urls for accessing services / ids for running experiments

# S3
output "s3_bucket_name" {
  # this shows up in `terraform output`
  description = "Name of the S3 upload bucket"

  # value to output
  # aws_s3_bucket.uploads.id = bucket name
  value = aws_s3_bucket.uploads.id
}

# DynamoDB
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.records.name
}

# Lambda
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.processor.arn
}

# SQS outputs
output "dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.url
}

/* dont work with terraform aws
#FIS outputs
output "fis_experiment_lambda_throttle_id" {
  description = "FIS experiment template ID for Lambda throttle"
  value       = aws_fis_experiment_template.lambda_throttle.id
  # ID used to start experiments
}

output "fis_experiment_concurrency_limit_id" {
  description = "FIS experiment template ID for Lambda concurrency limit"
  value       = aws_fis_experiment_template.lambda_concurrency_limit.id
}
*/

# Cloudwatch outputs

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"

  # need to construct console URL
  value = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${local.name_prefix}"
}

# demo commands
# shows after terraform apply

output "demo_commands" {
  description = "Commands to test the system"
  value       = <<-EOT

  # Demo Commands

  # 1. Upload test files to trigger Lambda:
  for i in {1..10}; do echo "test data $i" | aws s3 cp -
  s3://${aws_s3_bucket.uploads.id}/test-$i.txt; done

  # 2. Start Lambda throttle experiment (create via CLI first - see README)
  aws fis start-experiment --experiment-template-id <TEMPLATE_ID>

  # 3. Check DLQ depth (which should increase during chaos):
  aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.dlq.url}
  --attribute-names ApproximateNumberOfMessagesVisible

  # 4. View Lambda logs (to watch for errors)
  aws logs tail /aws/lambda/${aws_lambda_function.processor.function_name}
  --follow

  # 5. List running FIS experiments:
  aws fis list-experiments --query 'experiments[?state.status==`running`]'

  # 6. Stop an experiment manually:
  # aws fis stop-experiment --id <experiment-id>

  EOT
}

output "fis_role_arn" {
  value = aws_iam_role.fis.arn
}

output "api_endpoint" {
  description = "API Gateway endpoint for load testing"
  value       = aws_apigatewayv2_api.main.api_endpoint
}
