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
import random

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
# newly added environment variables for us deployment
CHAOS_ENABLED = os.environ.get('CHAOS_MODE', 'false') == 'true'
CHAOS_RATE = float(os.environ.get('CHAOS_RATE', '0.5'))

def lambda_handler(event: dict, context: Any) -> dict:
    """
    Main entry point. Routes to correct handler based on event source.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    if 'Records' in event:
        # S3 trigger
        return process_s3_event(event, context)
    else:
        # API Gateway trigger
        return process_api_event(event, context)

def process_s3_event(event: dict, context: Any) -> dict:
    """
    Process S3 trigger events.
    """
    table = dynamodb.Table(TABLE_NAME)
    processed = 0
    errors = []

    for record in event.get('Records', []):
        try:
            result = process_s3_record(record, table)
            if result:
                processed += 1
        except Exception as e:
            logger.error(f"Error processing record: {e}")
            errors.append(str(e))
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

def process_api_event(event: dict, context: Any) -> dict:
    """
    Process API Gateway requests for load testing.
    """
    table = dynamodb.Table(TABLE_NAME)

    if CHAOS_ENABLED and random.random() < CHAOS_RATE:
        logger.warning("CHAOS: Injecting simulated failure")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Chaos injection: simulated failure'})
        }

    try:
        body = json.loads(event.get('body', '{}'))

        record_id = hashlib.sha256(
            f"api/{body.get('filename', 'unknown')}/{datetime.now(timezone.utc).isoformat()}".encode()
        ).hexdigest()[:16]

        item = {
            'pk': f"FILE#{record_id}",
            'sk': f"PROCESSED#{datetime.now(timezone.utc).isoformat()}",
            'gsi1pk': datetime.now(timezone.utc).strftime('%Y-%m-%d'),
            'gsi1sk': f"FILE#{record_id}",
            'source': 'api',
            'filename': body.get('filename', 'unknown'),
            'content_length': len(body.get('content', '')),
            'processed_at': datetime.now(timezone.utc).isoformat(),
            'environment': ENVIRONMENT,
            'ttl': int(datetime.now(timezone.utc).timestamp()) + (7 * 24 * 60 * 60)
        }

        table.put_item(Item=item)
        logger.info(f"Stored API record: {item['pk']}")

        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Processed', 'id': record_id})
        }

    except Exception as e:
        logger.error(f"API processing error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def process_s3_record(record: dict, table) -> bool:
    """
    Process S3 trigger events.
    """

    # feature flag chaos injection
    if CHAOS_ENABLED and random.random() < CHAOS_RATE:
        logger.warning("CHAOS: Injecting simulated failure")
        raise Exception("Chaos injection: simulated failure")

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
    """

    return {
        'processed_count': 0,
        'error_count': 0,
        'avg_duration_ms': 0
    }
