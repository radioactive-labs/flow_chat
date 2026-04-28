# Telegram Development Guide

FlowChat provides comprehensive Telegram Bot API integration with support for inline keyboards, rich media, secure webhook validation, and flexible deployment modes.

## Key Features

- **Inline Keyboards**: Interactive buttons with callback data
- **Rich Media Support**: Photos, documents, videos, audio, and voice messages
- **Secure Webhooks**: Secret token validation via X-Telegram-Bot-Api-Secret-Token
- **Multiple Processing Modes**: Inline, background, and async
- **Callback Query Handling**: Automatic acknowledgment and processing
- **Multi-Tenant Support**: Named configurations for different bots
- **Location and Contact Sharing**: Handle user-shared locations and contacts

## Quick Start

### 1. Create Controller

```ruby
# app/controllers/telegram_controller.rb
class TelegramController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Telegram::Gateway::BotApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  rescue => e
    Rails.logger.error { "Telegram webhook error: #{e.message}" }
    head :internal_server_error
  end
end
```

### 2. Add Routes

```ruby
# config/routes.rb
post '/telegram/webhook', to: 'telegram#webhook'
```

### 3. Create a Flow

```ruby
# app/flow_chat/welcome_flow.rb
class WelcomeFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) do |prompt|
      prompt.ask "Hello! What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Hi #{name}! How can I help?", {
        "info" => "Get Information",
        "support" => "Contact Support",
        "feedback" => "Give Feedback"
      }
    end

    case choice
    when "info"
      show_info
    when "support"
      contact_support
    when "feedback"
      collect_feedback
    end
  end

  private

  def show_info
    app.say "Located at 123 Main Street\nHours: Mon-Fri 9AM-6PM"
  end

  def contact_support
    app.say "Call us at (555) 123-4567\nEmail: support@example.com"
  end

  def collect_feedback
    rating = app.screen(:rating) do |prompt|
      prompt.select "Rate our service:", {
        "1" => "1 Star",
        "2" => "2 Stars",
        "3" => "3 Stars",
        "4" => "4 Stars",
        "5" => "5 Stars"
      }
    end

    app.say "Thank you for your #{rating}-star rating!"
  end
end
```

## Configuration

### Option 1: Rails Credentials (Recommended)

```bash
rails credentials:edit
```

```yaml
telegram:
  bot_token: "123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
  secret_token: "your_webhook_secret_token"
  skip_signature_validation: false  # Set to true only for development
```

### Option 2: Environment Variables

```bash
export TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
export TELEGRAM_SECRET_TOKEN="your_webhook_secret_token"
export TELEGRAM_SKIP_SIGNATURE_VALIDATION="false"
```

### Option 3: Programmatic Configuration

```ruby
telegram_config = FlowChat::Telegram::Configuration.new(:my_bot)
telegram_config.bot_token = "123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
telegram_config.secret_token = "your_webhook_secret_token"
telegram_config.skip_signature_validation = false

processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Telegram::Gateway::BotApi, telegram_config
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

### Configuration Options

| Option | Description | Required |
|--------|-------------|----------|
| `bot_token` | Your Telegram bot token from @BotFather | Yes |
| `secret_token` | Secret token for webhook validation | No (recommended) |
| `skip_signature_validation` | Disable webhook signature checks | No (default: false) |

### Configuration Helper Methods

The configuration object provides several helper methods:

```ruby
config = FlowChat::Telegram::Configuration.from_credentials

# Check if configuration is valid
config.valid?  # => true if bot_token is present

# Get API base URL
config.api_base_url  # => "https://api.telegram.org/bot123456789:ABC..."

# Get bot ID from token
config.bot_id  # => "123456789"

# API endpoint URLs
config.send_message_url
config.set_webhook_url
config.get_webhook_info_url
config.delete_webhook_url
```

## Webhook Setup

Before your bot can receive messages, you must register your webhook URL with Telegram.

### Using the Client

```ruby
# In a Rails console or initializer
config = FlowChat::Telegram::Configuration.from_credentials
client = FlowChat::Telegram::Client.new(config)

# Set webhook with secret token for validation
result = client.set_webhook(
  "https://yourdomain.com/telegram/webhook",
  secret_token: config.secret_token,
  allowed_updates: ["message", "callback_query"]
)

if result["ok"]
  puts "Webhook set successfully!"
else
  puts "Error: #{result["description"]}"
end
```

### Using a Rake Task

```ruby
# lib/tasks/telegram.rake
namespace :telegram do
  desc "Set up Telegram webhook"
  task setup_webhook: :environment do
    config = FlowChat::Telegram::Configuration.from_credentials
    client = FlowChat::Telegram::Client.new(config)

    webhook_url = ENV["TELEGRAM_WEBHOOK_URL"] || "https://yourdomain.com/telegram/webhook"

    result = client.set_webhook(
      webhook_url,
      secret_token: config.secret_token
    )

    if result["ok"]
      puts "Webhook configured: #{webhook_url}"
    else
      puts "Failed to set webhook: #{result["description"]}"
    end
  end

  desc "Get webhook info"
  task webhook_info: :environment do
    config = FlowChat::Telegram::Configuration.from_credentials
    client = FlowChat::Telegram::Client.new(config)

    info = client.get_webhook_info
    puts JSON.pretty_generate(info)
  end

  desc "Delete webhook"
  task delete_webhook: :environment do
    config = FlowChat::Telegram::Configuration.from_credentials
    client = FlowChat::Telegram::Client.new(config)

    result = client.delete_webhook
    puts result["ok"] ? "Webhook deleted" : "Error: #{result["description"]}"
  end
end
```

### Webhook Requirements

- **HTTPS**: Telegram requires a valid SSL certificate
- **Port**: Must be on port 443, 80, 88, or 8443
- **Response Time**: Respond within 60 seconds (use background processing for slow flows)

## Inline Keyboards

FlowChat automatically renders choices as inline keyboards:

### Basic Keyboard

```ruby
def main_menu
  choice = app.screen(:menu) do |prompt|
    prompt.select "What would you like to do?", {
      "balance" => "Check Balance",
      "transfer" => "Transfer Money",
      "history" => "View History"
    }
  end

  handle_choice(choice)
end
```

### Keyboard Layout

The renderer automatically arranges buttons based on the number of choices:

- **1-4 choices**: 2 buttons per row
- **5+ choices**: 1 button per row

```ruby
# 4 choices = 2x2 grid
prompt.select "Pick one:", {
  "a" => "Option A",
  "b" => "Option B",
  "c" => "Option C",
  "d" => "Option D"
}

# 5+ choices = vertical list
prompt.select "Select category:", {
  "electronics" => "Electronics",
  "clothing" => "Clothing",
  "books" => "Books",
  "home" => "Home & Garden",
  "sports" => "Sports & Outdoors"
}
```

### Button Limits

- **Button text**: Maximum 64 characters (auto-truncated with "...")
- **Callback data**: Maximum 64 characters per button

## Rich Media Support

### Sending Media in Flows

```ruby
def product_showcase
  # Photo with prompt
  feedback = app.screen(:product_feedback) do |prompt|
    prompt.ask "What do you think of this product?",
      media: {
        type: :photo,
        url: "https://example.com/product.jpg"
      }
  end

  # Document response
  app.say "Thanks! Here's the product catalog:",
    media: {
      type: :document,
      url: "https://example.com/catalog.pdf",
      filename: "product_catalog.pdf"
    }
end

def video_tutorial
  app.say "Watch this tutorial:",
    media: {
      type: :video,
      url: "https://example.com/tutorial.mp4"
    }
end
```

### Media Types Supported

| Type | Usage | Options |
|------|-------|---------|
| `:photo` | Photos, images | `url` or `file_id` |
| `:document` | PDFs, files | `url` or `file_id`, `filename` |
| `:video` | Video files | `url` or `file_id` |
| `:audio` | Audio files | `url` or `file_id` |
| `:voice` | Voice messages | `url` or `file_id` |

### Media with Inline Keyboard

```ruby
def media_menu
  choice = app.screen(:options) do |prompt|
    prompt.select "Choose an option:",
      {
        "details" => "More Details",
        "buy" => "Buy Now",
        "share" => "Share"
      },
      media: {
        type: :photo,
        url: "https://example.com/product.jpg"
      }
  end
end
```

### Handling Incoming Media

```ruby
def handle_media_upload
  media = context["request.media"]

  if media
    case media[:type]
    when :photo
      app.say "Thanks for the photo! Processing..."
      # Access file_id: media[:file_id]
    when :document
      app.say "Document received: #{media[:file_name]}"
      # Access mime_type: media[:mime_type]
    when :voice
      app.say "Got your voice message (#{media[:duration]}s)"
    end
  else
    app.say "Please send a photo."
  end
end
```

### Handling Location

```ruby
def handle_location
  location = context["request.location"]

  if location
    lat = location["latitude"]
    lon = location["longitude"]
    app.say "You're at: #{lat}, #{lon}"
  else
    app.say "Please share your location."
  end
end
```

### Handling Contact

```ruby
def handle_contact
  contact = context["request.contact"]

  if contact
    phone = contact[:phone_number]
    name = contact[:first_name]
    app.say "Thanks #{name}! We'll contact you at #{phone}."
  else
    app.say "Please share your contact."
  end
end
```

## Telegram Client API

The `FlowChat::Telegram::Client` provides methods for sending messages outside of flows.

### Client Initialization

```ruby
# From credentials/environment variables
config = FlowChat::Telegram::Configuration.from_credentials
client = FlowChat::Telegram::Client.new(config)

# Using named configuration
config = FlowChat::Telegram::Configuration.get(:my_bot)
client = FlowChat::Telegram::Client.new(config)
```

### Text Messages

```ruby
# Simple text message
client.send_text(chat_id, "Hello! How can I help you today?")

# With parse mode (default is HTML)
client.send_text(chat_id, "<b>Bold</b> and <i>italic</i>", parse_mode: "HTML")
client.send_text(chat_id, "*Bold* and _italic_", parse_mode: "Markdown")
```

### Messages with Inline Keyboard

```ruby
keyboard = [
  [
    { text: "Option 1", callback_data: "opt1" },
    { text: "Option 2", callback_data: "opt2" }
  ],
  [
    { text: "Option 3", callback_data: "opt3" }
  ]
]

client.send_text_with_keyboard(chat_id, "Choose an option:", keyboard)
```

### Media Messages

```ruby
# Send photo
client.send_photo(chat_id, "https://example.com/image.jpg", caption: "Check this out!")

# Send document
client.send_document(chat_id, "https://example.com/file.pdf", caption: "Your document")

# Send video
client.send_video(chat_id, "https://example.com/video.mp4", caption: "Watch this")

# Send audio
client.send_audio(chat_id, "https://example.com/audio.mp3", caption: "Listen to this")

# Send voice message
client.send_voice(chat_id, "https://example.com/voice.ogg")
```

### Photo with Inline Keyboard

```ruby
keyboard = [
  [{ text: "Like", callback_data: "like" }, { text: "Share", callback_data: "share" }]
]

client.send_photo_with_keyboard(
  chat_id,
  "https://example.com/product.jpg",
  caption: "New product!",
  keyboard: keyboard
)
```

### Message Management

```ruby
# Edit message text
client.edit_message_text(chat_id, message_id, "Updated text", keyboard: new_keyboard)

# Delete message
client.delete_message(chat_id, message_id)

# Answer callback query (acknowledge button press)
client.answer_callback_query(callback_query_id, text: "Processing...", show_alert: false)
```

### Chat Actions / Typing Indicator

Broadcast a chat action (e.g. "typing…") to a Telegram chat. The action lasts ~5 seconds or until the next outbound message; there is **no stop-typing call**.

```ruby
client = FlowChat::Telegram::Client.new(config)

# Show "typing…"
client.send_chat_action(chat_id)

# Convenience equivalent of the line above
client.indicate_typing(chat_id)

# Other actions (e.g. while uploading a generated image)
client.send_chat_action(chat_id, action: "upload_photo")
```

Valid actions per the Telegram Bot API: `typing`, `upload_photo`, `record_video`, `upload_video`, `record_voice`, `upload_voice`, `upload_document`, `choose_sticker`, `find_location`, `record_video_note`, `upload_video_note`. FlowChat does not validate the action client-side; if Telegram rejects it the response will contain `"ok" => false` with the error description.

### Bot Information

```ruby
# Get bot info
bot_info = client.get_me
puts "Bot username: @#{bot_info["result"]["username"]}"
```

### Complete Service Example

```ruby
# Service for sending notifications
class TelegramNotificationService
  def initialize(config_name = :default)
    @config = FlowChat::Telegram::Configuration.get(config_name)
    @client = FlowChat::Telegram::Client.new(@config)
  end

  def send_order_confirmation(chat_id, order_id)
    # Send confirmation message with buttons
    keyboard = [
      [
        { text: "Track Order", callback_data: "track_#{order_id}" },
        { text: "Contact Support", callback_data: "support" }
      ]
    ]

    @client.send_text_with_keyboard(
      chat_id,
      "Order ##{order_id} confirmed!\n\nThank you for your purchase.",
      keyboard
    )
  end

  def send_document_notification(chat_id, document_url, filename)
    @client.send_document(
      chat_id,
      document_url,
      caption: "Your document is ready: #{filename}"
    )
  end

  def broadcast_message(chat_ids, message)
    chat_ids.each do |chat_id|
      @client.send_text(chat_id, message)
    rescue => e
      Rails.logger.error { "Failed to send to #{chat_id}: #{e.message}" }
    end
  end
end

# Usage
service = TelegramNotificationService.new(:main_bot)
service.send_order_confirmation(123456789, "ORD-12345")
```

## Context Variables

The gateway sets these context variables during request processing:

### Request Context

| Variable | Description | Example |
|----------|-------------|---------|
| `request.id` | Chat ID | `"123456789"` |
| `request.user_id` | User ID | `"987654321"` |
| `request.user_name` | User's full name | `"John Doe"` |
| `request.username` | Telegram username | `"johndoe"` |
| `request.gateway` | Gateway identifier | `:telegram_bot_api` |
| `request.platform` | Platform identifier | `:telegram` |
| `request.message_id` | Message ID | `"456"` |
| `request.timestamp` | ISO8601 timestamp | `"2024-01-15T10:30:00Z"` |
| `request.body` | Raw webhook body | `{...}` |

### Telegram-Specific Context

| Variable | Description |
|----------|-------------|
| `telegram.client` | Telegram client instance |
| `telegram.chat_type` | Chat type (`private`, `group`, `supergroup`, `channel`) |
| `telegram.callback_query_id` | Callback query ID (for button presses) |
| `telegram.original_message_id` | Original message ID (for callbacks) |

### Media Context

| Variable | Description |
|----------|-------------|
| `request.media` | Media info hash with `:type`, `:file_id`, etc. |
| `request.location` | Location hash with `latitude`, `longitude` |
| `request.contact` | Contact hash with `:phone_number`, `:first_name`, etc. |

### Accessing Context in Flows

```ruby
class MyFlow < FlowChat::Flow
  def main_page
    chat_id = context["request.id"]
    user_name = context["request.user_name"]
    chat_type = context["telegram.chat_type"]

    # Access Telegram client for custom operations
    client = context["telegram.client"]

    if chat_type == "group"
      app.say "Hello, group members!"
    else
      app.say "Hello, #{user_name}!"
    end
  end
end
```

## Security and Validation

### Webhook Signature Validation

Telegram sends a secret token in the `X-Telegram-Bot-Api-Secret-Token` header that you define when setting up the webhook. FlowChat validates this automatically.

#### How It Works

1. You set a `secret_token` when registering the webhook
2. Telegram includes this token in every webhook request
3. FlowChat compares the received token with your configured `secret_token`
4. Requests with invalid tokens are rejected with 401 Unauthorized

#### Production Configuration (Recommended)

```ruby
# config/credentials/production.yml
telegram:
  bot_token: "123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
  secret_token: "a_very_secure_random_string_at_least_32_chars"
  skip_signature_validation: false
```

```ruby
# Set up webhook with secret token
client.set_webhook(
  "https://yourdomain.com/telegram/webhook",
  secret_token: "a_very_secure_random_string_at_least_32_chars"
)
```

#### Development Configuration

```ruby
# Option 1: Use real secret token (recommended for staging)
config = FlowChat::Telegram::Configuration.new(:dev_bot)
config.bot_token = "your_token"
config.secret_token = "your_secret"
config.skip_signature_validation = false

# Option 2: Disable validation (development only)
config = FlowChat::Telegram::Configuration.new(:dev_bot)
config.bot_token = "your_token"
config.skip_signature_validation = true
```

#### Security Warning

Never disable signature validation in production. An attacker could send fake webhook requests to your endpoint.

### Error Handling

```ruby
def webhook
  processor = FlowChat::Processor.new(self) do |config|
    config.use_gateway FlowChat::Telegram::Gateway::BotApi
    config.use_session_store FlowChat::Session::CacheSessionStore
  end

  processor.run WelcomeFlow, :main_page
rescue FlowChat::Telegram::ConfigurationError => e
  Rails.logger.error { "Telegram configuration error: #{e.message}" }
  head :internal_server_error
rescue => e
  Rails.logger.error { "Telegram webhook error: #{e.message}" }
  head :internal_server_error
end
```

## Multi-Tenant Support

### Named Configurations

```ruby
# config/initializers/telegram_configs.rb
bot_a_config = FlowChat::Telegram::Configuration.new(:bot_a)
bot_a_config.bot_token = "bot_a_token"
bot_a_config.secret_token = "bot_a_secret"

bot_b_config = FlowChat::Telegram::Configuration.new(:bot_b)
bot_b_config.bot_token = "bot_b_token"
bot_b_config.secret_token = "bot_b_secret"
```

### Configuration API

```ruby
# Check if configuration exists
FlowChat::Telegram::Configuration.exists?(:bot_a)  # => true/false

# Get configuration by name
config = FlowChat::Telegram::Configuration.get(:bot_a)

# List all registered configurations
FlowChat::Telegram::Configuration.configuration_names  # => [:bot_a, :bot_b]

# Clear all configurations (useful for testing)
FlowChat::Telegram::Configuration.clear_all!
```

### Multi-Bot Controller

```ruby
class MultiTelegramController < ApplicationController
  skip_forgery_protection

  def webhook
    bot_name = params[:bot_name]&.to_sym

    unless FlowChat::Telegram::Configuration.exists?(bot_name)
      Rails.logger.error { "No configuration found for bot: #{bot_name}" }
      head :not_found
      return
    end

    config = FlowChat::Telegram::Configuration.get(bot_name)

    processor = FlowChat::Processor.new(self) do |c|
      c.use_gateway FlowChat::Telegram::Gateway::BotApi, config
      c.use_session_store FlowChat::Session::CacheSessionStore
      c.use_session_config(
        boundaries: [:flow, :platform, :bot],
        identifier: :user_id,
        bot: bot_name
      )
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

```ruby
# config/routes.rb
post '/telegram/:bot_name/webhook', to: 'multi_telegram#webhook'
```

## Testing and Development

### Local Development with ngrok

```bash
# Start ngrok tunnel
ngrok http 3000

# Use the HTTPS URL for webhook
# https://abc123.ngrok.io/telegram/webhook
```

### Test Setup

```ruby
# test/integration/telegram_test.rb
class TelegramIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    @config = FlowChat::Telegram::Configuration.new(:test)
    @config.bot_token = "test_token"
    @config.skip_signature_validation = true
  end

  def test_text_message_webhook
    webhook_data = {
      update_id: 123,
      message: {
        message_id: 1,
        from: { id: 123456, first_name: "Test", username: "testuser" },
        chat: { id: 123456, type: "private" },
        date: Time.now.to_i,
        text: "Hello"
      }
    }

    post "/telegram/webhook",
      params: webhook_data.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :ok
  end

  def test_callback_query_webhook
    webhook_data = {
      update_id: 124,
      callback_query: {
        id: "callback_123",
        from: { id: 123456, first_name: "Test" },
        message: {
          message_id: 1,
          chat: { id: 123456, type: "private" }
        },
        data: "option_1"
      }
    }

    post "/telegram/webhook",
      params: webhook_data.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :ok
  end
end
```

### Mock Client for Tests

```ruby
class MockTelegramClient
  attr_reader :sent_messages

  def initialize
    @sent_messages = []
  end

  def send_message(chat_id, prompt, choices: nil, media: nil)
    @sent_messages << {
      chat_id: chat_id,
      prompt: prompt,
      choices: choices,
      media: media
    }
    { "ok" => true, "result" => { "message_id" => 123 } }
  end

  def answer_callback_query(*)
    { "ok" => true }
  end
end
```

## Troubleshooting

### Common Issues

**1. Webhook not receiving updates**
```
No updates being received at webhook endpoint
```
**Solution**:
- Verify webhook is set: `client.get_webhook_info`
- Check URL is HTTPS with valid certificate
- Ensure secret_token matches (if using validation)
- Check server logs for 401 errors

**2. Invalid webhook signature**
```
401 Unauthorized responses
```
**Solution**:
- Verify `secret_token` matches what was set in `set_webhook`
- Check `X-Telegram-Bot-Api-Secret-Token` header is being sent
- For development, set `skip_signature_validation: true`

**3. Callback query not working**
```
Button presses don't trigger flow
```
**Solution**:
- Ensure `callback_query` is in `allowed_updates` when setting webhook
- Check callback_data is within 64 character limit
- Verify the callback is being answered (done automatically by gateway)

**4. Media not sending**
```
Photos/documents fail to send
```
**Solution**:
- Use HTTPS URLs for media
- Check file size limits (photos: 10MB, documents: 50MB)
- Verify MIME types are correct
- For large files, upload first and use file_id

### Debug Mode

Enable debug logging:

```ruby
# config/environments/development.rb
config.log_level = :debug

# This will log:
# - Webhook request parsing
# - Signature validation
# - Message extraction
# - API requests/responses
```

### Webhook Diagnostics

```ruby
# Check webhook status
config = FlowChat::Telegram::Configuration.from_credentials
client = FlowChat::Telegram::Client.new(config)

info = client.get_webhook_info
puts "URL: #{info.dig("result", "url")}"
puts "Pending updates: #{info.dig("result", "pending_update_count")}"
puts "Last error: #{info.dig("result", "last_error_message")}"
puts "Last error date: #{info.dig("result", "last_error_date")}"
```

## Best Practices

### 1. Message Design
- Keep button text concise (under 64 characters)
- Use clear, actionable labels
- Limit inline keyboard to reasonable number of options
- Consider user experience on mobile

### 2. Media Usage
- Compress images appropriately
- Provide meaningful captions
- Use appropriate media types
- Consider bandwidth limitations

### 3. Flow Design
- Handle unexpected input gracefully
- Provide clear error messages
- Use progressive disclosure for complex flows
- Always acknowledge user actions

### 4. Security
- Always validate webhooks in production
- Use environment variables for tokens
- Rotate secret tokens periodically
- Monitor for unusual patterns

### 5. Performance
- Use background processing for slow operations
- Respond to webhooks quickly (under 60s)
- Cache frequently used data
- Handle rate limits gracefully

## API Reference

### Core Classes

| Class | Description |
|-------|-------------|
| `FlowChat::Telegram::Gateway::BotApi` | Telegram Bot API gateway |
| `FlowChat::Telegram::Client` | API client for messaging |
| `FlowChat::Telegram::Configuration` | Configuration management |
| `FlowChat::Telegram::Renderer` | Message rendering logic |
| `FlowChat::Telegram::Middleware::ChoiceMapper` | Choice validation middleware |

### Client Methods

| Method | Description | Parameters |
|--------|-------------|------------|
| `send_message(chat_id, prompt, choices:, media:)` | Send FlowChat response | chat_id, prompt, options |
| `send_text(chat_id, text, parse_mode:)` | Send text message | chat_id, text, parse_mode |
| `send_text_with_keyboard(chat_id, text, keyboard)` | Send text with inline keyboard | chat_id, text, keyboard array |
| `send_photo(chat_id, photo, caption:)` | Send photo | chat_id, URL/file_id, caption |
| `send_photo_with_keyboard(chat_id, photo, caption:, keyboard:)` | Send photo with buttons | chat_id, photo, options |
| `send_document(chat_id, document, caption:)` | Send document | chat_id, URL/file_id, caption |
| `send_video(chat_id, video, caption:)` | Send video | chat_id, URL/file_id, caption |
| `send_audio(chat_id, audio, caption:)` | Send audio | chat_id, URL/file_id, caption |
| `send_voice(chat_id, voice)` | Send voice message | chat_id, URL/file_id |
| `edit_message_text(chat_id, message_id, text, keyboard:)` | Edit message | chat_id, msg_id, text, keyboard |
| `delete_message(chat_id, message_id)` | Delete message | chat_id, message_id |
| `answer_callback_query(id, text:, show_alert:)` | Acknowledge callback | query_id, options |
| `set_webhook(url, secret_token:, allowed_updates:)` | Set webhook URL | url, options |
| `delete_webhook` | Remove webhook | none |
| `get_webhook_info` | Get webhook status | none |
| `get_me` | Get bot information | none |

### Configuration Methods

| Method | Description |
|--------|-------------|
| `Configuration.from_credentials` | Load from Rails credentials/ENV |
| `Configuration.new(name)` | Create named configuration |
| `Configuration.get(name)` | Get configuration by name |
| `Configuration.exists?(name)` | Check if config exists |
| `Configuration.configuration_names` | List all config names |
| `Configuration.clear_all!` | Remove all configurations |
| `config.valid?` | Check if config is valid |
| `config.api_base_url` | Get API base URL |
| `config.bot_id` | Get bot ID from token |
| `config.register_as(name)` | Register config with name |

---

This guide covers everything you need to build Telegram bot integrations with FlowChat. For more examples and advanced patterns, check the [examples directory](../../examples/) in the FlowChat repository.
