variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "nyx"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "lambda_memory" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "error_rate_threshold" {
  description = "Error count threshold for FIS stop condition"
  type        = number
  default     = 15
}

variable "dlq_depth_threshold" {
  description = "DLQ message count threshold for alarm"
  type        = number
  default     = 100
}
