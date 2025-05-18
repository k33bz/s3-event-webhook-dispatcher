import json
import os
import boto3
import logging
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
eventbridge_client = boto3.client('events')

def lambda_handler(event, context):
    """
    Generate a pre-signed URL for an S3 object and publish an event to EventBridge.
    
    This function is triggered by S3 object creation events via EventBridge.
    It generates a pre-signed URL for the new object and publishes an event
    with the URL and metadata for further processing.
    
    Args:
        event (dict): The EventBridge event containing S3 object details
        context (LambdaContext): Lambda runtime information
        
    Returns:
        dict: Response indicating success or failure
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Extract S3 bucket and object key from the event
        bucket_name = event.get('detail', {}).get('bucket', {}).get('name')
        object_key = event.get('detail', {}).get('object', {}).get('key')
        
        if not bucket_name or not object_key:
            logger.error("Failed to extract bucket name or object key from event")
            return {
                'statusCode': 400,
                'body': json.dumps('Invalid event structure')
            }
        
        # Get URL expiration time from environment variable or use default
        expiration_seconds = int(os.environ.get('URL_EXPIRATION_SECONDS', 86400))  # Default: 24 hours
        expiration_text = format_expiration_time(expiration_seconds)
        
        # Generate pre-signed URL
        try:
            presigned_url = s3_client.generate_presigned_url(
                'get_object',
                Params={
                    'Bucket': bucket_name,
                    'Key': object_key
                },
                ExpiresIn=expiration_seconds
            )
            logger.info(f"Generated pre-signed URL for {bucket_name}/{object_key}")
        except ClientError as e:
            logger.error(f"Failed to generate pre-signed URL: {e}")
            return {
                'statusCode': 500,
                'body': json.dumps('Error generating pre-signed URL')
            }
        
        # Create payload for EventBridge
        payload = {
            'fileName': object_key,
            'fileUrl': presigned_url,
            'bucket': bucket_name,
            'expirationTime': expiration_text,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Get EventBridge configuration from environment variables
        event_source = os.environ.get('EVENT_SOURCE', 's3-link-generator')
        detail_type = os.environ.get('EVENT_DETAIL_TYPE', 'file-link-generated')
        event_bus_name = os.environ.get('EVENT_BUS_NAME', 'default')
        
        # Publish event to EventBridge
        try:
            response = eventbridge_client.put_events(
                Entries=[
                    {
                        'Source': event_source,
                        'DetailType': detail_type,
                        'Detail': json.dumps(payload),
                        'EventBusName': event_bus_name
                    }
                ]
            )
            logger.info(f"Published event to EventBridge: {response}")
        except ClientError as e:
            logger.error(f"Failed to publish event to EventBridge: {e}")
            return {
                'statusCode': 500,
                'body': json.dumps('Error publishing event to EventBridge')
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully generated pre-signed URL and published event')
        }
    
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Unexpected error: {str(e)}')
        }

def format_expiration_time(seconds):
    """
    Format the expiration time in a human-readable format.
    
    Args:
        seconds (int): Expiration time in seconds
        
    Returns:
        str: Formatted expiration time (e.g., "24 hours")
    """
    if seconds < 60:
        return f"{seconds} seconds"
    elif seconds < 3600:
        minutes = seconds // 60
        return f"{minutes} minute{'s' if minutes != 1 else ''}"
    elif seconds < 86400:
        hours = seconds // 3600
        return f"{hours} hour{'s' if hours != 1 else ''}"
    else:
        days = seconds // 86400
        return f"{days} day{'s' if days != 1 else ''}"