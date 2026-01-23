# iam based perms
# auto stop using cloudwatch alarms
# cloudtrail logging
# this injects chaos into the Lambda function to test how system handles Lambda failures

# FIS needs IAM role

resource "aws_iam_role" "fis" {
  name = "${local.name_prefix}-fis-role"

  #trust policy
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "fis.amazonaws.com"
        }
      }
    ]
  })
}

# needs permissions policies
resource "aws_iam_role_policy" "fis" {
  name = "${local.name_prefix}-fis-policy"
  role = aws_iam_role.fis.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Lambda Chaos Actions
        Sid    = "LambdaChaos"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionConfiguration",
          "lambda:InvokeFunction",
          "lambda:GetFunctionConcurrency",
          "lambda:PutFunctionConcurrency",
          "lambda:DeleteFunctionConcurrency"
        ]
        # allows only our specific lambda function
        Resource = aws_lambda_function.processor.arn
      },
      {
        # cloudwatch perms
        # fis needs to check alarm states to stop conditions
        Sid    = "CloudWatchAlarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms" # basically read or see alarms im pretty sure
        ]
        # allow on all alarms
        Resource = "*"
      }
    ]
  })
}

# -- experiment templates --
# Terraform AWS provider doesn't support Lambda FIS targets yet
# Create via AWS CLI after deploy

/*
resource "aws_fis_experiment_template" "lambda_throttle" {
  # description shows in FIS console and CloudTrail logs
  description = "Throttle Lambda to test S3 retry behavior and DLQ"

  # execution role fis will assume to perform actions
  role_arn = aws_iam_role.fis.arn

  # stop condition -> fis stops experiment and rolls back
  stop_condition {
    # set CloudWatch alarm as stop condition
    source = "aws:cloudwatch:alarm"
    # ARN of the alarm that is used to monitor
    value = aws_cloudwatch_metric_alarm.error_rate_high.arn
  }

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.dlq_depth_high.arn
  }

  # action -> throttle lambda
  # what chaos to inject

  action {
    # unique name for template
    name = "throttle-lambda"

    # fis action id
    # format is "aws:{service}:{action-name}"
    # this sets Lambda reserved concurrency
    action_id = "aws:lambda:function-concurrency-limit"

    description = "Set reserved concurrency to 0 (block all invocations)"

    # parameters for action
    parameter {
      key   = "value"
      value = "0" # no concurrent executions as stated above
    }

    # define target to apply this action to
    target {
      key   = "Functions"     # parameter name
      value = "lambda-target" #references target block below
    }
  }

  # target block
  target {
    # same as value in target
    name = "lambda-target"

    # format: aws:{service}:{resource-type}
    resource_type = "aws:lambda:function"

    # count(n) and percent(n) are also viable maybe
    selection_mode = "ALL" # affect all listed resource

    # list of resources that can be targeted
    resource_arns = [
      aws_lambda_function.processor.arn
    ]
  }
  tags = {
    Name       = "${local.name_prefix}-lambda-throttle"
    Experiment = "lambda-throttle"
  }
}

# experiment 2: lambda concurrency
# sets concurrency to 1
# tests queuing behavior and increased latency under load

resource "aws_fis_experiment_template" "lambda_concurrency_limit" {
  description = "Limit Lambda concurrency to 1 to test queuing behavior"
  role_arn    = aws_iam_role.fis.arn

  # only stop if errors get too high (less aggressive exp)
  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.error_rate_high.arn
  }

  action {
    name        = "limit-concurrency"
    action_id   = "aws:lambda:function-concurrency-limit"
    description = "Limit concurrency to 1 concurrent execution"

    parameter {
      key   = "value"
      value = "1" # only 1 concurrent execution allowed
    }

    target {
      key   = "Functions"
      value = "lambda-target"
    }
  }

  target {
    name           = "lambda-target"
    resource_type  = "aws:lambda:function"
    selection_mode = "ALL"

    resource_arns = [
      aws_lambda_function.processor.arn
    ]
  }

  tags = {
    Name       = "${local.name_prefix}-lambda-concurrency-limit"
    Experiment = "lambda-concurrency-limit"
  }
}
*/

# aws fis start-experiment -- experiment-template-id EXT123
# FIS assumes role -> executes actions ->
# FIS continuously checks CloudWatch alarms ->
# stop phase: a. manual stop --id EXP456 b. auto-stop (alarm enters alarm state) c. duration expires (set later)
# Rollback -> FIS calls (DeleteFunctionConcurrency) -> lambda returns to normal
