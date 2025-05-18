# Script for creating a deployment package for the Python Lambda function
# Adapted for your actual directory structure with flexible filename detection

# Set working directory to script location (root project directory)
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -Path $scriptPath

# Create a deployment directory if it doesn't exist
if (-not (Test-Path -Path "deployment")) {
    New-Item -ItemType Directory -Path "deployment"
    Write-Host "Created deployment directory"
}

# Create a package directory for dependencies
if (-not (Test-Path -Path "deployment\package")) {
    New-Item -ItemType Directory -Path "deployment\package"
    Write-Host "Created package directory"
}

# Install dependencies
Write-Host "Installing dependencies..."
pip install --target .\deployment\package boto3 --upgrade

# Check for the Python file in the s3-link-generator directory with different naming conventions
$possibleFiles = @(
    ".\s3-link-generator\s3_link_generator.py",
    ".\s3-link-generator\s3-link-generator.py",
    ".\s3-link-generator\main.py",
    ".\s3-link-generator\lambda_function.py",
    ".\s3-link-generator\handler.py"
)

$pythonFilePath = $null
$foundFileName = $null

# Find which file exists
foreach ($file in $possibleFiles) {
    if (Test-Path -Path $file) {
        $pythonFilePath = $file
        $foundFileName = Split-Path -Leaf $file
        Write-Host "Found Python Lambda file: $foundFileName in the s3-link-generator directory"
        break
    }
}

# If no matching file found, let's examine what's actually in the directory
if ($null -eq $pythonFilePath) {
    Write-Host "Checking files in s3-link-generator directory:"
    Get-ChildItem -Path ".\s3-link-generator" | ForEach-Object {
        Write-Host "  $($_.Name)"
    }
    
    # Ask user which file to use
    Write-Host "`nNo expected Python file found. Please enter the name of the Python file to use from the list above:"
    $userInput = Read-Host
    $pythonFilePath = ".\s3-link-generator\$userInput"
    
    if (Test-Path -Path $pythonFilePath) {
        $foundFileName = $userInput
        Write-Host "Using $foundFileName as the Lambda handler file"
    } else {
        Write-Error "File $userInput does not exist in the s3-link-generator directory"
        exit 1
    }
}

# Copy the Python file to the deployment directory
Copy-Item -Path $pythonFilePath -Destination ".\deployment\s3_link_generator.py"
Write-Host "Copied $foundFileName to the deployment directory as s3_link_generator.py"

# Navigate to package directory to zip dependencies
Set-Location -Path ".\deployment\package"
Write-Host "Creating deployment package..."

# Create zip file of dependencies
if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
    # Using PowerShell's Compress-Archive if available
    Compress-Archive -Path ".\*" -DestinationPath "..\deployment_package.zip" -Force
    Write-Host "Created zip file with dependencies using PowerShell's Compress-Archive"
} else {
    # Fallback to 7-Zip if installed
    if (Test-Path -Path "C:\Program Files\7-Zip\7z.exe") {
        & "C:\Program Files\7-Zip\7z.exe" a -tzip "..\deployment_package.zip" ".\*"
        Write-Host "Created zip file with dependencies using 7-Zip"
    } else {
        Write-Error "Could not create zip file. Please install 7-Zip or use PowerShell 5.0+"
        exit 1
    }
}

# Navigate back to deployment directory
Set-Location -Path ".."

# Add the Lambda handler to the zip
if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
    # Using PowerShell's Compress-Archive if available
    Compress-Archive -Path ".\s3_link_generator.py" -Update -DestinationPath ".\deployment_package.zip"
    Write-Host "Added s3_link_generator.py to the zip file using PowerShell's Compress-Archive"
} else {
    # Fallback to 7-Zip if installed
    if (Test-Path -Path "C:\Program Files\7-Zip\7z.exe") {
        & "C:\Program Files\7-Zip\7z.exe" a -tzip ".\deployment_package.zip" ".\s3_link_generator.py"
        Write-Host "Added s3_link_generator.py to the zip file using 7-Zip"
    }
}

# Navigate back to original directory
Set-Location -Path $scriptPath

Write-Host "Deployment package created at .\deployment\deployment_package.zip"
Write-Host "You can now deploy this package to AWS Lambda using:"
Write-Host "aws lambda create-function --function-name s3-link-generator --runtime python3.11 --architectures arm64 --handler s3_link_generator.lambda_handler --role YOUR_ROLE_ARN --zip-file fileb://deployment/deployment_package.zip --region us-east-2"
Write-Host "Or update an existing function with:"
Write-Host "aws lambda update-function-code --function-name s3-link-generator --zip-file fileb://deployment/deployment_package.zip --region us-east-2"