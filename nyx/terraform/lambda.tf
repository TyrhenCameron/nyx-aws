# start with IAM execution role
resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# custom IAM policy
# least privilege
resource "aws_iam_role_policy" "lambda_custom" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda.id

  #give it policies it can do as json
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # S3: Read uploaded files
        Sid    = "S3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",       # for reading file contents
          "s3:GetObjectVersion" # for reading specific versions
        ]
        # only uploads bucket and all the objects within
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        # DynamoDB for processed records
        Sid    = "DynamoDBWrite"
        Effect = "Allow"
        Action = [
          "dynamodb: PutItem",
          "dynamodb: UpdateItem",
          "dynamodb: GetItem",
          "dynamodb: Query"
        ]
        Resource = aws_dynamodb_table.records.arn
      },
      {
        Sid    = "SQSSendToDLQ"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        # only the dlq
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

# lambda code packaging
# runs locally during terraform plan/apply

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda.zip"
  output_path = "${path.module}/../lambda.zip"
}

# lamdba function

resource "aws_lambda_function" "processor" {
  # function name
  function_name = "${local.name_prefix}-processor"

  # code location
  filename = data.archive_file.lambda.output_path

  # source code hash
  source_code_hash = data.archive_file.lambda.output_base64sha256

  # handler
  handler = "handler.lambda_handler"

  # runtime
  runtime = "python3.11"

  # execution role
  role = aws_iam_role.lambda.arn

  # memory
  # 256 mb good for simple tasks
  memory_size = var.lambda_memory

  # timeout
  timeout = var.lambda_timeout

  # environment variables
  environment {
    variables = {
      DynamoDB_TABLE = aws_dynamodb_table.records.name # "gives nemesis-dev-records"
      ENVIRONMENT    = var.environment                 # dev
    }
  }

  # dead letter queue
  # where sent failed invocations get sent
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  # x-ray tracing
  # tracing for debugging
  # shows the request flow through services
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name = "${local.name_prefix}-processor"
  }
}

# S3 perms to invoke lambda are needed else S3 gets permission denied when trying to trigger the lambda

resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name # which lambda function
  principal     = "s3.amazonaws.com"                          # the principal that is allowed to invoke
  source_arn    = aws_s3_bucket.uploads.arn                   # the S3 bucket (restricting to only our buckets)
}

# define log groups to set retention period, ensure consistent naming, and manage using terraform

resource "aws_cloudwatch_log_group" "lambda" {
  name = "aws/lambda/${aws_lambda_function.processor.function_name}"

  # define retention
  # 0 = never delete (not good for costs though)
  retention_in_days = 14
}
