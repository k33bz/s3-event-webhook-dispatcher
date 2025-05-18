// Package main provides a Lambda function that dispatches S3 file events to webhook endpoints
// It's designed to be generic yet configured for Discord by default
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

// Config holds all environment-based configuration values
// All of these can be customized through Lambda environment variables
type Config struct {
	WebhookURL      string        // Target webhook URL
	MessageTemplate string        // Template for formatting the message
	Timeout         time.Duration // HTTP request timeout
	EmbedColor      int           // Color code for the embed (used by Discord)
	FooterText      string        // Text to appear in the footer of the embed
}

// FilePayload represents the event data structure received from EventBridge
// This matches the output format from the Link Generator Lambda
type FilePayload struct {
	FileName       string `json:"fileName"`       // The name of the uploaded file
	FileURL        string `json:"fileUrl"`        // The presigned URL for accessing the file
	Bucket         string `json:"bucket"`         // The S3 bucket name
	ExpirationTime string `json:"expirationTime"` // How long the URL will be valid
	Timestamp      string `json:"timestamp"`      // When the file was uploaded
}

// DiscordEmbed represents a Discord message embed structure
// Embeds provide a rich way to display structured content
type DiscordEmbed struct {
	Title       string    `json:"title"`       // Title of the embed
	Description string    `json:"description"` // Main content
	Color       int       `json:"color"`       // Color bar on the left side
	Timestamp   string    `json:"timestamp"`   // ISO timestamp
	Footer      EmbedItem `json:"footer"`      // Footer information
}

// EmbedItem represents elements in a Discord embed that have text attributes
type EmbedItem struct {
	Text string `json:"text"` // Text content of the embed element
}

// DiscordMessage represents the full webhook payload sent to Discord
type DiscordMessage struct {
	Embeds []DiscordEmbed `json:"embeds"` // Array of embeds (typically just one)
}

// loadConfig retrieves and parses all configuration from environment variables
// It provides sensible defaults when environment variables are not set
func loadConfig() Config {
	// Default timeout of 10 seconds if not specified
	timeoutSeconds := 10
	if os.Getenv("REQUEST_TIMEOUT_SECONDS") != "" {
		fmt.Sscanf(os.Getenv("REQUEST_TIMEOUT_SECONDS"), "%d", &timeoutSeconds)
	}

	// Default Discord blue color if not specified
	embedColor := 3447003
	if os.Getenv("EMBED_COLOR") != "" {
		fmt.Sscanf(os.Getenv("EMBED_COLOR"), "%d", &embedColor)
	}

	// Default message template with appropriate Discord markdown formatting
	messageTemplate := "A new file has been uploaded to S3.\n\n**File Name:** %s\n**Temporary Link:** [Download File](%s)\n**Link Expires:** After %s"
	if os.Getenv("MESSAGE_TEMPLATE") != "" {
		messageTemplate = os.Getenv("MESSAGE_TEMPLATE")
	}

	// Default footer text
	footerText := "S3 File Notification System"
	if os.Getenv("FOOTER_TEXT") != "" {
		footerText = os.Getenv("FOOTER_TEXT")
	}

	// Use WEBHOOK_URL as the primary env var name, but fall back to DISCORD_WEBHOOK_URL for backward compatibility
	webhookURL := os.Getenv("WEBHOOK_URL")
	if webhookURL == "" {
		webhookURL = os.Getenv("DISCORD_WEBHOOK_URL")
	}

	return Config{
		WebhookURL:      webhookURL,
		MessageTemplate: messageTemplate,
		Timeout:         time.Duration(timeoutSeconds) * time.Second,
		EmbedColor:      embedColor,
		FooterText:      footerText,
	}
}

// handler is the main Lambda function handler that processes EventBridge events
// It formats the file information and sends it to the configured webhook endpoint
func handler(ctx context.Context, event events.CloudWatchEvent) error {
	// Load configuration from environment variables
	config := loadConfig()

	// Validate webhook URL - cannot proceed without it
	if config.WebhookURL == "" {
		return fmt.Errorf("WEBHOOK_URL environment variable is not set")
	}

	// Parse the event detail from EventBridge into our FilePayload structure
	var payload FilePayload
	if err := json.Unmarshal([]byte(event.Detail), &payload); err != nil {
		return fmt.Errorf("failed to parse event detail: %v", err)
	}

	// Create description with formatted message using the template
	description := fmt.Sprintf(
		config.MessageTemplate,
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
				Color:       config.EmbedColor,
				Timestamp:   time.Now().Format(time.RFC3339),
				Footer: EmbedItem{
					Text: config.FooterText,
				},
			},
		},
	}

	// Serialize message to JSON for HTTP request
	messageJSON, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("failed to marshal message to JSON: %v", err)
	}

	// Create HTTP client with configured timeout
	client := &http.Client{
		Timeout: config.Timeout,
	}

	// Send request to webhook endpoint
	req, err := http.NewRequestWithContext(
		ctx,
		"POST",
		config.WebhookURL,
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

// main is the entry point for the Lambda function
func main() {
	lambda.Start(handler)
}