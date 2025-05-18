# setup_eventbridge.ps1

# Create a rule for S3 object creation events
& aws events put-rule `
    --name "s3-object-created" `
    --event-pattern "{\"source\":[\"aws.s3\"],\"detail-type\":[\"Object Created\"]}" `
    --region "us-east-2"

# Add the Link Generator Lambda as a target
& aws events put-targets `
    --rule "s3-object-created" `
    --targets "Id=1,Arn=arn:aws:lambda:us-east-2:842233511452:function:s3-link-generator" `
    --region "us-east-2"

# Grant permission for EventBridge to invoke the Lambda
& aws lambda add-permission `
    --function-name "s3-link-generator" `
    --statement-id "s3-events" `
    --action "lambda:InvokeFunction" `
    --principal "events.amazonaws.com" `
    --source-arn "arn:aws:events:us-east-2:842233511452:rule/s3-object-created" `
    --region "us-east-2"

# Create a rule for Link Generator events
& aws events put-rule `
    --name "link-generated" `
    --event-pattern "{\"source\":[\"s3-link-generator\"],\"detail-type\":[\"file-link-generated\"]}" `
    --region "us-east-2"

# Add the Webhook Dispatcher Lambda as a target
& aws events put-targets `
    --rule "link-generated" `
    --targets "Id=1,Arn=arn:aws:lambda:us-east-2:842233511452:function:s3-event-webhook-dispatcher" `
    --region "us-east-2"

# Grant permission for EventBridge to invoke the Lambda
& aws lambda add-permission `
    --function-name "s3-event-webhook-dispatcher" `
    --statement-id "link-events" `
    --action "lambda:InvokeFunction" `
    --principal "events.amazonaws.com" `
    --source-arn "arn:aws:events:us-east-2:842233511452:rule/link-generated" `
    --region "us-east-2"

Write-Host "EventBridge rules and targets have been set up!"