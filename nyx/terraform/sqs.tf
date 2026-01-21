resource "aws_sqs_queue" "dlq" {
  name = "${local.name_prefix}-dlq"

  message_retention_seconds = 1209600 # 14 day limit

  receive_wait_time_seconds = 20 # long polling

  tags = {
    Name = "${local.name_prefix}-dlq"
  }
}

# Lambda needs this policy to send failed events DLQ
resource "aws_sqs_queue_policy" "dlq" {
  # point to the queue this policy appleis to
  queue_url = aws_sqs_queue.dlq.id

  # iam policy doc in json
  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid = "AllowLambdaSendMessage"

        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        # add messages to queue
        Action = "sqs:SendMessage"

        Resource = aws_sqs_queue.dlq.arn

        # only allow if the source is our specific Lambda and prevent other Lambdas from using our DLQ
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_lambda_function.processor.arn
          }
        }
      }
    ]
  })
}
