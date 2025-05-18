# simplified_master_deploy.ps1
# A simpler master deployment script that avoids JSON syntax errors

# Set strict error handling
$ErrorActionPreference = "Stop"

function Write-StepHeader {
    param([string]$Message)
    Write-Host ""
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

# -----------------------------------------------------------------------------------
# STEP 1: Verify that role exists and create it if needed
# -----------------------------------------------------------------------------------
Write-StepHeader "STEP 1: Verifying IAM Role for Lambda Functions"

# Check if role already exists
try {
    $roleInfo = & aws iam get-role --role-name "LambdaS3EventNotifierRole" 2>$null
    if ($roleInfo) {
        Write-Success "IAM Role 'LambdaS3EventNotifierRole' already exists, using existing role"
    } else {
        # Role doesn't exist, call create_role.ps1
        Write-Host "IAM Role not found. Creating role..."
        & .\create_role.ps1
        Write-Success "IAM Role created successfully"
    }
} catch {
    Write-Host "Error checking role: $_" -ForegroundColor Red
    Write-Host "Attempting to create role..."
    & .\create_role.ps1
}

# -----------------------------------------------------------------------------------
# STEP 2: Deploy the Python Lambda function
# -----------------------------------------------------------------------------------
Write-StepHeader "STEP 2: Deploying Python Lambda Function"

# First ensure we have a deployment package
if (-not (Test-Path -Path ".\deployment\deployment_package.zip")) {
    Write-Host "Building Python Lambda deployment package..."
    & .\create_python_deployment.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create Python deployment package" -ForegroundColor Red
        exit 1
    }
    Write-Success "Python deployment package created"
} else {
    Write-Success "Python deployment package exists"
}

# Check if the Lambda function exists
try {
    $lambdaInfo = & aws lambda get-function --function-name "s3-link-generator" --region "us-east-2" 2>$null
    if ($lambdaInfo) {
        # Function exists, update it
        Write-Host "Python Lambda function exists, updating..."
        
        # Update function code
        & aws lambda update-function-code `
            --function-name "s3-link-generator" `
            --zip-file "fileb://deployment/deployment_package.zip" `
            --region "us-east-2"
            
        # Update environment variables
        & aws lambda update-function-configuration `
            --function-name "s3-link-generator" `
            --environment "Variables={URL_EXPIRATION_SECONDS=86400,EVENT_SOURCE=s3-link-generator,EVENT_DETAIL_TYPE=file-link-generated}" `
            --region "us-east-2"
            
        Write-Success "Python Lambda function updated"
    } else {
        # Function doesn't exist, create it
        Write-Host "Creating Python Lambda function..."
        
        & aws lambda create-function `
            --function-name "s3-link-generator" `
            --runtime "python3.11" `
            --architectures "arm64" `
            --handler "s3_link_generator.lambda_handler" `
            --role "arn:aws:iam::842233511452:role/LambdaS3EventNotifierRole" `
            --zip-file "fileb://deployment/deployment_package.zip" `
            --region "us-east-2" `
            --environment "Variables={URL_EXPIRATION_SECONDS=86400,EVENT_SOURCE=s3-link-generator,EVENT_DETAIL_TYPE=file-link-generated}"
            
        Write-Success "Python Lambda function created"
    }
} catch {
    Write-Host "Error deploying Python Lambda: $_" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------------
# STEP 3: Deploy the Go Lambda function
# -----------------------------------------------------------------------------------
Write-StepHeader "STEP 3: Deploying Go Lambda Function"

# First ensure we have a deployment package
if (-not (Test-Path -Path ".\s3-event-webhook-dispatcher\function.zip")) {
    Write-Host "Building Go Lambda deployment package..."
    & .\create_clean_go_lambda.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create Go deployment package" -ForegroundColor Red
        exit 1
    }
    Write-Success "Go deployment package created"
} else {
    Write-Success "Go deployment package exists"
}

# Ask for webhook URL
$webhookUrl = Read-Host "Enter your Discord webhook URL"
if (-not $webhookUrl) {
    Write-Host "Discord webhook URL is required" -ForegroundColor Red
    exit 1
}

# Check if the Lambda function exists
try {
    $lambdaInfo = & aws lambda get-function --function-name "s3-event-webhook-dispatcher" --region "us-east-2" 2>$null
    if ($lambdaInfo) {
        # Function exists, update it
        Write-Host "Go Lambda function exists, updating..."
        
        # Update function code
        & aws lambda update-function-code `
            --function-name "s3-event-webhook-dispatcher" `
            --zip-file "fileb://s3-event-webhook-dispatcher/function.zip" `
            --region "us-east-2"
            
        # Update environment variables
        & aws lambda update-function-configuration `
            --function-name "s3-event-webhook-dispatcher" `
            --environment "Variables={WEBHOOK_URL=$webhookUrl}" `
            --region "us-east-2"
            
        Write-Success "Go Lambda function updated"
    } else {
        # Function doesn't exist, create it
        Write-Host "Creating Go Lambda function..."
        
        & aws lambda create-function `
            --function-name "s3-event-webhook-dispatcher" `
            --runtime "go1.x" `
            --architectures "arm64" `
            --handler "main" `
            --role "arn:aws:iam::842233511452:role/LambdaS3EventNotifierRole" `
            --zip-file "fileb://s3-event-webhook-dispatcher/function.zip" `
            --region "us-east-2" `
            --environment "Variables={WEBHOOK_URL=$webhookUrl}"
            
        Write-Success "Go Lambda function created"
    }
} catch {
    Write-Host "Error deploying Go Lambda: $_" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------------
# STEP 4: Set up EventBridge rules
# -----------------------------------------------------------------------------------
Write-StepHeader "STEP 4: Setting up EventBridge Rules"

# Create a rule for S3 object creation events
Write-Host "Creating rule for S3 object creation events..."
& aws events put-rule `
    --name "s3-object-created" `
    --event-pattern "{\"source\":[\"aws.s3\"],\"detail-type\":[\"Object Created\"]}" `
    --region "us-east-2"

# Add the Link Generator Lambda as a target
Write-Host "Adding Python Lambda as target for S3 events..."
& aws events put-targets `
    --rule "s3-object-created" `
    --targets "Id=1,Arn=arn:aws:lambda:us-east-2:842233511452:function:s3-link-generator" `
    --region "us-east-2"

# Grant permission for EventBridge to invoke the Lambda
try {
    Write-Host "Granting permission for EventBridge to invoke Python Lambda..."
    & aws lambda add-permission `
        --function-name "s3-link-generator" `
        --statement-id "s3-events" `
        --action "lambda:InvokeFunction" `
        --principal "events.amazonaws.com" `
        --source-arn "arn:aws:events:us-east-2:842233511452:rule/s3-object-created" `
        --region "us-east-2"
} catch {
    Write-Host "Permission might already exist or failed to add" -ForegroundColor Yellow
}

# Create a rule for Link Generator events
Write-Host "Creating rule for link generated events..."
& aws events put-rule `
    --name "link-generated" `
    --event-pattern "{\"source\":[\"s3-link-generator\"],\"detail-type\":[\"file-link-generated\"]}" `
    --region "us-east-2"

# Add the Webhook Dispatcher Lambda as a target
Write-Host "Adding Go Lambda as target for link generated events..."
& aws events put-targets `
    --rule "link-generated" `
    --targets "Id=1,Arn=arn:aws:lambda:us-east-2:842233511452:function:s3-event-webhook-dispatcher" `
    --region "us-east-2"

# Grant permission for EventBridge to invoke the Lambda
try {
    Write-Host "Granting permission for EventBridge to invoke Go Lambda..."
    & aws lambda add-permission `
        --function-name "s3-event-webhook-dispatcher" `
        --statement-id "link-events" `
        --action "lambda:InvokeFunction" `
        --principal "events.amazonaws.com" `
        --source-arn "arn:aws:events:us-east-2:842233511452:rule/link-generated" `
        --region "us-east-2"
} catch {
    Write-Host "Permission might already exist or failed to add" -ForegroundColor Yellow
}

Write-Success "EventBridge rules and targets set up successfully"

# -----------------------------------------------------------------------------------
# STEP 5: Deployment Summary
# -----------------------------------------------------------------------------------
Write-StepHeader "DEPLOYMENT COMPLETE"
Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Upload a file to your S3 bucket to test the system" -ForegroundColor Yellow
Write-Host "2. Check CloudWatch Logs for any issues" -ForegroundColor Yellow
Write-Host "3. Verify that notifications appear in your Discord channel" -ForegroundColor Yellow