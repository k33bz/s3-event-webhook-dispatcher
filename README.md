# S3 Event Webhook Dispatcher

A serverless Go microservice that dispatches notifications to webhook endpoints (like Discord) when files are uploaded to Amazon S3 buckets.

## Overview

This Lambda function is designed to be part of a serverless event-driven architecture that works as follows:

1. Files are uploaded to an S3 bucket
2. S3 sends events to EventBridge
3. A Link Generator Lambda creates pre-signed URLs for the uploaded files
4. The Link Generator publishes events to EventBridge
5. This Webhook Dispatcher Lambda receives those events and forwards them to a webhook endpoint

The service is optimized for AWS Lambda using the arm64 architecture for better performance and cost-efficiency.

## Features

- Configurable through environment variables - no code changes needed for most use cases
- Optimized for Discord webhooks by default, but adaptable to other webhook APIs
- Proper error handling and timeout management
- Built for AWS Lambda arm64 architecture for better cost efficiency
- Part of an extensible event-driven architecture

## Architecture Diagram

```
┌─────────┐    ┌─────────────┐    ┌───────────────┐    ┌─────────────┐    ┌─────────────────┐    ┌────────┐
│         │    │             │    │               │    │             │    │                 │    │        │
│   S3    │───►│ EventBridge │───►│ Link Generator│───►│ EventBridge │───►│ Webhook Dispatch│───►│Discord │
│ Bucket  │    │             │    │    Lambda     │    │             │    │     Lambda      │    │        │
└─────────┘    └─────────────┘    └───────────────┘    └─────────────┘    └─────────────────┘    └────────┘
```

## Prerequisites

- Go 1.x
- AWS CLI
- An AWS account
- A Discord webhook URL (or other webhook endpoint)

## Configuration (Environment Variables)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WEBHOOK_URL` | Yes | - | The webhook URL to send notifications to |
| `MESSAGE_TEMPLATE` | No | Template with file details | Format string for the message (use %s placeholders) |
| `REQUEST_TIMEOUT_SECONDS` | No | 10 | Timeout for webhook HTTP requests |
| `EMBED_COLOR` | No | 3447003 (Discord blue) | Color code for Discord embeds |
| `FOOTER_TEXT` | No | "S3 File Notification System" | Text to display in the footer |

## Building and Deploying

### Build for ARM64 Lambda

```bash
GOOS=linux GOARCH=arm64 go build -o main main.go
zip function.zip main
```

### Deploy with AWS CLI

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

### Deploy with AWS SAM

Create a template.yaml file:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Resources:
  WebhookDispatcher:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: .
      Handler: main
      Runtime: go1.x
      Architectures:
        - arm64
      Environment:
        Variables:
          WEBHOOK_URL: your-webhook-url
```

Then deploy:

```bash
sam build
sam deploy --guided
```

## Integrating with EventBridge

Create an EventBridge rule that filters for the events published by your Link Generator:

```json
{
  "source": ["s3-link-generator"],
  "detail-type": ["file-link-generated"]
}
```

Set the target of this rule to your s3-event-webhook-dispatcher Lambda function.

## Testing

You can test the Lambda function locally using the AWS SAM CLI:

```bash
sam local invoke -e event.json
```

With event.json containing:

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

## Customization

### For Different Webhook Services

To adapt this for other webhook services besides Discord, you would need to modify:

1. The message structure in the handler function
2. Potentially the environment variables to capture service-specific parameters

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
