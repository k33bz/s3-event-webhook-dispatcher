# deploy_python_lambda.ps1

# Check for AWS account ID environment variable or prompt for it
if (-not $env:AWS_ACCOUNT_ID) {
    $env:AWS_ACCOUNT_ID = Read-Host "Enter your AWS Account ID"
    if (-not $env:AWS_ACCOUNT_ID) {
        throw "AWS Account ID is required"
    }
}

# Deploy the Python Lambda function
& aws lambda create-function `
    --function-name "s3-link-generator" `
    --runtime "python3.11" `
    --architectures "arm64" `
    --handler "s3_link_generator.lambda_handler" `
    --role "arn:aws:iam::$env:AWS_ACCOUNT_ID/role/LambdaS3EventNotifierRole" `
    --zip-file "fileb://deployment/deployment_package.zip" `
    --region "us-east-2"

# Wait for Lambda creation
Write-Host "Waiting for Lambda function creation..."
Start-Sleep -Seconds 5

# Add environment variables
& aws lambda update-function-configuration `
    --function-name "s3-link-generator" `
    --environment "Variables={URL_EXPIRATION_SECONDS=86400,EVENT_SOURCE=s3-link-generator,EVENT_DETAIL_TYPE=file-link-generated}" `
    --region "us-east-2"

# Verify the Lambda function was created
Write-Host "Verifying Lambda function creation..."
& aws lambda get-function --function-name "s3-link-generator" --region "us-east-2"