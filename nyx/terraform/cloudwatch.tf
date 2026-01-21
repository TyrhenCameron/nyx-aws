# monitoring, alarms, and dashboard
# allows us to see into system health provides stop conditions for FIS experiments and alerts

# alarm for lambda error rate high
# primary safety mech -> if errors spike fis experiment stops
# making alarms first for FIS as stop conditions

# Alarm States
# OK, alarm, and insufficient data
# when alarm enters alarm state the fis experiment stops

resource "aws_cloudwatch_metric_alarm" "error_rate_high" {
  # start with alarm name
  alarm_name = "${local.name_prefix}-error-rate-high"

  # comparison of metric value to threshold
  comparison_operator = "GreaterThanThreshold"

  # number of periods that must breach threshold 1= alarm immediately on first breach 3=alarm only if 3 consecutive periods breach
  evaluation_periods = 1

  #which metric to monitor
  metric_name = "Errors"     # which is the Lambda error count
  namespace   = "AWS/Lambda" # the AWS-provided Lambda metrics

  # how long each evaluation period is in seconds (so we're aggregating a minute of data)
  period = 60

  # how to aggregate the data points within the period
  statistic = "Sum" # total errors in the period

  # value that trigger the alarm
  threshold = var.error_rate_threshold # 15

  alarm_description = "Lambda error rate too high -> stops FIS experiment"

  # missing data treatment
  treat_missing_data = "notBreaching"

  # filter the metric for specific resources
  # errors metric exists for each Lambda function
  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  tags = {
    Name = "${local.name_prefix}-error-rate-high"
  }

}

# need to monitor how many messages are sitting in the Dead Letter Queue
# high dlq depth means lots of failures which means we have to shut down the chaos
resource "aws_cloudwatch_metric_alarm" "dlq_depth_high" {
  alarm_name          = "${local.name_prefix}-dlq-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1

  #sqs metric for messages that are available to receive
  metric_name = "ApproximateNumberOfMessagesVisible"
  namespace   = "AWS/SQS"

  period    = 60
  statistic = "Maximum"               # Worst case in the period
  threshold = var.dlq_depth_threshold # 100

  alarm_description  = "DLQ has too many messages -> stops FIS experiment"
  treat_missing_data = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  tags = {
    Name = "${local.name_prefix}-dlq-depth-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "latency_high" {
  alarm_name          = "${local.name_prefix}-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2

  metric_name = "Duration"
  namespace   = "AWS/Lambda"
  period      = 60

  # have to use extended_statistic instead of statistic
  extended_statistic = "p95"

  threshold = 5000 # translates to 5 seconds

  alarm_description  = "Lambda p95 latency too high"
  treat_missing_data = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  tags = {
    Name = "${local.name_prefix}-latency-high"
  }
}

# cloudwatch dashboard
# https://{region}.console.aws.amazon.com/cloudwatch/home#dashboards  (is this okay to have in code??)

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name_prefix # gives us nemesis-dev

  # dashboard body which is json
  # each widget has a type, xypos, size w/h, and properties

  dashboard_body = jsonencode({
    widgets = [
      # title widget
      {
        type   = "text"
        x      = 0  #column
        y      = 0  #row
        width  = 24 #fill width
        height = 1  # 1 row tall
        properties = {
          markdown = "Nyx AWS Chaos Engineering Dashboard"
        }
      },

      # Lambda invocations (for metric widget)
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8 # third of dashboard width
        height = 6
        properties = {
          title  = "Lambda Invocations"
          region = local.region
          # metrics array (array of an array) format should be [namespace, metric name, dimension_name, dimension_value, {options}]
          metrics = [
            [
              "AWS/Lambda",
              "Invocations",
              "FunctionName",
              aws_lambda_function.processor.function_name,

              { stat = "Sum", period = 60 }
            ]
          ]
        }
      },

      # lambda errors widget
      {
        type   = "metric"
        x      = 8 # start at column 8 (after invocations widget)
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = local.region
          # metrics array (array of an array) format should be [namespace, metric name, dimension_name, dimension_value, {options}]
          metrics = [
            [
              "AWS/Lambda",
              "Errors",
              "FunctionName",
              aws_lambda_function.processor.function_name,
              { stat = "Sum", period = 60, color = "#d62728" }
            ]
          ]
        }
      },

      # lambda duration (latency)
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Duration (p95)"
          region = local.region

          # metrics array (array of an array) format should be [namespace, metric name, dimension_name, dimension_value, {options}]
          metrics = {
            title  = "Lambda Duration (p95)"
            region = local.region
            metrics = [
              [
                "AWS/Lambda",
                "Duration",
                "FunctionName",
                aws_lambda_function.processor.function_name,
                { stat = "p95", period = 60 }
              ]
            ]
          }
        }
      },

      #dlq depth
      {
        type   = "metric"
        x      = 0
        y      = 7 # so it will be on second row of widgets
        width  = 12
        height = 6
        properties = {
          title  = "DLQ Depth"
          region = local.region
          # metrics array (array of an array) format should be [namespace, metric name, dimension_name, dimension_value, {options}]
          metrics = [
            [
              "AWS/SQS",
              "ApproximateNumberOfMessagesVisible",
              "QueueName",
              aws_sqs_queue.dlq.name,
              { stat = "Maximum", period = 60, color = "#ff7f0e" }
            ]
          ]
        }
      },
      # lambda throttles
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Throttles"
          region = local.region
          # metrics array (array of an array) format should be [namespace, metric name, dimension_name, dimension_value, {options}]
          metrics = [
            [
              "AWS/Lambda",
              "Throttles",
              "FunctionName",
              aws_lambda_function.processor.function_name,
              { stat = "Sum", period = 60, color = "#9467bd" }
            ]
          ]
        }
      }
    ]
  })
}
