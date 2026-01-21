"""
- Triggered by S3 file uploads
- reads file metadata from s3
- stores records in dynamodb
- fails gracefully to dlq when things go wrong

target of chaos experiments
"""

import json
import os # access environment variables
import logging # for cloudwatch
import boto3
from datetime import datetime, timezone
from typing import Any
import hashlib # generate unique IDs

# logging for structured output with levels (info, error, etc.)
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# aws client initialization
# boto3 clients are interface to AWS service

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# environment variables
# set by terraform in the Lambda configuration

TABLE_NAME = os.environ.get('DYNAMODB_TABLE', 'nyx-dev-records')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def lambda_handler(event: dict, context: Any) -> dict:
    """
    AWS Lambda invokes this function with:
    event = Input data (S3 event in our case)
    context = Runtime info (request ID, time remaining, etc.)

    Returns:
    dictionary with statusCode and body (standard Lambda response format)

    S3 Event Structure

    {
        "Records": [
        {
            "eventSource": "aws:s3",
            "eventTime": "2024-01-15T10:30:00.000Z",
            "eventName": "ObjectCreated:Put:",
            "s3": {
                "bucket": {
                "name": "nemesis-dev-uploads-123456789012:
            },
            "object": {
                "key": "test-file.txt",
                "size": 1024,
                "eTag": "abc123..."
                }
            }
        }
    ]
    }
    """
    # log incoming event
    logger.info(f"Received event: {json.dumps(event)}")

    # get dynamodb table ref
    table = dynamodb.Table(TABLE_NAME)

    # track processing results
    processed = 0
    errors = []

    # process each S3 record
    for record in event.get('Records', []):
        try:
            # process single record
            result = process_s3_record(record, table)
            if result:
                processed += 1

        except Exception as e:
            logger.error(f"Error processing record: {e}")
            errors.append(str(e))

            # re-raising the exception is important
            # re-reraise -> lambda retries invocation (2 time if async) -> send to dlq after retries exhausted
            raise

    response = {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Processing complete',
            'processed': processed,
            'errors': errors
        })
    }
    logger.info(f"Response: {response}")
    return response

def process_s3_record(record: dict, table) -> bool:
    """
    Process a single S3 event record

    1. Extract S3 bucket and key from event
    2. Call S3 API to get object metadata
    3. Create DynamoDB item
    4. Write to DynamoDB

    Args:
        record: Single S3 event record (from Records array)
        table: DynamoDB tables resource

    Returns:
        True if successful

    Raises:
        Exception on any failure (triggers retry/DLQ)
    """

    # extracting S3 details from events SUPER NESTED
    bucket = record['s3']['bucket']['name'] # nyx-dev-uploads-123456
    key = record['s3']['object']['key'] # test-file.txt
    size = record['s3']['object'].get('size', 0) #1024 bytes or w/e
    event_time = record.get('eventTime', datetime.now(timezone.utc).isoformat())

    logger.info(f"Processing: s3://{bucket}/{key}")

    # get object metadata S3
    # head_object gets metadata WITHOUT downloading the file
    # faster and cheaper than get_object

    try:
        response = s3.head_object(Bucket=bucket, Key=key)

        # extract useful metadata
        content_type = response.get('ContentType', 'unknown') # "text/plain"
        etag = response.get('ETag', '').strip('"') # to remove quotes from ETag

    except s3.exceptions.ClientError as e:
        # handling S3 errors for nosuchkey, accessdenied, w/e
        logger.error(f"Failed to get S3 object metadata: {e}")
        raise # all important re-raise for retry/dlq

    record_id = hashlib.sha256(
        f"{bucket}/{key}/{event_time}".encode()
    ).hexdigest()[:16] # first 16 chars of hash

    # dynamodb item prep

    #define structure: dictionary of attribute name -> value
    item = {
        'pk': f"FILE#{record_id}",
        'sk': f"PROCESSED#{event_time}",

        # GSI keys for time-based queries
        'gsi1pk': event_time[:10], # date only
        'gsi1sk': f"FILE#{record_id}", # for uniqueness

        # S3 Metadata
        'bucket': bucket,
        'key': key,
        'size': size,
        'content_type': content_type,
        'etag':etag,

        'processed_at': datetime.now(timezone.utc).isoformat(),
        'environment': ENVIRONMENT,
        'lambda_request_id': '',

        'ttl': int(datetime.now(timezone.utc).timestamp()) + (7 * 24 * 60 * 60)
    }

    # write to dynamodb

    try:
        # put_item to create or overwrite an item
        table.put_item(Item=item)
        logger.info(f"Stored record: {item['pk']}")

    except Exception as e:
        # for dynamodb errors: throttling, validation, etc.
        logger.error(f"Failed to write to DynamoDB: {e}")
        raise # re-raise as above for retry/DLQ

    return True

def get_metrics() -> dict:
    """
    Get processing metrics for steady state validation

    In a production system, you might:
    - Query CloudWatch for Lambda metrics
    - Check DLQ depth
    - Aggregate DynamoDB item counts

    Use this for expansion later
    """

    return {
        'processed_count': 0,
        'error_count': 0,
        'avg_duration_ms': 0
    }
