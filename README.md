# S3 File Notification System

A serverless architecture that automatically generates temporary download links and sends webhook notifications (e.g., to Discord) when files are uploaded to Amazon S3 buckets.

## Architecture Overview

This system uses a serverless event-driven architecture that works as follows:

1. Files are uploaded to an S3 bucket
2. S3 sends object creation events to EventBridge
3. The `s3_link_generator` Lambda (Python) creates pre-signed URLs for the uploaded files
4. The Link Generator publishes events to EventBridge
5. The `s3-event-webhook-dispatcher` Lambda (Go) receives those events and forwards them to a webhook endpoint

The architecture is optimized for AWS Lambda using the arm64 architecture for better performance and cost-efficiency.

```
┌─────────┐    ┌─────────────┐    ┌────────────────┐    ┌─────────────┐    ┌─────────────────┐    ┌────────┐
│         │    │             │    │                │    │             │    │                 │    │        │
│   S3    │───►│ EventBridge │───►│ s3_link_      │───►│ EventBridge │───►│ s3-event-       │───►│Discord │
│ Bucket  │    │             │    │ generator     │    │             │    │ webhook-        │    │        │
│         │    │             │    │ (Python/arm64)│    │             │    │ dispatcher      │    │        │
│         │    │             │    │               │    │             │    │ (Go/arm64)      │    │        │
└─────────┘    └─────────────┘    └────────────────┘    └─────────────┘    └─────────────────┘    └────────┘
```

## Features

- Automatically create temporary download links for uploaded files
- Send notifications to Discord (or other webhook endpoints)
- Highly configurable through environment variables
- Cost-efficient with arm64 architecture
- Proper error handling and timeout management
- Extensible event-driven architecture

## Lambda Functions

### 1. S3 Link Generator (Python 3.11, ARM64)

Located in `s3_link_generator.py`, this Lambda function:
- Is triggered by S3 object creation events via EventBridge
- Generates a pre-signed URL for the newly uploaded file
- Publishes an event to EventBridge with the file information and URL
- Configurable expiration time for pre-signed URLs

Environment Variables:
- `URL_EXPIRATION_SECONDS`: Time in seconds until the pre-signed URL expires (default: 86400)
- `EVENT_SOURCE`: Source name for the EventBridge event (default: 's3-link-generator')
- `EVENT_DETAIL_TYPE`: Detail type for the EventBridge event (default: 'file-link-generated')
- `EVENT_BUS_NAME`: EventBridge bus to publish events to (default: 'default')

### 2. S3 Event Webhook Dispatcher (Go, ARM64)

Located in the `main.go` file, this Lambda function:
- Is triggered by the events published by the S3 Link Generator
- Formats the file information into a webhook-friendly format
- Sends the information to a configured webhook endpoint (e.g., Discord)
- Handles retries and error reporting

Environment Variables:
- `WEBHOOK_URL`: The webhook URL to send notifications to (required)
- `MESSAGE_TEMPLATE`: Format string for the message (optional)
- `REQUEST_TIMEOUT_SECONDS`: Timeout for webhook HTTP requests (default: 10)
- `EMBED_COLOR`: Color code for Discord embeds (default: 3447003)
- `FOOTER_TEXT`: Text to display in the footer (default: "S3 File Notification System")

## Prerequisites

- AWS CLI configured with appropriate permissions
- Go 1.x (for building the webhook dispatcher)
- Python 3.11 (for building the link generator)
- An AWS account
- A Discord webhook URL (or other webhook endpoint)

## Deployment Instructions

### Building and Deploying the S3 Link Generator

1. Create a virtual environment and install dependencies:
```bash
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install boto3
```

2. Create a deployment package:
```bash
mkdir -p deployment/package
pip install --target ./deployment/package boto3
cd deployment/package
zip -r ../deployment_package.zip .
cd ..
zip -g deployment_package.zip ../s3_link_generator.py
```

3. Deploy to AWS Lambda:
```bash
aws lambda create-function \
    --function-name s3-link-generator \
    --runtime python3.11 \
    --architectures arm64 \
    --handler s3_link_generator.lambda_handler \
    --role your-lambda-execution-role-arn \
    --zip-file fileb://deployment_package.zip \
    --environment "Variables={URL_EXPIRATION_SECONDS=86400}"
```

### Building and Deploying the S3 Event Webhook Dispatcher

1. Build for ARM64 Lambda:
```bash
GOOS=linux GOARCH=arm64 go build -o main main.go
zip function.zip main
```

2. Deploy to AWS Lambda:
```bash
aws lambda create-function \
  --function-name s3-event-webhook-dispatcher \
  --runtime go1.x \
  --architectures arm64 \
  --handler main \
  --zip-file fileb://function.zip \
  --role your-lambda-execution-role-arn \
  --environment "Variables={WEBHOOK_URL=your-webhook-url}"
```

### Setting up EventBridge Rules

1. Create a rule for S3 object creation events:
```bash
aws events put-rule \
    --name s3-object-created \
    --event-pattern '{
      "source": ["aws.s3"],
      "detail-type": ["Object Created"]
    }'
```

2. Add the Link Generator Lambda as a target:
```bash
aws events put-targets \
    --rule s3-object-created \
    --targets '[{
      "Id": "1",
      "Arn": "arn:aws:lambda:region:account-id:function:s3-link-generator"
    }]'
```

3. Create a rule for Link Generator events:
```bash
aws events put-rule \
    --name link-generated \
    --event-pattern '{
      "source": ["s3-link-generator"],
      "detail-type": ["file-link-generated"]
    }'
```

4. Add the Webhook Dispatcher Lambda as a target:
```bash
aws events put-targets \
    --rule link-generated \
    --targets '[{
      "Id": "1",
      "Arn": "arn:aws:lambda:region:account-id:function:s3-event-webhook-dispatcher"
    }]'
```

5. Grant permissions for EventBridge to invoke Lambdas:
```bash
aws lambda add-permission \
    --function-name s3-link-generator \
    --statement-id s3-object-created \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:region:account-id:rule/s3-object-created

aws lambda add-permission \
    --function-name s3-event-webhook-dispatcher \
    --statement-id link-generated \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:region:account-id:rule/link-generated
```

## Testing

### Testing the S3 Link Generator

Create a test event in the Lambda console:

```json
{
  "detail-type": "Object Created",
  "source": "aws.s3",
  "detail": {
    "bucket": {
      "name": "your-bucket-name"
    },
    "object": {
      "key": "test-file.pdf"
    }
  }
}
```

### Testing the S3 Event Webhook Dispatcher

Create a test event in the Lambda console:

```json
{
  "detail-type": "file-link-generated",
  "source": "s3-link-generator",
  "detail": {
    "fileName": "test-file.pdf",
    "fileUrl": "https://example-bucket.s3.amazonaws.com/test-file.pdf?signature...",
    "bucket": "example-bucket",
    "expirationTime": "24 hours",
    "timestamp": "2025-05-17T10:00:00Z"
  }
}
```

## Development Setup

### Git Configuration

Before committing to this repository, make sure to configure your Git identity:

```bash
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

This ensures your commits are properly attributed to you.

## Customization

### For Different Webhook Services

To adapt this for other webhook services besides Discord:

1. Modify the message structure in the `handler` function of the Go Lambda
2. Update environment variables to capture service-specific parameters

### Adjusting URL Expiration Time

Set the `URL_EXPIRATION_SECONDS` environment variable for the Link Generator Lambda to change how long the temporary download links remain valid.

## Monitoring and Logging

Both Lambda functions include comprehensive logging. You can monitor them through:

- CloudWatch Logs
- CloudWatch Metrics
- X-Ray (if enabled)

## Security Considerations

- The pre-signed URLs grant temporary access to S3 objects without requiring AWS credentials
- Consider using shorter expiration times for sensitive files
- Review IAM permissions to ensure least privilege
- Consider adding IP restrictions to the S3 bucket policy

## Cost Considerations

This architecture is designed to be cost-efficient:

- ARM64 Lambda architecture reduces compute costs
- EventBridge and Lambda costs remain minimal for low-volume use cases (31 files/month)
- S3 costs depend on storage and data transfer
- All components stay within AWS free tier limits for the expected usage (5-31 files/month)

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
