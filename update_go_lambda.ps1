# Navigate to s3-event-webhook-dispatcher directory
Set-Location -Path ".\s3-event-webhook-dispatcher"

# Remove existing go.mod if it exists
if (Test-Path -Path "go.mod") {
    Remove-Item -Path "go.mod" -Force
}

# Use the go mod edit command as suggested by the error
& go mod edit -module=github.com/k33bz/s3-event-webhook-dispatcher

# Add the required dependencies
& go get github.com/aws/aws-lambda-go/lambda
& go get github.com/aws/aws-lambda-go/events

# Create the main.go file
$goCode = @'
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
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

// getRandomRainbowColor returns a random color from a rainbow-like palette
func getRandomRainbowColor() int {
	// Initialize random seed
	rand.Seed(time.Now().UnixNano())
	
	// Rainbow-like colors
	rainbowColors := []int{
		16711680, // Red (#FF0000)
		16733440, // Orange (#FF5500)
		16755200, // Light Orange (#FF9900)
		16776960, // Yellow (#FFFF00)
		8388352,  // Light Green (#80FF00)
		65280,    // Green (#00FF00)
		65407,    // Aqua/Cyan (#00FF7F)
		65535,    // Light Blue (#00FFFF)
		38655,    // Sky Blue (#0097FF)
		255,      // Blue (#0000FF)
		5767168,  // Indigo (#5800FF)
		11468799, // Purple (#AF00FF)
		16711935, // Magenta (#FF00FF)
		16711807, // Pink (#FF00BF)
	}
	
	// Return a random color from the rainbow array
	return rainbowColors[rand.Intn(len(rainbowColors))]
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

	// Create Discord message with embed using a random rainbow color
	message := DiscordMessage{
		Embeds: []DiscordEmbed{
			{
				Title:       "New File Uploaded",
				Description: description,
				Color:       getRandomRainbowColor(),
				Timestamp:   time.Now().Format(time.RFC3339),
				Footer: EmbedItem{
					Text: "Gaymitcraft File Notification System",
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

# Save the code to main.go
$goCode | Out-File -Path "main.go" -Encoding utf8

# Run go mod tidy to ensure the go.mod file is properly updated
& go mod tidy

# Return to the original directory
Set-Location -Path ".."