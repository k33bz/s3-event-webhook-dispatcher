# create_go_lambda_fixed.ps1

# Set working directory to script location
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -Path $scriptPath

# Create a temporary directory for our new Go project
$tempGoDir = ".\go_lambda_temp"
if (Test-Path -Path $tempGoDir) {
    # Clean up any existing directory
    Remove-Item -Path $tempGoDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempGoDir | Out-Null

# Navigate to the temporary Go project directory
Set-Location -Path $tempGoDir

# Initialize a new Go module
Write-Host "Initializing a new Go module..."
& go mod init lambda-webhook-dispatcher
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to initialize Go module"
    Set-Location -Path $scriptPath
    exit 1
}

# Create main.go file with Lambda handler
Write-Host "Creating main.go..."
$lambdaCode = @'
package main

import (
    "bytes"
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "os"
    "time"

    "github.com/aws/aws-lambda-go/events"
    "github.com/aws/aws-lambda-go/lambda"
)

// FilePayload represents the event data structure received from EventBridge
type FilePayload struct {
    FileName       string `json:"fileName"`
    FileURL        string `json:"fileUrl"`
    Bucket         string `json:"bucket"`
    ExpirationTime string `json:"expirationTime"`
    Timestamp      string `json:"timestamp"`
}

// DiscordEmbed represents a Discord message embed structure
type DiscordEmbed struct {
    Title       string    `json:"title"`
    Description string    `json:"description"`
    Color       int       `json:"color"`
    Timestamp   string    `json:"timestamp"`
    Footer      EmbedItem `json:"footer"`
}

// EmbedItem represents elements in a Discord embed that have text attributes
type EmbedItem struct {
    Text string `json:"text"`
}

// DiscordMessage represents the full webhook payload sent to Discord
type DiscordMessage struct {
    Embeds []DiscordEmbed `json:"embeds"`
}

// Handler is the Lambda function handler
func Handler(ctx context.Context, event events.CloudWatchEvent) error {
    // Get webhook URL from environment variables
    webhookURL := os.Getenv("WEBHOOK_URL")
    if webhookURL == "" {
        return fmt.Errorf("WEBHOOK_URL environment variable is not set")
    }

    // Parse the event detail
    var payload FilePayload
    if err := json.Unmarshal([]byte(event.Detail), &payload); err != nil {
        return fmt.Errorf("failed to parse event detail: %v", err)
    }

    // Create description with formatted message
    description := fmt.Sprintf(
        "A new file has been uploaded to S3.\n\n**File Name:** %s\n**Temporary Link:** [Download File](%s)\n**Link Expires:** After %s",
        payload.FileName,
        payload.FileURL,
        payload.ExpirationTime,
    )

    // Create Discord message with embed
    message := DiscordMessage{
        Embeds: []DiscordEmbed{
            {
                Title:       "New File Uploaded",
                Description: description,
                Color:       3447003, // Discord blue color
                Timestamp:   time.Now().Format(time.RFC3339),
                Footer: EmbedItem{
                    Text: "S3 File Notification System",
                },
            },
        },
    }

    // Serialize message to JSON for HTTP request
    messageJSON, err := json.Marshal(message)
    if err != nil {
        return fmt.Errorf("failed to marshal message to JSON: %v", err)
    }

    // Create HTTP client with timeout
    client := &http.Client{
        Timeout: 10 * time.Second,
    }

    // Send request to webhook endpoint
    req, err := http.NewRequestWithContext(
        ctx,
        "POST",
        webhookURL,
        bytes.NewBuffer(messageJSON),
    )
    if err != nil {
        return fmt.Errorf("failed to create HTTP request: %v", err)
    }
    req.Header.Set("Content-Type", "application/json")

    // Execute HTTP request
    resp, err := client.Do(req)
    if err != nil {
        return fmt.Errorf("failed to send message to webhook: %v", err)
    }
    defer resp.Body.Close()

    // Check for success status code
    if resp.StatusCode < 200 || resp.StatusCode >= 300 {
        return fmt.Errorf("webhook returned non-success status code: %d", resp.StatusCode)
    }

    return nil
}

func main() {
    lambda.Start(Handler)
}
'@

# Save the Lambda code to main.go
$lambdaCode | Out-File -FilePath "main.go" -Encoding utf8

# Get dependencies
Write-Host "Getting dependencies..."
& go get github.com/aws/aws-lambda-go/lambda
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get lambda dependency"
    Set-Location -Path $scriptPath
    exit 1
}

& go get github.com/aws/aws-lambda-go/events
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get events dependency"
    Set-Location -Path $scriptPath
    exit 1
}

# Build the Go binary for Lambda - naming it bootstrap for provided.al2023 runtime
Write-Host "Building Go binary for Lambda (ARM64)..."
$env:GOOS = "linux"
$env:GOARCH = "arm64"
& go build -o bootstrap main.go
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build Go binary"
    Set-Location -Path $scriptPath
    exit 1
}

# Create a ZIP file with the binary
Write-Host "Creating deployment package..."
Compress-Archive -Path "bootstrap" -DestinationPath "function.zip" -Force
Write-Host "Created zip file using PowerShell's Compress-Archive"

# Copy the ZIP file to the original s3-event-webhook-dispatcher directory
Copy-Item -Path "function.zip" -Destination "..\s3-event-webhook-dispatcher\" -Force
Write-Host "Copied deployment package to s3-event-webhook-dispatcher directory"

# Navigate back to original directory
Set-Location -Path $scriptPath

Write-Host "Deployment package created at .\s3-event-webhook-dispatcher\function.zip"
Write-Host "You can now update your Lambda function"