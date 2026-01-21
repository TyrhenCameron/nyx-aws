# table for storing processed records
resource "aws_dynamodb_table" "records" {
  name         = "${local.name_prefix}-records"
  billing_mode = "PAY_PER_REQUEST" # for on-demand pricing
  hash_key     = "pk"              # partition key for which partition stores data
  range_key    = "sk"              # sort key for enabling range queries within partition

  # only define attributes used in keys or indexes
  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S" #string
  }

  # attributes for GSI
  attribute {
    name = "gsi1pk"
    type = "S"
  }

  attribute {
    name = "gsi1sk"
    type = "S"
  }

  global_secondary_index {
    name            = "gsi1"
    hash_key        = "gsi1pk"
    range_key       = "gsi1sk"
    projection_type = "ALL"
  }

  # time to live for automatic cleanup (try it for now)
  # chaos experiment logs (auto-cleanup)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  #point in time recoevery enabled
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${local.name_prefix}-records"
  }
}
