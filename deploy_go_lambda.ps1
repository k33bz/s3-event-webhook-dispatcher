# deploy_go_lambda.ps1

# Check for AWS account ID environment variable or prompt for it
if (-not $env:AWS_ACCOUNT_ID) {
    $env:AWS_ACCOUNT_ID = Read-Host "Enter your AWS Account ID"
    if (-not $env:AWS_ACCOUNT_ID) {
        throw "AWS Account ID is required"
    }
}

# First, build the Go Lambda if it hasn't been built yet
if (-not (Test-Path -Path ".\s3-event-webhook-dispatcher\function.zip")) {
    Write-Host "Building Go Lambda function..."
    # Execute the Go deployment script
    & .\create_go_deployment.ps1
}

# Deploy the Go Lambda function
Write-Host "Deploying Go Lambda function..."
& aws lambda create-function `
    --function-name "s3-event-webhook-dispatcher" `
    --runtime "go1.x" `
    --architectures "arm64" `
    --handler "main" `
    --role "arn:aws:iam::$env:AWS_ACCOUNT_ID/role/LambdaS3EventNotifierRole" `
    --zip-file "fileb://s3-event-webhook-dispatcher/function.zip" `
    --region "us-east-2"

# Wait for Lambda creation
Write-Host "Waiting for Lambda function creation..."
Start-Sleep -Seconds 5

# Add environment variables
& aws lambda update-function-configuration `
    --function-name "s3-event-webhook-dispatcher" `
    --environment "Variables={WEBHOOK_URL=YOUR_DISCORD_WEBHOOK_URL}" `
    --region "us-east-2"

# Verify the Lambda function was created
Write-Host "Verifying Lambda function creation..."
& aws lambda get-function --function-name "s3-event-webhook-dispatcher" --region "us-east-2"