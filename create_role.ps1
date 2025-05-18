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

# Write to file with UTF8 encoding (no BOM)
[System.IO.File]::WriteAllText("$PWD\assume-role-policy.json", $assumeRolePolicy, [System.Text.Encoding]::ASCII)

# Create role
& aws iam create-role --role-name "LambdaS3EventNotifierRole" --assume-role-policy-document file://assume-role-policy.json

# Wait for role creation to propagate
Write-Host "Waiting for role creation to propagate..."
Start-Sleep -Seconds 5

# Attach policies
& aws iam attach-role-policy --role-name "LambdaS3EventNotifierRole" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
& aws iam attach-role-policy --role-name "LambdaS3EventNotifierRole" --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"

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

# Write to file with UTF8 encoding (no BOM)
[System.IO.File]::WriteAllText("$PWD\eventbridge-policy.json", $eventBridgePolicy, [System.Text.Encoding]::ASCII)

# Add EventBridge permissions
& aws iam put-role-policy --role-name "LambdaS3EventNotifierRole" --policy-name "EventBridgePermissions" --policy-document file://eventbridge-policy.json

# Wait for IAM changes to propagate
Write-Host "Waiting for IAM changes to propagate..."
Start-Sleep -Seconds 10

# Verify role creation
Write-Host "Verifying role creation..."
& aws iam get-role --role-name "LambdaS3EventNotifierRole"