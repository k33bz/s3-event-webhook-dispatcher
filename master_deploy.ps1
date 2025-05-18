# master_deploy.ps1 - Comprehensive deployment script for S3 notification system

# Set strict error handling
$ErrorActionPreference = "Stop"
$global:DeploymentSuccess = $true

# Create log directory if it doesn't exist
if (-not (Test-Path -Path ".\deployment_logs")) {
    New-Item -ItemType Directory -Path ".\deployment_logs" | Out-Null
}

# Start logging
$logFile = ".\deployment_logs\deployment_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $logFile -Append

function Write-Step {
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

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
    $global:DeploymentSuccess = $false
}

try {
    Write-Step "STEP 1: Creating IAM Role for Lambda Functions"
    
    # Create policy JSON files
    $assumeRolePolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
"@

    # Write to file with ASCII encoding
    [System.IO.File]::WriteAllText("$PWD\assume-role-policy.json", $assumeRolePolicy, [System.Text.Encoding]::ASCII)

    # Check if role already exists
    $roleExists = $false
    try {
        $roleInfo = & aws iam get-role --role-name "LambdaS3EventNotifierRole" 2>$null
        if ($roleInfo) {
            Write-Success "IAM Role 'LambdaS3EventNotifierRole' already exists, skipping creation"
            $roleExists = $true
        }
    } catch {
        # Role doesn't exist, we'll create it
    }

    if (-not $roleExists) {
        # Create role
        & aws iam create-role --role-name "LambdaS3EventNotifierRole" --assume-role-policy-document file://assume-role-policy.json
        if ($LASTEXITCODE -ne 0) { throw "Failed to create IAM role" }
        Write-Success "IAM Role created successfully"
        
        # Wait for role creation to propagate
        Write-Host "Waiting for role creation to propagate..."
        Start-Sleep -Seconds 10
    }

    # Attach policies
    & aws iam attach-role-policy --role-name "LambdaS3EventNotifierRole" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    if ($LASTEXITCODE -ne 0) { Write-Host "Warning: Policy attachment might have failed or already exists" -ForegroundColor Yellow }
    
    & aws iam attach-role-policy --role-name "LambdaS3EventNotifierRole" --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    if ($LASTEXITCODE -ne 0) { Write-Host "Warning: Policy attachment might have failed or already exists" -ForegroundColor Yellow }

    # Create EventBridge policy document
    $eventBridgePolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "events:PutEvents"
      ],
      "Resource": "*"
    }
  ]
}
"@

    # Write to file with ASCII encoding
    [System.IO.File]::WriteAllText("$PWD\eventbridge-policy.json", $eventBridgePolicy, [System.Text.Encoding]::ASCII)

    # Add EventBridge permissions
    & aws iam put-role-policy --role-name "LambdaS3EventNotifierRole" --policy-name "EventBridgePermissions" --policy-document file://eventbridge-policy.json
    if ($LASTEXITCODE -ne 0) { Write-Host "Warning: Policy attachment might have failed or already exists" -ForegroundColor Yellow }

    Write-Success "IAM policies attached successfully"

    Write-Step "STEP 2: Building Python Lambda Deployment Package"
    
    # Check if we need to build the Python package
    if (-not (Test-Path -Path ".\deployment\deployment_package.zip")) {
        # Run the Python deployment script
        & .\create_python_deployment.ps1
        if ($LASTEXITCODE -ne 0) { throw "Failed to create Python deployment package" }
    } else {
        Write-Success "Python deployment package already exists"
    }

    Write-Step "STEP 3: Deploying Python Lambda Function"
    
    # Check if function already exists
    $functionExists = $false
    try {
        $functionInfo = & aws lambda get-function --function-name "s3-link-generator" --region "us-east-2" 2>$null
        if ($functionInfo) {
            Write-Host "Lambda function 's3-link-generator' already exists, updating instead of creating" -ForegroundColor Yellow
            $functionExists = $true
        }
    } catch {
        # Function doesn't exist, we'll create it
    }

    if ($functionExists) {
        # Update function code
        & aws lambda update-function-code `
            --function-name "s3-link-generator" `
            --zip-file "fileb://deployment/deployment_package.zip" `
            --region "us-east-2"
        if ($LASTEXITCODE -ne 0) { throw "Failed to update Python Lambda function code" }
        
        # Update function configuration
        & aws lambda update-function-configuration `
            --function-name "s3-link-generator" `
            --environment "Variables={URL_EXPIRATION_SECONDS=86400,EVENT_SOURCE=s3-link-generator,EVENT_DETAIL_TYPE=file-link-generated}" `
            --region "us-east-2"
        if ($LASTEXITCODE -ne 0) { throw "Failed to update Python Lambda function configuration" }
    } else {
        # Create function
        & aws lambda create-function `
            --function-name "s3-link-generator" `
            --runtime "python3.11" `
            --architectures "arm64" `
            --handler "s3_link_generator.lambda_handler" `
            --role "arn:aws:iam::842233511452:role/LambdaS3EventNotifierRole" `
            --zip-file "fileb://deployment/deployment_package.zip" `
            --region "us-east-2" `
            --environment "Variables={URL_EXPIRATION_SECONDS=86400,EVENT_SOURCE=s3-link-generator,EVENT_DETAIL_TYPE=file-link-generated}"
        if ($LASTEXITCODE -ne 0) { throw "Failed to create Python Lambda function" }
    }

    Write-Success "Python Lambda function deployed successfully"

    Write-Step "STEP 4: Building Go Lambda Deployment Package"
    
    # Check if we need to build the Go package
    if (-not (Test-Path -Path ".\s3-event-webhook-dispatcher\function.zip")) {
        # Run the Go deployment script
        & .\create_go_deployment.ps1
        if ($LASTEXITCODE -ne 0) { throw "Failed to create Go deployment package" }
    } else {
        Write-Success "Go deployment package already exists"
    }

    Write-Step "STEP 5: Deploying Go Lambda Function"
    
    # Check if function already exists
    $functionExists = $false
    try {
        $functionInfo = & aws lambda get-function --function-name "s3-event-webhook-dispatcher" --region "us-east-2" 2>$null
        if ($functionInfo) {
            Write-Host "Lambda function 's3-event-webhook-dispatcher' already exists, updating instead of creating" -ForegroundColor Yellow
            $functionExists = $true
        }
    } catch {
        # Function doesn't exist, we'll create it
    }

    # Read webhook URL
    $webhookUrl = Read-Host "Enter your Discord webhook URL"
    if (-not $webhookUrl) {
        throw "Discord webhook URL is required"
    }

    if ($functionExists) {
        # Update function code
        & aws lambda update-function-code `
            --function-name "s3-event-webhook-dispatcher" `
            --zip-file "fileb://s3-event-webhook-dispatcher/function.zip" `
            --region "us-east-2"
        if ($LASTEXITCODE -ne 0) { throw "Failed to update Go Lambda function code" }
        
        # Update function configuration
        & aws lambda update-function-configuration `
            --function-name "s3-event-webhook-dispatcher" `
            --environment "Variables={WEBHOOK_URL=$webhookUrl}" `
            --region "us-east-2"
        if ($LASTEXITCODE -ne 0) { throw "Failed to update Go Lambda function configuration" }
    } else {
        # Create function
        & aws lambda create-function `
            --function-name "s3-event-webhook-dispatcher" `
            --runtime "go1.x" `
            --architectures "arm64" `
            --handler "main" `
            --role "arn:aws:iam::842233511452:role/LambdaS3EventNotifierRole" `
            --zip-file "fileb://s3-event-webhook-dispatcher/function.zip" `
            --region "us-east-2" `
            --environment "Variables={WEBHOOK_URL=$webhookUrl}"
        if ($LASTEXITCODE -ne 0) { throw "Failed to create Go Lambda function" }
    }

    Write-Success "Go Lambda function deployed successfully"

    Write-Step "STEP 6: Setting up EventBridge Rules"

    # Create a rule for S3 object creation events
    & aws events put-rule `
        --name "s3-object-created" `
        --event-pattern "{\"source\":[\"aws.s3\"],\"detail-type\":[\"Object Created\"]}" `
        --region "us-east-2"
    if ($LASTEXITCODE -ne 0) { Write-Host "Warning: Rule creation might have failed or already exists" -ForegroundColor Yellow }

    # Add the Link Generator Lambda as a target
    & aws events put-targets `
        --rule "s3-object-created" `
        --targets "Id=1,Arn=arn:aws:lambda:us-east-2:842233511452:function:s3-link-generator" `
        --region "us-east-2"
    if ($LASTEXITCODE -ne 0) { Write-Host "Warning: Target addition might have failed or already exists" -ForegroundColor Yellow }

    # Grant permission for EventBridge to invoke the Lambda
    try {
        & aws lambda add-permission `
            --function-name "s3-link-generator" `
            --statement-id "s3-events" `
            --action "lambda:InvokeFunction" `
            --principal "events.amazonaws.com" `
            --source-arn "arn:aws:events:us-east-2:842233511452:rule/s3-object-created" `
            --region "us-east-2"
        if ($LASTEXITCODE -ne 0) { 
            # If it fails, it might be because the permission already exists
            Write-Host "Warning: Permission addition might have failed or already exists" -ForegroundColor Yellow 
        }
    } catch {
        Write-Host "Warning: Permission addition might have failed or already exists" -ForegroundColor Yellow
    }

    # Create a rule for Link Generator events
    & aws events put-rule `
        --name "link-generated" `
        --event-pattern "{\"source\":[\"s3-link-generator\"],\"detail-type\":[\"file-link-generated\"]}" `
        --region "us-east-2"
    if ($LASTEXITCODE -ne 0) { Write-Host "Warning: Rule creation might have failed or already exists" -ForegroundColor Yellow }

    # Add the Webhook Dispatcher Lambda as a target
    & aws events put-targets `
        --rule "link-generated" `
        --targets "Id=1,Arn=arn:aws:lambda:us-east-2:842233511452:function:s3-event-webhook-dispatcher" `
        --region "us-east-2"
    if ($LASTEXITCODE -ne 0) { Write-Host "Warning: Target addition might have failed or already exists" -ForegroundColor Yellow }

    # Grant permission for EventBridge to invoke the Lambda
    try {
        & aws lambda add-permission `
            --function-name "s3-event-webhook-dispatcher" `
            --statement-id "link-events" `
            --action "lambda:InvokeFunction" `
            --principal "events.amazonaws.com" `
            --source-arn "arn:aws:events:us-east-2:842233511452:rule/link-generated" `
            --region "us-east-2"
        if ($LASTEXITCODE -ne 0) { 
            # If it fails, it might be because the permission already exists
            Write-Host "Warning: Permission addition might have failed or already exists" -ForegroundColor Yellow 
        }
    } catch {
        Write-Host "Warning: Permission addition might have failed or already exists" -ForegroundColor Yellow
    }

    Write-Success "EventBridge rules and targets set up successfully"

    # Clean up temporary files
    Remove-Item -Path ".\assume-role-policy.json" -ErrorAction SilentlyContinue
    Remove-Item -Path ".\eventbridge-policy.json" -ErrorAction SilentlyContinue

    Write-Step "DEPLOYMENT COMPLETE"
    if ($global:DeploymentSuccess) {
        Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
        Write-Host "   Log file: $logFile" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "1. Upload a file to your S3 bucket to test the system" -ForegroundColor Yellow
        Write-Host "2. Check CloudWatch Logs for any issues" -ForegroundColor Yellow
        Write-Host "3. Verify that notifications appear in your Discord channel" -ForegroundColor Yellow
    } else {
        Write-Host "⚠️ Deployment completed with warnings/errors." -ForegroundColor Yellow
        Write-Host "   Please check the log file for details: $logFile" -ForegroundColor Gray
    }

} catch {
    Write-Error "Deployment failed with error: $_"
    Write-Host "   Please check the log file for details: $logFile" -ForegroundColor Gray
} finally {
    Stop-Transcript
}